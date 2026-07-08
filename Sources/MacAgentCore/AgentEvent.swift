import Combine
import Foundation

public enum AgentPhase: String, Codable, CaseIterable, Sendable {
    case plan
    case validate
    case risk
    case preview
    case confirm
    case act
    case observe
    case summarize
}

public struct AgentEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var phase: AgentPhase
    public var message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        phase: AgentPhase,
        message: String
    ) {
        self.id = id
        self.date = date
        self.phase = phase
        self.message = message
    }
}

@MainActor
public final class AgentLogStore: ObservableObject {
    @Published public private(set) var events: [AgentEvent]

    public init(events: [AgentEvent] = []) {
        self.events = events
    }

    public func append(_ phase: AgentPhase, _ message: String) {
        events.append(AgentEvent(phase: phase, message: message))
    }

    public func reset() {
        events.removeAll()
    }
}

public struct ActionPreview: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var details: [String]
    public var writes: [String]
    public var opens: [String]
    public var conversions: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        details: [String] = [],
        writes: [String] = [],
        opens: [String] = [],
        conversions: [String] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.writes = writes
        self.opens = opens
        self.conversions = conversions
    }

    public var sideEffects: [String] {
        writes.map { "Write: \($0)" } + opens.map { "Open: \($0)" } + conversions.map { "Convert: \($0)" }
    }
}

public struct AgentRunResult: Equatable, Sendable {
    public var plan: AgentPlan
    public var previews: [ActionPreview]
    public var summary: String
    public var suggestions: [RunSuggestion]

    public init(
        plan: AgentPlan,
        previews: [ActionPreview],
        summary: String,
        suggestions: [RunSuggestion] = []
    ) {
        self.plan = plan
        self.previews = previews
        self.summary = summary
        self.suggestions = suggestions
    }
}

public struct RunSuggestion: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: RunSuggestionKind
    public var value: String

    public init(
        id: UUID = UUID(),
        title: String,
        kind: RunSuggestionKind,
        value: String
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.value = value
    }
}

public enum RunSuggestionKind: String, Codable, Equatable, Sendable {
    case revealInFinder
    case openFile
}
