import Foundation

public struct CreateWorkspaceCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.workspaces.create",
        displayName: "Create workspace launcher",
        description: "Save a named workspace of allowlisted apps and safe URLs.",
        operations: [.createWorkspace],
        plannerTools: [
            AgentTool(
                operation: .createWorkspace,
                name: "Create workspace launcher",
                description: "Save a named workspace containing allowlisted apps and safe http/https URLs.",
                requiredFields: ["workspaceName"],
                sideEffects: ["write local workspace file"],
                dryRunBehavior: "Show the workspace apps and URLs without saving.",
                examples: ["Create a workspace called research with Safari, VS Code, and https://github.com"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let workspace = try workspaceCreateSpec(plan, context: context)
        return [
            ActionPreview(
                title: "Save workspace \(workspace.name)",
                details: [
                    "Apps: \(workspace.apps.isEmpty ? "none" : workspace.apps.joined(separator: ", "))",
                    "URLs: \(workspace.urls.isEmpty ? "none" : workspace.urls.joined(separator: ", "))"
                ],
                writes: [context.workspaceStore.fileURL.path]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let workspace = try workspaceCreateSpec(plan, context: context)
        log(.act, "Saving workspace \(workspace.name)")
        try context.workspaceStore.save(workspace)
        log(.summarize, "Saved workspace")
        let summary = "Saved workspace \(workspace.name) with \(workspace.apps.count) app(s) and \(workspace.urls.count) URL(s)."
        return AgentRunResult(plan: plan, previews: previews, summary: summary)
    }

    private func workspaceCreateSpec(_ plan: AgentPlan, context: CapabilityExecutionContext) throws -> StoredWorkspace {
        guard let step = plan.steps.first(where: { $0.operation == .createWorkspace }) else {
            throw AgentExecutionError.invalidPlan("create_workspace step is missing.")
        }
        guard let name = step.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw AutomationStoreError.missingName("Workspace")
        }

        let apps = step.workspaceApps ?? []
        let urls = step.workspaceURLs ?? []
        guard !apps.isEmpty || !urls.isEmpty else {
            throw AutomationStoreError.emptyWorkspace
        }

        for app in apps {
            _ = try context.appCatalog.resolve(app)
        }
        for url in urls {
            _ = try SafeURL.validateWebURL(url)
        }

        return StoredWorkspace(name: name, apps: apps, urls: urls)
    }
}
