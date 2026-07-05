import Foundation

public struct OpenAllowlistedAppCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.apps.open-allowlisted-app",
        displayName: "Open allowlisted Mac app",
        description: "Open an app from the local allowlist by human app name.",
        operations: [.openApp],
        plannerTools: [
            AgentTool(
                operation: .openApp,
                name: "Open allowlisted Mac app",
                description: "Open an app from the local allowlist by human app name. Supported apps: \(MacAppCatalog.default.displayList).",
                requiredFields: ["appName"],
                sideEffects: ["open app"],
                dryRunBehavior: "Show the allowlisted app that would open.",
                examples: ["Open Safari", "Open Spotify", "Launch Apple Music"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .appOpening)
        ],
        defaultRiskTier: .tier1
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try spec(in: plan, context: context)
        return [
            ActionPreview(
                title: "Open \(spec.app.displayName)",
                details: [
                    "Bundle: \(spec.app.bundleIdentifier)",
                    "Allowed apps: \(context.appCatalog.displayList)"
                ],
                opens: [spec.app.displayName]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let spec = try spec(in: plan, context: context)
        log(.act, "Opening \(spec.app.displayName)")
        try await context.appOpener.open(bundleIdentifier: spec.app.bundleIdentifier)
        log(.summarize, "Opened \(spec.app.displayName)")
        return AgentRunResult(plan: plan, previews: previews, summary: "Opened \(spec.app.displayName).")
    }

    private struct AppSpec {
        var app: MacApp
    }

    private func spec(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> AppSpec {
        guard let step = plan.steps.first(where: { $0.operation == .openApp }) else {
            throw AgentExecutionError.invalidPlan("open_app step is missing.")
        }
        return AppSpec(app: try context.appCatalog.resolve(step.appName))
    }
}
