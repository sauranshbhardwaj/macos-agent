import Foundation

@MainActor
public protocol Planning {
    func plan(command: String) async throws -> AgentPlan
}

public enum PlannerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case badResponse(Int, String)
    case missingOutputText

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is not set. Add it to the environment before launching the app."
        case .badResponse(let status, let body):
            return "OpenAI planner request failed with HTTP \(status): \(body)"
        case .missingOutputText:
            return "OpenAI response did not include text output."
        }
    }
}

@MainActor
public final class OpenAIPlanner: Planning {
    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession
    private let toolRegistry: ToolRegistry

    public init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.5",
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        session: URLSession = .shared,
        toolRegistry: ToolRegistry = .default
    ) throws {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlannerError.missingAPIKey
        }
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.session = session
        self.toolRegistry = toolRegistry
    }

    public func plan(command: String) async throws -> AgentPlan {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(command: command))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlannerError.badResponse(-1, "No HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable body>"
            throw PlannerError.badResponse(httpResponse.statusCode, body)
        }

        let text = try OpenAIResponseParser.outputText(from: data)
        return try AgentPlanDecoder.decodeStrict(from: text)
    }

    private func requestBody(command: String) -> [String: Any] {
        [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [
                        [
                            "type": "input_text",
                            "text": Self.systemPrompt(toolRegistry: toolRegistry)
                        ]
                    ]
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": command
                        ]
                    ]
                ]
            ],
            "reasoning": [
                "effort": "medium"
            ],
            "text": [
                "verbosity": "low",
                "format": AgentPlanSchema.responseFormat()
            ]
        ]
    }

    nonisolated public static func systemPrompt(toolRegistry: ToolRegistry = .default) -> String {
        """
    You plan a tiny macOS agent. Return only a JSON object that matches the provided schema.

    Registered local tools:
    \(toolRegistry.plannerDescription)

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
    - For any unsupported request, return one unsupported step and explain why.
    - Never include shell commands, AppleScript, or code.
    """
    }
}

public enum OpenAIResponseParser {
    public static func outputText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw PlannerError.missingOutputText
        }

        if let direct = dictionary["output_text"] as? String, !direct.isEmpty {
            return direct
        }

        guard let output = dictionary["output"] as? [[String: Any]] else {
            throw PlannerError.missingOutputText
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }
            for part in content {
                if let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }

        throw PlannerError.missingOutputText
    }
}
