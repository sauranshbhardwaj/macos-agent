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

    public func approvalRequest(
        for preparedRun: PreparedAgentRun,
        logAssessment: Bool = false
    ) throws -> RiskApprovalRequest {
        let assessment = try executor.assessRisk(plan: preparedRun.plan)
        let request = RiskApprovalRequest(
            assessment: assessment,
            requirement: assessment.approvalRequirement(policy: approvalPolicy)
        )
        if logAssessment {
            logRiskAssessment(request)
        }
        return request
    }

    public func execute(
        _ preparedRun: PreparedAgentRun,
        approvalDecision: RiskApprovalDecision = .notRequested,
        confirmationMessage: String = "Execution approved",
        logRiskAssessment: Bool = true
    ) async throws -> AgentRunResult {
        let request = try approvalRequest(for: preparedRun, logAssessment: logRiskAssessment)
        switch request.requirement {
        case .autoRun:
            break
        case .lightweightConfirmation, .explicitApproval:
            guard case .approved(let approvedTier) = approvalDecision,
                  approvedTier.rawValue >= request.assessment.effectiveTier.rawValue else {
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

    private func logRiskAssessment(_ request: RiskApprovalRequest) {
        let assessment = request.assessment
        logStore.append(
            .risk,
            "risk.assessed: \(assessment.effectiveTier.displayName) (\(assessment.effectiveTier.semanticName)); approval: \(request.requirement.displayName)"
        )

        for escalation in assessment.escalations {
            logStore.append(
                .risk,
                "risk.escalated: \(escalation.fromTier.displayName) -> \(escalation.toTier.displayName): \(escalation.reason)"
            )
        }
    }
}
