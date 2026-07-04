import Foundation

public enum DefaultCapabilityAdapters {
    public static func all() -> [any CapabilityAdapter] {
        [
            LargestFilesZipCapabilityAdapter(),
            DocxConversionCapabilityAdapter(),
            HackerNewsMarkdownCapabilityAdapter(),
            OpenAllowlistedAppCapabilityAdapter(),
            OpenSafeURLCapabilityAdapter(),
            OpenMediaResultCapabilityAdapter(),
            MetadataOnlyCapabilityAdapter(metadata: finderSelection),
            MetadataOnlyCapabilityAdapter(metadata: revealInFinder),
            MetadataOnlyCapabilityAdapter(metadata: permissionReadiness),
            MetadataOnlyCapabilityAdapter(metadata: saveRoutine),
            MetadataOnlyCapabilityAdapter(metadata: runRoutine),
            MetadataOnlyCapabilityAdapter(metadata: createWorkspace),
            MetadataOnlyCapabilityAdapter(metadata: openWorkspace),
            MetadataOnlyCapabilityAdapter(metadata: clarify)
        ]
    }

    private static let finderSelection = CapabilityMetadata(
        id: "local.finder.read-selection",
        displayName: "Read Finder selection",
        description: "Read selected Finder items and validate them against the path whitelist.",
        operations: [.getFinderSelection],
        plannerTools: [
            AgentTool(
                operation: .getFinderSelection,
                name: "Read Finder selection",
                description: "Read selected Finder files and folders, validate that every path is inside the Desktop/Documents whitelist, and show them as context.",
                requiredFields: [],
                sideEffects: ["ask Finder for selection"],
                dryRunBehavior: "Show selected Finder items without modifying them.",
                examples: ["What is selected in Finder?", "Show my Finder selection"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .finderAutomation),
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess)
        ],
        defaultRiskTier: .tier0
    )

    private static let revealInFinder = CapabilityMetadata(
        id: "local.finder.reveal-path",
        displayName: "Reveal in Finder",
        description: "Reveal a whitelisted path in Finder.",
        operations: [.revealInFinder],
        plannerTools: [
            AgentTool(
                operation: .revealInFinder,
                name: "Reveal path in Finder",
                description: "Reveal a specific whitelisted path in Finder, or reveal the most recent file produced earlier in the same chain when outputPath is null.",
                requiredFields: [],
                sideEffects: ["open Finder"],
                dryRunBehavior: "Show the path that would be revealed.",
                examples: ["Reveal the zip in Finder", "Show the generated Markdown in Finder"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .desktopDocumentsAccess),
            CapabilityPermissionMetadata(requirement: .appOpening)
        ],
        defaultRiskTier: .tier1
    )

    private static let permissionReadiness = CapabilityMetadata(
        id: "local.permissions.readiness",
        displayName: "Permission readiness",
        description: "Show current readiness status without prompting for permissions.",
        operations: [.showPermissionReadiness],
        plannerTools: [
            AgentTool(
                operation: .showPermissionReadiness,
                name: "Show permission readiness",
                description: "Show readiness for OpenAI key, microphone, hotkey, Finder/Word automation, Desktop/Documents access, Accessibility, and Screen Recording.",
                requiredFields: [],
                sideEffects: [],
                dryRunBehavior: "Show permission readiness without requesting new permissions.",
                examples: ["Check Sonny permissions", "Show readiness panel"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier0
    )

    private static let saveRoutine = CapabilityMetadata(
        id: "local.routines.save",
        displayName: "Teach Sonny a routine",
        description: "Save a named declarative routine made from registered Sonny tools.",
        operations: [.saveRoutine],
        plannerTools: [
            AgentTool(
                operation: .saveRoutine,
                name: "Teach Sonny a routine",
                description: "Save a named routine made from nested registered routineSteps. Routines are declarative local plans, not scripts.",
                requiredFields: ["routineName", "routineSteps"],
                sideEffects: ["write local routine file"],
                dryRunBehavior: "Show the routine name and nested steps without saving.",
                examples: ["Teach Sonny a routine called morning setup that opens Safari and Notes"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    private static let runRoutine = CapabilityMetadata(
        id: "local.routines.run",
        displayName: "Run saved routine",
        description: "Load and run a saved routine through normal plan validation.",
        operations: [.runRoutine],
        plannerTools: [
            AgentTool(
                operation: .runRoutine,
                name: "Run saved routine",
                description: "Load a saved routine by name and execute its registered steps with the same validation and logging as normal plans.",
                requiredFields: ["routineName"],
                sideEffects: ["depends on saved routine"],
                dryRunBehavior: "Preview the saved routine without executing its steps.",
                examples: ["Run my morning setup routine"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    private static let createWorkspace = CapabilityMetadata(
        id: "local.workspaces.create",
        displayName: "Create workspace launcher",
        description: "Save a named workspace of allowlisted apps and safe URLs.",
        operations: [.createWorkspace],
        plannerTools: [
            AgentTool(
                operation: .createWorkspace,
                name: "Create workspace launcher",
                description: "Save a named workspace containing allowlisted apps and safe http/https URLs.",
                requiredFields: ["workspaceName"],
                sideEffects: ["write local workspace file"],
                dryRunBehavior: "Show the workspace apps and URLs without saving.",
                examples: ["Create a workspace called research with Safari, VS Code, and https://github.com"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier2
    )

    private static let openWorkspace = CapabilityMetadata(
        id: "local.workspaces.open",
        displayName: "Open saved workspace",
        description: "Open every allowlisted app and safe URL saved in a named workspace.",
        operations: [.openWorkspace],
        plannerTools: [
            AgentTool(
                operation: .openWorkspace,
                name: "Open saved workspace",
                description: "Open every app and URL saved in a named workspace.",
                requiredFields: ["workspaceName"],
                sideEffects: ["open apps", "open browser"],
                dryRunBehavior: "Show apps and URLs that would open.",
                examples: ["Open my research workspace", "Start research mode"]
            )
        ],
        requiredPermissions: [
            CapabilityPermissionMetadata(requirement: .appOpening),
            CapabilityPermissionMetadata(requirement: .browserOpening)
        ],
        defaultRiskTier: .tier1
    )

    private static let clarify = CapabilityMetadata(
        id: "local.planner.clarify",
        displayName: "Ask clarification",
        description: "Ask a short clarifying question with no side effects.",
        operations: [.clarify],
        plannerTools: [
            AgentTool(
                operation: .clarify,
                name: "Ask clarification",
                description: "Ask a short question when a required folder, app, count, or output destination is missing or ambiguous.",
                requiredFields: ["question"],
                sideEffects: [],
                dryRunBehavior: "Show the question and wait for the user answer.",
                examples: ["Which folder should I scan?"]
            )
        ],
        requiredPermissions: [],
        defaultRiskTier: .tier0
    )
}
