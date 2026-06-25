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

    let logStore = AgentLogStore()

    private var preparedRun: PreparedAgentRun?
    private var runner: AgentRunner?
    private var currentTask: Task<Void, Never>?

    var hasAPIKey: Bool {
        !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var modelName: String {
        ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.5"
    }

    var setupStatus: String {
        hasAPIKey ? "OpenAI ready - \(modelName)" : "Missing OPENAI_API_KEY"
    }

    var canSubmit: Bool {
        !isRunning && hasAPIKey && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCancel: Bool {
        isRunning && currentTask != nil
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
        preparedRun = nil
        showConfirmation = false

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

            if dryRun {
                finalSummary = "Dry run complete. No files were written, no apps were opened, and no documents were converted."
                logStore.append(.summarize, finalSummary)
            } else {
                showConfirmation = true
            }
        } catch is CancellationError {
            finalSummary = "Canceled."
            logStore.append(.summarize, "Canceled by user")
        } catch {
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
            let result = try await runner.execute(preparedRun)
            finalSummary = result.summary
        } catch is CancellationError {
            finalSummary = "Canceled."
            logStore.append(.summarize, "Canceled by user")
        } catch {
            errorMessage = error.localizedDescription
            logStore.append(.summarize, "Stopped: \(error.localizedDescription)")
        }
    }

    func cancelCurrentRun() {
        currentTask?.cancel()
        showConfirmation = false
    }

    func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(finalSummary, forType: .string)
    }

    func reset() {
        currentTask?.cancel()
        command = ""
        dryRun = true
        isRunning = false
        plan = nil
        previews = []
        finalSummary = ""
        errorMessage = nil
        showConfirmation = false
        preparedRun = nil
        runner = nil
        logStore.reset()
    }
}
