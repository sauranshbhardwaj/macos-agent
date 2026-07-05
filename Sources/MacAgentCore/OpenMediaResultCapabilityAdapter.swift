import Foundation

public struct OpenMediaResultCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.media.open-result",
        displayName: "Open music result",
        description: "Open Apple Music or Spotify result/search URLs without starting playback.",
        operations: [.playMedia],
        plannerTools: [
            AgentTool(
                operation: .playMedia,
                name: "Open music result",
                description: "Open a requested song or album in Apple Music or Spotify without starting playback. Apple Music opens the best matching catalog album result when found, otherwise search. Spotify opens a supplied Spotify result URI or a Spotify search.",
                requiredFields: ["mediaProvider", "mediaTitle"],
                sideEffects: ["open music app"],
                dryRunBehavior: "Show the provider, title, artist, and result/search behavior without opening an app.",
                examples: [
                    "Open Jimmy Cooks by Drake on Apple Music",
                    "Open Bad Habit by Steve Lacy on Spotify"
                ]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .appOpening),
            CapabilityPermissionMetadata(requirement: .networkAccess)
        ],
        defaultRiskTier: .tier1
    )

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try mediaSpec(plan)
        return [
            ActionPreview(
                title: "Open \(spec.request.displayTitle)",
                details: [
                    "Provider: \(spec.request.provider.displayName)",
                    spec.behaviorDescription
                ],
                opens: [spec.request.provider.displayName]
            )
        ]
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let spec = try mediaSpec(plan)
        log(.act, "Opening \(spec.request.provider.displayName) result for \(spec.request.displayTitle)")
        let summary = try await context.mediaOpener.open(spec.request)
        log(.summarize, summary)
        return AgentRunResult(plan: plan, previews: previews, summary: summary)
    }

    private struct MediaSpec {
        var request: MediaPlaybackRequest
        var behaviorDescription: String
    }

    private func mediaSpec(_ plan: AgentPlan) throws -> MediaSpec {
        guard let step = plan.steps.first(where: { $0.operation == .playMedia }) else {
            throw AgentExecutionError.invalidPlan("play_media step is missing.")
        }
        guard let provider = step.mediaProvider else {
            throw MediaPlaybackError.missingProvider
        }
        guard let rawTitle = step.mediaTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty else {
            throw MediaPlaybackError.missingTitle
        }

        let artist = step.mediaArtist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MediaPlaybackRequest(
            provider: provider,
            title: rawTitle,
            artist: artist?.isEmpty == false ? artist : nil,
            mediaURI: step.targetURL
        )

        let behavior: String
        switch provider {
        case .appleMusic:
            behavior = "Opens the best matching Apple Music album result, or Apple Music search if no match is found."
        case .spotify:
            if let mediaURI = request.mediaURI, !mediaURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                behavior = "Opens the supplied Spotify result URI."
            } else {
                behavior = "Opens Spotify search for the requested song or album."
            }
        }

        return MediaSpec(request: request, behaviorDescription: behavior)
    }
}
