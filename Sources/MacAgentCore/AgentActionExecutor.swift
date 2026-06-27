import AppKit
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
    private let mediaOpener: MediaOpening
    private let finderContextReader: FinderContextReading
    private let permissionReadinessService: PermissionReadinessService
    private let routineStore: RoutineStore
    private let workspaceStore: WorkspaceStore
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
        mediaOpener: MediaOpening = NativeMediaOpener(),
        finderContextReader: FinderContextReading = AppleScriptFinderContextReader(),
        permissionReadinessService: PermissionReadinessService = PermissionReadinessService(),
        routineStore: RoutineStore = RoutineStore(),
        workspaceStore: WorkspaceStore = WorkspaceStore(),
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
        self.mediaOpener = mediaOpener
        self.finderContextReader = finderContextReader
        self.permissionReadinessService = permissionReadinessService
        self.routineStore = routineStore
        self.workspaceStore = workspaceStore
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
        case .mediaOpen:
            return [try previewMediaOpen(plan)]
        case .finderSelection:
            return [try previewFinderSelection(plan)]
        case .revealInFinder:
            return [try previewRevealInFinder(plan)]
        case .permissionReadiness:
            return [previewPermissionReadiness()]
        case .saveRoutine:
            return [try previewSaveRoutine(plan)]
        case .runRoutine:
            return try previewRunRoutine(plan)
        case .createWorkspace:
            return [try previewCreateWorkspace(plan)]
        case .openWorkspace:
            return [try previewOpenWorkspace(plan)]
        case .chain:
            return try previewChain(plan)
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
        case .mediaOpen:
            let summary = try await executeMediaOpen(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .finderSelection:
            let summary = try executeFinderSelection(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .revealInFinder:
            let summary = try executeRevealInFinder(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .permissionReadiness:
            let summary = executePermissionReadiness(log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .saveRoutine:
            let summary = try executeSaveRoutine(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .runRoutine:
            return try await executeRunRoutine(resolvedPlan, log: log)
        case .createWorkspace:
            let summary = try executeCreateWorkspace(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .openWorkspace:
            let summary = try await executeOpenWorkspace(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: previews, summary: summary)
        case .chain:
            return try await executeChain(resolvedPlan, log: log)
        }
    }

    private enum Workflow: Equatable {
        case clarify
        case largestFiles
        case docx
        case hackerNews
        case openApp
        case openURL
        case mediaOpen
        case finderSelection
        case revealInFinder
        case permissionReadiness
        case saveRoutine
        case runRoutine
        case createWorkspace
        case openWorkspace
        case chain
    }

    private func workflow(in plan: AgentPlan) throws -> Workflow {
        try validateSupported(plan)

        let workflows = Set(try plan.steps.map { step in
            try workflow(for: step.operation)
        })

        guard workflows.count == 1, let workflow = workflows.first else {
            if workflows.contains(.clarify) {
                throw AgentExecutionError.invalidPlan("Clarification must be the only planned step.")
            }
            return .chain
        }

        if plan.steps.count > 1, shouldChainWhenRepeated(workflow) {
            return .chain
        }

        return workflow
    }

    private func shouldChainWhenRepeated(_ workflow: Workflow) -> Bool {
        switch workflow {
        case .openApp,
             .openURL,
             .mediaOpen,
             .finderSelection,
             .revealInFinder,
             .permissionReadiness,
             .saveRoutine,
             .runRoutine,
             .createWorkspace,
             .openWorkspace:
            return true
        case .clarify,
             .largestFiles,
             .docx,
             .hackerNews,
             .chain:
            return false
        }
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
        case .playMedia:
            return .mediaOpen
        case .getFinderSelection:
            return .finderSelection
        case .revealInFinder:
            return .revealInFinder
        case .showPermissionReadiness:
            return .permissionReadiness
        case .saveRoutine:
            return .saveRoutine
        case .runRoutine:
            return .runRoutine
        case .createWorkspace:
            return .createWorkspace
        case .openWorkspace:
            return .openWorkspace
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

    private func previewMediaOpen(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try mediaSpec(plan)
        return ActionPreview(
            title: "Open \(spec.request.displayTitle)",
            details: [
                "Provider: \(spec.request.provider.displayName)",
                spec.behaviorDescription
            ],
            opens: [spec.request.provider.displayName]
        )
    }

    private func executeMediaOpen(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let spec = try mediaSpec(plan)
        log(.act, "Opening \(spec.request.provider.displayName) result for \(spec.request.displayTitle)")
        let summary = try await mediaOpener.open(spec.request)
        log(.summarize, summary)
        return summary
    }

    private func previewFinderSelection(_ plan: AgentPlan) throws -> ActionPreview {
        let selection = try whitelistedFinderSelection()
        return ActionPreview(
            title: "Finder selection",
            details: selection.map(\.path)
        )
    }

    private func executeFinderSelection(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) throws -> String {
        log(.act, "Reading Finder selection")
        let selection = try whitelistedFinderSelection()
        log(.observe, "Found \(selection.count) selected item(s)")
        return "Finder selection contains \(selection.count) whitelisted item(s)."
    }

    private func previewRevealInFinder(_ plan: AgentPlan) throws -> ActionPreview {
        let url = try revealSpec(plan, requiresExistingPath: false)
        return ActionPreview(
            title: "Reveal in Finder",
            details: ["Reveal \(url.path)"],
            opens: ["Finder"]
        )
    }

    private func executeRevealInFinder(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) throws -> String {
        let url = try revealSpec(plan, requiresExistingPath: true)
        log(.act, "Revealing \(url.path) in Finder")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        log(.summarize, "Revealed in Finder")
        return "Revealed \(url.path) in Finder."
    }

    private func previewPermissionReadiness() -> ActionPreview {
        let items = permissionItems()
        return ActionPreview(
            title: "Permission readiness",
            details: items.map { "\($0.title): \($0.state.displayName) - \($0.detail)" }
        )
    }

    private func executePermissionReadiness(log: @escaping (AgentPhase, String) -> Void) -> String {
        let items = permissionItems()
        let needsAction = items.filter { $0.state == .needsAction }
        log(.observe, "Checked \(items.count) readiness item(s)")
        if needsAction.isEmpty {
            log(.summarize, "Permission readiness checked")
            return "Permission readiness checked. No blocking required-action items were found."
        }
        let names = needsAction.map(\.title).joined(separator: ", ")
        log(.summarize, "Needs action: \(names)")
        return "Permission readiness checked. Needs action: \(names)."
    }

    private func previewSaveRoutine(_ plan: AgentPlan) throws -> ActionPreview {
        let spec = try routineSaveSpec(plan)
        let nestedPreview = try preview(plan: spec.routine.plan)
        return ActionPreview(
            title: "Save routine \(spec.routine.name)",
            details: ["Steps: \(spec.routine.steps.count)"] + nestedPreview.map { "Will include: \($0.title)" },
            writes: [routineStore.fileURL.path]
        )
    }

    private func executeSaveRoutine(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) throws -> String {
        let spec = try routineSaveSpec(plan)
        log(.act, "Saving routine \(spec.routine.name)")
        try routineStore.save(spec.routine)
        log(.summarize, "Saved routine")
        return "Saved routine \(spec.routine.name) with \(spec.routine.steps.count) step(s)."
    }

    private func previewRunRoutine(_ plan: AgentPlan) throws -> [ActionPreview] {
        let routine = try routineRunSpec(plan)
        let nested = try preview(plan: routine.plan)
        return [
            ActionPreview(
                title: "Run routine \(routine.name)",
                details: ["Saved steps: \(routine.steps.count)"]
            )
        ] + nested
    }

    private func executeRunRoutine(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        let routine = try routineRunSpec(plan)
        log(.act, "Running routine \(routine.name)")
        let result = try await execute(plan: routine.plan, log: log)
        return AgentRunResult(
            plan: plan,
            previews: try previewRunRoutine(plan),
            summary: "Ran routine \(routine.name). \(result.summary)",
            suggestions: result.suggestions
        )
    }

    private func previewCreateWorkspace(_ plan: AgentPlan) throws -> ActionPreview {
        let workspace = try workspaceCreateSpec(plan)
        return ActionPreview(
            title: "Save workspace \(workspace.name)",
            details: [
                "Apps: \(workspace.apps.isEmpty ? "none" : workspace.apps.joined(separator: ", "))",
                "URLs: \(workspace.urls.isEmpty ? "none" : workspace.urls.joined(separator: ", "))"
            ],
            writes: [workspaceStore.fileURL.path]
        )
    }

    private func executeCreateWorkspace(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) throws -> String {
        let workspace = try workspaceCreateSpec(plan)
        log(.act, "Saving workspace \(workspace.name)")
        try workspaceStore.save(workspace)
        log(.summarize, "Saved workspace")
        return "Saved workspace \(workspace.name) with \(workspace.apps.count) app(s) and \(workspace.urls.count) URL(s)."
    }

    private func previewOpenWorkspace(_ plan: AgentPlan) throws -> ActionPreview {
        let workspace = try workspaceRunSpec(plan)
        return ActionPreview(
            title: "Open workspace \(workspace.name)",
            details: [
                "Apps: \(workspace.apps.isEmpty ? "none" : workspace.apps.joined(separator: ", "))",
                "URLs: \(workspace.urls.isEmpty ? "none" : workspace.urls.joined(separator: ", "))"
            ],
            opens: workspace.apps + workspace.urls
        )
    }

    private func executeOpenWorkspace(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> String {
        let workspace = try workspaceRunSpec(plan)
        for appName in workspace.apps {
            let app = try appCatalog.resolve(appName)
            log(.act, "Opening \(app.displayName)")
            try await appOpener.open(bundleIdentifier: app.bundleIdentifier)
        }
        for rawURL in workspace.urls {
            let url = try SafeURL.validateWebURL(rawURL)
            log(.act, "Opening \(url.absoluteString)")
            try await browserOpener.open(url)
        }
        log(.summarize, "Opened workspace")
        return "Opened workspace \(workspace.name) with \(workspace.apps.count) app(s) and \(workspace.urls.count) URL(s)."
    }

    private func previewChain(_ plan: AgentPlan) throws -> [ActionPreview] {
        var previews: [ActionPreview] = []
        var previousArtifactPath: String?

        for segment in try segmentPlans(in: plan) {
            let resolved = resolveRevealPathIfNeeded(in: segment, previousArtifactPath: previousArtifactPath)
            let segmentPreviews = try preview(plan: resolved)
            previews.append(contentsOf: segmentPreviews)
            if let producedPath = segmentPreviews.flatMap(\.writes).last {
                previousArtifactPath = producedPath
            }
        }

        return previews
    }

    private func executeChain(
        _ plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        var summaries: [String] = []
        var suggestions: [RunSuggestion] = []
        var previousArtifactPath: String?

        for segment in try segmentPlans(in: plan) {
            let resolved = resolveRevealPathIfNeeded(in: segment, previousArtifactPath: previousArtifactPath)
            let result = try await execute(plan: resolved, log: log)
            summaries.append(result.summary)
            suggestions.append(contentsOf: result.suggestions)
            if let producedPath = result.previews.flatMap(\.writes).last {
                previousArtifactPath = producedPath
            } else if let suggestionPath = result.suggestions.last?.value {
                previousArtifactPath = suggestionPath
            }
        }

        let preview = try previewChain(plan)
        let summary = summaries.joined(separator: " ")
        return AgentRunResult(plan: plan, previews: preview, summary: summary, suggestions: suggestions)
    }

    private func segmentPlans(in plan: AgentPlan) throws -> [AgentPlan] {
        var segments: [AgentPlan] = []
        var index = 0

        while index < plan.steps.count {
            let step = plan.steps[index]
            switch step.operation {
            case .scanSelectLargestFiles:
                var steps = [step]
                if index + 1 < plan.steps.count,
                   plan.steps[index + 1].operation == .createZip {
                    steps.append(plan.steps[index + 1])
                    index += 1
                }
                segments.append(segmentPlan(from: plan, steps: steps))
            case .scanDocx:
                var steps = [step]
                if index + 1 < plan.steps.count,
                   plan.steps[index + 1].operation == .convertDocxToPDF {
                    steps.append(plan.steps[index + 1])
                    index += 1
                }
                segments.append(segmentPlan(from: plan, steps: steps))
            case .openHackerNews:
                var steps = [step]
                while index + 1 < plan.steps.count,
                      [.fetchHNHeadlines, .writeMarkdown].contains(plan.steps[index + 1].operation) {
                    steps.append(plan.steps[index + 1])
                    index += 1
                }
                segments.append(segmentPlan(from: plan, steps: steps))
            default:
                segments.append(segmentPlan(from: plan, steps: [step]))
            }
            index += 1
        }

        return segments
    }

    private func segmentPlan(from plan: AgentPlan, steps: [AgentStep]) -> AgentPlan {
        AgentPlan(
            summary: plan.summary,
            requiresConfirmation: plan.requiresConfirmation,
            steps: steps
        )
    }

    private func resolveRevealPathIfNeeded(in plan: AgentPlan, previousArtifactPath: String?) -> AgentPlan {
        guard plan.steps.count == 1,
              plan.steps[0].operation == .revealInFinder,
              plan.steps[0].outputPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              plan.steps[0].inputPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              let previousArtifactPath else {
            return plan
        }

        var resolved = plan
        resolved.steps[0].outputPath = previousArtifactPath
        return resolved
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
        guard let folderPath = try pathOrFinderSelectedDirectory(
            primary: scanStep?.inputPath,
            secondary: zipStep?.inputPath,
            contextSource: scanStep?.contextSource ?? zipStep?.contextSource
        ) else {
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
        guard let folderPath = try pathOrFinderSelectedDirectory(
            primary: scanStep?.inputPath,
            secondary: convertStep?.inputPath,
            contextSource: scanStep?.contextSource ?? convertStep?.contextSource
        ) else {
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

    private struct MediaSpec {
        var request: MediaPlaybackRequest
        var behaviorDescription: String
    }

    private func urlSpec(_ plan: AgentPlan) throws -> URLSpec {
        guard let step = plan.steps.first(where: { $0.operation == .openURL }) else {
            throw AgentExecutionError.invalidPlan("open_url step is missing.")
        }
        return URLSpec(url: try SafeURL.validateWebURL(step.targetURL))
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

    private func whitelistedFinderSelection() throws -> [URL] {
        try finderContextReader.selectedItems().map { url in
            try whitelist.validateInsideWhitelist(url.path)
        }
    }

    private func pathOrFinderSelectedDirectory(
        primary: String?,
        secondary: String?,
        contextSource: FinderContextSource?
    ) throws -> String? {
        if let path = primary ?? secondary,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }

        guard contextSource == .finderSelection else {
            return nil
        }

        let selection = try whitelistedFinderSelection()
        guard selection.count == 1 else {
            throw FinderContextError.noDirectorySelection
        }

        let url = selection[0]
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw FinderContextError.noDirectorySelection
        }
        return url.path
    }

    private func revealSpec(_ plan: AgentPlan, requiresExistingPath: Bool) throws -> URL {
        guard let step = plan.steps.first(where: { $0.operation == .revealInFinder }) else {
            throw AgentExecutionError.invalidPlan("reveal_in_finder step is missing.")
        }

        if let rawPath = step.outputPath ?? step.inputPath,
           !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = try whitelist.validateInsideWhitelist(rawPath)
            guard !requiresExistingPath || fileManager.fileExists(atPath: url.path) else {
                throw PathValidationError.notFound(url.path)
            }
            return url
        }

        throw AgentExecutionError.invalidPlan("reveal_in_finder needs outputPath or a previous chained artifact.")
    }

    private struct RoutineSaveSpec {
        var routine: StoredRoutine
    }

    private func routineSaveSpec(_ plan: AgentPlan) throws -> RoutineSaveSpec {
        guard let step = plan.steps.first(where: { $0.operation == .saveRoutine }) else {
            throw AgentExecutionError.invalidPlan("save_routine step is missing.")
        }
        guard let name = step.routineName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            throw AutomationStoreError.missingName("Routine")
        }
        guard let routineSteps = step.routineSteps, !routineSteps.isEmpty else {
            throw AutomationStoreError.emptyRoutine
        }

        try validateRoutineSteps(routineSteps)
        return RoutineSaveSpec(routine: StoredRoutine(name: name, steps: routineSteps))
    }

    private func routineRunSpec(_ plan: AgentPlan) throws -> StoredRoutine {
        guard let step = plan.steps.first(where: { $0.operation == .runRoutine }) else {
            throw AgentExecutionError.invalidPlan("run_routine step is missing.")
        }
        return try routineStore.routine(named: step.routineName ?? "")
    }

    private func validateRoutineSteps(_ steps: [AgentStep]) throws {
        for step in steps {
            switch step.operation {
            case .saveRoutine, .runRoutine, .createWorkspace, .openWorkspace, .clarify, .unsupported:
                throw AutomationStoreError.unsafeRoutineStep(step.operation.rawValue)
            default:
                break
            }

            if let nested = step.routineSteps, !nested.isEmpty {
                throw AutomationStoreError.unsafeRoutineStep("nested routineSteps")
            }
        }

        _ = try preview(plan: AgentPlan(summary: "Validate routine.", requiresConfirmation: true, steps: steps))
    }

    private func workspaceCreateSpec(_ plan: AgentPlan) throws -> StoredWorkspace {
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
            _ = try appCatalog.resolve(app)
        }
        for url in urls {
            _ = try SafeURL.validateWebURL(url)
        }

        return StoredWorkspace(name: name, apps: apps, urls: urls)
    }

    private func workspaceRunSpec(_ plan: AgentPlan) throws -> StoredWorkspace {
        guard let step = plan.steps.first(where: { $0.operation == .openWorkspace }) else {
            throw AgentExecutionError.invalidPlan("open_workspace step is missing.")
        }
        let workspace = try workspaceStore.workspace(named: step.workspaceName ?? "")
        for app in workspace.apps {
            _ = try appCatalog.resolve(app)
        }
        for url in workspace.urls {
            _ = try SafeURL.validateWebURL(url)
        }
        return workspace
    }

    private func permissionItems() -> [PermissionReadinessItem] {
        let hasAPIKey = !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return permissionReadinessService.currentStatus(hasAPIKey: hasAPIKey, hotKeyReady: true)
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
