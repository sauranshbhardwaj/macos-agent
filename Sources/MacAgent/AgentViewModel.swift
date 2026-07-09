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
    @Published var savedRoutines: [StoredRoutine] = []
    @Published var savedWorkspaces: [StoredWorkspace] = []
    @Published var approvalRequest: RiskApprovalRequest?
    @Published var showClipboardHistoryNotice: Bool = false
    @Published var clipboardHistoryEnabled: Bool = true

    let logStore = AgentLogStore()

    private var preparedRun: PreparedAgentRun?
    private var runner: AgentRunner?
    private var currentTask: Task<Void, Never>?
    private let audioRecorder = AudioCommandRecorder()
    private let permissionReadinessService = PermissionReadinessService()
    private let routineStore = RoutineStore()
    private let workspaceStore = WorkspaceStore()
    private let snippetStore = SnippetStore()
    private let recentArtifactStore = RecentArtifactStore()
    private let shortcutCatalog: any ShortcutCatalogProviding = ProcessShortcutCatalog()
    private let shortcutRunHistoryStore = ShortcutRunHistoryStore()
    private let clipboardHistorySettingsStore = ClipboardHistorySettingsStore()
    private let clipboardHistoryMonitor = ClipboardHistoryMonitor()
    private var clipboardHistoryTimer: Timer?
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
        if isAwaitingApproval {
            return !isRunning && preparedRun != nil && runner != nil
        }
        return !isRunning && !isTranscribingVoice && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCancel: Bool {
        isAwaitingApproval || (isRunning && currentTask != nil)
    }

    var canUseVoice: Bool {
        hasAPIKey && !isAwaitingApproval && !isRunning && !isPreparingVoiceRecording && !isTranscribingVoice
    }

    var isAwaitingApproval: Bool {
        approvalRequest != nil
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

    var primaryButtonTitle: String {
        if isAwaitingApproval {
            return "Approve"
        }
        return dryRun ? "Preview" : "Run"
    }

    var primaryButtonIcon: String {
        if isAwaitingApproval {
            return "checkmark.shield"
        }
        return dryRun ? "eye" : "play"
    }

    func start(autoExecute: Bool = false) {
        if isAwaitingApproval {
            approvePendingRun()
            return
        }

        guard canSubmit else {
            if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Enter a natural-language command first."
            }
            return
        }

        currentTask?.cancel()
        isRunning = true
        currentTask = Task {
            await performStart(autoExecute: autoExecute)
        }
    }

    private func performStart(autoExecute: Bool) async {
        errorMessage = nil
        finalSummary = ""
        plan = nil
        previews = []
        suggestions = []
        clarificationQuestion = nil
        clarificationAnswer = ""
        preparedRun = nil
        approvalRequest = nil
        stepStatuses = [:]

        defer {
            isRunning = false
            currentTask = nil
        }

        do {
            let submittedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let executor = makeExecutor()
            let runner: AgentRunner
            let prepared: PreparedAgentRun

            if let resolution = makeInstantCommandResolver().resolve(command: submittedCommand) {
                runner = AgentRunner(
                    planner: InstantOnlyFallbackPlanner(),
                    executor: executor,
                    logStore: logStore,
                    recentArtifactStore: recentArtifactStore
                )
                switch resolution {
                case .plan(let localPlan), .clarify(let localPlan):
                    prepared = try runner.prepare(plan: localPlan, source: .instantResolver)
                }
            } else {
                let planner = try OpenAIPlanner()
                runner = AgentRunner(
                    planner: planner,
                    executor: executor,
                    logStore: logStore,
                    recentArtifactStore: recentArtifactStore
                )
                prepared = try await runner.prepare(command: submittedCommand)
            }
            self.runner = runner

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
                let request = try runner.approvalRequest(for: prepared, logAssessment: true)
                switch request.requirement {
                case .autoRun:
                    break
                case .lightweightConfirmation, .explicitApproval:
                    approvalRequest = request
                    finalSummary = "Approval needed before Sonny can act."
                    logStore.append(.confirm, "Approval required for \(request.assessment.effectiveTier.displayName)")
                    return
                case .previewOnly:
                    markAllSteps(.complete)
                    finalSummary = "Preview complete. The current approval policy does not allow this action to run automatically."
                    logStore.append(.summarize, finalSummary)
                    return
                case .refuse:
                    markAllSteps(.failed)
                    errorMessage = "Sonny refused this action under the current approval policy."
                    logStore.append(.summarize, "Refused by approval policy")
                    return
                }

                let result = try await executePreparedRun(
                    preparedRun: prepared,
                    runner: runner,
                    approvalDecision: .notRequested,
                    confirmationMessage: autoExecute ? "Voice command auto-approved execution" : "Typed command auto-approved execution",
                    logRiskAssessment: false
                )
                finalSummary = result.summary
                suggestions = result.suggestions
                refreshSavedItems()
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
        if isAwaitingApproval {
            approvalRequest = nil
            preparedRun = nil
            runner = nil
            markAllSteps(.canceled)
            finalSummary = "Approval canceled. No action was taken."
            logStore.append(.summarize, "Approval canceled by user")
            return
        }

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

    func refreshSavedItems() {
        savedRoutines = ((try? routineStore.loadAll().values.map { $0 }) ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        savedWorkspaces = ((try? workspaceStore.loadAll().values.map { $0 }) ?? [])
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func refreshClipboardHistoryNotice() {
        let settings = (try? clipboardHistorySettingsStore.load()) ?? ClipboardHistorySettings()
        clipboardHistoryEnabled = settings.isEnabled
        showClipboardHistoryNotice = !settings.noticeDismissed

        if settings.noticeDismissed && settings.isEnabled {
            startClipboardHistoryMonitoring()
        } else {
            stopClipboardHistoryMonitoring()
        }
    }

    func applyClipboardHistoryNoticeChoice() {
        let settings = ClipboardHistorySettings(
            noticeDismissed: true,
            isEnabled: clipboardHistoryEnabled
        )
        do {
            try clipboardHistorySettingsStore.save(settings)
            showClipboardHistoryNotice = false
            if clipboardHistoryEnabled {
                startClipboardHistoryMonitoring()
            } else {
                stopClipboardHistoryMonitoring()
            }
        } catch {
            errorMessage = "Could not save clipboard history setting: \(error.localizedDescription)"
        }
    }

    func runRoutineWidget(_ routine: StoredRoutine) {
        command = "Run my \(routine.name) routine."
        dryRun = false
        start(autoExecute: true)
    }

    func openWorkspaceWidget(_ workspace: StoredWorkspace) {
        command = "Open my \(workspace.name) workspace."
        dryRun = false
        start(autoExecute: true)
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
        approvalRequest = nil
        suggestions = []
        stepStatuses = [:]
        voiceTranscript = ""
        isPreparingVoiceRecording = false
        isRecordingVoice = false
        isTranscribingVoice = false
        isPushToTalkHotKeyDown = false
        showPermissionPanel = false
        refreshPermissions()
        refreshSavedItems()
        refreshClipboardHistoryNotice()
        preparedRun = nil
        runner = nil
        logStore.reset()
    }

    private func startClipboardHistoryMonitoring() {
        guard clipboardHistoryTimer == nil else {
            return
        }

        _ = try? clipboardHistoryMonitor.poll()
        clipboardHistoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                _ = try? self.clipboardHistoryMonitor.poll()
            }
        }
    }

    private func stopClipboardHistoryMonitoring() {
        clipboardHistoryTimer?.invalidate()
        clipboardHistoryTimer = nil
    }

    private func makeInstantCommandResolver() -> InstantCommandResolver {
        InstantCommandResolver(
            snippetStore: snippetStore,
            recentArtifactStore: recentArtifactStore,
            routineStore: routineStore,
            workspaceStore: workspaceStore,
            shortcutCatalog: shortcutCatalog
        )
    }

    private func makeExecutor() -> AgentActionExecutor {
        AgentActionExecutor(
            routineStore: routineStore,
            workspaceStore: workspaceStore,
            snippetStore: snippetStore,
            recentArtifactStore: recentArtifactStore,
            shortcutCatalog: shortcutCatalog,
            shortcutRunHistoryStore: shortcutRunHistoryStore
        )
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
        approvalDecision: RiskApprovalDecision,
        confirmationMessage: String,
        logRiskAssessment: Bool
    ) async throws -> AgentRunResult {
        markAllSteps(.running)
        let result = try await runner.execute(
            preparedRun,
            approvalDecision: approvalDecision,
            confirmationMessage: confirmationMessage,
            logRiskAssessment: logRiskAssessment
        )
        markAllSteps(.complete)
        return result
    }

    private func approvePendingRun() {
        guard !isRunning, let preparedRun, let runner, let approvalRequest else {
            return
        }

        currentTask?.cancel()
        isRunning = true
        currentTask = Task {
            await performApproval(preparedRun: preparedRun, runner: runner, approvalRequest: approvalRequest)
        }
    }

    private func performApproval(
        preparedRun: PreparedAgentRun,
        runner: AgentRunner,
        approvalRequest: RiskApprovalRequest
    ) async {
        errorMessage = nil
        finalSummary = ""
        self.approvalRequest = nil

        defer {
            isRunning = false
            currentTask = nil
        }

        do {
            let result = try await executePreparedRun(
                preparedRun: preparedRun,
                runner: runner,
                approvalDecision: .approved(approvalRequest.assessment.effectiveTier),
                confirmationMessage: "User approved \(approvalRequest.assessment.effectiveTier.displayName) action",
                logRiskAssessment: true
            )
            finalSummary = result.summary
            suggestions = result.suggestions
            refreshSavedItems()
        } catch is CancellationError {
            markAllSteps(.canceled)
            finalSummary = "Canceled."
            logStore.append(.summarize, "Canceled by user")
        } catch RiskApprovalError.approvalRequired(let request) {
            markAllSteps(.pending)
            self.approvalRequest = request
            finalSummary = "Approval needed before Sonny can act."
            logStore.append(.confirm, "Approval required for \(request.assessment.effectiveTier.displayName)")
        } catch {
            markAllSteps(.failed)
            errorMessage = error.localizedDescription
            logStore.append(.summarize, "Stopped: \(error.localizedDescription)")
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

@MainActor
private struct InstantOnlyFallbackPlanner: Planning {
    func plan(command: String) async throws -> AgentPlan {
        throw PlannerError.missingAPIKey
    }
}
