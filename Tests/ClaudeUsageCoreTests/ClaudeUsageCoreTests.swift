import Foundation
import XCTest
@testable import ClaudeUsageCore

final class ClaudeUsageCoreTests: XCTestCase {
    func testParsesClaudeCodeAssistantUsageLine() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-03T01:02:03.000Z","message":{"id":"msg_1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}}
        """

        let records = UsageJSONLParser(source: .claudeCode).parseLines([line])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, .claudeCode)
        XCTAssertEqual(records[0].messageID, "msg_1")
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

    func testParsesFlatCacheCreationField() {
        let line = #"{"timestamp":"2026-07-03T01:02:03.000Z","message":{"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":30,"cache_read_input_tokens":4}}}"#

        let record = UsageJSONLParser(source: .claudeCode).parseLines([line]).first

        XCTAssertEqual(record?.tokens.cacheCreation, 30)
    }

    func testParsesNestedCacheCreationFields() {
        let line = #"{"timestamp":"2026-07-03T01:02:03.000Z","message":{"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":30,"cache_creation":{"ephemeral_5m_input_tokens":40,"ephemeral_1h_input_tokens":50},"cache_read_input_tokens":4}}}"#

        let record = UsageJSONLParser(source: .claudeCode).parseLines([line]).first

        XCTAssertEqual(record?.tokens.cacheCreation, 90)
    }

    func testDeduplicatesByMessageIDKeepingLastRecord() {
        let first = #"{"timestamp":"2026-07-03T01:00:00.000Z","message":{"id":"msg_1","usage":{"input_tokens":1}}}"#
        let second = #"{"timestamp":"2026-07-03T01:01:00.000Z","message":{"id":"msg_1","usage":{"input_tokens":5}}}"#

        let records = UsageJSONLParser(source: .claudeCode).parseLines([first, second])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].tokens.input, 5)
        XCTAssertEqual(records[0].timestamp, ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-07-03T01:01:00.000Z"))
    }

    func testDeduplicatesByRequestIDWhenMessageIDMissing() {
        let first = #"{"timestamp":"2026-07-03T01:00:00.000Z","requestId":"req_1","message":{"usage":{"input_tokens":1}}}"#
        let second = #"{"timestamp":"2026-07-03T01:01:00.000Z","requestId":"req_1","message":{"usage":{"input_tokens":5}}}"#

        let records = UsageJSONLParser(source: .claudeCode).parseLines([first, second])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].requestID, "req_1")
        XCTAssertEqual(records[0].tokens.input, 5)
    }

    func testPreservesRecordsWithoutIdentity() {
        let first = #"{"timestamp":"2026-07-03T01:00:00.000Z","message":{"usage":{"input_tokens":1}}}"#
        let second = #"{"timestamp":"2026-07-03T01:01:00.000Z","message":{"usage":{"input_tokens":5}}}"#

        let records = UsageJSONLParser(source: .claudeCode).parseLines([first, second])

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.tokens.input), [1, 5])
    }

    func testParsesRunBudgetCachePayload() {
        let cache = """
        binary-prefix https://claude.ai/v1/code/routines/run-budget({"limit":"25","unified_billing_enabled":true,"used":"7"}) trailing
        """

        let snapshots = CacheSnapshotParser().parse(text: cache)

        XCTAssertEqual(snapshots.first?.kind, .runBudget)
        XCTAssertEqual(snapshots.first?.used, 7)
        XCTAssertEqual(snapshots.first?.limit, 25)
        XCTAssertEqual(snapshots.first?.percentUsed, 28)
    }

    func testAggregatesTodayMonthAndSourceBreakdown() throws {
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
        XCTAssertEqual(aggregate.month.tokens.total, 25)
        XCTAssertEqual(aggregate.bySource[.claudeCode]?.tokens.total, 15)
        XCTAssertEqual(aggregate.bySource[.desktopCowork]?.tokens.total, 10)
    }

    func testDiscoversClaudeCodeSourceRoots() throws {
        let fixture = try SourceDiscoveryFixture()
        try fixture.createDirectory(".claude/projects")
        try fixture.createDirectory("custom/projects")
        try fixture.createDirectory(".claude-alt/projects")
        try fixture.createDirectory("Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects")

        let discovery = UsageSourceDiscovery(
            homeDirectory: fixture.home,
            environment: ["CLAUDE_CONFIG_DIR": fixture.url("custom").path],
            fileManager: fixture.fileManager
        )

        let roots = discovery.claudeCodeProjectRoots().map(\.standardizedFileURL.path)

        XCTAssertEqual(Set(roots), Set([
            fixture.url(".claude/projects").standardizedFileURL.path,
            fixture.url("custom/projects").standardizedFileURL.path,
            fixture.url(".claude-alt/projects").standardizedFileURL.path,
            fixture.url("Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects").standardizedFileURL.path
        ]))
    }

    func testDeduplicatesDiscoveredSourceRoots() throws {
        let fixture = try SourceDiscoveryFixture()
        try fixture.createDirectory(".claude/projects")

        let discovery = UsageSourceDiscovery(
            homeDirectory: fixture.home,
            environment: ["CLAUDE_CONFIG_DIR": fixture.url(".claude").path],
            fileManager: fixture.fileManager
        )

        XCTAssertEqual(discovery.claudeCodeProjectRoots().count, 1)
    }

    func testOAuthUsageServiceParsesBuckets() async throws {
        MockURLProtocol.response = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        MockURLProtocol.data = #"{"five_hour":{"utilization":42.5,"resets_at":"2026-07-03T06:00:00.000Z"},"seven_day":{"utilization":11},"seven_day_oauth_apps":{"utilization":2},"seven_day_opus":{"utilization":3},"seven_day_sonnet":{"utilization":4}}"#.data(using: .utf8)
        let service = OAuthUsageService(session: mockSession())
        let token = UUID().uuidString

        let snapshot = try await service.fetchUsage(accessToken: token, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.fiveHour?.utilization, 42.5)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, ISO8601DateFormatter.withFractionalSeconds.date(from: "2026-07-03T06:00:00.000Z"))
        XCTAssertEqual(snapshot.sevenDay?.utilization, 11)
        XCTAssertEqual(snapshot.sevenDayOAuthApps?.utilization, 2)
        XCTAssertEqual(snapshot.sevenDayOpus?.utilization, 3)
        XCTAssertEqual(snapshot.sevenDaySonnet?.utilization, 4)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer "), true)
    }

    func testOAuthUsageServiceMapsUnauthorizedAndRateLimitedResponses() async throws {
        let service = OAuthUsageService(session: mockSession())

        MockURLProtocol.response = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, statusCode: 401, httpVersion: nil, headerFields: nil)
        await XCTAssertThrowsOAuthError(.unauthorized) {
            _ = try await service.fetchUsage(accessToken: UUID().uuidString, now: Date())
        }

        MockURLProtocol.response = HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, statusCode: 429, httpVersion: nil, headerFields: nil)
        await XCTAssertThrowsOAuthError(.rateLimited) {
            _ = try await service.fetchUsage(accessToken: UUID().uuidString, now: Date())
        }
    }

    func testUsageStoreDoesNotFetchOAuthWhenDisabled() async throws {
        let fixture = try SourceDiscoveryFixture()
        let client = SpyOAuthUsageClient()
        let store = UsageStore(
            homeDirectory: fixture.home,
            fileManager: fixture.fileManager,
            enableOAuthLiveQuota: false,
            oauthCredentialProvider: StaticOAuthCredentialProvider(token: UUID().uuidString),
            oauthClient: client
        )

        let aggregate = await store.loadAsync(now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(client.fetchCount, 0)
        XCTAssertNil(aggregate.liveQuota)
        XCTAssertEqual(aggregate.liveQuotaStatus, .unavailable)
    }
}

private struct SourceDiscoveryFixture {
    let home: URL
    let fileManager = FileManager.default

    init() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func url(_ path: String) -> URL {
        home.appendingPathComponent(path)
    }

    func createDirectory(_ path: String) throws {
        try fileManager.createDirectory(at: url(path), withIntermediateDirectories: true)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: HTTPURLResponse?
    nonisolated(unsafe) static var data: Data?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let response = Self.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.data ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func XCTAssertThrowsOAuthError(
    _ expected: OAuthUsageError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws -> Void
) async {
    do {
        try await expression()
        XCTFail("Expected OAuthUsageError.\(expected)", file: file, line: line)
    } catch let error as OAuthUsageError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

private final class SpyOAuthUsageClient: OAuthUsageClient, @unchecked Sendable {
    private(set) var fetchCount = 0

    func fetchUsage(accessToken: String, now: Date) async throws -> OAuthUsageSnapshot {
        fetchCount += 1
        return OAuthUsageSnapshot(fetchedAt: now)
    }
}
