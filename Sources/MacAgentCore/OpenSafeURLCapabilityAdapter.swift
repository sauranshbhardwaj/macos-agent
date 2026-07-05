import Foundation

public struct OpenSafeURLCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.browser.open-url",
        displayName: "Open safe web URL",
        description: "Open a validated http or https URL in the default browser.",
        operations: [.openURL],
        plannerTools: [
            AgentTool(
                operation: .openURL,
                name: "Open web URL",
                description: "Open a safe http or https URL in the default browser.",
                requiredFields: ["targetURL"],
                sideEffects: ["open browser"],
                dryRunBehavior: "Show the URL that would open.",
                examples: ["Open GitHub", "Open https://gmail.com"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .browserOpening)
        ],
        defaultRiskTier: .tier1
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try spec(in: plan)
        return [
            ActionPreview(
                title: "Open URL",
                details: ["Open \(spec.url.absoluteString)"],
                opens: [spec.url.absoluteString]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let spec = try spec(in: plan)
        log(.act, "Opening \(spec.url.absoluteString)")
        try await context.browserOpener.open(spec.url)
        log(.summarize, "Opened URL")
        return AgentRunResult(plan: plan, previews: previews, summary: "Opened \(spec.url.absoluteString).")
    }

    private struct URLSpec {
        var url: URL
    }

    private func spec(in plan: AgentPlan) throws -> URLSpec {
        guard let step = plan.steps.first(where: { $0.operation == .openURL }) else {
            throw AgentExecutionError.invalidPlan("open_url step is missing.")
        }
        return URLSpec(url: try SafeURL.validateWebURL(step.targetURL))
    }
}
