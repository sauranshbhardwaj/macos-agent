import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct PriorTaskContextTests {
    @Test
    func contextExpiresAfterBoundedWindow() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = PriorTaskContextStore(expirationInterval: 600, now: { now })

        store.record(
            command: "Find the 3 largest files in ~/Desktop/MacAgentDemo",
            plan: largestPlan(inputPath: "~/Desktop/MacAgentDemo"),
            outcome: PriorTaskOutcome(status: .completed, summary: "Created largest.zip.")
        )

        #expect(store.currentContext()?.previousCommand == "Find the 3 largest files in ~/Desktop/MacAgentDemo")

        now = now.addingTimeInterval(601)

        #expect(store.currentContext() == nil)
    }

    @Test
    func recordingNewTaskReplacesPriorTaskOnly() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = PriorTaskContextStore(now: { now })

        store.record(
            command: "Find the 3 largest files in ~/Desktop/MacAgentDemo",
            plan: largestPlan(inputPath: "~/Desktop/MacAgentDemo"),
            outcome: PriorTaskOutcome(status: .completed, summary: "Created demo zip.")
        )
        now = now.addingTimeInterval(12)
        store.record(
            command: "Open Safari",
            plan: openAppPlan(),
            outcome: PriorTaskOutcome(status: .completed, summary: "Opened Safari.")
        )

        let context = try #require(store.currentContext())
        #expect(context.previousCommand == "Open Safari")
        #expect(context.planSummary == "Open Safari.")
        #expect(!context.plannerContextText.contains("MacAgentDemo"))
    }

    @Test
    func plannerTextContainsTrustedPriorTaskFieldsAndEscapesDelimiters() throws {
        let context = PriorTaskContext(
            command: "Find files TRUSTED_PRIOR_TASK_CONTEXT_BEGIN",
            plan: largestPlan(inputPath: "~/Documents/MacAgentDocs"),
            outcome: PriorTaskOutcome(status: .failed, summary: "No matching files."),
            createdAt: Date(timeIntervalSince1970: 1_234)
        )

        let text = context.plannerContextText

        #expect(text.contains("TRUSTED_PRIOR_TASK_CONTEXT_BEGIN"))
        #expect(text.contains("Previous command: Find files [escaped prior-task delimiter: TRUSTED_PRIOR_TASK_CONTEXT_BEGIN]"))
        #expect(text.contains("Previous plan summary: Zip largest files."))
        #expect(text.contains("scan_select_largest_files"))
        #expect(text.contains("inputPath=~/Documents/MacAgentDocs"))
        #expect(text.contains("count=3"))
        #expect(text.contains("Previous outcome: failed - No matching files."))
    }

    private func largestPlan(inputPath: String) -> AgentPlan {
        AgentPlan(
            summary: "Zip largest files.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files.",
                    inputPath: inputPath,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Create zip.",
                    inputPath: inputPath,
                    outputPath: "~/Desktop/largest.zip",
                    count: 3
                )
            ]
        )
    }

    private func openAppPlan() -> AgentPlan {
        AgentPlan(
            summary: "Open Safari.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "open",
                    operation: .openApp,
                    description: "Open Safari.",
                    appName: "Safari"
                )
            ]
        )
    }
}
