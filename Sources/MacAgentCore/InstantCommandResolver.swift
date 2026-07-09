import Foundation

public enum InstantCommandResolution: Equatable, Sendable {
    case plan(AgentPlan)
    case clarify(AgentPlan)
}

public struct InstantCommandResolver: Sendable {
    public init() {}

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

        if looksLikeBareArithmetic(command) || looksLikeBareConversion(command) {
            return .plan(calculatorPlan(expression: command))
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
