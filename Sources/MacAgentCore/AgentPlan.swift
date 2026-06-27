import Foundation

public struct AgentPlan: Codable, Equatable, Sendable {
    public var summary: String
    public var requiresConfirmation: Bool
    public var steps: [AgentStep]

    public init(summary: String, requiresConfirmation: Bool, steps: [AgentStep]) {
        self.summary = summary
        self.requiresConfirmation = requiresConfirmation
        self.steps = steps
    }
}

public struct AgentStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var operation: AgentOperation
    public var description: String
    public var inputPath: String?
    public var outputPath: String?
    public var count: Int?
    public var targetURL: String?
    public var appName: String?
    public var question: String?

    public init(
        id: String,
        operation: AgentOperation,
        description: String,
        inputPath: String? = nil,
        outputPath: String? = nil,
        count: Int? = nil,
        targetURL: String? = nil,
        appName: String? = nil,
        question: String? = nil
    ) {
        self.id = id
        self.operation = operation
        self.description = description
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.count = count
        self.targetURL = targetURL
        self.appName = appName
        self.question = question
    }
}

public enum AgentOperation: String, Codable, CaseIterable, Sendable {
    case scanSelectLargestFiles = "scan_select_largest_files"
    case createZip = "create_zip"
    case scanDocx = "scan_docx"
    case convertDocxToPDF = "convert_docx_to_pdf"
    case openHackerNews = "open_hacker_news"
    case fetchHNHeadlines = "fetch_hn_headlines"
    case writeMarkdown = "write_markdown"
    case openApp = "open_app"
    case openURL = "open_url"
    case clarify
    case unsupported
}

public enum AgentPlanDecodingError: Error, Equatable, LocalizedError {
    case invalidJSON
    case unexpectedTopLevelKey(String)
    case unexpectedStepKey(String)
    case missingOutputText

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Planner returned invalid JSON."
        case .unexpectedTopLevelKey(let key):
            return "Planner returned an unexpected top-level key: \(key)."
        case .unexpectedStepKey(let key):
            return "Planner returned an unexpected step key: \(key)."
        case .missingOutputText:
            return "Planner response did not include output text."
        }
    }
}

public enum AgentPlanDecoder {
    private static let topLevelKeys: Set<String> = [
        "summary",
        "requiresConfirmation",
        "steps"
    ]

    private static let stepKeys: Set<String> = [
        "id",
        "operation",
        "description",
        "inputPath",
        "outputPath",
        "count",
        "targetURL",
        "appName",
        "question"
    ]

    public static func decodeStrict(from data: Data) throws -> AgentPlan {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw AgentPlanDecodingError.invalidJSON
        }

        for key in dictionary.keys where !topLevelKeys.contains(key) {
            throw AgentPlanDecodingError.unexpectedTopLevelKey(key)
        }

        guard let steps = dictionary["steps"] as? [[String: Any]] else {
            throw AgentPlanDecodingError.invalidJSON
        }

        for step in steps {
            for key in step.keys where !stepKeys.contains(key) {
                throw AgentPlanDecodingError.unexpectedStepKey(key)
            }
        }

        return try JSONDecoder().decode(AgentPlan.self, from: data)
    }

    public static func decodeStrict(from text: String) throws -> AgentPlan {
        guard let data = text.data(using: .utf8) else {
            throw AgentPlanDecodingError.invalidJSON
        }
        return try decodeStrict(from: data)
    }
}

public enum AgentPlanSchema {
    public static func responseFormat() -> [String: Any] {
        [
            "type": "json_schema",
            "name": "agent_plan",
            "strict": true,
            "schema": [
                "type": "object",
                "additionalProperties": false,
                "required": ["summary", "requiresConfirmation", "steps"],
                "properties": [
                    "summary": [
                        "type": "string",
                        "description": "Short human-readable summary of the proposed action."
                    ],
                    "requiresConfirmation": [
                        "type": "boolean",
                        "description": "True when the action writes files, opens apps, or converts documents."
                    ],
                    "steps": [
                        "type": "array",
                        "minItems": 1,
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": [
                                "id",
                                "operation",
                                "description",
                                "inputPath",
                                "outputPath",
                                "count",
                                "targetURL",
                                "appName",
                                "question"
                            ],
                            "properties": [
                                "id": ["type": "string"],
                                "operation": [
                                    "type": "string",
                                    "enum": AgentOperation.allCases.map(\.rawValue)
                                ],
                                "description": ["type": "string"],
                                "inputPath": [
                                    "type": ["string", "null"],
                                    "description": "Folder or file path supplied by the user, or null."
                                ],
                                "outputPath": [
                                    "type": ["string", "null"],
                                    "description": "Destination folder or file path, or null."
                                ],
                                "count": [
                                    "type": ["integer", "null"],
                                    "description": "Requested count, such as top 3 files or top 5 headlines."
                                ],
                                "targetURL": [
                                    "type": ["string", "null"],
                                    "description": "URL for browser/fetch actions, or null."
                                ],
                                "appName": [
                                    "type": ["string", "null"],
                                    "description": "Human app name for open_app actions, or null."
                                ],
                                "question": [
                                    "type": ["string", "null"],
                                    "description": "Clarifying question for clarify actions, or null."
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }
}
