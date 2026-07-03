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

    public init(source: UsageSource, timestamp: Date, model: String, tokens: TokenUsage) {
        self.source = source
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
    }
}

public enum CacheSnapshotKind: String, Sendable {
    case runBudget = "Run Budget"
    case usage = "Usage"
    case subscriptionStatus = "Subscription"
}

public struct CacheSnapshot: Equatable, Sendable {
    public var kind: CacheSnapshotKind
    public var used: Double
    public var limit: Double
    public var capturedAt: Date?

    public init(kind: CacheSnapshotKind, used: Double, limit: Double, capturedAt: Date? = nil) {
        self.kind = kind
        self.used = used
        self.limit = limit
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

public struct UsageAggregate: Equatable, Sendable {
    public var today: UsageBucket
    public var week: UsageBucket
    public var bySource: [UsageSource: UsageBucket]
    public var records: [UsageRecord]
    public var accountSnapshot: CacheSnapshot?
    public var refreshedAt: Date

    public init(
        today: UsageBucket,
        week: UsageBucket,
        bySource: [UsageSource: UsageBucket],
        records: [UsageRecord],
        accountSnapshot: CacheSnapshot? = nil,
        refreshedAt: Date = Date()
    ) {
        self.today = today
        self.week = week
        self.bySource = bySource
        self.records = records
        self.accountSnapshot = accountSnapshot
        self.refreshedAt = refreshedAt
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
