import AppKit
import Foundation

public struct RevealInFinderCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.finder.reveal-path",
        displayName: "Reveal in Finder",
        description: "Reveal a whitelisted path in Finder.",
        operations: [.revealInFinder],
        plannerTools: [
            AgentTool(
                operation: .revealInFinder,
                name: "Reveal path in Finder",
                description: "Reveal a specific whitelisted path in Finder, or reveal the most recent file produced earlier in the same chain when outputPath is null.",
                requiredFields: [],
                sideEffects: ["open Finder"],
                dryRunBehavior: "Show the path that would be revealed.",
                examples: ["Reveal the zip in Finder", "Show the generated Markdown in Finder"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess),
            CapabilityPermissionMetadata(requirement: .appOpening)
        ],
        defaultRiskTier: .tier1
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let url = try revealSpec(in: plan, context: context, requiresExistingPath: false)
        return [
            ActionPreview(
                title: "Reveal in Finder",
                details: ["Reveal \(url.path)"],
                opens: ["Finder"]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let url = try revealSpec(in: plan, context: context, requiresExistingPath: true)
        log(.act, "Revealing \(url.path) in Finder")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        log(.summarize, "Revealed in Finder")
        let summary = "Revealed \(url.path) in Finder."
        return AgentRunResult(plan: plan, previews: previews, summary: summary)
    }

    private func revealSpec(
        in plan: AgentPlan,
        context: CapabilityExecutionContext,
        requiresExistingPath: Bool
    ) throws -> URL {
        guard let step = plan.steps.first(where: { $0.operation == .revealInFinder }) else {
            throw AgentExecutionError.invalidPlan("reveal_in_finder step is missing.")
        }

        if let rawPath = step.outputPath ?? step.inputPath,
           !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = try context.whitelist.validateInsideWhitelist(rawPath)
            guard !requiresExistingPath || context.fileManager.fileExists(atPath: url.path) else {
                throw PathValidationError.notFound(url.path)
            }
            return url
        }

        throw AgentExecutionError.invalidPlan("reveal_in_finder needs outputPath or a previous chained artifact.")
    }
}
