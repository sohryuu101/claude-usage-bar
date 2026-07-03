import Foundation

public struct UsageAggregator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func aggregate(
        records: [UsageRecord],
        accountSnapshot: CacheSnapshot? = nil,
        now: Date = Date()
    ) -> UsageAggregate {
        var today = UsageBucket()
        var month = UsageBucket()
        var bySource: [UsageSource: UsageBucket] = [:]
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        for record in records {
            bySource[record.source, default: UsageBucket()].add(record)
            if calendar.isDate(record.timestamp, inSameDayAs: now) {
                today.add(record)
            }
            if calendar.component(.month, from: record.timestamp) == currentMonth &&
               calendar.component(.year, from: record.timestamp) == currentYear {
                month.add(record)
            }
        }

        return UsageAggregate(
            today: today,
            month: month,
            bySource: bySource,
            records: records,
            accountSnapshot: accountSnapshot,
            refreshedAt: now
        )
    }
}
