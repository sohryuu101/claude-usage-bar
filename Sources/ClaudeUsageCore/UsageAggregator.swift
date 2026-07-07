import Foundation

public struct UsageAggregator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func aggregate(
        records: [UsageRecord],
        accountSnapshot: CacheSnapshot? = nil,
        designSnapshot: CacheSnapshot? = nil,
        subscriptionSnapshot: CacheSnapshot? = nil,
        liveQuota: OAuthUsageSnapshot? = nil,
        liveQuotaStatus: OAuthLiveQuotaStatus = .unavailable,
        now: Date = Date()
    ) -> UsageAggregate {
        var today = UsageBucket()
        var month = UsageBucket()
        var last5Hours = UsageBucket()
        var bySource: [UsageSource: UsageBucket] = [:]
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)

        for record in records {
            bySource[record.source, default: UsageBucket()].add(record)
            if calendar.isDate(record.timestamp, inSameDayAs: now) {
                today.add(record)
            }
            if calendar.component(.month, from: record.timestamp) == currentMonth &&
               calendar.component(.year, from: record.timestamp) == currentYear {
                month.add(record)
            }
            if record.timestamp >= fiveHoursAgo {
                last5Hours.add(record)
            }
        }

        return UsageAggregate(
            today: today,
            month: month,
            last5Hours: last5Hours,
            bySource: bySource,
            records: records,
            accountSnapshot: accountSnapshot,
            designSnapshot: designSnapshot,
            subscriptionSnapshot: subscriptionSnapshot,
            liveQuota: liveQuota,
            liveQuotaStatus: liveQuotaStatus,
            refreshedAt: now
        )
    }
}
