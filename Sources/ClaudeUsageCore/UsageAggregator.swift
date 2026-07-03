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
        var week = UsageBucket()
        var bySource: [UsageSource: UsageBucket] = [:]
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)

        for record in records {
            bySource[record.source, default: UsageBucket()].add(record)
            if calendar.isDate(record.timestamp, inSameDayAs: now) {
                today.add(record)
            }
            if let weekInterval, weekInterval.contains(record.timestamp) {
                week.add(record)
            }
        }

        return UsageAggregate(
            today: today,
            week: week,
            bySource: bySource,
            records: records,
            accountSnapshot: accountSnapshot,
            refreshedAt: now
        )
    }
}
