import AppKit
import Foundation
import MacAgentCore

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var command: String = ""
    @Published var dryRun: Bool = true
    @Published var isRunning: Bool = false
    @Published var plan: AgentPlan?
    @Published var previews: [ActionPreview] = []
    @Published var finalSummary: String = ""
    @Published var errorMessage: String?
    @Published var clarificationQuestion: String?
    @Published var clarificationAnswer: String = ""
    @Published var suggestions: [RunSuggestion] = []
    @Published var stepStatuses: [String: AgentStepStatus] = [:]
    @Published var voiceTranscript: String = ""
    @Published var isPreparingVoiceRecording: Bool = false
    @Published var isRecordingVoice: Bool = false
    @Published var isTranscribingVoice: Bool = false
    @Published var voiceHotKeyStatus: String = "Hold Ctrl-Opt-Space"
    @Published var voiceHotKeyReady: Bool = true
    @Published var showPermissionPanel: Bool = false
    @Published var permissionItems: [PermissionReadinessItem] = []

    let logStore = AgentLogStore()

    private var preparedRun: PreparedAgentRun?
    private var runner: AgentRunner?
    private var currentTask: Task<Void, Never>?
    private let audioRecorder = AudioCommandRecorder()
    private let permissionReadinessService = PermissionReadinessService()
    private var clarificationAutoExecute = false
    private var isPushToTalkHotKeyDown = false

    private enum VoiceRecordingTrigger {
        case button
        case hotKey
    }

    var hasAPIKey: Bool {
        !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var modelName: String {
        ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.5"
    }

    var transcriptionModelName: String {
        ProcessInfo.processInfo.environment["OPENAI_TRANSCRIBE_MODEL"] ?? "gpt-4o-mini-transcribe"
    }

    var setupStatus: String {
        hasAPIKey ? "Ready - \(modelName); voice - \(transcriptionModelName)" : "Missing OPENAI_API_KEY"
    }

    var canSubmit: Bool {
        !isRunning && !isTranscribingVoice && hasAPIKey && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCancel: Bool {
        isRunning && currentTask != nil
    }

    var canUseVoice: Bool {
        hasAPIKey && !isRunning && !isPreparingVoiceRecording && !isTranscribingVoice
    }

    var voiceButtonTitle: String {
        if isPreparingVoiceRecording {
            return "Starting"
        }
        if isRecordingVoice {
            return "Stop"
        }
        if isTranscribingVoice {
            return "Transcribing"
        }
        return "Speak"
    }

    var voiceButtonIcon: String {
        isRecordingVoice ? "stop.circle" : "mic"
    }

    var primaryButtonTitle: String { dryRun ? "Preview" : "Run" }

    var primaryButtonIcon: String { dryRun ? "eye" : "play" }

    func start(autoExecute: Bool = false) {
        guard canSubmit else {
            if !hasAPIKey {
                errorMessage = "OPENAI_API_KEY is not set. Export it before launching Sonny, then relaunch the app."
            }
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            await performStart(autoExecute: autoExecute)
        }
    }

    private func performStart(autoExecute: Bool) async {
        isRunning = true
        errorMessage = nil
        finalSummary = ""
        plan = nil
        previews = []
        suggestions = []
        clarificationQuestion = nil
        clarificationAnswer = ""
        preparedRun = nil
        stepStatuses = [:]

        defer {
            isRunning = false
            currentTask = nil
        }

        do {
            let planner = try OpenAIPlanner()
            let runner = AgentRunner(planner: planner, logStore: logStore)
            self.runner = runner

            let prepared = try await runner.prepare(command: command)
            preparedRun = prepared
            plan = prepared.plan
            previews = prepared.previews
            initializeStepStatuses(for: prepared.plan)

            if let question = prepared.clarificationQuestion {
                clarificationQuestion = question
                clarificationAutoExecute = autoExecute || !dryRun
                finalSummary = "Clarification needed before I can act."
                logStore.append(.summarize, "Clarification needed: \(question)")
                return
            }

            if dryRun {
                markAllSteps(.complete)
                finalSummary = "Dry run complete. No files were written, no apps were opened, and no documents were converted."
                logStore.append(.summarize, finalSummary)
            } else {
                let result = try await executePreparedRun(
                    preparedRun: prepared,
                    runner: runner,
                    confirmationMessage: autoExecute ? "Voice command auto-approved execution" : "Typed command auto-approved execution"
                )
                finalSummary = result.summary
                suggestions = result.suggestions
            }
        } catch is CancellationError {
            markAllSteps(.canceled)
            finalSummary = "Canceled."
            logStore.append(.summarize, "Canceled by user")
        } catch {
            markAllSteps(.failed)
            errorMessage = error.localizedDescription
            logStore.append(.summarize, "Stopped: \(error.localizedDescription)")
        }
    }

    func cancelCurrentRun() {
        currentTask?.cancel()
    }

    func submitClarification() {
        guard let question = clarificationQuestion else {
            return
        }

        let answer = clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            errorMessage = "Enter an answer before continuing."
            return
        }

        command = """
        \(command.trimmingCharacters(in: .whitespacesAndNewlines))

        Clarification question: \(question)
        Clarification answer: \(answer)
        """
        let shouldAutoExecute = clarificationAutoExecute
        clarificationAutoExecute = false
        clarificationQuestion = nil
        clarificationAnswer = ""
        start(autoExecute: shouldAutoExecute)
    }

    func toggleVoiceRecording() {
        if isRecordingVoice {
            stopVoiceRecordingAndTranscribe()
        } else {
            startVoiceRecording(trigger: .button)
        }
    }

    func beginPushToTalkVoice() {
        guard !isPushToTalkHotKeyDown else {
            return
        }
        guard canUseVoice else {
            if !hasAPIKey {
                errorMessage = "OPENAI_API_KEY is not set. Export it before launching Sonny, then relaunch the app."
            }
            return
        }

        isPushToTalkHotKeyDown = true
        startVoiceRecording(trigger: .hotKey)
    }

    func endPushToTalkVoice() {
        guard isPushToTalkHotKeyDown else {
            return
        }

        isPushToTalkHotKeyDown = false
        guard isRecordingVoice else {
            return
        }

        stopVoiceRecordingAndTranscribe()
    }

    func markVoiceHotKeyUnavailable(_ message: String) {
        voiceHotKeyReady = false
        voiceHotKeyStatus = "Hotkey unavailable"
        errorMessage = message
        refreshPermissions()
    }

    func refreshPermissions() {
        permissionItems = permissionReadinessService.currentStatus(
            hasAPIKey: hasAPIKey,
            hotKeyReady: voiceHotKeyReady
        )
    }

    func togglePermissionPanel() {
        refreshPermissions()
        showPermissionPanel.toggle()
    }

    func runSuggestion(_ suggestion: RunSuggestion) {
        let url = URL(fileURLWithPath: suggestion.value)
        switch suggestion.kind {
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openFile:
            NSWorkspace.shared.open(url)
        }
    }

    func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(finalSummary, forType: .string)
    }

    func reset() {
        currentTask?.cancel()
        audioRecorder.cancel()
        command = ""
        dryRun = true
        isRunning = false
        plan = nil
        previews = []
        finalSummary = ""
        errorMessage = nil
        clarificationQuestion = nil
        clarificationAnswer = ""
        clarificationAutoExecute = false
        suggestions = []
        stepStatuses = [:]
        voiceTranscript = ""
        isPreparingVoiceRecording = false
        isRecordingVoice = false
        isTranscribingVoice = false
        isPushToTalkHotKeyDown = false
        showPermissionPanel = false
        refreshPermissions()
        preparedRun = nil
        runner = nil
        logStore.reset()
    }

    private func startVoiceRecording(trigger: VoiceRecordingTrigger) {
        guard canUseVoice else {
            if !hasAPIKey {
                errorMessage = "OPENAI_API_KEY is not set. Export it before launching Sonny, then relaunch the app."
            }
            return
        }

        isPreparingVoiceRecording = true

        Task {
            let granted = await AudioCommandRecorder.requestMicrophonePermission()
            guard granted else {
                isPreparingVoiceRecording = false
                errorMessage = "Microphone permission was denied. Allow microphone access for the launching app, then try again."
                return
            }

            if trigger == .hotKey && !isPushToTalkHotKeyDown {
                isPreparingVoiceRecording = false
                return
            }

            do {
                try audioRecorder.start()
                if trigger == .hotKey && !isPushToTalkHotKeyDown {
                    audioRecorder.cancel()
                    isPreparingVoiceRecording = false
                    return
                }

                isPreparingVoiceRecording = false
                isRecordingVoice = true
                voiceTranscript = ""
                finalSummary = ""
                errorMessage = nil
                let recordingMessage = trigger == .hotKey
                    ? "Recording voice command from hotkey"
                    : "Recording voice command"
                logStore.append(.observe, recordingMessage)
            } catch {
                isPreparingVoiceRecording = false
                errorMessage = error.localizedDescription
                logStore.append(.summarize, "Voice recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopVoiceRecordingAndTranscribe() {
        let audioURL: URL
        do {
            audioURL = try audioRecorder.stop()
            isRecordingVoice = false
        } catch {
            isRecordingVoice = false
            isPushToTalkHotKeyDown = false
            errorMessage = error.localizedDescription
            return
        }

        Task {
            isTranscribingVoice = true
            errorMessage = nil
            logStore.append(.act, "Transcribing voice command")
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }

            do {
                let transcriber = try OpenAITranscriber()
                let result = try await transcriber.transcribe(audioFileURL: audioURL)
                command = result.text
                voiceTranscript = result.text
                dryRun = false
                finalSummary = ""
                isTranscribingVoice = false
                logStore.append(.observe, "Transcript ready. Sonny will act now.")
                start(autoExecute: true)
            } catch {
                isTranscribingVoice = false
                errorMessage = error.localizedDescription
                logStore.append(.summarize, "Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    private func executePreparedRun(
        preparedRun: PreparedAgentRun,
        runner: AgentRunner,
        confirmationMessage: String
    ) async throws -> AgentRunResult {
        markAllSteps(.running)
        let result = try await runner.execute(preparedRun, confirmationMessage: confirmationMessage)
        markAllSteps(.complete)
        return result
    }

    private func initializeStepStatuses(for plan: AgentPlan) {
        stepStatuses = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, AgentStepStatus.pending) })
    }

    private func markAllSteps(_ status: AgentStepStatus) {
        guard !stepStatuses.isEmpty else {
            return
        }
        stepStatuses = Dictionary(uniqueKeysWithValues: stepStatuses.keys.map { ($0, status) })
    }
}

enum AgentStepStatus: String {
    case pending
    case running
    case complete
    case failed
    case canceled
}
