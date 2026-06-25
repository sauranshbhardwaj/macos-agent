import Foundation

public enum AgentExecutionError: Error, LocalizedError, Equatable {
    case emptyCommand
    case unsupported(String)
    case missingPath(String)
    case invalidPlan(String)
    case noMatchingFiles(String)

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
        }
    }
}

public struct PreparedAgentRun: Equatable, Sendable {
    public var plan: AgentPlan
    public var previews: [ActionPreview]

    public init(plan: AgentPlan, previews: [ActionPreview]) {
        self.plan = plan
        self.previews = previews
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
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        whitelist: PathWhitelist = PathWhitelist(),
        inventory: FileInventory = FileInventory(),
        zipArchiver: ZipArchiving = ProcessZipArchiver(),
        documentConverter: DocumentConverting = AutoDocumentConverter(),
        browserOpener: BrowserOpening = WorkspaceBrowserOpener(),
        hackerNewsFetcher: HackerNewsFetching = HackerNewsAPIClient(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.whitelist = whitelist
        self.inventory = inventory
        self.zipArchiver = zipArchiver
        self.documentConverter = documentConverter
        self.browserOpener = browserOpener
        self.hackerNewsFetcher = hackerNewsFetcher
        self.fileManager = fileManager
        self.now = now
    }

    public func preview(plan: AgentPlan) throws -> [ActionPreview] {
        try validateSupported(plan)

        if plan.steps.contains(where: { $0.operation == .createZip || $0.operation == .scanSelectLargestFiles }) {
            return [try previewLargestFiles(plan)]
        }

        if plan.steps.contains(where: { $0.operation == .scanDocx || $0.operation == .convertDocxToPDF }) {
            return [try previewDocxConversion(plan)]
        }

        if plan.steps.contains(where: { $0.operation == .openHackerNews || $0.operation == .fetchHNHeadlines || $0.operation == .writeMarkdown }) {
            return [try previewHackerNews(plan)]
        }

        throw AgentExecutionError.invalidPlan("No executable supported operation was present.")
    }

    public func execute(
        plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let previews = try preview(plan: plan)

        if plan.steps.contains(where: { $0.operation == .createZip || $0.operation == .scanSelectLargestFiles }) {
            let summary = try await executeLargestFiles(plan, log: log)
            return AgentRunResult(plan: plan, previews: previews, summary: summary)
        }

        if plan.steps.contains(where: { $0.operation == .scanDocx || $0.operation == .convertDocxToPDF }) {
            let summary = try await executeDocxConversion(plan, log: log)
            return AgentRunResult(plan: plan, previews: previews, summary: summary)
        }

        if plan.steps.contains(where: { $0.operation == .openHackerNews || $0.operation == .fetchHNHeadlines || $0.operation == .writeMarkdown }) {
            let summary = try await executeHackerNews(plan, log: log)
            return AgentRunResult(plan: plan, previews: previews, summary: summary)
        }

        throw AgentExecutionError.invalidPlan("No executable supported operation was present.")
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
