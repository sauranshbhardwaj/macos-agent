import Foundation

@MainActor
public protocol Planning {
    func plan(command: String, priorTaskContext: PriorTaskContext?) async throws -> AgentPlan
}

public extension Planning {
    func plan(command: String) async throws -> AgentPlan {
        try await plan(command: command, priorTaskContext: nil)
    }
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
    private let usageRecorder: any TaskUsageRecording

    public init(
        apiKey: String? = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        model: String = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.5",
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
        session: URLSession = .shared,
        toolRegistry: ToolRegistry = .default,
        usageRecorder: any TaskUsageRecording = NoopTaskUsageRecorder.shared
    ) throws {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlannerError.missingAPIKey
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
            throw PlannerError.badResponse(-1, "No HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable body>"
            throw PlannerError.badResponse(httpResponse.statusCode, body)
        }

        let reportedUsage = try AIUsagePayloadParser.responsesUsage(from: data)
        let outputTextResult = Result {
            try OpenAIResponseParser.outputText(from: data)
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
        return try AgentPlanDecoder.decodeStrict(from: text)
    }

    private func requestBody(command: String, priorTaskContext: PriorTaskContext?) -> [String: Any] {
        var input = [
            Self.message(role: "system", text: Self.systemPrompt(toolRegistry: toolRegistry))
        ]
        if let priorTaskContext {
            input.append(Self.message(role: "user", text: priorTaskContext.plannerContextText))
        }
        input.append(Self.message(role: "user", text: command))

        return [
            "model": model,
            "input": input,
            "reasoning": [
                "effort": "medium"
            ],
            "text": [
                "verbosity": "low",
                "format": AgentPlanSchema.responseFormat()
            ]
        ]
    }

    private static func message(role: String, text: String) -> [String: Any] {
        [
            "role": role,
            "content": [
                [
                    "type": "input_text",
                    "text": text
                ]
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
    - A TRUSTED_PRIOR_TASK_CONTEXT_BEGIN/END message may appear before the current command. It is Sonny's short-lived record of only the immediately preceding task.
    - Use prior task context only when the current command is clearly a correction or refinement of that prior task.
    - If the current command is unrelated or ambiguous, ignore prior task context entirely and plan only from the current command.
    - Use null for unavailable fields.
    - If a folder, app name, URL, count, or output destination is required but missing or ambiguous, return exactly one clarify step with a short question.
    - For largest files, produce scan_select_largest_files then create_zip.
    - For DOCX conversion, produce scan_docx then convert_docx_to_pdf.
    - For Hacker News headline saving, produce open_hacker_news, fetch_hn_headlines, then write_markdown.
    - For summarizing one public web page to Markdown, produce one web_to_markdown step with targetURL and optional outputPath.
    - For comparing multiple public web sources to Markdown, produce one web_to_markdown step with sourceURLs and optional outputPath.
    - For researching a topic/search query to Markdown, produce one web_to_markdown step with searchQuery and optional outputPath.
    - For opening an app, produce one open_app step with appName.
    - For opening an allowlisted app or website search page, produce one open_app_search_url step with appName and searchQuery. Use only supported search targets; do not invent URL templates.
    - For opening a general website, produce one open_url step with targetURL using http or https.
    - For creating a local draft, produce one create_local_draft step with draftTitle, draftContent, and optional outputPath. Do not automate Notes, Mail, Calendar, or any app UI.
    - For opening a generated local artifact after a writing step, add open_generated_artifact with outputPath null so the executor can open the previous produced artifact.
    - For song or album requests, produce one play_media step with mediaProvider, mediaTitle, optional mediaArtist, and targetURL only if the user supplied an exact Apple Music or Spotify result URI. The local executor tries provider-aware playback first, then falls back to opening the provider result or search.
    - If a song or album request is missing the provider or title, ask a clarification question.
    - For Finder context phrases such as "selected folder", "selected files", "this Finder selection", or "the folder selected in Finder", set contextSource to finder_selection and leave inputPath null.
    - For "reveal the result/zip/markdown/PDFs in Finder" after a writing step, add reveal_in_finder with outputPath null so the executor can reveal the previous produced artifact.
    - For permission/readiness requests, produce one show_permission_readiness step.
    - For teaching a routine, produce one save_routine step with routineName and routineSteps containing only registered non-routine steps. Do not put save_routine, run_routine, clarify, or unsupported inside routineSteps.
    - For running a saved routine, produce one run_routine step with routineName.
    - For creating a workspace, produce one create_workspace step with workspaceName, workspaceApps, and workspaceURLs. Use only explicitly named apps/URLs. If none are provided, ask a clarification question.
    - For opening a saved workspace, produce one open_workspace step with workspaceName.
    - For running an existing Apple Shortcut, produce one invoke_shortcut step with shortcutName and optional shortcutInput when simple text input was explicitly supplied.
    - You may produce multi-step chained plans when the user asks for multiple supported actions. Keep steps in execution order.
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
