import Foundation

@MainActor
public final class AgentRunner {
    private let planner: Planning
    private let executor: AgentActionExecutor
    private let logStore: AgentLogStore

    public init(
        planner: Planning,
        executor: AgentActionExecutor = AgentActionExecutor(),
        logStore: AgentLogStore = AgentLogStore()
    ) {
        self.planner = planner
        self.executor = executor
        self.logStore = logStore
    }

    public func prepare(command: String) async throws -> PreparedAgentRun {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentExecutionError.emptyCommand
        }

        logStore.reset()
        logStore.append(.plan, "Sending command to planner")
        let plan = try await planner.plan(command: trimmed)
        logStore.append(.observe, "Received plan: \(plan.summary)")
        logStore.append(.validate, "Validating whitelist and supported operations")
        let preparedRun = try executor.prepare(plan: plan)
        logStore.append(.preview, "Prepared \(preparedRun.previews.count) preview item(s)")
        return preparedRun
    }

    public func execute(
        _ preparedRun: PreparedAgentRun,
        confirmationMessage: String = "Execution approved"
    ) async throws -> AgentRunResult {
        logStore.append(.confirm, confirmationMessage)
        return try await executor.execute(plan: preparedRun.plan) { phase, message in
            self.logStore.append(phase, message)
        }
    }
}
