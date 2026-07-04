import Foundation

public struct RunRoutineCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.routines.run",
        displayName: "Run saved routine",
        description: "Load and run a saved routine through normal plan validation.",
        operations: [.runRoutine],
        plannerTools: [
            AgentTool(
                operation: .runRoutine,
                name: "Run saved routine",
                description: "Load a saved routine by name and execute its registered steps with the same validation and logging as normal plans.",
                requiredFields: ["routineName"],
                sideEffects: ["depends on saved routine"],
                dryRunBehavior: "Preview the saved routine without executing its steps.",
                examples: ["Run my morning setup routine"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let routine = try routineRunSpec(plan, context: context)
        let nested = try context.previewNestedPlan(routine.plan)
        return [
            ActionPreview(
                title: "Run routine \(routine.name)",
                details: ["Saved steps: \(routine.steps.count)"]
            )
        ] + nested
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let routine = try routineRunSpec(plan, context: context)
        log(.act, "Running routine \(routine.name)")
        let result = try await context.executeNestedPlan(routine.plan, log)
        return AgentRunResult(
            plan: plan,
            previews: try preview(plan: plan, context: context),
            summary: "Ran routine \(routine.name). \(result.summary)",
            suggestions: result.suggestions
        )
    }

    private func routineRunSpec(_ plan: AgentPlan, context: CapabilityExecutionContext) throws -> StoredRoutine {
        guard let step = plan.steps.first(where: { $0.operation == .runRoutine }) else {
            throw AgentExecutionError.invalidPlan("run_routine step is missing.")
        }
        return try context.routineStore.routine(named: step.routineName ?? "")
    }
}
