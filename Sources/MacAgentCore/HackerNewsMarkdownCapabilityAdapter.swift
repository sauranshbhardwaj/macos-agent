import Foundation

public struct HackerNewsMarkdownCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.web.hacker-news-markdown",
        displayName: "Hacker News Markdown",
        description: "Open Hacker News, fetch top headlines, and save them as Markdown.",
        operations: [.openHackerNews, .fetchHNHeadlines, .writeMarkdown],
        plannerTools: [
            AgentTool(
                operation: .openHackerNews,
                name: "Open Hacker News",
                description: "Open Hacker News in the default browser as part of the headline workflow.",
                requiredFields: [],
                sideEffects: ["open browser"],
                dryRunBehavior: "Show that Hacker News would open.",
                examples: ["Open Hacker News"]
            ),
            AgentTool(
                operation: .fetchHNHeadlines,
                name: "Fetch Hacker News headlines",
                description: "Fetch the top Hacker News headlines from the public API.",
                requiredFields: ["count"],
                sideEffects: ["network request"],
                dryRunBehavior: "Show the number of headlines that would be fetched.",
                examples: ["Grab the top 5 headlines"]
            ),
            AgentTool(
                operation: .writeMarkdown,
                name: "Write Markdown file",
                description: "Write fetched Hacker News headlines to Markdown in a whitelisted output path.",
                requiredFields: [],
                sideEffects: ["write file"],
                dryRunBehavior: "Show the Markdown path without writing it.",
                examples: ["Save to a Markdown file"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .browserOpening),
            CapabilityPermissionMetadata(requirement: .networkAccess),
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess)
        ],
        defaultRiskTier: .tier2
    )

    public func resolveDefaultOutputs(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> AgentPlan {
        var resolvedPlan = plan
        guard let markdownIndex = resolvedPlan.steps.firstIndex(where: { $0.operation == .writeMarkdown }) else {
            return resolvedPlan
        }

        resolvedPlan.steps[markdownIndex].outputPath = try spec(in: resolvedPlan, context: context).outputURL.path
        return resolvedPlan
    }

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try spec(in: plan, context: context)
        return [
            ActionPreview(
                title: "Fetch Hacker News top \(spec.count)",
                details: [
                    "Open https://news.ycombinator.com",
                    "Fetch top \(spec.count) headlines",
                    "Save Markdown to \(spec.outputURL.path)"
                ],
                writes: [spec.outputURL.path],
                opens: [Self.hackerNewsURL.absoluteString]
            )
        ]
    }

    public func assessRisk(plan: AgentPlan, context: CapabilityExecutionContext) throws -> CapabilityRiskAssessment {
        let spec = try spec(in: plan, context: context)
        let escalations = context.fileManager.fileExists(atPath: spec.outputURL.path)
            ? [
                CapabilityRiskEscalation(
                    fromTier: metadata.defaultRiskTier,
                    toTier: .tier3,
                    reason: "Markdown output already exists at \(spec.outputURL.path)."
                )
            ]
            : []
        return CapabilityRiskAssessment(defaultTier: metadata.defaultRiskTier, escalations: escalations)
    }

    public func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan, context: context)
        let spec = try spec(in: plan, context: context)
        log(.act, "Opening Hacker News")
        try await context.browserOpener.open(Self.hackerNewsURL)
        log(.act, "Fetching top \(spec.count) headlines")
        let headlines = try await context.hackerNewsFetcher.topHeadlines(limit: spec.count)
        log(.observe, "Fetched \(headlines.count) headlines")
        let markdown = MarkdownWriter.hackerNewsMarkdown(headlines: headlines, date: context.now())
        try markdown.data(using: .utf8)?.write(to: spec.outputURL, options: .atomic)
        log(.summarize, "Saved Markdown")

        let summary = "Saved \(headlines.count) Hacker News headlines to \(spec.outputURL.path)."
        return AgentRunResult(plan: plan, previews: previews, summary: summary, suggestions: suggestions(for: spec))
    }

    private static let hackerNewsURL = URL(string: "https://news.ycombinator.com")!

    private struct HackerNewsSpec {
        var count: Int
        var outputURL: URL
    }

    private func spec(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> HackerNewsSpec {
        let writeStep = plan.steps.first { $0.operation == .writeMarkdown }
        let fetchStep = plan.steps.first { $0.operation == .fetchHNHeadlines }
        let count = max(fetchStep?.count ?? writeStep?.count ?? 5, 1)

        let outputURL: URL
        if let rawOutput = writeStep?.outputPath, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (rawOutput as NSString).expandingTildeInPath
            if context.fileManager.fileExists(atPath: expanded) {
                let url = try context.whitelist.validateInsideWhitelist(rawOutput)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    outputURL = url.appendingPathComponent("hacker-news-\(Timestamp.fileSafe(context.now())).md")
                } else {
                    outputURL = try context.whitelist.validateOutputPath(rawOutput)
                }
            } else {
                outputURL = try context.whitelist.validateOutputPath(rawOutput)
            }
        } else {
            outputURL = try context.whitelist.defaultOutputFile(
                name: "hacker-news-\(Timestamp.fileSafe(context.now()))",
                extension: "md"
            )
        }

        return HackerNewsSpec(count: count, outputURL: outputURL)
    }

    private func suggestions(for spec: HackerNewsSpec) -> [RunSuggestion] {
        [
            RunSuggestion(
                title: "Open Markdown",
                kind: .openFile,
                value: spec.outputURL.path
            ),
            RunSuggestion(
                title: "Reveal Markdown in Finder",
                kind: .revealInFinder,
                value: spec.outputURL.path
            )
        ]
    }
}
