import Foundation
import Testing
@testable import MacAgentCore

@Suite
@MainActor
struct SnippetExpansionTests {
    @Test
    func storeSavesAndFindsExactTriggersOnly() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        let snippet = StoredSnippet(
            trigger: " ;sig ",
            expansion: " Best,\nSonny ",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try store.save(snippet)

        #expect(try store.snippet(matchingTrigger: ";sig").expansion == "Best,\nSonny")
        #expect(try store.findExactTrigger(";sig")?.trigger == ";sig")
        #expect(try store.findExactTrigger(" ;sig ")?.trigger == ";sig")
        #expect(try store.findExactTrigger(";SIG") == nil)
    }

    @Test
    func storeValidatesTriggerAndExpansion() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))

        #expect(throws: SnippetStoreError.missingTrigger) {
            try store.save(StoredSnippet(trigger: " ", expansion: "Hello"))
        }
        #expect(throws: SnippetStoreError.missingExpansion) {
            try store.save(StoredSnippet(trigger: ";hello", expansion: " "))
        }
    }

    @Test
    func resolverBuildsSnippetPlanForExactSavedTrigger() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        try store.save(StoredSnippet(trigger: ";sig", expansion: "Best,\nSonny"))
        let resolver = InstantCommandResolver(snippetStore: store)

        guard case .plan(let plan) = resolver.resolve(command: ";sig") else {
            Issue.record("Expected saved snippet trigger to resolve locally.")
            return
        }

        #expect(plan.steps.map(\.operation) == [.expandSnippet])
        #expect(plan.steps[0].searchQuery == ";sig")
        #expect(resolver.resolve(command: ";missing") == nil)
    }

    @Test
    func snippetExpansionUsesTierZeroRunnerPath() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        try store.save(StoredSnippet(trigger: ";sig", expansion: "Best,\nSonny"))
        let executor = AgentActionExecutor(snippetStore: store)
        let runner = AgentRunner(planner: FailingPlanner(), executor: executor)
        let plan = AgentPlan(
            summary: "Expand snippet ;sig.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "snippet",
                    operation: .expandSnippet,
                    description: "Expand snippet ;sig.",
                    searchQuery: ";sig"
                )
            ]
        )

        let prepared = try runner.prepare(plan: plan, source: .instantResolver)
        #expect(prepared.previews.first?.title == "Expand snippet")
        #expect(prepared.previews.first?.details.contains("Expansion: Best,\nSonny") == true)

        let request = try runner.approvalRequest(for: prepared)
        #expect(request.assessment.effectiveTier == .tier0)
        #expect(request.requirement == .autoRun)

        let result = try await runner.execute(prepared)
        #expect(result.summary == "Best,\nSonny")
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnippetExpansionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct FailingPlanner: Planning {
    func plan(command: String) async throws -> AgentPlan {
        Issue.record("Planner should not be called for snippet instant commands.")
        throw PlannerError.missingAPIKey
    }
}
