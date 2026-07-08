import Foundation
import Testing
@testable import MacAgentCore

@Suite
@MainActor
struct AgentRunnerTests {
    @Test
    func tierOneTypedCommandAutoRunsWithoutApprovalDecision() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appOpener = RecordingAppOpener()
        let runner = AgentRunner(
            planner: StaticPlanner(plan: openAppPlan(appName: "Safari")),
            executor: makeExecutor(root: root, appOpener: appOpener)
        )

        let prepared = try await runner.prepare(command: "Open Safari")
        let request = try runner.approvalRequest(for: prepared)
        let result = try await runner.execute(
            prepared,
            confirmationMessage: "Typed command auto-approved execution"
        )

        #expect(request.assessment.effectiveTier == .tier1)
        #expect(request.requirement == .autoRun)
        #expect(appOpener.openedBundleIDs == ["com.apple.Safari"])
        #expect(result.summary == "Opened Safari.")
    }

    @Test
    func tierOneVoiceCommandAutoRunsWithoutApprovalDecision() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let browserOpener = RecordingBrowserOpener()
        let runner = AgentRunner(
            planner: StaticPlanner(plan: openURLPlan(url: "https://github.com")),
            executor: makeExecutor(root: root, browserOpener: browserOpener)
        )

        let prepared = try await runner.prepare(command: "Open GitHub")
        let request = try runner.approvalRequest(for: prepared)
        let result = try await runner.execute(
            prepared,
            confirmationMessage: "Voice command auto-approved execution"
        )

        #expect(request.assessment.effectiveTier == .tier1)
        #expect(request.requirement == .autoRun)
        #expect(browserOpener.openedURLs.map(\.absoluteString) == ["https://github.com"])
        #expect(result.summary == "Opened https://github.com.")
    }

    @Test
    func tierZeroCommandAutoRunsWithoutApprovalDecision() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = AgentRunner(
            planner: StaticPlanner(plan: permissionReadinessPlan()),
            executor: makeExecutor(root: root)
        )

        let prepared = try await runner.prepare(command: "Check Sonny permissions")
        let request = try runner.approvalRequest(for: prepared)
        let result = try await runner.execute(prepared)

        #expect(request.assessment.effectiveTier == .tier0)
        #expect(request.requirement == .autoRun)
        #expect(result.summary.hasPrefix("Permission readiness checked."))
    }

    @Test
    func tierTwoCommandRequiresApprovalBeforeRunnerExecutes() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        let zipArchiver = RecordingZipArchiver()
        let runner = AgentRunner(
            planner: StaticPlanner(plan: largestPlan(root: root, output: output)),
            executor: makeExecutor(root: root, zipArchiver: zipArchiver)
        )

        let prepared = try await runner.prepare(command: "Zip the largest files")
        let request = try runner.approvalRequest(for: prepared)

        do {
            _ = try await runner.execute(prepared)
            Issue.record("Expected tier 2 execution to require approval.")
        } catch RiskApprovalError.approvalRequired(let approvalRequest) {
            #expect(approvalRequest.requirement == .lightweightConfirmation)
            #expect(approvalRequest.assessment.effectiveTier == .tier2)
        } catch {
            Issue.record("Expected approvalRequired, got \(error).")
        }

        #expect(request.assessment.effectiveTier == .tier2)
        #expect(request.requirement == .lightweightConfirmation)
        #expect(zipArchiver.createdArchives.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: output.path))

        _ = try await runner.execute(
            prepared,
            approvalDecision: .approved(request.assessment.effectiveTier),
            confirmationMessage: "User approved Tier 2 action"
        )

        #expect(zipArchiver.createdArchives == [output])
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func runnerRefusesTierFourBeforeExecutorExecution() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try CapabilityRegistry(adapters: [
            StaticTierOpenURLAdapter(defaultRiskTier: .tier4)
        ])
        let runner = AgentRunner(
            planner: StaticPlanner(plan: openURLPlan(url: "https://example.com")),
            executor: makeExecutor(root: root, capabilityRegistry: registry)
        )

        let prepared = try await runner.prepare(command: "Open example")
        let request = try runner.approvalRequest(for: prepared)

        do {
            _ = try await runner.execute(
                prepared,
                approvalDecision: .approved(.tier4),
                confirmationMessage: "User approved Tier 4 action"
            )
            Issue.record("Expected tier 4 execution to be refused.")
        } catch RiskApprovalError.refused(let approvalRequest) {
            #expect(approvalRequest.assessment.effectiveTier == .tier4)
        } catch {
            Issue.record("Expected refused, got \(error).")
        }

        #expect(request.requirement == .refuse)
    }

    @Test
    func executorAssessRiskUsesHighestStaticTierInMixedPlan() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("largest.zip")
        let executor = makeExecutor(root: root)
        let plan = AgentPlan(
            summary: "Zip files and open Safari.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files.",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files.",
                    inputPath: root.path,
                    outputPath: output.path,
                    count: 3
                ),
                AgentStep(
                    id: "open",
                    operation: .openApp,
                    description: "Open Safari.",
                    appName: "Safari"
                )
            ]
        )

        let assessment = try executor.assessRisk(plan: plan)

        #expect(assessment.defaultTier == .tier2)
        #expect(assessment.effectiveTier == .tier2)
        #expect(assessment.escalations.isEmpty)
        #expect(assessment.approvalRequirement() == .lightweightConfirmation)
        #expect(assessment.approvalCopy?.involvedResource.contains(output.path) == true)
    }

    @Test
    func existingZipOutputEscalatesToTierThreeAndLogsRiskEvent() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        try write("existing zip", to: output)
        let logStore = AgentLogStore()
        let runner = AgentRunner(
            planner: StaticPlanner(plan: largestPlan(root: root, output: output)),
            executor: makeExecutor(root: root),
            logStore: logStore
        )

        let prepared = try await runner.prepare(command: "Zip the largest files")
        let request = try runner.approvalRequest(for: prepared, logAssessment: true)

        #expect(request.assessment.defaultTier == .tier2)
        #expect(request.assessment.effectiveTier == .tier3)
        #expect(request.requirement == .explicitApproval)
        #expect(request.assessment.escalations == [
            CapabilityRiskEscalation(
                fromTier: .tier2,
                toTier: .tier3,
                reason: "Zip output already exists at \(output.path)."
            )
        ])
        #expect(logStore.events.contains { event in
            event.phase == .risk && event.message.contains("risk.escalated")
        })
    }

    @Test
    func staleTierTwoApprovalDoesNotAuthorizeLaterTierThreeEscalation() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        let zipArchiver = RecordingZipArchiver()
        let runner = AgentRunner(
            planner: StaticPlanner(plan: largestPlan(root: root, output: output)),
            executor: makeExecutor(root: root, zipArchiver: zipArchiver)
        )

        let prepared = try await runner.prepare(command: "Zip the largest files")
        let originalRequest = try runner.approvalRequest(for: prepared)
        try write("appeared after approval", to: output)

        do {
            _ = try await runner.execute(
                prepared,
                approvalDecision: .approved(originalRequest.assessment.effectiveTier),
                confirmationMessage: "User approved Tier 2 action"
            )
            Issue.record("Expected later escalation to require a fresh approval.")
        } catch RiskApprovalError.approvalRequired(let newRequest) {
            #expect(originalRequest.assessment.effectiveTier == .tier2)
            #expect(newRequest.assessment.effectiveTier == .tier3)
            #expect(newRequest.requirement == .explicitApproval)
        } catch {
            Issue.record("Expected approvalRequired, got \(error).")
        }

        #expect(zipArchiver.createdArchives.isEmpty)
    }

    @Test
    func existingHackerNewsMarkdownOutputEscalatesToTierThree() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("hn.md")
        try write("existing markdown", to: output)
        let runner = AgentRunner(
            planner: StaticPlanner(plan: hnPlan(output: output)),
            executor: makeExecutor(root: root)
        )

        let prepared = try await runner.prepare(command: "Save Hacker News to Markdown")
        let request = try runner.approvalRequest(for: prepared)

        #expect(request.assessment.defaultTier == .tier2)
        #expect(request.assessment.effectiveTier == .tier3)
        #expect(request.requirement == .explicitApproval)
        #expect(request.assessment.escalations.first?.reason == "Markdown output already exists at \(output.path).")
    }

    @Test
    func replacingExistingRoutineEscalatesToTierThree() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let routineStore = RoutineStore(fileURL: root.appendingPathComponent("routines.json"))
        try routineStore.save(StoredRoutine(name: "Morning Setup", steps: [openAppStep(id: "existing-open")]))
        let runner = AgentRunner(
            planner: StaticPlanner(plan: saveRoutinePlan(name: "Morning Setup")),
            executor: makeExecutor(root: root, routineStore: routineStore)
        )

        let prepared = try await runner.prepare(command: "Teach my morning setup")
        let request = try runner.approvalRequest(for: prepared)

        #expect(request.assessment.effectiveTier == .tier3)
        #expect(request.requirement == .explicitApproval)
        #expect(request.assessment.escalations.first?.reason == "Routine named Morning Setup already exists and would be replaced.")
    }

    @Test
    func replacingExistingWorkspaceEscalatesToTierThree() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceStore = WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json"))
        try workspaceStore.save(StoredWorkspace(name: "Research", apps: ["Safari"], urls: []))
        let runner = AgentRunner(
            planner: StaticPlanner(plan: createWorkspacePlan(name: "Research")),
            executor: makeExecutor(root: root, workspaceStore: workspaceStore)
        )

        let prepared = try await runner.prepare(command: "Create a research workspace")
        let request = try runner.approvalRequest(for: prepared)

        #expect(request.assessment.effectiveTier == .tier3)
        #expect(request.requirement == .explicitApproval)
        #expect(request.assessment.escalations.first?.reason == "Workspace named Research already exists and would be replaced.")
    }

    @Test
    func docxExistingPDFSkipDoesNotEscalate() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("docx", to: root.appendingPathComponent("a.docx"))
        try write("existing pdf", to: root.appendingPathComponent("a.pdf"))
        let runner = AgentRunner(
            planner: StaticPlanner(plan: docxPlan(root: root)),
            executor: makeExecutor(root: root, documentConverter: FakeDocumentConverter())
        )

        let prepared = try await runner.prepare(command: "Convert DOCX files")
        let request = try runner.approvalRequest(for: prepared)

        #expect(request.assessment.defaultTier == .tier2)
        #expect(request.assessment.effectiveTier == .tier2)
        #expect(request.assessment.escalations.isEmpty)
        #expect(request.requirement == .lightweightConfirmation)
    }

    private func makeExecutor(
        root: URL,
        zipArchiver: ZipArchiving = RecordingZipArchiver(),
        documentConverter: DocumentConverting = FakeDocumentConverter(),
        browserOpener: BrowserOpening = NoopBrowserOpener(),
        appOpener: AppOpening = NoopAppOpener(),
        routineStore: RoutineStore? = nil,
        workspaceStore: WorkspaceStore? = nil,
        capabilityRegistry: CapabilityRegistry = .default
    ) -> AgentActionExecutor {
        AgentActionExecutor(
            whitelist: PathWhitelist(roots: [root]),
            zipArchiver: zipArchiver,
            documentConverter: documentConverter,
            browserOpener: browserOpener,
            appOpener: appOpener,
            routineStore: routineStore ?? RoutineStore(fileURL: root.appendingPathComponent("routines.json")),
            workspaceStore: workspaceStore ?? WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json")),
            capabilityRegistry: capabilityRegistry
        )
    }

    private func openAppPlan(appName: String) -> AgentPlan {
        AgentPlan(
            summary: "Open \(appName).",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "open-app",
                    operation: .openApp,
                    description: "Open \(appName).",
                    appName: appName
                )
            ]
        )
    }

    private func openURLPlan(url: String) -> AgentPlan {
        AgentPlan(
            summary: "Open \(url).",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "open-url",
                    operation: .openURL,
                    description: "Open \(url).",
                    targetURL: url
                )
            ]
        )
    }

    private func largestPlan(root: URL, output: URL) -> AgentPlan {
        AgentPlan(
            summary: "Zip largest files.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files.",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files.",
                    inputPath: root.path,
                    outputPath: output.path,
                    count: 3
                )
            ]
        )
    }

    private func hnPlan(output: URL) -> AgentPlan {
        AgentPlan(
            summary: "Save HN headlines.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "open",
                    operation: .openHackerNews,
                    description: "Open HN.",
                    targetURL: "https://news.ycombinator.com"
                ),
                AgentStep(
                    id: "fetch",
                    operation: .fetchHNHeadlines,
                    description: "Fetch headlines.",
                    count: 5,
                    targetURL: "https://news.ycombinator.com"
                ),
                AgentStep(
                    id: "write",
                    operation: .writeMarkdown,
                    description: "Write Markdown.",
                    outputPath: output.path,
                    count: 5
                )
            ]
        )
    }

    private func saveRoutinePlan(name: String) -> AgentPlan {
        AgentPlan(
            summary: "Teach routine.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "save-routine",
                    operation: .saveRoutine,
                    description: "Save routine.",
                    routineName: name,
                    routineSteps: [openAppStep(id: "open-safari")]
                )
            ]
        )
    }

    private func createWorkspacePlan(name: String) -> AgentPlan {
        AgentPlan(
            summary: "Create workspace.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "create-workspace",
                    operation: .createWorkspace,
                    description: "Create workspace.",
                    workspaceName: name,
                    workspaceApps: ["Safari"],
                    workspaceURLs: ["https://github.com"]
                )
            ]
        )
    }

    private func docxPlan(root: URL) -> AgentPlan {
        AgentPlan(
            summary: "Convert DOCX files.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanDocx,
                    description: "Scan DOCX.",
                    inputPath: root.path
                ),
                AgentStep(
                    id: "convert",
                    operation: .convertDocxToPDF,
                    description: "Convert DOCX.",
                    inputPath: root.path
                )
            ]
        )
    }

    private func openAppStep(id: String) -> AgentStep {
        AgentStep(
            id: id,
            operation: .openApp,
            description: "Open Safari.",
            appName: "Safari"
        )
    }

    private func permissionReadinessPlan() -> AgentPlan {
        AgentPlan(
            summary: "Show permission readiness.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "permissions",
                    operation: .showPermissionReadiness,
                    description: "Show readiness."
                )
            ]
        )
    }

    private func write(_ string: String, to url: URL) throws {
        try string.data(using: .utf8)?.write(to: url)
    }
}

private struct StaticPlanner: Planning {
    var plan: AgentPlan

    func plan(command: String) async throws -> AgentPlan {
        plan
    }
}

@MainActor
private final class RecordingZipArchiver: ZipArchiving {
    private(set) var createdArchives: [URL] = []

    func createArchive(sourceFolder: URL, files: [URL], outputURL: URL) async throws {
        createdArchives.append(outputURL)
        try "fake zip".data(using: .utf8)?.write(to: outputURL)
    }
}

private struct NoopBrowserOpener: BrowserOpening {
    func open(_ url: URL) async throws {}
}

@MainActor
private final class RecordingBrowserOpener: BrowserOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) async throws {
        openedURLs.append(url)
    }
}

private struct NoopAppOpener: AppOpening {
    func open(bundleIdentifier: String) async throws {}
}

private struct FakeDocumentConverter: DocumentConverting {
    var isAvailable: Bool { true }
    var modeName: String { "Fake converter" }

    func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord] {
        records.filter { !$0.skippedBecausePDFExists }
    }
}

@MainActor
private final class RecordingAppOpener: AppOpening {
    private(set) var openedBundleIDs: [String] = []

    func open(bundleIdentifier: String) async throws {
        openedBundleIDs.append(bundleIdentifier)
    }
}

private struct StaticTierOpenURLAdapter: CapabilityAdapter {
    var defaultRiskTier: CapabilityRiskTier

    var metadata: CapabilityMetadata {
        CapabilityMetadata(
            id: "local.test.static-tier-open-url",
            displayName: "Static tier open URL",
            description: "Test adapter for a static risk tier.",
            operations: [.openURL],
            plannerTools: [
                AgentTool(
                    operation: .openURL,
                    name: "Static tier open URL",
                    description: "Test adapter for a static risk tier.",
                    requiredFields: ["targetURL"],
                    sideEffects: ["open browser"],
                    dryRunBehavior: "Preview test URL."
                )
            ],
            defaultRiskTier: defaultRiskTier
        )
    }

    func preview(plan: AgentPlan, context: CapabilityExecutionContext) throws -> [ActionPreview] {
        [
            ActionPreview(
                title: "Static tier URL",
                details: ["Preview only"],
                opens: ["https://example.com"]
            )
        ]
    }

    func execute(
        plan: AgentPlan,
        context: CapabilityExecutionContext,
        log: @escaping (AgentPhase, String) -> Void
    ) async throws -> AgentRunResult {
        AgentRunResult(
            plan: plan,
            previews: try preview(plan: plan, context: context),
            summary: "Executed static tier URL."
        )
    }
}
