import Foundation

@MainActor
public final class AgentRunner {
    private let planner: Planning
    private let executor: AgentActionExecutor
    private let logStore: AgentLogStore
    private let approvalPolicy: RiskApprovalPolicy

    public init(
        planner: Planning,
        executor: AgentActionExecutor = AgentActionExecutor(),
        logStore: AgentLogStore = AgentLogStore(),
        approvalPolicy: RiskApprovalPolicy = .default
    ) {
        self.planner = planner
        self.executor = executor
        self.logStore = logStore
        self.approvalPolicy = approvalPolicy
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

    public func approvalRequest(for preparedRun: PreparedAgentRun) throws -> RiskApprovalRequest {
        let assessment = try executor.assessRisk(plan: preparedRun.plan)
        return RiskApprovalRequest(
            assessment: assessment,
            requirement: assessment.approvalRequirement(policy: approvalPolicy)
        )
    }

    public func execute(
        _ preparedRun: PreparedAgentRun,
        approvalDecision: RiskApprovalDecision = .notRequested,
        confirmationMessage: String = "Execution approved"
    ) async throws -> AgentRunResult {
        let request = try approvalRequest(for: preparedRun)
        switch request.requirement {
        case .autoRun:
            break
        case .lightweightConfirmation, .explicitApproval:
            guard approvalDecision == .approved else {
                logStore.append(.confirm, "Approval required for \(request.assessment.effectiveTier.displayName)")
                throw RiskApprovalError.approvalRequired(request)
            }
        case .previewOnly:
            logStore.append(.confirm, "Execution paused by preview-only approval policy")
            throw RiskApprovalError.previewOnly(request)
        case .refuse:
            logStore.append(.confirm, "Execution refused by approval policy")
            throw RiskApprovalError.refused(request)
        }

        logStore.append(.confirm, confirmationMessage)
        return try await executor.execute(plan: preparedRun.plan) { phase, message in
            self.logStore.append(phase, message)
        }
    }
}
