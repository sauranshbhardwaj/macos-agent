import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacAgent")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " Agent"
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 560, height: 720)
        popover.contentViewController = NSHostingController(rootView: ContentView())

        print("MacAgent is running. Click the Agent item in the macOS menu bar to open it.")
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
