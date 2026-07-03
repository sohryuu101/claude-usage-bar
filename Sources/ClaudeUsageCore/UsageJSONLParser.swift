import Foundation

public struct UsageJSONLParser: Sendable {
    private let source: UsageSource

    public init(source: UsageSource) {
        self.source = source
    }

    public func parseLines(_ lines: [String]) -> [UsageRecord] {
        lines.compactMap(parseLine)
    }

    public func parseFile(at url: URL) -> [UsageRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parseLines(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    private func parseLine(_ line: String) -> UsageRecord? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else {
            return nil
        }

        let input = intValue(usage["input_tokens"])
        let output = intValue(usage["output_tokens"])
        let cacheCreation = intValue(usage["cache_creation_input_tokens"])
        let cacheRead = intValue(usage["cache_read_input_tokens"])
        let tokens = TokenUsage(
            input: input,
            output: output,
            cacheCreation: cacheCreation,
            cacheRead: cacheRead
        )
        guard tokens.total > 0 else { return nil }

        var timestamp: Date? = nil
        if let tsString = object["timestamp"] as? String {
            timestamp = parseDate(tsString)
        } else if let tsNum = object["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: tsNum > 1_000_000_000_000 ? tsNum / 1000.0 : tsNum)
        } else if let auditTsString = object["_audit_timestamp"] as? String {
            timestamp = parseDate(auditTsString)
        } else if let auditTsNum = object["_audit_timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: auditTsNum > 1_000_000_000_000 ? auditTsNum / 1000.0 : auditTsNum)
        }
        guard let validTimestamp = timestamp else { return nil }

        return UsageRecord(
            source: source,
            timestamp: validTimestamp,
            model: message["model"] as? String ?? "unknown",
            tokens: tokens
        )
    }

    private func parseDate(_ text: String) -> Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: text)
            ?? ISO8601DateFormatter.internetDateTime.date(from: text)
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as Int:
            return number
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? 0
        default:
            return 0
        }
    }
}
