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
    @Published var showConfirmation: Bool = false
    @Published var clarificationQuestion: String?
    @Published var clarificationAnswer: String = ""
    @Published var suggestions: [RunSuggestion] = []
    @Published var stepStatuses: [String: AgentStepStatus] = [:]
    @Published var voiceTranscript: String = ""
    @Published var isRecordingVoice: Bool = false
    @Published var isTranscribingVoice: Bool = false

    let logStore = AgentLogStore()

    private var preparedRun: PreparedAgentRun?
    private var runner: AgentRunner?
    private var currentTask: Task<Void, Never>?
    private let audioRecorder = AudioCommandRecorder()

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
        hasAPIKey ? "OpenAI ready - \(modelName); voice - \(transcriptionModelName)" : "Missing OPENAI_API_KEY"
    }

    var canSubmit: Bool {
        !isRunning && !isTranscribingVoice && hasAPIKey && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCancel: Bool {
        isRunning && currentTask != nil
    }

    var canUseVoice: Bool {
        hasAPIKey && !isRunning && !isTranscribingVoice
    }

    var voiceButtonTitle: String {
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

    var primaryButtonTitle: String {
        dryRun ? "Preview" : "Plan"
    }

    var primaryButtonIcon: String {
        dryRun ? "eye" : "play"
    }

    var confirmationItems: [String] {
        preparedRun?.sideEffects ?? []
    }

    func start() {
        guard canSubmit else {
            if !hasAPIKey {
                errorMessage = "OPENAI_API_KEY is not set. Export it before launching MacAgent, then relaunch the app."
            }
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            await performStart()
        }
    }

    private func performStart() async {
        isRunning = true
        errorMessage = nil
        finalSummary = ""
        plan = nil
        previews = []
        suggestions = []
        clarificationQuestion = nil
        clarificationAnswer = ""
        preparedRun = nil
        showConfirmation = false
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
                finalSummary = "Clarification needed before I can act."
                logStore.append(.summarize, "Clarification needed: \(question)")
                return
            }

            if dryRun {
                markAllSteps(.complete)
                finalSummary = "Dry run complete. No files were written, no apps were opened, and no documents were converted."
                logStore.append(.summarize, finalSummary)
            } else {
                showConfirmation = true
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

    func executeConfirmed() {
        guard let preparedRun, let runner else {
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            await performExecuteConfirmed(preparedRun: preparedRun, runner: runner)
        }
    }

    private func performExecuteConfirmed(preparedRun: PreparedAgentRun, runner: AgentRunner) async {
        isRunning = true
        errorMessage = nil
        showConfirmation = false
        finalSummary = ""

        defer {
            isRunning = false
            currentTask = nil
        }

        do {
            markAllSteps(.running)
            let result = try await runner.execute(preparedRun)
            finalSummary = result.summary
            suggestions = result.suggestions
            markAllSteps(.complete)
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
        showConfirmation = false
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
        clarificationQuestion = nil
        clarificationAnswer = ""
        start()
    }

    func toggleVoiceRecording() {
        if isRecordingVoice {
            stopVoiceRecordingAndTranscribe()
        } else {
            startVoiceRecording()
        }
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
        showConfirmation = false
        clarificationQuestion = nil
        clarificationAnswer = ""
        suggestions = []
        stepStatuses = [:]
        voiceTranscript = ""
        isRecordingVoice = false
        isTranscribingVoice = false
        preparedRun = nil
        runner = nil
        logStore.reset()
    }

    private func startVoiceRecording() {
        guard canUseVoice else {
            if !hasAPIKey {
                errorMessage = "OPENAI_API_KEY is not set. Export it before launching MacAgent, then relaunch the app."
            }
            return
        }

        Task {
            let granted = await AudioCommandRecorder.requestMicrophonePermission()
            guard granted else {
                errorMessage = "Microphone permission was denied. Allow microphone access for the launching app, then try again."
                return
            }

            do {
                try audioRecorder.start()
                isRecordingVoice = true
                voiceTranscript = ""
                finalSummary = ""
                errorMessage = nil
                logStore.append(.observe, "Recording voice command")
            } catch {
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
            errorMessage = error.localizedDescription
            return
        }

        Task {
            isTranscribingVoice = true
            errorMessage = nil
            logStore.append(.act, "Transcribing voice command")
            defer {
                isTranscribingVoice = false
                try? FileManager.default.removeItem(at: audioURL)
            }

            do {
                let transcriber = try OpenAITranscriber()
                let result = try await transcriber.transcribe(audioFileURL: audioURL)
                command = result.text
                voiceTranscript = result.text
                finalSummary = "Transcript ready. Review or edit it, then preview the plan."
                logStore.append(.observe, "Transcript ready")
            } catch {
                errorMessage = error.localizedDescription
                logStore.append(.summarize, "Transcription failed: \(error.localizedDescription)")
            }
        }
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
