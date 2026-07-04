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
    private let capabilityRegistry: CapabilityRegistry
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
        capabilityRegistry: CapabilityRegistry = .default,
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
        self.capabilityRegistry = capabilityRegistry
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
            return try previewCapability(for: .scanSelectLargestFiles, plan: plan)
        case .docx:
            return try previewCapability(for: .scanDocx, plan: plan)
        case .hackerNews:
            return try previewCapability(for: .openHackerNews, plan: plan)
        case .openApp:
            return try previewCapability(for: .openApp, plan: plan)
        case .openURL:
            return try previewCapability(for: .openURL, plan: plan)
        case .mediaOpen:
            return try previewCapability(for: .playMedia, plan: plan)
        case .finderSelection:
            return try previewCapability(for: .getFinderSelection, plan: plan)
        case .revealInFinder:
            return try previewCapability(for: .revealInFinder, plan: plan)
        case .permissionReadiness:
            return try previewCapability(for: .showPermissionReadiness, plan: plan)
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
        let workflow = try workflow(in: resolvedPlan)
        let previews = { try self.preview(plan: resolvedPlan) }

        switch workflow {
        case .clarify:
            throw AgentExecutionError.missingClarificationQuestion
        case .largestFiles:
            return try await executeCapability(for: .scanSelectLargestFiles, plan: resolvedPlan, log: log)
        case .docx:
            return try await executeCapability(for: .scanDocx, plan: resolvedPlan, log: log)
        case .hackerNews:
            return try await executeCapability(for: .openHackerNews, plan: resolvedPlan, log: log)
        case .openApp:
            return try await executeCapability(for: .openApp, plan: resolvedPlan, log: log)
        case .openURL:
            return try await executeCapability(for: .openURL, plan: resolvedPlan, log: log)
        case .mediaOpen:
            return try await executeCapability(for: .playMedia, plan: resolvedPlan, log: log)
        case .finderSelection:
            return try await executeCapability(for: .getFinderSelection, plan: resolvedPlan, log: log)
        case .revealInFinder:
            return try await executeCapability(for: .revealInFinder, plan: resolvedPlan, log: log)
        case .permissionReadiness:
            return try await executeCapability(for: .showPermissionReadiness, plan: resolvedPlan, log: log)
        case .saveRoutine:
            let summary = try executeSaveRoutine(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: try previews(), summary: summary)
        case .runRoutine:
            return try await executeRunRoutine(resolvedPlan, log: log)
        case .createWorkspace:
            let summary = try executeCreateWorkspace(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: try previews(), summary: summary)
        case .openWorkspace:
            let summary = try await executeOpenWorkspace(resolvedPlan, log: log)
            return AgentRunResult(plan: resolvedPlan, previews: try previews(), summary: summary)
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

        if resolvedPlan.steps.contains(where: { $0.operation == .createZip }) {
            resolvedPlan = try capabilityRegistry
                .adapter(for: .scanSelectLargestFiles)
                .resolveDefaultOutputs(in: resolvedPlan, context: capabilityContext())
        }

        if let markdownIndex = resolvedPlan.steps.firstIndex(where: { $0.operation == .writeMarkdown }) {
            resolvedPlan = try capabilityRegistry
                .adapter(for: resolvedPlan.steps[markdownIndex].operation)
                .resolveDefaultOutputs(in: resolvedPlan, context: capabilityContext())
        }

        return resolvedPlan
    }

    private func validateSupported(_ plan: AgentPlan) throws {
        if let unsupported = plan.steps.first(where: { $0.operation == .unsupported }) {
            throw AgentExecutionError.unsupported(unsupported.description)
        }
    }

    private func previewCapability(for operation: AgentOperation, plan: AgentPlan) throws -> [ActionPreview] {
        try capabilityRegistry
            .adapter(for: operation)
            .preview(plan: plan, context: capabilityContext())
    }

    private func executeCapability(
        for operation: AgentOperation,
        plan: AgentPlan,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        try await capabilityRegistry
            .adapter(for: operation)
            .execute(plan: plan, context: capabilityContext(), log: log)
    }

    private func capabilityContext() -> CapabilityExecutionContext {
        CapabilityExecutionContext(
            whitelist: whitelist,
            inventory: inventory,
            zipArchiver: zipArchiver,
            documentConverter: documentConverter,
            browserOpener: browserOpener,
            hackerNewsFetcher: hackerNewsFetcher,
            appCatalog: appCatalog,
            appOpener: appOpener,
            mediaOpener: mediaOpener,
            finderContextReader: finderContextReader,
            permissionReadinessService: permissionReadinessService,
            fileManager: fileManager,
            now: now
        )
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

}
