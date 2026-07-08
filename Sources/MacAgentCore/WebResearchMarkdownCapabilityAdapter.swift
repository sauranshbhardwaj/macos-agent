import Foundation

public struct WebResearchMarkdownCapabilityAdapter: CapabilityAdapter {
    public init() {}

    public var metadata: CapabilityMetadata {
        Self.metadata
    }

    public static let metadata = CapabilityMetadata(
        id: "local.web.research-markdown",
        displayName: "Web research Markdown",
        description: "Fetch public web pages, synthesize a research note, and save Markdown with source links.",
        operations: [.webToMarkdown],
        plannerTools: [
            AgentTool(
                operation: .webToMarkdown,
                name: "Web page to Markdown",
                description: "Fetch one public http/https URL, or multiple http/https sourceURLs for comparison, synthesize a research note, and save Markdown in a whitelisted output path.",
                requiredFields: ["targetURL or sourceURLs"],
                sideEffects: ["network request", "send fetched public page content to OpenAI", "write file"],
                dryRunBehavior: "Show source URL(s) and Markdown output path without fetching pages or writing files.",
                examples: [
                    "Summarize https://example.com/article and save as Markdown",
                    "Compare these source URLs and save a Markdown note"
                ]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .networkAccess),
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess)
        ],
        defaultRiskTier: .tier2
    )

    public func resolveDefaultOutputs(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> AgentPlan {
        var resolvedPlan = plan
        guard let stepIndex = resolvedPlan.steps.firstIndex(where: { $0.operation == .webToMarkdown }) else {
            return resolvedPlan
        }

        resolvedPlan.steps[stepIndex].outputPath = try spec(in: resolvedPlan, context: context).outputURL.path
        return resolvedPlan
    }

    public func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        let spec = try spec(in: plan, context: context)
        return [
            ActionPreview(
                title: spec.sourceURLs.count == 1 ? "Save web article Markdown" : "Save web comparison Markdown",
                details: [
                    "Sources: \(spec.sourceURLs.map(\.absoluteString).joined(separator: ", "))",
                    "Save Markdown to \(spec.outputURL.path)"
                ],
                writes: [spec.outputURL.path]
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
        let resolvedPlan = try resolveDefaultOutputs(in: plan, context: context)
        let previews = try preview(plan: resolvedPlan, context: context)
        let spec = try spec(in: resolvedPlan, context: context)

        var pages: [ReadableWebPage] = []
        for sourceURL in spec.sourceURLs {
            log(.act, "Fetching \(sourceURL.absoluteString)")
            let page = try await context.webPageLoader.load(rawURL: sourceURL.absoluteString)
            log(.observe, "Extracted readable content from \(page.sourceURL.absoluteString)")
            pages.append(page)
        }

        let prompt = WebResearchPromptBuilder.prompt(
            trustedPlan: resolvedPlan,
            trustedUserInstruction: spec.instruction,
            pages: pages
        )
        log(.act, "Synthesizing web research note")
        let note = try await context.webResearchSynthesizer.synthesize(prompt: prompt)
        let markdown = WebResearchMarkdownWriter.markdown(note: note, pages: pages, generatedAt: context.now())
        try Data(markdown.utf8).write(to: spec.outputURL, options: .atomic)
        log(.summarize, "Saved web research Markdown")

        let summary = spec.sourceURLs.count == 1
            ? "Saved web research Markdown to \(spec.outputURL.path)."
            : "Saved comparison Markdown for \(spec.sourceURLs.count) sources to \(spec.outputURL.path)."
        return AgentRunResult(
            plan: resolvedPlan,
            previews: previews,
            summary: summary,
            suggestions: suggestions(for: spec)
        )
    }

    private struct WebResearchSpec {
        var sourceURLs: [URL]
        var outputURL: URL
        var instruction: String
    }

    private func spec(in plan: AgentPlan, context: CapabilityExecutionContext) throws -> WebResearchSpec {
        guard let step = plan.steps.first(where: { $0.operation == .webToMarkdown }) else {
            throw AgentExecutionError.invalidPlan("web_to_markdown step is missing.")
        }

        let sourceURLStrings = try sourceStrings(in: step)
        let sourceURLs = try sourceURLStrings.map { try SafeURL.validateWebURL($0) }
        let outputURL = try outputURL(for: step.outputPath, context: context)
        let instruction = [plan.summary, step.description]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Create a concise Markdown research note from the supplied web source(s)."

        return WebResearchSpec(sourceURLs: sourceURLs, outputURL: outputURL, instruction: instruction)
    }

    private func sourceStrings(in step: AgentStep) throws -> [String] {
        let fromList = (step.sourceURLs ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !fromList.isEmpty {
            return fromList
        }

        if let targetURL = step.targetURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !targetURL.isEmpty {
            return [targetURL]
        }

        throw AgentExecutionError.invalidPlan("web_to_markdown needs targetURL or sourceURLs.")
    }

    private func outputURL(for rawOutput: String?, context: CapabilityExecutionContext) throws -> URL {
        if let rawOutput, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (rawOutput as NSString).expandingTildeInPath
            if context.fileManager.fileExists(atPath: expanded) {
                let url = try context.whitelist.validateInsideWhitelist(rawOutput)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    return url.appendingPathComponent("web-research-\(Timestamp.fileSafe(context.now())).md")
                }
                return try context.whitelist.validateOutputPath(rawOutput)
            }
            return try context.whitelist.validateOutputPath(rawOutput)
        }

        return try context.whitelist.defaultOutputFile(
            name: "web-research-\(Timestamp.fileSafe(context.now()))",
            extension: "md"
        )
    }

    private func suggestions(for spec: WebResearchSpec) -> [RunSuggestion] {
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

public enum WebResearchMarkdownWriter {
    public static func markdown(note: WebResearchNote, pages: [ReadableWebPage], generatedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "# \(escape(note.title))",
            "",
            "Generated: \(formatter.string(from: generatedAt))",
            ""
        ]

        if !note.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Summary")
            lines.append("")
            lines.append(escape(note.summary))
            lines.append("")
        }

        if !note.keyPoints.isEmpty {
            lines.append("## Key Points")
            lines.append("")
            for point in note.keyPoints {
                lines.append("- \(escape(point))")
            }
            lines.append("")
        }

        if !note.citations.isEmpty {
            lines.append("## Citations")
            lines.append("")
            for citation in note.citations {
                lines.append("- \(escape(citation))")
            }
            lines.append("")
        }

        lines.append("## Sources")
        lines.append("")
        for page in pages {
            lines.append("- [\(escape(page.title))](\(page.sourceURL.absoluteString))")
            lines.append("  - Retrieved: \(formatter.string(from: page.retrievedAt))")
            if let author = page.author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("  - Author: \(escape(author))")
            }
            if let publishedDate = page.publishedDate, !publishedDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("  - Published: \(escape(publishedDate))")
            }
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }
}
