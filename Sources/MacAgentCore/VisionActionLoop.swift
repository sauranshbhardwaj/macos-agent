import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// SONNY-69 experiment (throwaway spike — never merges). Screenshot the target app's front
// window, ask a vision model (Gemma 4 31B) which control to click, synthesize a real CGEvent
// click, re-screenshot, loop. Deliberately OUTSIDE the risk/approval engine — the model can
// click anything, including destructive controls. Supervised runs on the founder's machine
// only; every click is logged to the console (coordinates + rationale) before it is issued.

public struct VisionActionRequest: Equatable, Sendable {
    public let appName: String
    public let goal: String

    public init(appName: String, goal: String) {
        self.appName = appName
        self.goal = goal
    }
}

public enum VisionActionExperiment {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SONNY_VISION_DEBUG"] == "1"
    }

    public enum ParseOutcome: Equatable, Sendable {
        case request(VisionActionRequest)
        case malformed(hint: String)
    }

    /// nil means "not a vision command at all" — the normal pipeline proceeds untouched.
    public static func parseCommand(_ command: String) -> ParseOutcome? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("vision:") else { return nil }
        let rest = trimmed.dropFirst("vision:".count)
        let parts = rest.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let appName = parts.count == 2 ? parts[0].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let goal = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard parts.count == 2, !appName.isEmpty, !goal.isEmpty else {
            return .malformed(hint: "Vision experiment format: vision: <App Name> | <goal>")
        }
        return .request(VisionActionRequest(appName: appName, goal: goal))
    }
}

public enum VisionActionLoopError: Error, LocalizedError {
    case missingAPIKey(String)
    case screenRecordingNotGranted
    case accessibilityNotGranted
    case targetAppNotRunning(String, available: [String])
    case captureFailed(String)
    case badResponse(Int, String)
    case unparseableModelReply(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let variable):
            return "\(variable) is not set. Add it to the environment before launching the app."
        case .screenRecordingNotGranted:
            return "Screen Recording is not granted. Enable Sonny under System Settings > Privacy & Security > Screen Recording, then relaunch and retry."
        case .accessibilityNotGranted:
            return "Accessibility is not granted. Enable Sonny under System Settings > Privacy & Security > Accessibility, then retry."
        case .targetAppNotRunning(let name, let available):
            return "\(name) is not running with a visible window. Running apps: \(available.joined(separator: ", "))"
        case .captureFailed(let reason):
            return "Window capture failed: \(reason)"
        case .badResponse(let status, let body):
            return "Vision model request failed with HTTP \(status): \(body)"
        case .unparseableModelReply(let reply):
            return "Vision model reply was not usable JSON: \(reply)"
        }
    }
}

public enum VisionActionLoop {
    public static let maxIterations = 10

    public struct ClickRecord: Sendable {
        public let iteration: Int
        public let imagePoint: CGPoint
        public let globalPoint: CGPoint
        public let target: String
        public let rationale: String
        public let visionLatencySeconds: Double
    }

    public struct RunSummary: Sendable {
        public enum Outcome: Sendable {
            case done(String)
            case stuck(String)
            case iterationCapReached
        }

        public let outcome: Outcome
        public let clicks: [ClickRecord]
        public let iterations: Int
        public let transcript: [String]
        public let modelDescription: String

        public var userSummary: String {
            let clickPhrase = "\(clicks.count) click\(clicks.count == 1 ? "" : "s") in \(iterations) iteration\(iterations == 1 ? "" : "s") via \(modelDescription)"
            switch outcome {
            case .done(let rationale):
                return "Vision experiment finished: goal reported done after \(clickPhrase). \(rationale)"
            case .stuck(let rationale):
                return "Vision experiment stopped: model reported stuck after \(clickPhrase). \(rationale)"
            case .iterationCapReached:
                return "Vision experiment stopped: iteration cap (\(maxIterations)) reached after \(clickPhrase)."
            }
        }
    }

    public static func run(_ request: VisionActionRequest) async throws -> RunSummary {
        try preflightPermissions()
        let client = try VisionModelClient()

        var transcript: [String] = []
        func emit(_ line: String) {
            print("[VisionLoop] \(line)")
            transcript.append(line)
        }

        emit("start host=\(client.host.rawValue) model=\(client.model) app=\"\(request.appName)\" goal=\"\(request.goal)\"")

        var history: [String] = []
        var clicks: [ClickRecord] = []
        var iterationsRun = 0

        for iteration in 1...maxIterations {
            iterationsRun = iteration

            guard let pid = await activateApp(named: request.appName) else {
                throw VisionActionLoopError.targetAppNotRunning(request.appName, available: await visibleAppNames())
            }
            try await Task.sleep(nanoseconds: 800_000_000)

            let capture = try await captureFrontWindow(ofProcess: pid, appName: request.appName)
            let png = try pngData(from: capture.image)
            guard png.count <= 9_000_000 else {
                throw VisionActionLoopError.captureFailed("screenshot PNG is \(png.count) bytes, over the vision API payload limit")
            }
            emit("iteration \(iteration): captured \(capture.image.width)x\(capture.image.height)px of window \"\(capture.windowTitle)\" (\(png.count) bytes, window frame \(Int(capture.windowFrame.origin.x)),\(Int(capture.windowFrame.origin.y)) \(Int(capture.windowFrame.width))x\(Int(capture.windowFrame.height))pt)")

            let prompt = decisionPrompt(
                request: request,
                windowTitle: capture.windowTitle,
                imageWidth: capture.image.width,
                imageHeight: capture.image.height,
                history: history
            )
            let (reply, latency) = try await client.decide(prompt: prompt, pngData: png)
            let decision = try VisionDecision.parse(reply)
            emit("iteration \(iteration): model replied in \(String(format: "%.2f", latency))s action=\(decision.kind.rawValue) target=\"\(decision.target)\"")

            switch decision.kind {
            case .done:
                return RunSummary(outcome: .done(decision.rationale), clicks: clicks, iterations: iteration, transcript: transcript, modelDescription: "\(client.host.rawValue)/\(client.model)")
            case .stuck:
                return RunSummary(outcome: .stuck(decision.rationale), clicks: clicks, iterations: iteration, transcript: transcript, modelDescription: "\(client.host.rawValue)/\(client.model)")
            case .click:
                guard let x = decision.x, let y = decision.y else {
                    throw VisionActionLoopError.unparseableModelReply(reply)
                }
                // The screenshot is requested at 1x, but the scale is always recomputed from the
                // actual image dimensions so a 2x capture still maps correctly to window points.
                let frame = capture.windowFrame
                let scaleX = frame.width / CGFloat(capture.image.width)
                let scaleY = frame.height / CGFloat(capture.image.height)
                let windowPoint = CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY)
                // SCWindow.frame and CGEvent both use top-left-origin global display coordinates,
                // so the mapping is pure translation — no y-flip.
                let globalPoint = CGPoint(x: frame.origin.x + windowPoint.x, y: frame.origin.y + windowPoint.y)

                // Mandated by the ticket's safety note: log BEFORE the click is issued.
                emit("iteration \(iteration): CLICK image(\(x),\(y)) -> global(\(Int(globalPoint.x)),\(Int(globalPoint.y))) target=\"\(decision.target)\" rationale=\"\(decision.rationale)\"")
                try await synthesizeClick(at: globalPoint)

                clicks.append(ClickRecord(
                    iteration: iteration,
                    imagePoint: CGPoint(x: x, y: y),
                    globalPoint: globalPoint,
                    target: decision.target,
                    rationale: decision.rationale,
                    visionLatencySeconds: latency
                ))
                history.append("iteration \(iteration): clicked \"\(decision.target)\" at image (\(x), \(y)) — \(decision.rationale)")
                if let previous = clicks.dropLast().last,
                   abs(previous.imagePoint.x - CGFloat(x)) <= 5, abs(previous.imagePoint.y - CGFloat(y)) <= 5 {
                    history.append("warning: you clicked this same spot twice with no visible effect — choose a different control or report stuck")
                }
                try await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }

        return RunSummary(outcome: .iterationCapReached, clicks: clicks, iterations: iterationsRun, transcript: transcript, modelDescription: "\(client.host.rawValue)/\(client.model)")
    }

    // MARK: - Permissions

    static func preflightPermissions() throws {
        if !CGPreflightScreenCaptureAccess() {
            // Triggers the system prompt / creates the System Settings entry, but the grant only
            // takes effect after relaunch — so this attempt still fails loudly.
            CGRequestScreenCaptureAccess()
            throw VisionActionLoopError.screenRecordingNotGranted
        }
        // Literal value of kAXTrustedCheckOptionPrompt — the SDK global is a mutable `var` and
        // Swift 6 strict concurrency refuses to read it from a nonisolated context.
        let promptKey = "AXTrustedCheckOptionPrompt"
        if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            throw VisionActionLoopError.accessibilityNotGranted
        }
    }

    // MARK: - App activation (AppKit values never leave the MainActor closures)

    private static func activateApp(named appName: String) async -> pid_t? {
        await MainActor.run {
            let apps = NSWorkspace.shared.runningApplications
            let match = apps.first { $0.localizedName?.caseInsensitiveCompare(appName) == .orderedSame }
                ?? apps.first { $0.localizedName?.localizedCaseInsensitiveContains(appName) ?? false }
            guard let match else { return nil }
            match.activate()
            return match.processIdentifier
        }
    }

    private static func visibleAppNames() async -> [String] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.localizedName }
                .sorted()
        }
    }

    // MARK: - Capture

    struct WindowCapture {
        let image: CGImage
        let windowFrame: CGRect
        let windowTitle: String
    }

    private static func captureFrontWindow(ofProcess pid: pid_t, appName: String) async throws -> WindowCapture {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { window in
            window.owningApplication?.processID == pid
                && window.isOnScreen
                && window.windowLayer == 0
                && window.frame.width >= 80
                && window.frame.height >= 80
        }
        guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            throw VisionActionLoopError.captureFailed("no on-screen window found for \(appName) (pid \(pid))")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        configuration.showsCursor = false
        configuration.captureResolution = .nominal

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return WindowCapture(image: image, windowFrame: window.frame, windowTitle: window.title ?? "untitled")
    }

    private static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw VisionActionLoopError.captureFailed("could not create PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionActionLoopError.captureFailed("could not encode PNG")
        }
        return data as Data
    }

    // MARK: - Click synthesis

    private static func synthesizeClick(at point: CGPoint) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw VisionActionLoopError.captureFailed("could not create CGEventSource")
        }
        func post(_ type: CGEventType) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        post(.mouseMoved)
        try await Task.sleep(nanoseconds: 60_000_000)
        post(.leftMouseDown)
        try await Task.sleep(nanoseconds: 80_000_000)
        post(.leftMouseUp)
    }

    // MARK: - Prompt

    private static func decisionPrompt(
        request: VisionActionRequest,
        windowTitle: String,
        imageWidth: Int,
        imageHeight: Int,
        history: [String]
    ) -> String {
        let historyBlock = history.isEmpty ? "none yet" : history.joined(separator: "\n")
        return """
        You are a precise macOS UI vision agent. You see one screenshot of the window \"\(windowTitle)\" of the app \"\(request.appName)\". The screenshot is \(imageWidth)x\(imageHeight) pixels; the coordinate origin (0,0) is the TOP-LEFT corner, x grows right, y grows down.

        GOAL: \(request.goal)

        Actions already taken:
        \(historyBlock)

        Decide the single next action toward the goal. Reply with ONLY a JSON object, no markdown fences, no extra text:
        {"action":"click","x":<int>,"y":<int>,"target":"<visible label of the control>","rationale":"<one short sentence>"}
        Coordinates must be pixels inside this screenshot; click the CENTER of the target control.
        Use {"action":"done","x":null,"y":null,"target":"","rationale":"<why>"} when the goal is already visibly complete in this screenshot.
        Use {"action":"stuck","x":null,"y":null,"target":"","rationale":"<why>"} if no visible click can advance the goal.
        """
    }
}

// MARK: - Vision model client (Cerebras primary, Google hosted fallback)

struct VisionModelClient {
    enum Host: String {
        case cerebras
        case google
    }

    let host: Host
    let model: String
    private let apiKey: String
    private let session: URLSession

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) throws {
        let host = Host(rawValue: environment["SONNY_VISION_HOST"]?.lowercased() ?? "") ?? .cerebras
        self.host = host
        self.session = session
        switch host {
        case .cerebras:
            self.model = environment["SONNY_VISION_MODEL"] ?? "gemma-4-31b"
            guard let key = environment["CEREBRAS_API_KEY"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VisionActionLoopError.missingAPIKey("CEREBRAS_API_KEY")
            }
            self.apiKey = key
        case .google:
            self.model = environment["SONNY_VISION_MODEL"] ?? "gemma-4-31b-it"
            guard let key = environment["GEMINI_API_KEY"], !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VisionActionLoopError.missingAPIKey("GEMINI_API_KEY")
            }
            self.apiKey = key
        }
    }

    func decide(prompt: String, pngData: Data) async throws -> (reply: String, latencySeconds: Double) {
        let started = Date()
        let reply: String
        switch host {
        case .cerebras:
            reply = try await decideViaCerebras(prompt: prompt, pngData: pngData)
        case .google:
            reply = try await decideViaGoogle(prompt: prompt, pngData: pngData)
        }
        return (reply, Date().timeIntervalSince(started))
    }

    private func decideViaCerebras(prompt: String, pngData: Data) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(pngData.base64EncodedString())"]
                        ]
                    ]
                ]
            ]
        ]
        var request = URLRequest(url: URL(string: "https://api.cerebras.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        return try CerebrasChatResponseParser.messageContent(from: data)
    }

    private func decideViaGoogle(prompt: String, pngData: Data) async throws -> String {
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["inline_data": ["mime_type": "image/png", "data": pngData.base64EncodedString()]],
                        ["text": prompt]
                    ]
                ]
            ]
        ]
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw VisionActionLoopError.unparseableModelReply(String(data: data, encoding: .utf8) ?? "<unreadable body>")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw VisionActionLoopError.unparseableModelReply(String(data: data, encoding: .utf8) ?? "<unreadable body>")
        }
        return text
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionActionLoopError.badResponse(-1, "No HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw VisionActionLoopError.badResponse(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "<unreadable body>")
        }
        return data
    }
}

// MARK: - Model decision parsing (deliberately lenient — Gemma has no structured-output guarantee)

struct VisionDecision {
    enum Kind: String {
        case click
        case done
        case stuck
    }

    let kind: Kind
    let x: Int?
    let y: Int?
    let target: String
    let rationale: String

    static func parse(_ reply: String) throws -> VisionDecision {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              start < end else {
            throw VisionActionLoopError.unparseableModelReply(reply)
        }
        let jsonText = String(reply[start...end])
        guard let object = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
              let actionRaw = object["action"] as? String,
              let kind = Kind(rawValue: actionRaw.lowercased()) else {
            throw VisionActionLoopError.unparseableModelReply(reply)
        }
        func intValue(_ key: String) -> Int? {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? Double { return Int(value) }
            if let value = object[key] as? String { return Int(value) }
            return nil
        }
        return VisionDecision(
            kind: kind,
            x: intValue("x"),
            y: intValue("y"),
            target: object["target"] as? String ?? "",
            rationale: object["rationale"] as? String ?? ""
        )
    }
}
