import XCTest
@testable import ClaudeUsageCore

final class ClaudeUsageCoreTests: XCTestCase {
    func testParsesClaudeCodeAssistantUsageLine() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-03T01:02:03.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
        """

        let records = UsageJSONLParser(source: .claudeCode).parseLines([line])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, .claudeCode)
        XCTAssertEqual(records[0].model, "claude-sonnet-4-6")
        XCTAssertEqual(records[0].tokens.total, 100)
        XCTAssertEqual(records[0].timestamp, ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-07-03T01:02:03.000Z"))
    }

    func testParsesCoworkAuditAssistantUsageLine() {
        let line = """
        {"type":"assistant","_audit_timestamp":"2026-07-03T02:00:00.000Z","message":{"model":"claude-opus-4-7","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}}}
        """

        let records = UsageJSONLParser(source: .desktopCowork).parseLines([line])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, .desktopCowork)
        XCTAssertEqual(records[0].model, "claude-opus-4-7")
        XCTAssertEqual(records[0].tokens.total, 10)
    }

    func testIgnoresMalformedAndUsageFreeLines() {
        let records = UsageJSONLParser(source: .claudeCode).parseLines([
            "not json",
            #"{"type":"user","timestamp":"2026-07-03T01:02:03.000Z"}"#
        ])

        XCTAssertTrue(records.isEmpty)
    }

    func testParsesRunBudgetCachePayload() {
        let cache = """
        binary-prefix https://claude.ai/v1/code/routines/run-budget({"limit":"25","unified_billing_enabled":true,"used":"7"} trailing
        """

        let snapshot = CacheSnapshotParser().parse(text: cache)

        XCTAssertEqual(snapshot?.kind, .runBudget)
        XCTAssertEqual(snapshot?.used, 7)
        XCTAssertEqual(snapshot?.limit, 25)
        XCTAssertEqual(snapshot?.percentUsed, 28)
    }

    func testAggregatesTodayWeekAndSourceBreakdown() throws {
        let today = ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-07-03T01:00:00.000Z")!
        let yesterday = ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-07-02T01:00:00.000Z")!
        let calendar = Calendar(identifier: .gregorian)
        let aggregate = UsageAggregator(calendar: calendar).aggregate(
            records: [
                UsageRecord(source: .claudeCode, timestamp: today, model: "sonnet", tokens: TokenUsage(input: 1, output: 2, cacheCreation: 3, cacheRead: 4)),
                UsageRecord(source: .desktopCowork, timestamp: today, model: "opus", tokens: TokenUsage(input: 10, output: 0, cacheCreation: 0, cacheRead: 0)),
                UsageRecord(source: .claudeCode, timestamp: yesterday, model: "sonnet", tokens: TokenUsage(input: 5, output: 0, cacheCreation: 0, cacheRead: 0))
            ],
            now: today
        )

        XCTAssertEqual(aggregate.today.tokens.total, 20)
        XCTAssertEqual(aggregate.today.messages, 2)
        XCTAssertEqual(aggregate.week.tokens.total, 25)
        XCTAssertEqual(aggregate.bySource[.claudeCode]?.tokens.total, 15)
        XCTAssertEqual(aggregate.bySource[.desktopCowork]?.tokens.total, 10)
    }
}
