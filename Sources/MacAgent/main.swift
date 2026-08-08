import AppKit
import MacAgentCore
import SwiftUI

// SONNY-69 experiment (throwaway spike): headless planner comparison. When the env var is set,
// print side-by-side transcripts and exit — NSApplication, the menu bar, and every local store
// stay untouched, so this cannot collide with a live packaged instance.
if let compareSpec = ProcessInfo.processInfo.environment["SONNY_PLANNER_COMPARE"] {
    Task { @MainActor in
        await PlannerComparison.run(spec: compareSpec)
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
