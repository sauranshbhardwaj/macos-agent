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

    var canSubmit: Bool {
        !isRunning && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func start() async {
        guard canSubmit else {
            return
        }

        isRunning = true
        errorMessage = nil
        finalSummary = ""
        plan = nil
        previews = []
        preparedRun = nil
        showConfirmation = false

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
        } catch {
            errorMessage = error.localizedDescription
            logStore.append(.summarize, "Stopped: \(error.localizedDescription)")
        }

        isRunning = false
    }

    func executeConfirmed() async {
        guard let preparedRun, let runner else {
            return
        }

        isRunning = true
        errorMessage = nil
        showConfirmation = false
        finalSummary = ""

        do {
            let result = try await runner.execute(preparedRun)
            finalSummary = result.summary
        } catch {
            errorMessage = error.localizedDescription
            logStore.append(.summarize, "Stopped: \(error.localizedDescription)")
        }

        isRunning = false
    }

    func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(finalSummary, forType: .string)
    }

    func reset() async {
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
