import Foundation

// SONNY-69 experiment (throwaway spike — never merges). Headless side-by-side planner harness:
// SONNY_PLANNER_COMPARE="cmd1||cmd2||cmd3" runs every command through both planners, prints a
// transcript to stdout, and the process exits before the UI (or any local store) ever boots.
// Network-only, so no bundle identity or TCC grant is needed — `swift run MacAgent` suffices.

public enum PlannerComparison {
    @MainActor
    public static func run(spec: String) async {
        let commands = spec
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        print("=== SONNY-69 planner comparison — \(commands.count) command(s) ===")

        var planners: [(label: String, planner: any Planning)] = []
        let openAIModel = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.5"
        let cerebrasModel = ProcessInfo.processInfo.environment["CEREBRAS_MODEL"] ?? "gpt-oss-120b"
        do {
            planners.append(("openai/\(openAIModel)", try OpenAIPlanner()))
        } catch {
            print("!!! openai side skipped: \(error.localizedDescription)")
        }
        do {
            planners.append(("cerebras/\(cerebrasModel)", try CerebrasPlanner()))
        } catch {
            print("!!! cerebras side skipped: \(error.localizedDescription)")
        }

        for command in commands {
            print("\n### COMMAND: \(command)")
            for (label, planner) in planners {
                let started = Date()
                do {
                    let plan = try await planner.plan(command: command, priorTaskContext: nil)
                    let elapsed = Date().timeIntervalSince(started)
                    print("--- [\(label)] ok in \(String(format: "%.2f", elapsed))s")
                    print(prettyJSON(plan))
                } catch {
                    let elapsed = Date().timeIntervalSince(started)
                    print("--- [\(label)] FAILED in \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
                }
            }
        }
        print("\n=== comparison complete ===")
    }

    private static func prettyJSON(_ plan: AgentPlan) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plan), let text = String(data: data, encoding: .utf8) else {
            return "<encoding failed>"
        }
        return text
    }
}
