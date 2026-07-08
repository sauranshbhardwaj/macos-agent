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
        let browserOpener = RecordingBrowserOpener()
        let executor = makeExecutor(
            root: root,
            browserOpener: browserOpener,
            hackerNewsFetcher: StaticHackerNewsFetcher()
        )

        let result = try await executor.execute(plan: hnPlan(output: output)) { _, _ in }

        let markdown = try String(contentsOf: output)
        #expect(markdown.contains("Fixture headline"))
        #expect(browserOpener.openedURLs.map(\.absoluteString) == ["https://news.ycombinator.com"])
        #expect(result.suggestions.contains { suggestion in
            suggestion.title == "Reveal Markdown in Finder" &&
                suggestion.kind == .revealInFinder &&
                suggestion.value == output.path
        })
    }

    @Test
    func webResearchExecutionWritesMarkdownWithSourcesAndSuggestions() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("web-note.md")
        let source = URL(string: "https://example.com/article")!
        let retrievedAt = Date(timeIntervalSince1970: 1_783_526_400)
        let pageLoader = webPageLoader(pages: [
            source.absoluteString: readablePage(
                url: source,
                retrievedAt: retrievedAt,
                title: "Article One"
            )
        ])
        let synthesizer = StaticWebResearchSynthesizer(
            note: WebResearchNote(
                title: "Article One Notes",
                summary: "A concise summary.",
                keyPoints: ["First point"],
                citations: ["Article One citation"],
                sources: [
                    WebResearchNoteSource(
                        title: "Article One",
                        url: source.absoluteString,
                        retrievedAt: ISO8601DateFormatter().string(from: retrievedAt)
                    )
                ]
            )
        )
        let executor = makeExecutor(
            root: root,
            webPageLoader: pageLoader,
            webResearchSynthesizer: synthesizer
        )

        let result = try await executor.execute(plan: webMarkdownPlan(url: source, output: output)) { _, _ in }

        let markdown = try String(contentsOf: output)
        #expect(markdown.contains("# Article One Notes"))
        #expect(markdown.contains("Generated:"))
        #expect(markdown.contains("- [Article One](https://example.com/article)"))
        #expect(markdown.contains("Retrieved: 2026-07-08T16:00:00Z"))
        #expect(markdown.contains("A concise summary."))
        #expect(synthesizer.prompts.count == 1)
        #expect(synthesizer.prompts[0].trustedPlan.steps.map(\.operation) == [.webToMarkdown])
        #expect(result.suggestions.contains { suggestion in
            suggestion.title == "Open Markdown" &&
                suggestion.kind == .openFile &&
                suggestion.value == output.path
        })
        #expect(result.suggestions.contains { suggestion in
            suggestion.title == "Reveal Markdown in Finder" &&
                suggestion.kind == .revealInFinder &&
                suggestion.value == output.path
        })
    }

    @Test
    func webResearchCanWriteComparisonMarkdownForMultipleSources() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("comparison.md")
        let first = URL(string: "https://example.com/one")!
        let second = URL(string: "https://example.com/two")!
        let pageLoader = webPageLoader(pages: [
            first.absoluteString: readablePage(url: first, title: "First Source"),
            second.absoluteString: readablePage(url: second, title: "Second Source")
        ])
        let executor = makeExecutor(
            root: root,
            webPageLoader: pageLoader,
            webResearchSynthesizer: StaticWebResearchSynthesizer(
                note: WebResearchNote(
                    title: "Comparison",
                    summary: "The sources differ.",
                    keyPoints: ["Compare point"],
                    citations: [],
                    sources: []
                )
            )
        )

        let result = try await executor.execute(
            plan: webComparisonPlan(urls: [first, second], output: output)
        ) { _, _ in }

        let markdown = try String(contentsOf: output)
        #expect(markdown.contains("# Comparison"))
        #expect(markdown.contains("- [First Source](https://example.com/one)"))
        #expect(markdown.contains("- [Second Source](https://example.com/two)"))
        #expect(result.summary == "Saved comparison Markdown for 2 sources to \(output.path).")
    }

    @Test
    func webResearchSearchQueryUsesInjectedProviderAndWritesMarkdown() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("search-note.md")
        let first = URL(string: "https://example.com/swift-one")!
        let second = URL(string: "https://example.com/swift-two")!
        let searchProvider = StaticWebSearchProvider(results: [
            WebSearchResult(title: "Swift One", url: first, snippet: "First snippet"),
            WebSearchResult(title: "Swift Two", url: second, snippet: "Second snippet")
        ])
        let pageLoader = webPageLoader(pages: [
            first.absoluteString: readablePage(url: first, title: "Swift One"),
            second.absoluteString: readablePage(url: second, title: "Swift Two")
        ])
        let synthesizer = StaticWebResearchSynthesizer(
            note: WebResearchNote(
                title: "Swift Concurrency Research",
                summary: "Search-backed research summary.",
                keyPoints: ["Search point"],
                citations: [],
                sources: []
            )
        )
        let executor = makeExecutor(
            root: root,
            webPageLoader: pageLoader,
            webSearchProvider: searchProvider,
            webResearchSynthesizer: synthesizer
        )
        let plan = webSearchPlan(query: "Swift concurrency", output: output, count: 2)

        let preview = try executor.preview(plan: plan)
        #expect(preview.first?.title == "Save web research Markdown")
        #expect(preview.first?.details.contains("Search query: Swift concurrency") == true)
        #expect(preview.first?.writes == [output.path])

        let result = try await executor.execute(plan: plan) { _, _ in }

        let markdown = try String(contentsOf: output)
        #expect(searchProvider.queries == ["Swift concurrency"])
        #expect(searchProvider.limits == [2])
        #expect(markdown.contains("# Swift Concurrency Research"))
        #expect(markdown.contains("- [Swift One](https://example.com/swift-one)"))
        #expect(markdown.contains("- [Swift Two](https://example.com/swift-two)"))
        #expect(synthesizer.prompts[0].trustedPlan.steps[0].searchQuery == "Swift concurrency")
        #expect(result.summary == "Saved web research Markdown for search query \"Swift concurrency\" using 2 sources to \(output.path).")
    }

    @Test
    func webResearchSearchWithoutConfiguredProviderFailsClearly() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("search-note.md")
        let executor = makeExecutor(
            root: root,
            webResearchSynthesizer: StaticWebResearchSynthesizer(
                note: WebResearchNote(title: "Unused", summary: "Unused", keyPoints: [], citations: [], sources: [])
            )
        )
        let plan = webSearchPlan(query: "unconfigured provider", output: output)

        let preview = try executor.preview(plan: plan)
        #expect(preview.first?.details.contains("Search query: unconfigured provider") == true)
        await #expect(throws: WebResearchError.searchProviderNotConfigured) {
            try await executor.execute(plan: plan) { _, _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
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
    func openAppAndURLExecutionUseInjectedOpeners() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let appOpener = RecordingAppOpener()
        let browserOpener = RecordingBrowserOpener()
        let executor = makeExecutor(root: root, browserOpener: browserOpener, appOpener: appOpener)

        let appResult = try await executor.execute(plan: openAppPlan(appName: "Safari")) { _, _ in }
        let urlResult = try await executor.execute(plan: openURLPlan(url: "https://github.com")) { _, _ in }

        #expect(appOpener.openedBundleIDs == ["com.apple.Safari"])
        #expect(browserOpener.openedURLs.map(\.absoluteString) == ["https://github.com"])
        #expect(appResult.summary == "Opened Safari.")
        #expect(urlResult.summary == "Opened https://github.com.")
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
    func revealPreviewAllowsFuturePathButExecuteRequiresExistingPath() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let futureOutput = root.appendingPathComponent("future.zip")
        let executor = makeExecutor(root: root)

        let preview = try executor.preview(plan: revealPlan(output: futureOutput))

        #expect(preview.first?.title == "Reveal in Finder")
        #expect(preview.first?.details == ["Reveal \(futureOutput.path)"])
        await #expect(throws: PathValidationError.notFound(futureOutput.path)) {
            try await executor.execute(plan: revealPlan(output: futureOutput)) { _, _ in }
        }
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
    func permissionReadinessPreviewAndExecutionAreReadOnlyStatusChecks() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = makeExecutor(root: root)

        let prepared = try executor.prepare(plan: permissionReadinessPlan())
        let result = try await executor.execute(plan: permissionReadinessPlan()) { _, _ in }

        #expect(prepared.previews.first?.title == "Permission readiness")
        #expect(prepared.sideEffects.isEmpty)
        #expect(result.previews.first?.title == "Permission readiness")
        #expect(result.previews.first?.details.count == prepared.previews.first?.details.count)
        #expect(result.summary.hasPrefix("Permission readiness checked."))
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
    func routineRunUsesNestedDispatchForMixedChains() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let routineStore = RoutineStore(fileURL: root.appendingPathComponent("routines.json"))
        let appOpener = RecordingAppOpener()
        let browserOpener = RecordingBrowserOpener()
        let executor = makeExecutor(
            root: root,
            browserOpener: browserOpener,
            appOpener: appOpener,
            routineStore: routineStore
        )
        let savePlan = AgentPlan(
            summary: "Teach mixed routine.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "save-routine",
                    operation: .saveRoutine,
                    description: "Save routine.",
                    routineName: "Mixed Launch",
                    routineSteps: [
                        AgentStep(
                            id: "open-safari",
                            operation: .openApp,
                            description: "Open Safari.",
                            appName: "Safari"
                        ),
                        AgentStep(
                            id: "open-github",
                            operation: .openURL,
                            description: "Open GitHub.",
                            targetURL: "https://github.com"
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
                    routineName: "Mixed Launch"
                )
            ]
        )

        _ = try await executor.execute(plan: savePlan) { _, _ in }
        let result = try await executor.execute(plan: runPlan) { _, _ in }

        #expect(appOpener.openedBundleIDs == ["com.apple.Safari"])
        #expect(browserOpener.openedURLs.map(\.absoluteString) == ["https://github.com"])
        #expect(result.summary == "Ran routine Mixed Launch. Opened Safari. Opened https://github.com.")
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
        workspaceStore: WorkspaceStore? = nil,
        webPageLoader: PublicWebPageLoader? = nil,
        webSearchProvider: (any WebSearchProviding)? = nil,
        webResearchSynthesizer: (any WebResearchSynthesizing)? = nil
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
            workspaceStore: workspaceStore ?? WorkspaceStore(fileURL: root.appendingPathComponent("workspaces.json")),
            webPageLoader: webPageLoader,
            webSearchProvider: webSearchProvider,
            webResearchSynthesizer: webResearchSynthesizer
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

    private func webMarkdownPlan(url: URL, output: URL) -> AgentPlan {
        AgentPlan(
            summary: "Summarize the article as Markdown.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "web",
                    operation: .webToMarkdown,
                    description: "Summarize web article.",
                    outputPath: output.path,
                    targetURL: url.absoluteString
                )
            ]
        )
    }

    private func webComparisonPlan(urls: [URL], output: URL) -> AgentPlan {
        AgentPlan(
            summary: "Compare web sources as Markdown.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "web-comparison",
                    operation: .webToMarkdown,
                    description: "Compare source URLs.",
                    outputPath: output.path,
                    sourceURLs: urls.map(\.absoluteString)
                )
            ]
        )
    }

    private func webSearchPlan(query: String, output: URL, count: Int? = nil) -> AgentPlan {
        AgentPlan(
            summary: "Research a topic as Markdown.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "web-search",
                    operation: .webToMarkdown,
                    description: "Research topic.",
                    outputPath: output.path,
                    count: count,
                    searchQuery: query
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

    private func revealPlan(output: URL) -> AgentPlan {
        AgentPlan(
            summary: "Reveal a file.",
            requiresConfirmation: true,
            steps: [
                AgentStep(
                    id: "reveal",
                    operation: .revealInFinder,
                    description: "Reveal generated output",
                    outputPath: output.path
                )
            ]
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
                    description: "Show readiness"
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

private func webPageLoader(pages: [String: ReadableWebPage]) -> PublicWebPageLoader {
    PublicWebPageLoader(
        fetcher: StaticWebPageFetcher(pages: pages),
        robotsChecker: AllowingRobotsChecker(),
        extractor: StaticReadableWebExtractor(pages: pages)
    )
}

private func readablePage(
    url: URL,
    retrievedAt: Date = Date(timeIntervalSince1970: 1_783_526_400),
    title: String
) -> ReadableWebPage {
    ReadableWebPage(
        sourceURL: url,
        retrievedAt: retrievedAt,
        title: title,
        author: "Fixture Author",
        publishedDate: "2026-07-08",
        headings: [title],
        links: [],
        images: [],
        citations: ["Fixture citation"],
        readableText: "Readable content for \(title)."
    )
}

@MainActor
private struct StaticWebPageFetcher: WebPageFetching {
    var pages: [String: ReadableWebPage]

    func fetch(_ url: URL) async throws -> FetchedWebPage {
        guard let page = pages[url.absoluteString] else {
            throw WebResearchError.noReadableContent(url.absoluteString)
        }
        return FetchedWebPage(
            requestedURL: url,
            html: page.readableText,
            retrievedAt: page.retrievedAt
        )
    }
}

@MainActor
private struct AllowingRobotsChecker: RobotsTXTChecking {
    func canFetch(_ url: URL, userAgent: String) async throws -> Bool {
        true
    }
}

private struct StaticReadableWebExtractor: ReadableWebExtracting {
    var pages: [String: ReadableWebPage]

    func extract(html: String, sourceURL: URL, retrievedAt: Date) throws -> ReadableWebPage {
        guard let page = pages[sourceURL.absoluteString] else {
            throw WebResearchError.noReadableContent(sourceURL.absoluteString)
        }
        return page
    }
}

@MainActor
private final class StaticWebResearchSynthesizer: WebResearchSynthesizing {
    var note: WebResearchNote
    private(set) var prompts: [WebResearchSynthesisPrompt] = []

    init(note: WebResearchNote) {
        self.note = note
    }

    func synthesize(prompt: WebResearchSynthesisPrompt) async throws -> WebResearchNote {
        prompts.append(prompt)
        return note
    }
}

@MainActor
private final class StaticWebSearchProvider: WebSearchProviding {
    var results: [WebSearchResult]
    private(set) var queries: [String] = []
    private(set) var limits: [Int] = []

    init(results: [WebSearchResult]) {
        self.results = results
    }

    func search(query: String, limit: Int) async throws -> [WebSearchResult] {
        queries.append(query)
        limits.append(limit)
        return Array(results.prefix(max(limit, 0)))
    }
}
