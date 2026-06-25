import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct AgentPlanDecoderTests {
    @Test
    func decodesGoldenPlan() throws {
        let json = """
        {
          "summary": "Zip the three largest files.",
          "requiresConfirmation": true,
          "steps": [
            {
              "id": "scan",
              "operation": "scan_select_largest_files",
              "description": "Scan the folder.",
              "inputPath": "~/Desktop",
              "outputPath": null,
              "count": 3,
              "targetURL": null
            },
            {
              "id": "zip",
              "operation": "create_zip",
              "description": "Create the archive.",
              "inputPath": "~/Desktop",
              "outputPath": "~/Desktop/largest.zip",
              "count": 3,
              "targetURL": null
            }
          ]
        }
        """

        let plan = try AgentPlanDecoder.decodeStrict(from: json)

        #expect(plan.summary == "Zip the three largest files.")
        #expect(plan.steps.map(\.operation) == [.scanSelectLargestFiles, .createZip])
        #expect(plan.steps[0].count == 3)
    }

    @Test
    func rejectsUnexpectedTopLevelKey() throws {
        let json = """
        {
          "summary": "Nope",
          "requiresConfirmation": false,
          "steps": [],
          "shell": "rm -rf"
        }
        """

        #expect(throws: AgentPlanDecodingError.unexpectedTopLevelKey("shell")) {
            try AgentPlanDecoder.decodeStrict(from: json)
        }
    }

    @Test
    func rejectsUnexpectedStepKey() throws {
        let json = """
        {
          "summary": "Nope",
          "requiresConfirmation": false,
          "steps": [
            {
              "id": "bad",
              "operation": "unsupported",
              "description": "Nope",
              "inputPath": null,
              "outputPath": null,
              "count": null,
              "targetURL": null,
              "appleScript": "display dialog"
            }
          ]
        }
        """

        #expect(throws: AgentPlanDecodingError.unexpectedStepKey("appleScript")) {
            try AgentPlanDecoder.decodeStrict(from: json)
        }
    }

    @Test
    func rejectsUnknownOperation() throws {
        let json = """
        {
          "summary": "Nope",
          "requiresConfirmation": false,
          "steps": [
            {
              "id": "bad",
              "operation": "delete_everything",
              "description": "Nope",
              "inputPath": null,
              "outputPath": null,
              "count": null,
              "targetURL": null
            }
          ]
        }
        """

        #expect(throws: (any Error).self) {
            try AgentPlanDecoder.decodeStrict(from: json)
        }
    }

    @Test
    func parsesResponsesOutputText() throws {
        let response = """
        {
          "id": "resp_123",
          "output": [
            {
              "type": "message",
              "content": [
                {
                  "type": "output_text",
                  "text": "{\\"summary\\":\\"HN\\",\\"requiresConfirmation\\":true,\\"steps\\":[{\\"id\\":\\"fetch\\",\\"operation\\":\\"fetch_hn_headlines\\",\\"description\\":\\"Fetch\\",\\"inputPath\\":null,\\"outputPath\\":null,\\"count\\":5,\\"targetURL\\":\\"https://news.ycombinator.com\\"}]}"
                }
              ]
            }
          ]
        }
        """

        let text = try OpenAIResponseParser.outputText(from: Data(response.utf8))
        let plan = try AgentPlanDecoder.decodeStrict(from: text)

        #expect(plan.steps[0].operation == .fetchHNHeadlines)
    }
}
