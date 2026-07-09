import Foundation

public enum InstantCommandResolution: Equatable, Sendable {
    case plan(AgentPlan)
    case clarify(AgentPlan)
}

public struct InstantCommandResolver: Sendable {
    private let snippetStore: SnippetStore
    private let recentArtifactStore: RecentArtifactStore

    public init(
        snippetStore: SnippetStore = SnippetStore(),
        recentArtifactStore: RecentArtifactStore = RecentArtifactStore()
    ) {
        self.snippetStore = snippetStore
        self.recentArtifactStore = recentArtifactStore
    }

    public func resolve(command rawCommand: String) -> InstantCommandResolution? {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            return nil
        }

        if let expression = prefixedCalculatorExpression(in: command) {
            guard !expression.isEmpty else {
                return .clarify(calculatorClarificationPlan())
            }
            return .plan(calculatorPlan(expression: expression))
        }

        if let query = prefixedClipboardHistoryQuery(in: command) {
            return .plan(clipboardHistoryPlan(query: query))
        }

        if let query = prefixedRunningAppQuery(in: command) {
            guard !query.isEmpty else {
                return .clarify(runningAppClarificationPlan())
            }
            return .plan(runningAppSwitchPlan(query: query))
        }

        if let request = recentArtifactRequest(in: command) {
            switch request {
            case .lookup(let query):
                return .plan(recentArtifactsPlan(query: query))
            case .open(let query):
                return recentArtifactOpenResolution(query: query)
            }
        }

        if let snippet = try? snippetStore.findExactTrigger(command) {
            return .plan(snippetPlan(snippet))
        }

        if looksLikeBareArithmetic(command) || looksLikeBareConversion(command) {
            return .plan(calculatorPlan(expression: command))
        }

        return nil
    }

    private enum RecentArtifactRequest {
        case lookup(String?)
        case open(String?)
    }

    private func prefixedRunningAppQuery(in command: String) -> String? {
        let lowered = command.lowercased()
        for prefix in ["switch to", "switch", "focus", "activate"] {
            if lowered == prefix {
                return ""
            }
            if lowered.hasPrefix("\(prefix) ") {
                return String(command.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func recentArtifactRequest(in command: String) -> RecentArtifactRequest? {
        let lowered = command.lowercased()
        for prefix in ["open recent artifact", "open recent file", "open recent result"] {
            if lowered == prefix {
                return .open(nil)
            }
            if lowered.hasPrefix("\(prefix) ") {
                let query = String(command.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .open(query.isEmpty ? nil : query)
            }
        }

        for prefix in ["recent artifacts", "recent artifact", "recent results", "recent files", "artifacts"] {
            if lowered == prefix {
                return .lookup(nil)
            }
            if lowered.hasPrefix("\(prefix) ") {
                let query = String(command.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .lookup(query.isEmpty ? nil : query)
            }
        }

        return nil
    }

    private func prefixedClipboardHistoryQuery(in command: String) -> String? {
        let lowered = command.lowercased()
        for prefix in ["clipboard history", "clipboard", "clip"] {
            if lowered == prefix {
                return ""
            }
            if lowered.hasPrefix("\(prefix) ") {
                return String(command.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func prefixedCalculatorExpression(in command: String) -> String? {
        let lowered = command.lowercased()
        for prefix in ["calc", "calculate"] {
            if lowered == prefix {
                return ""
            }
            if lowered.hasPrefix("\(prefix) ") {
                return String(command.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if command.hasPrefix("=") {
            return String(command.dropFirst())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func looksLikeBareArithmetic(_ command: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() \t\n")
        let scalars = command.unicodeScalars
        guard scalars.allSatisfy({ allowed.contains($0) }) else {
            return false
        }
        let hasDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let hasOperator = scalars.contains { ["+", "-", "*", "/"].contains(String($0)) }
        return hasDigit && hasOperator
    }

    private func looksLikeBareConversion(_ command: String) -> Bool {
        let parts = command
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard parts.count == 4,
              Double(parts[0]) != nil,
              ["to", "in"].contains(parts[2].lowercased()) else {
            return false
        }
        return true
    }

    private func calculatorPlan(expression: String) -> AgentPlan {
        AgentPlan(
            summary: "Calculate \(expression).",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "calculate",
                    operation: .calculateUtility,
                    description: "Calculate \(expression).",
                    searchQuery: expression
                )
            ]
        )
    }

    private func clipboardHistoryPlan(query: String?) -> AgentPlan {
        let summary: String
        if let query, !query.isEmpty {
            summary = "Search clipboard history for \(query)."
        } else {
            summary = "Show clipboard history."
        }
        return AgentPlan(
            summary: summary,
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "clipboard-history",
                    operation: .lookupClipboardHistory,
                    description: summary,
                    count: 10,
                    searchQuery: query?.isEmpty == true ? nil : query
                )
            ]
        )
    }

    private func runningAppSwitchPlan(query: String) -> AgentPlan {
        AgentPlan(
            summary: "Switch to \(query).",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "switch-running-app",
                    operation: .switchRunningApp,
                    description: "Switch to running app \(query).",
                    appName: query
                )
            ]
        )
    }

    private func recentArtifactsPlan(query: String?) -> AgentPlan {
        let summary: String
        if let query, !query.isEmpty {
            summary = "Search recent artifacts for \(query)."
        } else {
            summary = "Show recent artifacts."
        }
        return AgentPlan(
            summary: summary,
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "recent-artifacts",
                    operation: .lookupRecentArtifacts,
                    description: summary,
                    count: 10,
                    searchQuery: query?.isEmpty == true ? nil : query
                )
            ]
        )
    }

    private func recentArtifactOpenResolution(query: String?) -> InstantCommandResolution {
        let artifacts = (try? recentArtifactStore.recent(matching: query, limit: 2)) ?? []
        guard let artifact = artifacts.first else {
            return .clarify(recentArtifactClarificationPlan(query: query))
        }
        return .plan(openRecentArtifactPlan(artifact))
    }

    private func openRecentArtifactPlan(_ artifact: RecentArtifact) -> AgentPlan {
        AgentPlan(
            summary: "Open recent artifact \(artifact.title).",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "open-recent-artifact",
                    operation: .openGeneratedArtifact,
                    description: "Open recent artifact \(artifact.title).",
                    outputPath: artifact.path
                )
            ]
        )
    }

    private func snippetPlan(_ snippet: StoredSnippet) -> AgentPlan {
        AgentPlan(
            summary: "Expand snippet \(snippet.trigger).",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "snippet-expansion",
                    operation: .expandSnippet,
                    description: "Expand snippet \(snippet.trigger).",
                    searchQuery: snippet.trigger
                )
            ]
        )
    }

    private func runningAppClarificationPlan() -> AgentPlan {
        AgentPlan(
            summary: "Clarification needed.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "clarify-running-app",
                    operation: .clarify,
                    description: "Ask which running app to switch to.",
                    question: "Which running app should I switch to?"
                )
            ]
        )
    }

    private func recentArtifactClarificationPlan(query: String?) -> AgentPlan {
        let question: String
        if let query, !query.isEmpty {
            question = "I could not find a recent artifact matching \(query). Which artifact should I open?"
        } else {
            question = "Which recent artifact should I open?"
        }
        return AgentPlan(
            summary: "Clarification needed.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "clarify-recent-artifact",
                    operation: .clarify,
                    description: "Ask which recent artifact to open.",
                    question: question
                )
            ]
        )
    }

    private func calculatorClarificationPlan() -> AgentPlan {
        AgentPlan(
            summary: "Clarification needed.",
            requiresConfirmation: false,
            steps: [
                AgentStep(
                    id: "clarify-calculator",
                    operation: .clarify,
                    description: "Ask what to calculate.",
                    question: "What would you like me to calculate?"
                )
            ]
        )
    }
}
