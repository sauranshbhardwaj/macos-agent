import Foundation

public struct SnippetSaveCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.instant.snippet-save",
        displayName: "Save snippet",
        description: "Save an exact local snippet trigger without calling the model planner.",
        operations: [.saveSnippet],
        plannerTools: [],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try snippetSpec(in: plan)
        return [
            ActionPreview(
                title: "Save snippet",
                details: [
                    "Trigger: \(spec.trigger)",
                    "Expansion: \(spec.expansion)"
                ],
                writes: [context.snippetStore.fileURL.path]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let spec = try snippetSpec(in: plan)
        log(.act, "Saving snippet \(spec.trigger)")
        try context.snippetStore.save(
            StoredSnippet(
                trigger: spec.trigger,
                expansion: spec.expansion,
                updatedAt: context.now()
            )
        )
        log(.summarize, "Snippet saved")
        return AgentRunResult(
            plan: plan,
            previews: previews,
            summary: "Saved snippet \(spec.trigger)."
        )
    }

    private struct SnippetSpec {
        var trigger: String
        var expansion: String
    }

    private func snippetSpec(in plan: AgentPlan) throws -> SnippetSpec {
        guard let step = plan.steps.first(where: { $0.operation == .saveSnippet }) else {
            throw AgentExecutionError.invalidPlan("save_snippet step is missing.")
        }
        let trigger = step.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expansion = step.draftContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trigger.isEmpty else {
            throw SnippetStoreError.missingTrigger
        }
        guard !expansion.isEmpty else {
            throw SnippetStoreError.missingExpansion
        }
        return SnippetSpec(trigger: trigger, expansion: expansion)
    }
}
