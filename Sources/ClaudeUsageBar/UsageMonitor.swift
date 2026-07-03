import ClaudeUsageCore
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var aggregate: UsageAggregate

    private let store: UsageStore
    private var timer: Timer?

    init(store: UsageStore = UsageStore()) {
        self.store = store
        self.aggregate = UsageAggregator().aggregate(records: [])
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var menuTitle: String {
        if let snapshot = aggregate.accountSnapshot {
            return "\(snapshot.percentUsed)%"
        }
        return formatCompact(aggregate.today.tokens.total)
    }

    func refresh() {
        aggregate = store.load()
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
