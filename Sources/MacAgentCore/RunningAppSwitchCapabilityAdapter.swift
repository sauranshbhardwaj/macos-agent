import Foundation

public struct RunningAppSwitchCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.instant.running-app-switch",
        displayName: "Switch running app",
        description: "Bring an already-running regular macOS app to the front without launching new apps.",
        operations: [.switchRunningApp],
        plannerTools: [],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .appOpening)
        ],
        defaultRiskTier: .tier1
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let app = try app(in: plan, context: context)
        return [
            ActionPreview(
                title: "Switch running app",
                details: [
                    "App: \(app.displayName)",
                    "Bundle: \(app.bundleIdentifier)"
                ],
                opens: [app.displayName]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let app = try app(in: plan, context: context)
        log(.act, "Switching to \(app.displayName)")
        try await context.runningAppSwitcher.activate(bundleIdentifier: app.bundleIdentifier)
        log(.summarize, "Switched running app")
        return AgentRunResult(
            plan: plan,
            previews: previews,
            summary: "Switched to \(app.displayName)."
        )
    }

    @MainActor
    private func app(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> RunningApp {
        guard let step = plan.steps.first(where: { $0.operation == .switchRunningApp }) else {
            throw AgentExecutionError.invalidPlan("switch_running_app step is missing.")
        }
        return try RunningAppMatcher.bestMatch(
            query: step.appName ?? step.searchQuery,
            in: context.runningAppSwitcher.runningApps()
        )
    }
}
