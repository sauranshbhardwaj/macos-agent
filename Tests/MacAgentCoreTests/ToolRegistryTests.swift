import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct ToolRegistryTests {
    @Test
    func defaultRegistryDescribesNewAgentTools() {
        let registry = ToolRegistry.default
        let operations = registry.tools.map(\.operation)

        #expect(operations.contains(.openApp))
        #expect(operations.contains(.openURL))
        #expect(operations.contains(.webToMarkdown))
        #expect(operations.contains(.playMedia))
        #expect(operations.contains(.clarify))
        #expect(registry.plannerDescription.contains("open_app"))
        #expect(registry.plannerDescription.contains("open_url"))
        #expect(registry.plannerDescription.contains("web_to_markdown"))
        #expect(registry.plannerDescription.contains("play_media"))
        #expect(registry.plannerDescription.contains("Play Jimmy Cooks by Drake on Apple Music"))
        #expect(registry.plannerDescription.contains("Spotify"))
        #expect(registry.plannerDescription.contains("Apple Music"))
    }

    @Test
    func plannerPromptIsGeneratedFromToolRegistry() {
        let registry = ToolRegistry(
            tools: [
                AgentTool(
                    operation: .openApp,
                    name: "Open test app",
                    description: "Open a test app.",
                    requiredFields: ["appName"],
                    sideEffects: ["open app"],
                    dryRunBehavior: "Preview the app.",
                    examples: ["Open Test"]
                )
            ]
        )

        let prompt = OpenAIPlanner.systemPrompt(toolRegistry: registry)

        #expect(prompt.contains("open_app"))
        #expect(prompt.contains("Open test app"))
        #expect(prompt.contains("Do not invent tools"))
    }
}
