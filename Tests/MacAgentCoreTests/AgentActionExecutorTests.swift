import Foundation
import Testing
@testable import MacAgentCore

@Suite
@MainActor
struct AgentActionExecutorTests {
    @Test
    func largestFilesDryRunDoesNotWriteZip() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 1024), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: largestPlan(root: root, output: output))

        #expect(preview.first?.writes == [output.path])
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func largestFilesExecutionCreatesZip() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        let executor = makeExecutor(root: root, zipArchiver: ProcessZipArchiver())

        _ = try await executor.execute(plan: largestPlan(root: root, output: output)) { _, _ in }

        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func asyncProcessRunnerCancelsRunningProcess() async throws {
        let task = Task {
            try await AsyncProcessRunner.run(executablePath: "/bin/sleep", arguments: ["5"])
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected process cancellation to throw CancellationError.")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }
    }

    @Test
    func defaultZipOutputIsStableBetweenPreviewAndExecution() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let executor = makeExecutor(root: root)
        let plan = AgentPlan(
            summary: "Zip largest files.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files",
                    inputPath: root.path,
                    count: 3
                )
            ]
        )

        let prepared = try executor.prepare(plan: plan)
        let previewPath = try #require(prepared.previews.first?.writes.first)
        _ = try await executor.execute(plan: prepared.plan) { _, _ in }

        #expect(FileManager.default.fileExists(atPath: previewPath))
    }

    @Test
    func docxDryRunSkipsExistingPDFAndWritesNothing() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("docx-a", to: root.appendingPathComponent("a.docx"))
        try write("existing", to: root.appendingPathComponent("a.pdf"))
        try write("docx-b", to: root.appendingPathComponent("b.docx"))
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: docxPlan(root: root))

        #expect(preview.first?.writes.count == 1)
        #expect(preview.first?.writes.first?.hasSuffix("/\(root.lastPathComponent)/b.pdf") == true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("b.pdf").path))
    }

    @Test
    func docxExecutionUsesInjectedConverter() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("docx-b", to: root.appendingPathComponent("b.docx"))
        let executor = makeExecutor(root: root, documentConverter: FakeDocumentConverter())

        _ = try await executor.execute(plan: docxPlan(root: root)) { _, _ in }

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.pdf").path))
    }

    @Test
    func docxPreviewCanUseSelectedFinderFolderContext() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("docx-b", to: root.appendingPathComponent("b.docx"))
        let executor = makeExecutor(
            root: root,
            finderContextReader: FakeFinderContextReader(selection: [root])
        )
        let plan = AgentPlan(
            summary: "Convert selected Finder folder.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan-docx",
                    operation: .scanDocx,
                    description: "Scan selected Finder folder.",
                    contextSource: .finderSelection
                ),
                AgentStep(
                    id: "convert-docx",
                    operation: .convertDocxToPDF,
                    description: "Convert selected Finder folder.",
                    contextSource: .finderSelection
                )
            ]
        )

        let preview = try executor.preview(plan: plan)

        #expect(preview.first?.title == "Convert 1 DOCX files")
        #expect(preview.first?.writes.first?.hasSuffix("/\(root.lastPathComponent)/b.pdf") == true)
    }

    @Test
    func outputFileNormalizerMakesPDFUserReadable() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("normalized.pdf")
        try write("%PDF-1.7", to: pdf)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pdf.path)

        OutputFileNormalizer.normalizeUserWritablePDF(at: pdf)

        let attributes = try FileManager.default.attributesOfItem(atPath: pdf.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o644)
    }

    @Test
    func hackerNewsDryRunDoesNotWriteMarkdown() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("hn.md")
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: hnPlan(output: output))

        #expect(preview.first?.writes == [output.path])
        #expect(preview.first?.opens == ["https://news.ycombinator.com"])
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test
    func hackerNewsExecutionWritesFixtureMarkdown() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("hn.md")
        let executor = makeExecutor(
            root: root,
            browserOpener: NoopBrowserOpener(),
            hackerNewsFetcher: StaticHackerNewsFetcher()
        )

        _ = try await executor.execute(plan: hnPlan(output: output)) { _, _ in }

        let markdown = try String(contentsOf: output)
        #expect(markdown.contains("Fixture headline"))
    }

    @Test
    func openAppPreviewUsesAllowlist() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: openAppPlan(appName: "Visual Studio Code"))

        #expect(preview.first?.opens == ["VS Code"])
        #expect(preview.first?.details.contains("Bundle: com.microsoft.VSCode") == true)
    }

    @Test
    func openAppPreviewSupportsMusicApps() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let spotify = try executor.preview(plan: openAppPlan(appName: "Spotify"))
        let appleMusic = try executor.preview(plan: openAppPlan(appName: "Music"))

        #expect(spotify.first?.opens == ["Spotify"])
        #expect(appleMusic.first?.opens == ["Apple Music"])
    }

    @Test
    func openAppRejectsUnknownApp() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        #expect(throws: MacAppCatalogError.appNotAllowed("Untrusted App")) {
            try executor.preview(plan: openAppPlan(appName: "Untrusted App"))
        }
    }

    @Test
    func openURLAllowsHTTPAndHTTPSOnly() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: openURLPlan(url: "https://github.com"))

        #expect(preview.first?.opens == ["https://github.com"])
        #expect(throws: SafeURLError.unsupportedScheme("ftp")) {
            try executor.preview(plan: openURLPlan(url: "ftp://example.com"))
        }
    }

    @Test
    func mediaOpenPreviewShowsProviderAndSong() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let appleMusic = try executor.preview(plan: mediaPlan(provider: .appleMusic))
        let spotify = try executor.preview(plan: mediaPlan(provider: .spotify))

        #expect(appleMusic.first?.opens == ["Apple Music"])
        #expect(appleMusic.first?.title == "Open Jimmy Cooks by Drake")
        #expect(appleMusic.first?.details.contains("Opens the best matching Apple Music album result, or Apple Music search if no match is found.") == true)
        #expect(spotify.first?.opens == ["Spotify"])
        #expect(spotify.first?.details.contains("Opens Spotify search for the requested song or album.") == true)
    }

    @Test
    func mediaOpenExecutionUsesInjectedOpener() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let opener = FakeMediaOpener()
        let executor = makeExecutor(root: root, mediaOpener: opener)

        let result = try await executor.execute(plan: mediaPlan(provider: .appleMusic)) { _, _ in }

        #expect(result.summary == "Opened Jimmy Cooks by Drake in Apple Music.")
        #expect(opener.requests == [
            MediaPlaybackRequest(provider: .appleMusic, title: "Jimmy Cooks", artist: "Drake")
        ])
    }

    @Test
    func mediaOpenRequiresProviderAndTitle() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        #expect(throws: MediaPlaybackError.missingProvider) {
            try executor.preview(plan: mediaPlan(provider: nil))
        }
        #expect(throws: MediaPlaybackError.missingTitle) {
            try executor.preview(plan: mediaPlan(provider: .appleMusic, title: " "))
        }
    }

    @Test
    func clarificationPlanPreparesQuestionWithoutSideEffects() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let prepared = try executor.prepare(plan: clarifyPlan())

        #expect(prepared.clarificationQuestion == "Which folder should I scan?")
        #expect(prepared.sideEffects.isEmpty)
    }

    @Test
    func mixedWorkflowPlanExecutesAsChain() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let output = root.appendingPathComponent("largest.zip")
        let appOpener = RecordingAppOpener()
        let executor = makeExecutor(root: root, appOpener: appOpener)
        let plan = AgentPlan(
            summary: "Zip and open app.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files",
                    inputPath: root.path,
                    outputPath: output.path,
                    count: 3
                ),
                AgentStep(
                    id: "open",
                    operation: .openApp,
                    description: "Open Safari",
                    appName: "Safari"
                )
            ]
        )

        let result = try await executor.execute(plan: plan) { _, _ in }

        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(appOpener.openedBundleIDs == ["com.apple.Safari"])
        #expect(result.summary.contains("Created largest.zip"))
        #expect(result.summary.contains("Opened Safari."))
    }

    @Test
    func chainPreviewCanRevealFutureGeneratedZip() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let executor = makeExecutor(root: root)
        let plan = AgentPlan(
            summary: "Zip and reveal.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan files",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "reveal",
                    operation: .revealInFinder,
                    description: "Reveal generated zip"
                )
            ]
        )

        let preview = try executor.preview(plan: plan)

        #expect(preview.count == 2)
        #expect(preview[0].writes.first?.contains("largest-files-") == true)
        #expect(preview[1].title == "Reveal in Finder")
        #expect(preview[1].details.first == "Reveal \(preview[0].writes[0])")
        #expect(!FileManager.default.fileExists(atPath: preview[0].writes[0]))
    }

    @Test
    func finderSelectionCanSupplySelectedFolderContext() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("small", to: root.appendingPathComponent("small.txt"))
        try write(String(repeating: "x", count: 2048), to: root.appendingPathComponent("large.txt"))
        let executor = makeExecutor(
            root: root,
            finderContextReader: FakeFinderContextReader(selection: [root])
        )
        let plan = AgentPlan(
            summary: "Zip selected Finder folder.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "scan",
                    operation: .scanSelectLargestFiles,
                    description: "Scan selected folder",
                    count: 3,
                    contextSource: .finderSelection
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip selected folder",
                    count: 3,
                    contextSource: .finderSelection
                )
            ]
        )

        let preview = try executor.preview(plan: plan)

        #expect(preview.first?.title == "Zip 2 largest files")
    }

    @Test
    func routineCanBeSavedAndRun() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let routineStore = RoutineStore(fileURL: root.appendingPathComponent("routines.json"))
        let appOpener = RecordingAppOpener()
        let executor = makeExecutor(root: root, appOpener: appOpener, routineStore: routineStore)
        let savePlan = AgentPlan(
            summary: "Teach routine.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "save-routine",
                    operation: .saveRoutine,
                    description: "Save routine.",
                    routineName: "Morning Setup",
                    routineSteps: [
                        AgentStep(
                            id: "open-safari",
                            operation: .openApp,
                            description: "Open Safari.",
                            appName: "Safari"
                        ),
                        AgentStep(
                            id: "open-notes",
                            operation: .openApp,
                            description: "Open Notes.",
                            appName: "Notes"
                        )
                    ]
                )
            ]
        )
        let runPlan = AgentPlan(
            summary: "Run routine.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "run-routine",
                    operation: .runRoutine,
                    description: "Run routine.",
                    routineName: "Morning Setup"
                )
            ]
        )

        _ = try await executor.execute(plan: savePlan) { _, _ in }
        let result = try await executor.execute(plan: runPlan) { _, _ in }

        #expect(appOpener.openedBundleIDs == ["com.apple.Safari", "com.apple.Notes"])
        #expect(result.summary.contains("Ran routine Morning Setup."))
    }

    @Test
    func workspaceCanBeSavedAndOpened() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceStore = WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json"))
        let appOpener = RecordingAppOpener()
        let browserOpener = RecordingBrowserOpener()
        let executor = makeExecutor(
            root: root,
            browserOpener: browserOpener,
            appOpener: appOpener,
            workspaceStore: workspaceStore
        )
        let createPlan = AgentPlan(
            summary: "Create workspace.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "create-workspace",
                    operation: .createWorkspace,
                    description: "Create workspace.",
                    workspaceName: "Research",
                    workspaceApps: ["Safari"],
                    workspaceURLs: ["https://github.com"]
                )
            ]
        )
        let openPlan = AgentPlan(
            summary: "Open workspace.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "open-workspace",
                    operation: .openWorkspace,
                    description: "Open workspace.",
                    workspaceName: "Research"
                )
            ]
        )

        _ = try await executor.execute(plan: createPlan) { _, _ in }
        let result = try await executor.execute(plan: openPlan) { _, _ in }

        #expect(appOpener.openedBundleIDs == ["com.apple.Safari"])
        #expect(browserOpener.openedURLs.map(\.absoluteString) == ["https://github.com"])
        #expect(result.summary == "Opened workspace Research with 1 app(s) and 1 URL(s).")
    }

    private func makeExecutor(
        root: URL,
        zipArchiver: ZipArchiving = RecordingZipArchiver(),
        documentConverter: DocumentConverting = FakeDocumentConverter(),
        browserOpener: BrowserOpening = NoopBrowserOpener(),
        hackerNewsFetcher: HackerNewsFetching = StaticHackerNewsFetcher(),
        appCatalog: MacAppCatalog = .default,
        appOpener: AppOpening = NoopAppOpener(),
        mediaOpener: MediaOpening = FakeMediaOpener(),
        finderContextReader: FinderContextReading = FakeFinderContextReader(selection: []),
        routineStore: RoutineStore? = nil,
        workspaceStore: WorkspaceStore? = nil
    ) -> AgentActionExecutor {
        AgentActionExecutor(
            whitelist: PathWhitelist(roots: [root]),
            zipArchiver: zipArchiver,
            documentConverter: documentConverter,
            browserOpener: browserOpener,
            hackerNewsFetcher: hackerNewsFetcher,
            appCatalog: appCatalog,
            appOpener: appOpener,
            mediaOpener: mediaOpener,
            finderContextReader: finderContextReader,
            routineStore: routineStore ?? RoutineStore(fileURL: root.appendingPathComponent("routines.json")),
            workspaceStore: workspaceStore ?? WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json"))
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
                    description: "Scan files",
                    inputPath: root.path,
                    count: 3
                ),
                AgentStep(
                    id: "zip",
                    operation: .createZip,
                    description: "Zip files",
                    inputPath: root.path,
                    outputPath: output.path,
                    count: 3
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
                    description: "Scan DOCX",
                    inputPath: root.path
                ),
                AgentStep(
                    id: "convert",
                    operation: .convertDocxToPDF,
                    description: "Convert DOCX",
                    inputPath: root.path
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
                    description: "Open HN",
                    targetURL: "https://news.ycombinator.com"
                ),
                AgentStep(
                    id: "fetch",
                    operation: .fetchHNHeadlines,
                    description: "Fetch headlines",
                    count: 5,
                    targetURL: "https://news.ycombinator.com"
                ),
                AgentStep(
                    id: "write",
                    operation: .writeMarkdown,
                    description: "Write Markdown",
                    outputPath: output.path,
                    count: 5
                )
            ]
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

    private func mediaPlan(provider: MediaProvider?, title: String = "Jimmy Cooks") -> AgentPlan {
        AgentPlan(
            summary: "Open a song result.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "play-media",
                    operation: .playMedia,
                    description: "Open the requested song result.",
                    targetURL: nil,
                    mediaProvider: provider,
                    mediaTitle: title,
                    mediaArtist: "Drake"
                )
            ]
        )
    }

    private func clarifyPlan() -> AgentPlan {
        AgentPlan(
            summary: "Need clarification.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "clarify",
                    operation: .clarify,
                    description: "Ask which folder to scan.",
                    question: "Which folder should I scan?"
                )
            ]
        )
    }

    private func write(_ string: String, to url: URL) throws {
        try string.data(using: .utf8)?.write(to: url)
    }
}

private struct RecordingZipArchiver: ZipArchiving {
    func createArchive(sourceFolder: URL, files: [URL], outputURL: URL) async throws {
        try "fake zip".data(using: .utf8)?.write(to: outputURL)
    }
}

private struct FakeDocumentConverter: DocumentConverting {
    var isAvailable: Bool { true }
    var modeName: String { "Fake converter" }

    func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord] {
        var converted: [DocxRecord] = []
        for record in records where !record.skippedBecausePDFExists {
            log("Converting \(record.sourceURL.lastPathComponent)")
            try "fake pdf".data(using: .utf8)?.write(to: record.destinationURL)
            converted.append(record)
        }
        return converted
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

@MainActor
private final class RecordingAppOpener: AppOpening {
    private(set) var openedBundleIDs: [String] = []

    func open(bundleIdentifier: String) async throws {
        openedBundleIDs.append(bundleIdentifier)
    }
}

@MainActor
private final class FakeMediaOpener: MediaOpening {
    private(set) var requests: [MediaPlaybackRequest] = []

    func open(_ request: MediaPlaybackRequest) async throws -> String {
        requests.append(request)
        return "Opened \(request.displayTitle) in \(request.provider.displayName)."
    }
}

private struct FakeFinderContextReader: FinderContextReading {
    var selection: [URL]

    func selectedItems() throws -> [URL] {
        guard !selection.isEmpty else {
            throw FinderContextError.noSelection
        }
        return selection
    }
}

private struct StaticHackerNewsFetcher: HackerNewsFetching {
    func topHeadlines(limit: Int) async throws -> [HackerNewsHeadline] {
        (1...limit).map { index in
            HackerNewsHeadline(title: "Fixture headline \(index)", url: "https://example.com/\(index)")
        }
    }
}
