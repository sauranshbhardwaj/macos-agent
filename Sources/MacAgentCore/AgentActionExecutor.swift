import Foundation

public enum AgentExecutionError: Error, LocalizedError, Equatable {
    case emptyCommand
    case unsupported(String)
    case missingPath(String)
    case invalidPlan(String)
    case noMatchingFiles(String)
    case missingClarificationQuestion

    public var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "Enter a natural-language command first."
        case .unsupported(let detail):
            return detail
        case .missingPath(let operation):
            return "\(operation) needs a folder path."
        case .invalidPlan(let detail):
            return "The generated plan is invalid: \(detail)"
        case .noMatchingFiles(let detail):
            return detail
        case .missingClarificationQuestion:
            return "The planner asked for clarification but did not include a question."
        }
    }
}

public struct PreparedAgentRun: Equatable, Sendable {
    public var plan: AgentPlan
    public var previews: [ActionPreview]
    public var clarificationQuestion: String?

    public init(plan: AgentPlan, previews: [ActionPreview], clarificationQuestion: String? = nil) {
        self.plan = plan
        self.previews = previews
        self.clarificationQuestion = clarificationQuestion
    }

    public var sideEffects: [String] {
        previews.flatMap(\.sideEffects)
    }
}

@MainActor
public final class AgentActionExecutor {
    private let whitelist: PathWhitelist
    private let inventory: FileInventory
    private let zipArchiver: ZipArchiving
    private let documentConverter: DocumentConverting
    private let browserOpener: BrowserOpening
    private let hackerNewsFetcher: HackerNewsFetching
    private let appCatalog: MacAppCatalog
    private let appOpener: AppOpening
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        whitelist: PathWhitelist = PathWhitelist(),
        inventory: FileInventory = FileInventory(),
        zipArchiver: ZipArchiving = ProcessZipArchiver(),
        documentConverter: DocumentConverting = AutoDocumentConverter(),
        browserOpener: BrowserOpening = WorkspaceBrowserOpener(),
        hackerNewsFetcher: HackerNewsFetching = HackerNewsAPIClient(),
        appCatalog: MacAppCatalog = .default,
        appOpener: AppOpening = WorkspaceAppOpener(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.whitelist = whitelist
        self.inventory = inventory
        self.zipArchiver = zipArchiver
        self.documentConverter = documentConverter
        self.browserOpener = browserOpener
        self.hackerNewsFetcher = hackerNewsFetcher
        self.appCatalog = appCatalog
        self.appOpener = appOpener
        self.fileManager = fileManager
        self.now = now
    }

    public func prepare(plan: AgentPlan) throws -> PreparedAgentRun {
        if let question = try clarificationQuestion(in: plan) {
            let preview = ActionPreview(
                title: "Clarification needed",
                details: [question]
            )
            return PreparedAgentRun(plan: plan, previews: [preview], clarificationQuestion: question)
        }

        let resolvedPlan = try resolveDefaultOutputs(in: plan)
        let previews = try preview(plan: resolvedPlan)
        return PreparedAgentRun(plan: resolvedPlan, previews: previews)
    }

    public func preview(plan: AgentPlan) throws -> [ActionPreview] {
        switch try workflow(in: plan) {
        case .clarify:
            guard let question = try clarificationQuestion(in: plan) else {
                throw AgentExecutionError.missingClarificationQuestion
            }
            return [
                ActionPreview(
                    title: "Clarification needed",
                    details: [question]
                )
            ]
        case .largestFiles:
            return [try previewLargestFiles(plan)]
        case .docx:
            return [try previewDocxConversion(plan)]
        case .hackerNews:
            return [try previewHackerNews(plan)]
        case .openApp:
            return [try previewOpenApp(plan)]
        case .openURL:
            return [try previewOpenURL(plan)]
        }
    }

    public func execute(
        plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let resolvedPlan = try resolveDefaultOutputs(in: plan)
        let previews = try preview(plan: resolvedPlan)

        switch try workflow(in: resolvedPlan) {
        case .clarify:
            throw AgentExecutionError.missingClarificationQuestion
        case .largestFiles:
            let summary = try await executeLargestFiles(resolvedPlan, log: log)
            let suggestions = try largestFileSuggestions(resolvedPlan)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary, suggestions: suggestions)
        case .docx:
            let summary = try await executeDocxConversion(resolvedPlan, log: log)
            let suggestions = try docxSuggestions(resolvedPlan)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary, suggestions: suggestions)
        case .hackerNews:
            let summary = try await executeHackerNews(resolvedPlan, log: log)
            let suggestions = try hackerNewsSuggestions(resolvedPlan)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary, suggestions: suggestions)
        case .openApp:
            let summary = try await executeOpenApp(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .openURL:
            let summary = try await executeOpenURL(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        }
    }

    private enum Workflow: Equatable {
        case clarify
        case largestFiles
        case docx
        case hackerNews
        case openApp
        case openURL
    }

    private func workflow(in plan: AgentPlan) throws -> Workflow {
        try validateSupported(plan)

        let workflows = Set(try plan.steps.map { step in
            try workflow(for: step.operation)
        })

        guard workflows.count == 1, let workflow = workflows.first else {
            throw AgentExecutionError.invalidPlan("A plan must contain exactly one supported workflow.")
        }

        return workflow
    }

    private func workflow(for operation: AgentOperation) throws -> Workflow {
        switch operation {
        case .clarify:
            return .clarify
        case .scanSelectLargestFiles, .createZip:
            return .largestFiles
        case .scanDocx, .convertDocxToPDF:
            return .docx
        case .openHackerNews, .fetchHNHeadlines, .writeMarkdown:
            return .hackerNews
        case .openApp:
            return .openApp
        case .openURL:
            return .openURL
        case .unsupported:
            throw AgentExecutionError.unsupported("Unsupported operation.")
        }
    }

    private func clarificationQuestion(in plan: AgentPlan) throws -> String? {
        guard try workflow(in: plan) == .clarify else {
            return nil
        }

        guard let question = plan.steps.first(where: { $0.operation == .clarify })?.question?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !question.isEmpty else {
            throw AgentExecutionError.missingClarificationQuestion
        }

        return question
    }

    private func resolveDefaultOutputs(in plan: AgentPlan) throws -> AgentPlan {
        _ = try workflow(in: plan)
        var resolvedPlan = plan

        if let zipIndex = resolvedPlan.steps.firstIndex(where: { $0.operation == .createZip }) {
            let outputPath = resolvedPlan.steps[zipIndex].outputPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            if outputPath?.isEmpty != false {
                resolvedPlan.steps[zipIndex].outputPath = try largestFileSpec(resolvedPlan).outputURL.path
            }
        }

        if let markdownIndex = resolvedPlan.steps.firstIndex(where: { $0.operation == .writeMarkdown }) {
            resolvedPlan.steps[markdownIndex].outputPath = try hackerNewsSpec(resolvedPlan).outputURL.path
        }

        return resolvedPlan
    }

    private func validateSupported(_ plan: AgentPlan) throws {
        if let unsupported = plan.steps.first(where: { $0.operation == .unsupported }) {
            throw AgentExecutionError.unsupported(unsupported.description)
        }
    }

    private func previewLargestFiles(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try largestFileSpec(plan)
        let files = try inventory.largestFiles(in: spec.folder, count: spec.count)
        guard !files.isEmpty else {
            throw AgentExecutionError.noMatchingFiles("No regular files were found in \(spec.folder.path).")
        }

        return ActionPreview(
            title: "Zip \(files.count) largest files",
            details: files.map { "\($0.url.pathRelative(to: spec.folder)) (\($0.displaySize))" },
            writes: [spec.outputURL.path]
        )
    }

    private func executeLargestFiles(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try largestFileSpec(plan)
        log(.act, "Scanning \(spec.folder.path) for regular files")
        let files = try inventory.largestFiles(in: spec.folder, count: spec.count)
        guard !files.isEmpty else {
            throw AgentExecutionError.noMatchingFiles("No regular files were found in \(spec.folder.path).")
        }

        log(.observe, "Selected \(files.count) files")
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        let totalSize = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        log(.act, "Creating \(spec.outputURL.path) from \(files.count) files (\(totalSize))")
        try await zipArchiver.createArchive(sourceFolder: spec.folder, files: files.map(\.url), outputURL: spec.outputURL)
        log(.summarize, "Created zip archive")
        return "Created \(spec.outputURL.lastPathComponent) with \(files.count) largest files from \(spec.folder.path)."
    }

    private func previewDocxConversion(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try docxSpec(plan)
        let records = try inventory.docxFiles(
            in: spec.folder,
            outputFolder: spec.outputFolder,
            mockDestinations: spec.usesMockDestinations
        )
        guard !records.isEmpty else {
            throw AgentExecutionError.noMatchingFiles("No .docx files were found in \(spec.folder.path).")
        }

        let pending = records.filter { !$0.skippedBecausePDFExists }
        let skipped = records.filter(\.skippedBecausePDFExists)

        return ActionPreview(
            title: "Convert \(pending.count) DOCX files",
            details: [
                "Converter: \(documentConverter.modeName)",
                "Found \(records.count) .docx files",
                "Skipping \(skipped.count) existing PDFs"
            ],
            writes: pending.map(\.destinationURL.path),
            conversions: pending.map { "\($0.sourceURL.path) -> \($0.destinationURL.path)" }
        )
    }

    private func executeDocxConversion(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try docxSpec(plan)
        log(.act, "Scanning \(spec.folder.path) for .docx files")
        let records = try inventory.docxFiles(
            in: spec.folder,
            outputFolder: spec.outputFolder,
            mockDestinations: spec.usesMockDestinations
        )
        guard !records.isEmpty else {
            throw AgentExecutionError.noMatchingFiles("No .docx files were found in \(spec.folder.path).")
        }

        let pending = records.filter { !$0.skippedBecausePDFExists }
        let skipped = records.count - pending.count
        log(.observe, "Found \(records.count) .docx files, skipping \(skipped) existing PDFs")
        guard !pending.isEmpty else {
            log(.summarize, "No DOCX files needed conversion")
            return "No DOCX files needed conversion in \(spec.folder.path). Skipped \(skipped) existing PDF outputs."
        }
        log(.act, "Starting \(pending.count) conversion(s) with \(documentConverter.modeName)")
        let converted = try await documentConverter.convert(records) { message in
            log(.act, message)
        }
        log(.summarize, "Converted \(converted.count) files")
        return "Converted \(converted.count) DOCX files from \(spec.folder.path). Skipped \(skipped) existing PDF outputs."
    }

    private func previewHackerNews(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try hackerNewsSpec(plan)
        return ActionPreview(
            title: "Fetch Hacker News top \(spec.count)",
            details: [
                "Open https://news.ycombinator.com",
                "Fetch top \(spec.count) headlines",
                "Save Markdown to \(spec.outputURL.path)"
            ],
            writes: [spec.outputURL.path],
            opens: ["https://news.ycombinator.com"]
        )
    }

    private func executeHackerNews(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try hackerNewsSpec(plan)
        let hnURL = URL(string: "https://news.ycombinator.com")!
        log(.act, "Opening Hacker News")
        try await browserOpener.open(hnURL)
        log(.act, "Fetching top \(spec.count) headlines")
        let headlines = try await hackerNewsFetcher.topHeadlines(limit: spec.count)
        log(.observe, "Fetched \(headlines.count) headlines")
        let markdown = MarkdownWriter.hackerNewsMarkdown(headlines: headlines, date: now())
        try markdown.data(using: .utf8)?.write(to: spec.outputURL, options: .atomic)
        log(.summarize, "Saved Markdown")
        return "Saved \(headlines.count) Hacker News headlines to \(spec.outputURL.path)."
    }

    private func previewOpenApp(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try appSpec(plan)
        return ActionPreview(
            title: "Open \(spec.app.displayName)",
            details: [
                "Bundle: \(spec.app.bundleIdentifier)",
                "Allowed apps: \(appCatalog.displayList)"
            ],
            opens: [spec.app.displayName]
        )
    }

    private func executeOpenApp(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try appSpec(plan)
        log(.act, "Opening \(spec.app.displayName)")
        try await appOpener.open(bundleIdentifier: spec.app.bundleIdentifier)
        log(.summarize, "Opened \(spec.app.displayName)")
        return "Opened \(spec.app.displayName)."
    }

    private func previewOpenURL(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try urlSpec(plan)
        return ActionPreview(
            title: "Open URL",
            details: ["Open \(spec.url.absoluteString)"],
            opens: [spec.url.absoluteString]
        )
    }

    private func executeOpenURL(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try urlSpec(plan)
        log(.act, "Opening \(spec.url.absoluteString)")
        try await browserOpener.open(spec.url)
        log(.summarize, "Opened URL")
        return "Opened \(spec.url.absoluteString)."
    }

    private func largestFileSuggestions(_ plan: AgentPlan) throws -> [RunSuggestion] {
        let spec = try largestFileSpec(plan)
        return [
            RunSuggestion(
                title: "Reveal zip in Finder",
                kind: .revealInFinder,
                value: spec.outputURL.path
            )
        ]
    }

    private func docxSuggestions(_ plan: AgentPlan) throws -> [RunSuggestion] {
        let spec = try docxSpec(plan)
        return [
            RunSuggestion(
                title: "Reveal PDFs in Finder",
                kind: .revealInFinder,
                value: spec.outputFolder?.path ?? spec.folder.path
            )
        ]
    }

    private func hackerNewsSuggestions(_ plan: AgentPlan) throws -> [RunSuggestion] {
        let spec = try hackerNewsSpec(plan)
        return [
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

    private struct LargestFileSpec {
        var folder: URL
        var count: Int
        var outputURL: URL
    }

    private func largestFileSpec(_ plan: AgentPlan) throws -> LargestFileSpec {
        let scanStep = plan.steps.first { $0.operation == .scanSelectLargestFiles }
        let zipStep = plan.steps.first { $0.operation == .createZip }
        guard let folderPath = scanStep?.inputPath ?? zipStep?.inputPath else {
            throw AgentExecutionError.missingPath("largest file scan")
        }

        let folder = try whitelist.validateExistingDirectory(folderPath)
        let count = max(scanStep?.count ?? zipStep?.count ?? 3, 1)
        let outputURL: URL
        if let rawOutput = zipStep?.outputPath, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputURL = try whitelist.validateOutputPath(rawOutput)
        } else {
            outputURL = folder.appendingPathComponent("largest-files-\(Timestamp.fileSafe(now())).zip")
        }

        return LargestFileSpec(folder: folder, count: count, outputURL: outputURL)
    }

    private struct DocxSpec {
        var folder: URL
        var outputFolder: URL?
        var usesMockDestinations: Bool
    }

    private func docxSpec(_ plan: AgentPlan) throws -> DocxSpec {
        let scanStep = plan.steps.first { $0.operation == .scanDocx }
        let convertStep = plan.steps.first { $0.operation == .convertDocxToPDF }
        guard let folderPath = scanStep?.inputPath ?? convertStep?.inputPath else {
            throw AgentExecutionError.missingPath("DOCX conversion")
        }

        let folder = try whitelist.validateExistingDirectory(folderPath)
        var outputFolder: URL?
        if let rawOutput = convertStep?.outputPath, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputFolder = try whitelist.validateExistingDirectory(rawOutput)
        }

        let usesMock = !MicrosoftWordDocumentConverter().isAvailable &&
            ProcessInfo.processInfo.environment["MAC_AGENT_MOCK_DOCX"] == "1"
        return DocxSpec(folder: folder, outputFolder: outputFolder, usesMockDestinations: usesMock)
    }

    private struct HackerNewsSpec {
        var count: Int
        var outputURL: URL
    }

    private struct AppSpec {
        var app: MacApp
    }

    private func appSpec(_ plan: AgentPlan) throws -> AppSpec {
        guard let step = plan.steps.first(where: { $0.operation == .openApp }) else {
            throw AgentExecutionError.invalidPlan("open_app step is missing.")
        }
        return AppSpec(app: try appCatalog.resolve(step.appName))
    }

    private struct URLSpec {
        var url: URL
    }

    private func urlSpec(_ plan: AgentPlan) throws -> URLSpec {
        guard let step = plan.steps.first(where: { $0.operation == .openURL }) else {
            throw AgentExecutionError.invalidPlan("open_url step is missing.")
        }
        return URLSpec(url: try SafeURL.validateWebURL(step.targetURL))
    }

    private func hackerNewsSpec(_ plan: AgentPlan) throws -> HackerNewsSpec {
        let writeStep = plan.steps.first { $0.operation == .writeMarkdown }
        let fetchStep = plan.steps.first { $0.operation == .fetchHNHeadlines }
        let count = max(fetchStep?.count ?? writeStep?.count ?? 5, 1)

        let outputURL: URL
        if let rawOutput = writeStep?.outputPath, !rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = (rawOutput as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expanded) {
                let url = try whitelist.validateInsideWhitelist(rawOutput)
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    outputURL = url.appendingPathComponent("hacker-news-\(Timestamp.fileSafe(now())).md")
                } else {
                    outputURL = try whitelist.validateOutputPath(rawOutput)
                }
            } else {
                outputURL = try whitelist.validateOutputPath(rawOutput)
            }
        } else {
            outputURL = try whitelist.defaultOutputFile(name: "hacker-news-\(Timestamp.fileSafe(now()))", extension: "md")
        }

        return HackerNewsSpec(count: count, outputURL: outputURL)
    }
}
