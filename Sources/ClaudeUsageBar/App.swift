import ClaudeUsageCore
import AppKit
import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var monitor = UsageMonitor()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(monitor: monitor)
        } label: {
            Text(monitor.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}
