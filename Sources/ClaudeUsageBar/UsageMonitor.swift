import ClaudeUsageCore
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var aggregate: UsageAggregate
    @Published var enableOAuthLiveQuota: Bool {
        didSet {
            if oldValue != enableOAuthLiveQuota {
                refresh()
            }
        }
    }

    private var store: UsageStore
    private var timer: Timer?

    init(store: UsageStore = UsageStore()) {
        self.store = store
        self.enableOAuthLiveQuota = UserDefaults.standard.bool(forKey: UsageSettings.enableOAuthLiveQuotaKey)
        self.aggregate = UsageAggregator().aggregate(records: [])
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    var menuTitle: String {
        if let fiveHour = aggregate.liveQuota?.fiveHour {
            return "🅒 \(Int(fiveHour.utilization.rounded()))%"
        }

        let primary = aggregate.accountSnapshot
        let sub = aggregate.subscriptionSnapshot

        let showPrimary: Bool
        if let primaryDate = primary?.capturedAt, let subDate = sub?.capturedAt {
            showPrimary = primaryDate >= subDate
        } else if primary != nil {
            showPrimary = true
        } else {
            showPrimary = false
        }

        if showPrimary, let snapshot = primary {
            return "🅒 \(snapshot.percentUsed)%"
        } else if let subscription = sub {
            let messagesUsed = aggregate.last5Hours.messages
            let limit = estimated5HourLimit(for: subscription.plan)
            let percent = Int((Double(messagesUsed) / Double(limit) * 100).rounded())
            return "🅒 \(percent)%"
        }

        return "🅒 \(formatCompact(aggregate.today.tokens.total))"
    }

    private func estimated5HourLimit(for plan: String?) -> Int {
        switch plan?.lowercased() {
        case "free": return 15
        case "pro": return 45
        case "max": return 100
        default: return 45
        }
    }

    func refresh() {
        store.enableOAuthLiveQuota = enableOAuthLiveQuota
        let store = self.store
        Task {
            let newAggregate = await Task.detached {
                return await store.loadAsync()
            }.value
            self.aggregate = newAggregate
        }
    }

    private func formatCompact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}
