import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct PlannerBoundaryTests {
    @Test
    func defaultToolRegistryPlannerDescriptionMatchesGolden() {
        assertExactString(ToolRegistry.default.plannerDescription, expectedDefaultPlannerDescription)
    }

    @Test
    func defaultSystemPromptMatchesGolden() {
        let expected = """
        You plan a tiny macOS agent. Return only a JSON object that matches the provided schema.

        Registered local tools:
        \(expectedDefaultPlannerDescription)

        Important rules:
        - Use only the fixed operation enum values.
        - Use registered tools only. Do not invent tools, commands, scripts, or APIs.
        - Include user-supplied paths exactly as written. Do not invent local file paths.
        - Use null for unavailable fields.
        - If a folder, app name, URL, count, or output destination is required but missing or ambiguous, return exactly one clarify step with a short question.
        - For largest files, produce scan_select_largest_files then create_zip.
        - For DOCX conversion, produce scan_docx then convert_docx_to_pdf.
        - For Hacker News headline saving, produce open_hacker_news, fetch_hn_headlines, then write_markdown.
        - For opening an app, produce one open_app step with appName.
        - For opening a general website, produce one open_url step with targetURL using http or https.
        - For song or album requests, produce one play_media step with mediaProvider, mediaTitle, optional mediaArtist, and targetURL only if the user supplied an exact Apple Music or Spotify result URI. The local executor opens the provider result; it does not start playback.
        - If a song or album request is missing the provider or title, ask a clarification question.
        - For Finder context phrases such as "selected folder", "selected files", "this Finder selection", or "the folder selected in Finder", set contextSource to finder_selection and leave inputPath null.
        - For "reveal the result/zip/markdown/PDFs in Finder" after a writing step, add reveal_in_finder with outputPath null so the executor can reveal the previous produced artifact.
        - For permission/readiness requests, produce one show_permission_readiness step.
        - For teaching a routine, produce one save_routine step with routineName and routineSteps containing only registered non-routine steps. Do not put save_routine, run_routine, clarify, or unsupported inside routineSteps.
        - For running a saved routine, produce one run_routine step with routineName.
        - For creating a workspace, produce one create_workspace step with workspaceName, workspaceApps, and workspaceURLs. Use only explicitly named apps/URLs. If none are provided, ask a clarification question.
        - For opening a saved workspace, produce one open_workspace step with workspaceName.
        - You may produce multi-step chained plans when the user asks for multiple supported actions. Keep steps in execution order.
        - For any unsupported request, return one unsupported step and explain why.
        - Never include shell commands, AppleScript, or code.
        """

        assertExactString(OpenAIPlanner.systemPrompt(toolRegistry: .default), expected)
    }

    @Test
    func responseFormatPreservesStrictAgentPlanSchemaShape() throws {
        let format = AgentPlanSchema.responseFormat()
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "agent_plan")
        #expect(format["strict"] as? Bool == true)

        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["type"] as? String == "object")
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["summary", "requiresConfirmation", "steps"])

        let properties = try #require(schema["properties"] as? [String: Any])
        let steps = try #require(properties["steps"] as? [String: Any])
        #expect(steps["type"] as? String == "array")
        #expect(steps["minItems"] as? Int == 1)

        let stepItems = try #require(steps["items"] as? [String: Any])
        #expect(stepItems["type"] as? String == "object")
        #expect(stepItems["additionalProperties"] as? Bool == false)
        #expect(stepItems["required"] as? [String] == [
            "id",
            "operation",
            "description",
            "inputPath",
            "outputPath",
            "count",
            "targetURL",
            "appName",
            "question",
            "mediaProvider",
            "mediaTitle",
            "mediaArtist",
            "contextSource",
            "routineName",
            "routineSteps",
            "workspaceName",
            "workspaceApps",
            "workspaceURLs"
        ])

        let stepProperties = try #require(stepItems["properties"] as? [String: Any])
        let operation = try #require(stepProperties["operation"] as? [String: Any])
        #expect(operation["type"] as? String == "string")
        #expect(operation["enum"] as? [String] == AgentOperation.allCases.map(\.rawValue))

        let routineSteps = try #require(stepProperties["routineSteps"] as? [String: Any])
        #expect(routineSteps["type"] as? [String] == ["array", "null"])
        let nestedItems = try #require(routineSteps["items"] as? [String: Any])
        let nestedProperties = try #require(nestedItems["properties"] as? [String: Any])
        let nestedRoutineSteps = try #require(nestedProperties["routineSteps"] as? [String: Any])
        #expect(nestedRoutineSteps["type"] as? String == "null")
    }
}

private let expectedDefaultPlannerDescription = """
- scan_select_largest_files: Scan and select largest files
  description: Recursively scan a whitelisted folder, skip symlinks, and select the largest regular files.
  required fields: inputPath, count
  side effects: none
  dry run: Show the selected files and sizes.
  examples: Find the 3 largest files in ~/Desktop/MacAgentDemo
- create_zip: Create zip archive
  description: Create a timestamped zip archive from the selected largest files.
  required fields: inputPath
  side effects: write file
  dry run: Show the zip path without writing it.
  examples: Zip the selected files
- scan_docx: Scan DOCX files
  description: Recursively find .docx files in a whitelisted folder.
  required fields: inputPath
  side effects: none
  dry run: List conversion targets and skipped existing PDFs.
  examples: Find DOCX files in ~/Documents/MacAgentDocs
- convert_docx_to_pdf: Convert DOCX to PDF
  description: Convert discovered DOCX files to PDFs using Microsoft Word or explicit mock mode.
  required fields: inputPath
  side effects: write files, control Microsoft Word
  dry run: Show conversion pairs without opening Word or writing PDFs.
  examples: Convert all .docx to .pdf in ~/Documents/MacAgentDocs
- open_hacker_news: Open Hacker News
  description: Open Hacker News in the default browser as part of the headline workflow.
  required fields: none
  side effects: open browser
  dry run: Show that Hacker News would open.
  examples: Open Hacker News
- fetch_hn_headlines: Fetch Hacker News headlines
  description: Fetch the top Hacker News headlines from the public API.
  required fields: count
  side effects: network request
  dry run: Show the number of headlines that would be fetched.
  examples: Grab the top 5 headlines
- write_markdown: Write Markdown file
  description: Write fetched Hacker News headlines to Markdown in a whitelisted output path.
  required fields: none
  side effects: write file
  dry run: Show the Markdown path without writing it.
  examples: Save to a Markdown file
- open_app: Open allowlisted Mac app
  description: Open an app from the local allowlist by human app name. Supported apps: Safari, Chrome, Finder, Notes, Calendar, Mail, Messages, Apple Music, Spotify, Slack, VS Code, Terminal.
  required fields: appName
  side effects: open app
  dry run: Show the allowlisted app that would open.
  examples: Open Safari | Open Spotify | Launch Apple Music
- open_url: Open web URL
  description: Open a safe http or https URL in the default browser.
  required fields: targetURL
  side effects: open browser
  dry run: Show the URL that would open.
  examples: Open GitHub | Open https://gmail.com
- play_media: Open music result
  description: Open a requested song or album in Apple Music or Spotify without starting playback. Apple Music opens the best matching catalog album result when found, otherwise search. Spotify opens a supplied Spotify result URI or a Spotify search.
  required fields: mediaProvider, mediaTitle
  side effects: open music app
  dry run: Show the provider, title, artist, and result/search behavior without opening an app.
  examples: Open Jimmy Cooks by Drake on Apple Music | Open Bad Habit by Steve Lacy on Spotify
- get_finder_selection: Read Finder selection
  description: Read selected Finder files and folders, validate that every path is inside the Desktop/Documents whitelist, and show them as context.
  required fields: none
  side effects: ask Finder for selection
  dry run: Show selected Finder items without modifying them.
  examples: What is selected in Finder? | Show my Finder selection
- reveal_in_finder: Reveal path in Finder
  description: Reveal a specific whitelisted path in Finder, or reveal the most recent file produced earlier in the same chain when outputPath is null.
  required fields: none
  side effects: open Finder
  dry run: Show the path that would be revealed.
  examples: Reveal the zip in Finder | Show the generated Markdown in Finder
- show_permission_readiness: Show permission readiness
  description: Show readiness for OpenAI key, microphone, hotkey, Finder/Word automation, Desktop/Documents access, Accessibility, and Screen Recording.
  required fields: none
  side effects: none
  dry run: Show permission readiness without requesting new permissions.
  examples: Check Sonny permissions | Show readiness panel
- save_routine: Teach Sonny a routine
  description: Save a named routine made from nested registered routineSteps. Routines are declarative local plans, not scripts.
  required fields: routineName, routineSteps
  side effects: write local routine file
  dry run: Show the routine name and nested steps without saving.
  examples: Teach Sonny a routine called morning setup that opens Safari and Notes
- run_routine: Run saved routine
  description: Load a saved routine by name and execute its registered steps with the same validation and logging as normal plans.
  required fields: routineName
  side effects: depends on saved routine
  dry run: Preview the saved routine without executing its steps.
  examples: Run my morning setup routine
- create_workspace: Create workspace launcher
  description: Save a named workspace containing allowlisted apps and safe http/https URLs.
  required fields: workspaceName
  side effects: write local workspace file
  dry run: Show the workspace apps and URLs without saving.
  examples: Create a workspace called research with Safari, VS Code, and https://github.com
- open_workspace: Open saved workspace
  description: Open every app and URL saved in a named workspace.
  required fields: workspaceName
  side effects: open apps, open browser
  dry run: Show apps and URLs that would open.
  examples: Open my research workspace | Start research mode
- clarify: Ask clarification
  description: Ask a short question when a required folder, app, count, or output destination is missing or ambiguous.
  required fields: question
  side effects: none
  dry run: Show the question and wait for the user answer.
  examples: Which folder should I scan?
"""

private func assertExactString(_ actual: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    guard actual != expected else {
        return
    }

    let actualScalars = Array(actual.unicodeScalars)
    let expectedScalars = Array(expected.unicodeScalars)
    let mismatch = (0..<min(actualScalars.count, expectedScalars.count)).first {
        actualScalars[$0] != expectedScalars[$0]
    }
    let detail: String
    if let mismatch {
        detail = "Mismatch at scalar \(mismatch): actual \(debugScalar(actualScalars[mismatch])), expected \(debugScalar(expectedScalars[mismatch]))."
    } else {
        detail = "No scalar mismatch before one string ended."
    }
    Issue.record("\(detail) actualCount=\(actualScalars.count), expectedCount=\(expectedScalars.count)", sourceLocation: sourceLocation)
}

private func debugScalar(_ scalar: UnicodeScalar) -> String {
    "\\u{\(String(scalar.value, radix: 16))} (\(String(scalar)))"
}
