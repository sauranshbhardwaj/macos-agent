import Foundation

// SONNY-69 experiment (throwaway spike — never merges). A planner speaking the OpenAI-compatible
// Chat Completions dialect to Cerebras inference (gpt-oss-120b), behind the same `Planning`
// protocol the app already consumes. Selected only when SONNY_PLANNER=cerebras; the default
// OpenAI Responses path is untouched.

public enum CerebrasPlannerError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case badResponse(Int, String)
    case missingOutputText

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "CEREBRAS_API_KEY is not set. Add it to the environment before launching the app."
        case .badResponse(let status, let body):
            return "Cerebras planner request failed with HTTP \(status): \(body)"
        case .missingOutputText:
            return "Cerebras response did not include message content."
        }
    }
}

@MainActor
public final class CerebrasPlanner: Planning {
    private let apiKey: String
    private let model: String
    private let endpoint: URL
    private let session: URLSession
    private let toolRegistry: ToolRegistry
    private let usageRecorder: any TaskUsageRecording

    public init(
        apiKey: String? = ProcessInfo.processInfo.environment["CEREBRAS_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["CEREBRAS_MODEL"] ?? "gpt-oss-120b",
        endpoint: URL = URL(string: "https://api.cerebras.ai/v1/chat/completions")!,
        session: URLSession = .shared,
        toolRegistry: ToolRegistry = .default,
        usageRecorder: any TaskUsageRecording = NoopTaskUsageRecorder.shared
    ) throws {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CerebrasPlannerError.missingAPIKey
        }
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.session = session
        self.toolRegistry = toolRegistry
        self.usageRecorder = usageRecorder
    }

    public func plan(command: String, priorTaskContext: PriorTaskContext? = nil) async throws -> AgentPlan {
        let requestBody = requestBody(command: command, priorTaskContext: priorTaskContext)
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CerebrasPlannerError.badResponse(-1, "No HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable body>"
            throw CerebrasPlannerError.badResponse(httpResponse.statusCode, body)
        }

        // `responsesUsage` already reads both key dialects (input_tokens/prompt_tokens,
        // output_tokens/completion_tokens), so the Chat Completions usage object parses as-is.
        let reportedUsage = try AIUsagePayloadParser.responsesUsage(from: data)
        let outputTextResult = Result {
            try CerebrasChatResponseParser.messageContent(from: data)
        }
        usageRecorder.record(
            AIUsageRecord.responses(
                kind: .planner,
                model: model,
                reportedUsage: reportedUsage,
                estimatedInputText: String(data: requestData, encoding: .utf8) ?? command,
                estimatedOutputText: (try? outputTextResult.get()) ?? ""
            )
        )
        let text = try outputTextResult.get()
        return try AgentPlanDecoder.decodeStrict(from: CerebrasChatResponseParser.strippedJSONText(text))
    }

    private func requestBody(command: String, priorTaskContext: PriorTaskContext?) -> [String: Any] {
        // Cerebras's documented structured-output constraints reject the shared plan schema
        // (5,000-char schema cap vs our ~9.2KB, and no `"type": [T, "null"]` unions, used 25
        // times) — so the default mode embeds the schema in the system prompt and relies on
        // AgentPlanDecoder.decodeStrict for enforcement. SONNY_CEREBRAS_STRUCTURED=1 opts into
        // the native response_format anyway so the rejection/acceptance can be measured live.
        let useNativeStructured = ProcessInfo.processInfo.environment["SONNY_CEREBRAS_STRUCTURED"] == "1"
        var systemPrompt = OpenAIPlanner.systemPrompt(toolRegistry: toolRegistry)
        if !useNativeStructured {
            systemPrompt += Self.schemaPromptSuffix()
        }

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        if let priorTaskContext {
            messages.append(["role": "user", "content": priorTaskContext.plannerContextText])
        }
        messages.append(["role": "user", "content": command])

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "reasoning_effort": "medium"
        ]
        if useNativeStructured {
            body["response_format"] = Self.chatCompletionsResponseFormat()
        }
        return body
    }

    static func schemaPromptSuffix() -> String {
        let flat = AgentPlanSchema.responseFormat()
        let schema = flat["schema"] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return "\n\nReturn ONLY a single JSON object — no markdown fences, no commentary — conforming exactly to this JSON Schema:\n" + text
    }

    // The shared schema is authored in the Responses `text.format` shape (flat
    // type/name/strict/schema); Chat Completions nests name/strict/schema one level down
    // under a "json_schema" key. Re-wrap rather than duplicating the 500-line schema.
    static func chatCompletionsResponseFormat() -> [String: Any] {
        let flat = AgentPlanSchema.responseFormat()
        return [
            "type": "json_schema",
            "json_schema": [
                "name": flat["name"] ?? "agent_plan",
                "strict": flat["strict"] ?? true,
                "schema": flat["schema"] ?? [:]
            ]
        ]
    }
}

public enum CerebrasChatResponseParser {
    public static func messageContent(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let choices = dictionary["choices"] as? [[String: Any]] else {
            throw CerebrasPlannerError.missingOutputText
        }
        for choice in choices {
            if let message = choice["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                return content
            }
        }
        throw CerebrasPlannerError.missingOutputText
    }

    // Structured outputs should guarantee raw JSON, but `AgentPlanDecoder.decodeStrict`
    // tolerates no fencing at all, so strip a stray markdown fence defensively.
    public static func strippedJSONText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
