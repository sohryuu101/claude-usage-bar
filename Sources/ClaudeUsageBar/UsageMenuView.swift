import ClaudeUsageCore
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageSettings.enableOAuthLiveQuotaKey) private var enableOAuthLiveQuota = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            accountSection
            localSection
            Divider()
            settingsSection
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 390)
        .onAppear {
            monitor.enableOAuthLiveQuota = enableOAuthLiveQuota
        }
        .onChange(of: enableOAuthLiveQuota) { _, newValue in
            monitor.enableOAuthLiveQuota = newValue
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let url = Bundle.module.url(forResource: "clawd", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                let _ = nsImage.size = NSSize(width: 36, height: 36)
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Usage")
                    .font(.title2.bold())
                Text("Local monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let liveQuota = monitor.aggregate.liveQuota {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Quota")
                        .font(.headline)
                    quotaRow("5-hour", bucket: liveQuota.fiveHour)
                    quotaRow("7-day", bucket: liveQuota.sevenDay)
                    quotaRow("OAuth apps", bucket: liveQuota.sevenDayOAuthApps)
                    quotaRow("Opus", bucket: liveQuota.sevenDayOpus)
                    quotaRow("Sonnet", bucket: liveQuota.sevenDaySonnet)
                    Text("Fetched \(liveQuota.fetchedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = monitor.aggregate.accountSnapshot {
                if monitor.aggregate.liveQuota != nil {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 6) {
                    row(title: "\(snapshot.kind.rawValue) Cache", value: "$\(formatNumber(snapshot.used)) of $\(formatNumber(snapshot.limit)) (\(snapshot.percentUsed)%)")
                    ProgressView(value: snapshot.used, total: max(snapshot.limit, 1))
                        .tint(snapshot.percentUsed > 80 ? .orange : .blue)
                    if let capturedAt = snapshot.capturedAt {
                        Text("Stale fallback from \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let design = monitor.aggregate.designSnapshot {
                if monitor.aggregate.accountSnapshot != nil || monitor.aggregate.liveQuota != nil {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 6) {
                    row(title: design.kind.rawValue, value: "\(design.percentUsed)% used")
                    ProgressView(value: design.used, total: max(design.limit, 1))
                        .tint(design.percentUsed >= 100 ? .red : .purple)
                    Text("Included allowance for Claude Design (Canvas)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let showSub = monitor.aggregate.subscriptionSnapshot != nil || monitor.aggregate.last5Hours.messages > 0
            if showSub {
                if monitor.aggregate.accountSnapshot != nil ||
                    monitor.aggregate.designSnapshot != nil ||
                    monitor.aggregate.liveQuota != nil {
                    Divider()
                }
                let planName = monitor.aggregate.subscriptionSnapshot?.plan?.capitalized ?? "Pro"
                let messagesUsed = monitor.aggregate.last5Hours.messages
                let limit = estimated5HourLimit(for: monitor.aggregate.subscriptionSnapshot?.plan)
                let percent = limit > 0 ? Int((Double(messagesUsed) / Double(limit) * 100).rounded()) : 0
                VStack(alignment: .leading, spacing: 6) {
                    row(title: "Claude \(planName)", value: "\(messagesUsed) of \(limit) messages (\(percent)%)")
                    ProgressView(value: Double(messagesUsed), total: Double(max(limit, 1)))
                        .tint(planColor(for: monitor.aggregate.subscriptionSnapshot?.plan, used: messagesUsed, total: limit))
                    Text("Sliding 5-hour message quota (local estimate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if monitor.aggregate.accountSnapshot == nil &&
               monitor.aggregate.designSnapshot == nil &&
               monitor.aggregate.liveQuota == nil &&
               !showSub {
                VStack(alignment: .leading, spacing: 4) {
                    row(title: "Account Quota", value: "Unavailable")
                    Text("Open Claude settings usage once to refresh the local app cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use Claude Code OAuth for live quota", isOn: $enableOAuthLiveQuota)
            Text(oauthStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var oauthStatusText: String {
        if !enableOAuthLiveQuota {
            return "Unavailable"
        }
        switch monitor.aggregate.liveQuotaStatus {
        case .enabled:
            if let fetchedAt = monitor.aggregate.liveQuota?.fetchedAt {
                return "Enabled · last fetched \(fetchedAt.formatted(date: .omitted, time: .standard))"
            }
            return "Enabled"
        case .unauthorized:
            return "Unauthorized"
        case .rateLimited:
            return "Rate limited"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func estimated5HourLimit(for plan: String?) -> Int {
        switch plan?.lowercased() {
        case "free": return 15
        case "pro": return 45
        case "max": return 100
        default: return 45
        }
    }

    private func planColor(for plan: String?, used: Int, total: Int) -> Color {
        let percent = Double(used) / Double(total)
        if percent >= 0.8 {
            return .red
        }
        switch plan?.lowercased() {
        case "free": return .gray
        case "max": return .orange
        default: return .purple
        }
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local Activity")
                .font(.headline)
            metricRow("Today", bucket: monitor.aggregate.today)
            metricRow("This Month", bucket: monitor.aggregate.month)
            ForEach(UsageSource.allCases, id: \.self) { source in
                metricRow(source.rawValue, bucket: monitor.aggregate.bySource[source] ?? UsageBucket())
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Updated \(monitor.aggregate.refreshedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func metricRow(_ title: String, bucket: UsageBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row(title: title, value: "\(formatTokens(bucket.tokens.total))")
            Text("\(bucket.messages) messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func quotaRow(_ title: String, bucket: OAuthQuotaBucket?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let utilization = bucket?.utilization ?? 0
            row(title: title, value: "\(Int(utilization.rounded()))%")
            ProgressView(value: utilization, total: 100)
                .tint(utilization >= 90 ? .red : utilization >= 75 ? .orange : .blue)
            if let resetsAt = bucket?.resetsAt {
                Text("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK tokens", Double(value) / 1_000)
        }
        return "\(value) tokens"
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func freshnessText(_ snapshot: CacheSnapshot) -> String {
        guard let capturedAt = snapshot.capturedAt else {
            return ""
        }
        return " · cached \(capturedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
