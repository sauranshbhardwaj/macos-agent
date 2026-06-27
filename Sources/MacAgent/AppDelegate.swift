import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel = AgentViewModel()
    private var pushToTalkHotKey: PushToTalkHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Sonny")
        item.button?.imagePosition = .imageLeading
        item.button?.title = " Sonny"
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 600, height: 740)
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        do {
            pushToTalkHotKey = try PushToTalkHotKey(
                onPress: { [weak self] in
                    self?.showPopover()
                    self?.viewModel.beginPushToTalkVoice()
                },
                onRelease: { [weak self] in
                    self?.viewModel.endPushToTalkVoice()
                }
            )
        } catch {
            viewModel.markVoiceHotKeyUnavailable(error.localizedDescription)
            print("Sonny could not register push-to-talk hotkey: \(error.localizedDescription)")
        }

        print("Sonny is running. Click the Sonny item in the macOS menu bar to open it.")
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard statusItem?.button != nil else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
