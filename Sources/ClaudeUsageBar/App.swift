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
            HStack {
                if let clawdImage = loadClawdIcon() {
                    clawdImage
                }
                Text(monitor.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func loadClawdIcon() -> Image? {
        let url = Bundle.main.url(forResource: "clawd", withExtension: "png") ??
                  Bundle.module.url(forResource: "clawd", withExtension: "png")
        guard let url = url,
              let nsImage = NSImage(contentsOf: url) else {
            return nil
        }
        nsImage.size = NSSize(width: 17, height: 17)
        return Image(nsImage: nsImage)
    }
}
