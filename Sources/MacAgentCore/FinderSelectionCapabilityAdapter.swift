import Foundation

public struct FinderSelectionCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.finder.read-selection",
        displayName: "Read Finder selection",
        description: "Read selected Finder items and validate them against the path whitelist.",
        operations: [.getFinderSelection],
        plannerTools: [
            AgentTool(
                operation: .getFinderSelection,
                name: "Read Finder selection",
                description: "Read selected Finder files and folders, validate that every path is inside the Desktop/Documents whitelist, and show them as context.",
                requiredFields: [],
                sideEffects: ["ask Finder for selection"],
                dryRunBehavior: "Show selected Finder items without modifying them.",
                examples: ["What is selected in Finder?", "Show my Finder selection"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .finderAutomation),
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess)
        ],
        defaultRiskTier: .tier0
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let selection = try whitelistedSelection(context: context)
        return [
            ActionPreview(
                title: "Finder selection",
                details: selection.map(\.path)
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        log(.act, "Reading Finder selection")
        let selection = try whitelistedSelection(context: context)
        log(.observe, "Found \(selection.count) selected item(s)")
        let summary = "Finder selection contains \(selection.count) whitelisted item(s)."
        return AgentRunResult(plan: plan, previews: previews, summary: summary)
    }

    private func whitelistedSelection(context: CapabilityExecutionContext) throws -> [URL] {
        try FinderSelectionResolver.whitelistedSelection(
            whitelist: context.whitelist,
            finderContextReader: context.finderContextReader
        )
    }
}
