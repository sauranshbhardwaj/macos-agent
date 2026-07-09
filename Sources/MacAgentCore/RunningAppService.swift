import AppKit
import Foundation

public struct RunningApp: Equatable, Sendable {
    public var displayName: String
    public var bundleIdentifier: String
    public var processIdentifier: Int32

    public init(displayName: String, bundleIdentifier: String, processIdentifier: Int32) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public enum RunningAppSwitchError: Error, Equatable, LocalizedError {
    case missingQuery
    case noMatchingRunningApp(String)
    case failedToActivate(String)

    public var errorDescription: String? {
        switch self {
        case .missingQuery:
            return "Switching apps requires a running app name."
        case .noMatchingRunningApp(let query):
            return "No running app matched \(query)."
        case .failedToActivate(let app):
            return "Could not switch to \(app)."
        }
    }
}

@MainActor
public protocol RunningAppSwitching: AnyObject {
    func runningApps() -> [RunningApp]
    func activate(bundleIdentifier: String) async throws
}

@MainActor
public final class WorkspaceRunningAppSwitcher: RunningAppSwitching {
    public init() {}

    public func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  let displayName = app.localizedName,
                  let bundleIdentifier = app.bundleIdentifier else {
                return nil
            }
            return RunningApp(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: app.processIdentifier
            )
        }
    }

    public func activate(bundleIdentifier: String) async throws {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw RunningAppSwitchError.noMatchingRunningApp(bundleIdentifier)
        }
        let didActivate = app.activate(options: [.activateAllWindows])
        guard didActivate else {
            throw RunningAppSwitchError.failedToActivate(app.localizedName ?? bundleIdentifier)
        }
    }
}

public enum RunningAppMatcher {
    public static func bestMatch(query rawQuery: String?, in apps: [RunningApp]) throws -> RunningApp {
        guard let rawQuery else {
            throw RunningAppSwitchError.missingQuery
        }
        let query = normalize(rawQuery)
        guard !query.isEmpty else {
            throw RunningAppSwitchError.missingQuery
        }

        if let exact = apps.first(where: { normalize($0.displayName) == query || normalize($0.bundleIdentifier) == query }) {
            return exact
        }

        if let prefix = apps.first(where: {
            normalize($0.displayName).hasPrefix(query) || normalize($0.bundleIdentifier).hasPrefix(query)
        }) {
            return prefix
        }

        if let contains = apps.first(where: {
            normalize($0.displayName).contains(query) || normalize($0.bundleIdentifier).contains(query)
        }) {
            return contains
        }

        throw RunningAppSwitchError.noMatchingRunningApp(rawQuery)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }
}
