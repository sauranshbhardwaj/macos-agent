import Foundation

public struct AgentTool: Equatable, Sendable {
    public var operation: AgentOperation
    public var name: String
    public var description: String
    public var requiredFields: [String]
    public var sideEffects: [String]
    public var dryRunBehavior: String
    public var examples: [String]

    public init(
        operation: AgentOperation,
        name: String,
        description: String,
        requiredFields: [String],
        sideEffects: [String],
        dryRunBehavior: String,
        examples: [String] = []
    ) {
        self.operation = operation
        self.name = name
        self.description = description
        self.requiredFields = requiredFields
        self.sideEffects = sideEffects
        self.dryRunBehavior = dryRunBehavior
        self.examples = examples
    }
}

public struct ToolRegistry: Equatable, Sendable {
    public var tools: [AgentTool]

    public init(tools: [AgentTool] = Self.default.tools) {
        self.tools = tools
    }

    public static let `default` = ToolRegistry(tools: [
        AgentTool(
            operation: .scanSelectLargestFiles,
            name: "Scan and select largest files",
            description: "Recursively scan a whitelisted folder, skip symlinks, and select the largest regular files.",
            requiredFields: ["inputPath", "count"],
            sideEffects: [],
            dryRunBehavior: "Show the selected files and sizes.",
            examples: ["Find the 3 largest files in ~/Desktop/MacAgentDemo"]
        ),
        AgentTool(
            operation: .createZip,
            name: "Create zip archive",
            description: "Create a timestamped zip archive from the selected largest files.",
            requiredFields: ["inputPath"],
            sideEffects: ["write file"],
            dryRunBehavior: "Show the zip path without writing it.",
            examples: ["Zip the selected files"]
        ),
        AgentTool(
            operation: .scanDocx,
            name: "Scan DOCX files",
            description: "Recursively find .docx files in a whitelisted folder.",
            requiredFields: ["inputPath"],
            sideEffects: [],
            dryRunBehavior: "List conversion targets and skipped existing PDFs.",
            examples: ["Find DOCX files in ~/Documents/MacAgentDocs"]
        ),
        AgentTool(
            operation: .convertDocxToPDF,
            name: "Convert DOCX to PDF",
            description: "Convert discovered DOCX files to PDFs using Microsoft Word or explicit mock mode.",
            requiredFields: ["inputPath"],
            sideEffects: ["write files", "control Microsoft Word"],
            dryRunBehavior: "Show conversion pairs without opening Word or writing PDFs.",
            examples: ["Convert all .docx to .pdf in ~/Documents/MacAgentDocs"]
        ),
        AgentTool(
            operation: .openHackerNews,
            name: "Open Hacker News",
            description: "Open Hacker News in the default browser as part of the headline workflow.",
            requiredFields: [],
            sideEffects: ["open browser"],
            dryRunBehavior: "Show that Hacker News would open.",
            examples: ["Open Hacker News"]
        ),
        AgentTool(
            operation: .fetchHNHeadlines,
            name: "Fetch Hacker News headlines",
            description: "Fetch the top Hacker News headlines from the public API.",
            requiredFields: ["count"],
            sideEffects: ["network request"],
            dryRunBehavior: "Show the number of headlines that would be fetched.",
            examples: ["Grab the top 5 headlines"]
        ),
        AgentTool(
            operation: .writeMarkdown,
            name: "Write Markdown file",
            description: "Write fetched Hacker News headlines to Markdown in a whitelisted output path.",
            requiredFields: [],
            sideEffects: ["write file"],
            dryRunBehavior: "Show the Markdown path without writing it.",
            examples: ["Save to a Markdown file"]
        ),
        AgentTool(
            operation: .openApp,
            name: "Open allowlisted Mac app",
            description: "Open an app from the local allowlist by human app name. Supported apps: \(MacAppCatalog.default.displayList).",
            requiredFields: ["appName"],
            sideEffects: ["open app"],
            dryRunBehavior: "Show the allowlisted app that would open.",
            examples: ["Open Safari", "Open Spotify", "Launch Apple Music"]
        ),
        AgentTool(
            operation: .openURL,
            name: "Open web URL",
            description: "Open a safe http or https URL in the default browser.",
            requiredFields: ["targetURL"],
            sideEffects: ["open browser"],
            dryRunBehavior: "Show the URL that would open.",
            examples: ["Open GitHub", "Open https://gmail.com"]
        ),
        AgentTool(
            operation: .playMedia,
            name: "Open music result",
            description: "Open a requested song or album in Apple Music or Spotify without starting playback. Apple Music opens the best matching catalog album result when found, otherwise search. Spotify opens a supplied Spotify result URI or a Spotify search.",
            requiredFields: ["mediaProvider", "mediaTitle"],
            sideEffects: ["open music app"],
            dryRunBehavior: "Show the provider, title, artist, and result/search behavior without opening an app.",
            examples: [
                "Open Jimmy Cooks by Drake on Apple Music",
                "Open Bad Habit by Steve Lacy on Spotify"
            ]
        ),
        AgentTool(
            operation: .getFinderSelection,
            name: "Read Finder selection",
            description: "Read selected Finder files and folders, validate that every path is inside the Desktop/Documents whitelist, and show them as context.",
            requiredFields: [],
            sideEffects: ["ask Finder for selection"],
            dryRunBehavior: "Show selected Finder items without modifying them.",
            examples: ["What is selected in Finder?", "Show my Finder selection"]
        ),
        AgentTool(
            operation: .revealInFinder,
            name: "Reveal path in Finder",
            description: "Reveal a specific whitelisted path in Finder, or reveal the most recent file produced earlier in the same chain when outputPath is null.",
            requiredFields: [],
            sideEffects: ["open Finder"],
            dryRunBehavior: "Show the path that would be revealed.",
            examples: ["Reveal the zip in Finder", "Show the generated Markdown in Finder"]
        ),
        AgentTool(
            operation: .showPermissionReadiness,
            name: "Show permission readiness",
            description: "Show readiness for OpenAI key, microphone, hotkey, Finder/Word automation, Desktop/Documents access, Accessibility, and Screen Recording.",
            requiredFields: [],
            sideEffects: [],
            dryRunBehavior: "Show permission readiness without requesting new permissions.",
            examples: ["Check Sonny permissions", "Show readiness panel"]
        ),
        AgentTool(
            operation: .saveRoutine,
            name: "Teach Sonny a routine",
            description: "Save a named routine made from nested registered routineSteps. Routines are declarative local plans, not scripts.",
            requiredFields: ["routineName", "routineSteps"],
            sideEffects: ["write local routine file"],
            dryRunBehavior: "Show the routine name and nested steps without saving.",
            examples: ["Teach Sonny a routine called morning setup that opens Safari and Notes"]
        ),
        AgentTool(
            operation: .runRoutine,
            name: "Run saved routine",
            description: "Load a saved routine by name and execute its registered steps with the same validation and logging as normal plans.",
            requiredFields: ["routineName"],
            sideEffects: ["depends on saved routine"],
            dryRunBehavior: "Preview the saved routine without executing its steps.",
            examples: ["Run my morning setup routine"]
        ),
        AgentTool(
            operation: .createWorkspace,
            name: "Create workspace launcher",
            description: "Save a named workspace containing allowlisted apps and safe http/https URLs.",
            requiredFields: ["workspaceName"],
            sideEffects: ["write local workspace file"],
            dryRunBehavior: "Show the workspace apps and URLs without saving.",
            examples: ["Create a workspace called research with Safari, VS Code, and https://github.com"]
        ),
        AgentTool(
            operation: .openWorkspace,
            name: "Open saved workspace",
            description: "Open every app and URL saved in a named workspace.",
            requiredFields: ["workspaceName"],
            sideEffects: ["open apps", "open browser"],
            dryRunBehavior: "Show apps and URLs that would open.",
            examples: ["Open my research workspace", "Start research mode"]
        ),
        AgentTool(
            operation: .clarify,
            name: "Ask clarification",
            description: "Ask a short question when a required folder, app, count, or output destination is missing or ambiguous.",
            requiredFields: ["question"],
            sideEffects: [],
            dryRunBehavior: "Show the question and wait for the user answer.",
            examples: ["Which folder should I scan?"]
        )
    ])

    public var plannerDescription: String {
        tools.map { tool in
            let required = tool.requiredFields.isEmpty ? "none" : tool.requiredFields.joined(separator: ", ")
            let effects = tool.sideEffects.isEmpty ? "none" : tool.sideEffects.joined(separator: ", ")
            let examples = tool.examples.isEmpty ? "" : "\n  examples: \(tool.examples.joined(separator: " | "))"
            return """
            - \(tool.operation.rawValue): \(tool.name)
              description: \(tool.description)
              required fields: \(required)
              side effects: \(effects)
              dry run: \(tool.dryRunBehavior)\(examples)
            """
        }
        .joined(separator: "\n")
    }
}
