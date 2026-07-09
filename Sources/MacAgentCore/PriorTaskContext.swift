import Foundation

public struct PriorTaskContext: Codable, Equatable, Sendable {
    public static let defaultExpirationInterval: TimeInterval = 10 * 60

    public var previousCommand: String
    public var planSummary: String
    public var steps: [PriorTaskStepContext]
    public var outcome: PriorTaskOutcome
    public var createdAt: Date

    public init(
        previousCommand: String,
        planSummary: String,
        steps: [PriorTaskStepContext],
        outcome: PriorTaskOutcome,
        createdAt: Date
    ) {
        self.previousCommand = previousCommand
        self.planSummary = planSummary
        self.steps = steps
        self.outcome = outcome
        self.createdAt = createdAt
    }

    public init(
        command: String,
        plan: AgentPlan,
        outcome: PriorTaskOutcome,
        createdAt: Date
    ) {
        self.init(
            previousCommand: command.trimmingCharacters(in: .whitespacesAndNewlines),
            planSummary: plan.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: plan.steps.map(PriorTaskStepContext.init(step:)),
            outcome: outcome,
            createdAt: createdAt
        )
    }

    public init(
        command: String,
        outcome: PriorTaskOutcome,
        createdAt: Date
    ) {
        self.init(
            previousCommand: command.trimmingCharacters(in: .whitespacesAndNewlines),
            planSummary: "",
            steps: [],
            outcome: outcome,
            createdAt: createdAt
        )
    }

    public func isExpired(
        at now: Date,
        expirationInterval: TimeInterval = Self.defaultExpirationInterval
    ) -> Bool {
        now.timeIntervalSince(createdAt) > expirationInterval
    }

    public var shortDisplayText: String {
        let summary = planSummary.isEmpty ? previousCommand : planSummary
        guard summary.count > 72 else {
            return summary
        }
        return String(summary.prefix(69)) + "..."
    }

    public var plannerContextText: String {
        let formatter = ISO8601DateFormatter()
        let stepLines = steps.enumerated().map { index, step in
            "\(index + 1). \(step.plannerText)"
        }

        let planSummaryText = planSummary.isEmpty
            ? "- unavailable; prior task failed before preparation completed"
            : Self.escapeForPlanner(planSummary)
        let stepsText = stepLines.isEmpty
            ? "- none available; prior task failed before preparation completed"
            : stepLines.joined(separator: "\n")

        return """
        TRUSTED_PRIOR_TASK_CONTEXT_BEGIN
        Previous command: \(Self.escapeForPlanner(previousCommand))
        Previous plan summary: \(planSummaryText)
        Previous plan steps:
        \(stepsText)
        Previous outcome: \(outcome.plannerText)
        Captured at: \(formatter.string(from: createdAt))
        TRUSTED_PRIOR_TASK_CONTEXT_END
        """
    }

    private static func escapeForPlanner(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: "TRUSTED_PRIOR_TASK_CONTEXT_BEGIN",
                with: "[escaped prior-task delimiter: TRUSTED_PRIOR_TASK_CONTEXT_BEGIN]"
            )
            .replacingOccurrences(
                of: "TRUSTED_PRIOR_TASK_CONTEXT_END",
                with: "[escaped prior-task delimiter: TRUSTED_PRIOR_TASK_CONTEXT_END]"
            )
    }
}

public struct PriorTaskStepContext: Codable, Equatable, Sendable {
    public var operation: AgentOperation
    public var description: String
    public var details: [String]

    public init(operation: AgentOperation, description: String, details: [String]) {
        self.operation = operation
        self.description = description
        self.details = details
    }

    public init(step: AgentStep) {
        var details: [String] = []
        Self.append("inputPath", step.inputPath, to: &details)
        Self.append("outputPath", step.outputPath, to: &details)
        Self.append("count", step.count.map(String.init), to: &details)
        Self.append("targetURL", step.targetURL, to: &details)
        Self.append("appName", step.appName, to: &details)
        Self.append("mediaProvider", step.mediaProvider?.rawValue, to: &details)
        Self.append("mediaTitle", step.mediaTitle, to: &details)
        Self.append("mediaArtist", step.mediaArtist, to: &details)
        Self.append("contextSource", step.contextSource?.rawValue, to: &details)
        Self.append("routineName", step.routineName, to: &details)
        Self.append("workspaceName", step.workspaceName, to: &details)
        Self.append("sourceURLs", step.sourceURLs?.joined(separator: ", "), to: &details)
        Self.append("searchQuery", step.searchQuery, to: &details)
        Self.append("draftTitle", step.draftTitle, to: &details)
        Self.append("shortcutName", step.shortcutName, to: &details)
        Self.append("shortcutInput", step.shortcutInput, to: &details)

        self.init(
            operation: step.operation,
            description: step.description.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details
        )
    }

    public var plannerText: String {
        let detailText = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        return "\(operation.rawValue): \(description)\(detailText)"
    }

    private static func append(_ key: String, _ value: String?, to details: inout [String]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return
        }
        details.append("\(key)=\(value)")
    }
}

public struct PriorTaskOutcome: Codable, Equatable, Sendable {
    public var status: PriorTaskOutcomeStatus
    public var summary: String

    public init(status: PriorTaskOutcomeStatus, summary: String) {
        self.status = status
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var plannerText: String {
        if summary.isEmpty {
            return status.rawValue
        }
        return "\(status.rawValue) - \(summary)"
    }
}

public enum PriorTaskOutcomeStatus: String, Codable, Equatable, Sendable {
    case prepared
    case dryRun = "dry_run"
    case completed
    case failed
    case canceled
    case approvalNeeded = "approval_needed"
    case clarificationNeeded = "clarification_needed"
}

public final class PriorTaskContextStore {
    private var storedContext: PriorTaskContext?
    private let expirationInterval: TimeInterval
    private let now: () -> Date

    public init(
        expirationInterval: TimeInterval = PriorTaskContext.defaultExpirationInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.expirationInterval = expirationInterval
        self.now = now
    }

    public func currentContext() -> PriorTaskContext? {
        guard let storedContext else {
            return nil
        }
        if storedContext.isExpired(at: now(), expirationInterval: expirationInterval) {
            self.storedContext = nil
            return nil
        }
        return storedContext
    }

    public func record(command: String, plan: AgentPlan, outcome: PriorTaskOutcome) {
        storedContext = PriorTaskContext(
            command: command,
            plan: plan,
            outcome: outcome,
            createdAt: now()
        )
    }

    public func record(command: String, outcome: PriorTaskOutcome) {
        storedContext = PriorTaskContext(
            command: command,
            outcome: outcome,
            createdAt: now()
        )
    }

    public func replace(with context: PriorTaskContext) {
        storedContext = context
    }

    public func clear() {
        storedContext = nil
    }
}
