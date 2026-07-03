import ClaudeUsageCore
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            accountSection
            localSection
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 390)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
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
        if let snapshot = monitor.aggregate.accountSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                row(title: snapshot.kind.rawValue, value: "\(snapshot.percentUsed)%")
                ProgressView(value: snapshot.used, total: max(snapshot.limit, 1))
                Text("\(formatNumber(snapshot.used)) of \(formatNumber(snapshot.limit)) used\(freshnessText(snapshot))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                row(title: "Account Snapshot", value: "Unavailable")
                Text("Open Claude settings usage once to refresh the local app cache.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
