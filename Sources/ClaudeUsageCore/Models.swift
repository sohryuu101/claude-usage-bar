import Foundation

public enum UsageSource: String, CaseIterable, Codable, Hashable, Sendable {
    case claudeCode = "Claude Code"
    case desktopCowork = "Desktop/Cowork"
}

public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public var total: Int {
        input + output + cacheCreation + cacheRead
    }

    public mutating func add(_ other: TokenUsage) {
        input += other.input
        output += other.output
        cacheCreation += other.cacheCreation
        cacheRead += other.cacheRead
    }
}

public struct UsageRecord: Equatable, Sendable {
    public var source: UsageSource
    public var timestamp: Date
    public var model: String
    public var tokens: TokenUsage
    public var messageID: String?
    public var requestID: String?
    public var sessionID: String?

    public init(
        source: UsageSource,
        timestamp: Date,
        model: String,
        tokens: TokenUsage,
        messageID: String? = nil,
        requestID: String? = nil,
        sessionID: String? = nil
    ) {
        self.source = source
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
        self.messageID = messageID
        self.requestID = requestID
        self.sessionID = sessionID
    }
}

public enum CacheSnapshotKind: String, Sendable {
    case runBudget = "Run Budget"
    case usage = "Usage"
    case subscriptionStatus = "Subscription"
    case designAllowance = "Claude Design"
}

public struct CacheSnapshot: Equatable, Sendable {
    public var kind: CacheSnapshotKind
    public var used: Double
    public var limit: Double
    public var plan: String?
    public var capturedAt: Date?

    public init(kind: CacheSnapshotKind, used: Double, limit: Double, plan: String? = nil, capturedAt: Date? = nil) {
        self.kind = kind
        self.used = used
        self.limit = limit
        self.plan = plan
        self.capturedAt = capturedAt
    }

    public var percentUsed: Int {
        guard limit > 0 else { return 0 }
        return Int((used / limit * 100).rounded())
    }
}

public struct UsageBucket: Equatable, Sendable {
    public var tokens: TokenUsage
    public var messages: Int

    public init(tokens: TokenUsage = TokenUsage(), messages: Int = 0) {
        self.tokens = tokens
        self.messages = messages
    }

    public mutating func add(_ record: UsageRecord) {
        tokens.add(record.tokens)
        messages += 1
    }
}

public enum PlanType: String, Codable, Sendable {
    case free
    case pro
    case enterprise
}

public struct UsageAggregate: Equatable, Sendable {
    public var today: UsageBucket
    public var month: UsageBucket
    public var last5Hours: UsageBucket
    public var bySource: [UsageSource: UsageBucket]
    public var records: [UsageRecord]
    public var accountSnapshot: CacheSnapshot?
    public var designSnapshot: CacheSnapshot?
    public var subscriptionSnapshot: CacheSnapshot?
    public var liveQuota: OAuthUsageSnapshot?
    public var liveQuotaStatus: OAuthLiveQuotaStatus
    public var planType: PlanType
    public var refreshedAt: Date

    public init(
        today: UsageBucket,
        month: UsageBucket,
        last5Hours: UsageBucket,
        bySource: [UsageSource: UsageBucket],
        records: [UsageRecord],
        accountSnapshot: CacheSnapshot? = nil,
        designSnapshot: CacheSnapshot? = nil,
        subscriptionSnapshot: CacheSnapshot? = nil,
        liveQuota: OAuthUsageSnapshot? = nil,
        liveQuotaStatus: OAuthLiveQuotaStatus = .unavailable,
        planType: PlanType = .free,
        refreshedAt: Date = Date()
    ) {
        self.today = today
        self.month = month
        self.last5Hours = last5Hours
        self.bySource = bySource
        self.records = records
        self.accountSnapshot = accountSnapshot
        self.designSnapshot = designSnapshot
        self.subscriptionSnapshot = subscriptionSnapshot
        self.liveQuota = liveQuota
        self.liveQuotaStatus = liveQuotaStatus
        self.planType = planType
        self.refreshedAt = refreshedAt
    }
}

public enum OAuthLiveQuotaStatus: Equatable, Sendable {
    case unavailable
    case enabled
    case unauthorized
    case rateLimited
}

public struct OAuthQuotaBucket: Equatable, Sendable {
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date? = nil) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct OAuthExtraUsage: Equatable, Sendable {
    public var isEnabled: Bool
    public var monthlyLimit: Double? // in cents
    public var usedCredits: Double? // in cents
    public var utilization: Double? // percentage

    public init(isEnabled: Bool, monthlyLimit: Double? = nil, usedCredits: Double? = nil, utilization: Double? = nil) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
    }
}

public struct OAuthUsageSnapshot: Equatable, Sendable {
    public var fiveHour: OAuthQuotaBucket?
    public var sevenDay: OAuthQuotaBucket?
    public var sevenDayOAuthApps: OAuthQuotaBucket?
    public var sevenDayOpus: OAuthQuotaBucket?
    public var sevenDaySonnet: OAuthQuotaBucket?
    public var extraUsage: OAuthExtraUsage?
    public var fetchedAt: Date

    public init(
        fiveHour: OAuthQuotaBucket? = nil,
        sevenDay: OAuthQuotaBucket? = nil,
        sevenDayOAuthApps: OAuthQuotaBucket? = nil,
        sevenDayOpus: OAuthQuotaBucket? = nil,
        sevenDaySonnet: OAuthQuotaBucket? = nil,
        extraUsage: OAuthExtraUsage? = nil,
        fetchedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOAuthApps = sevenDayOAuthApps
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
        self.fetchedAt = fetchedAt
    }
}

public extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
