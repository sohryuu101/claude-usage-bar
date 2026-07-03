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

        let timestampText = (object["timestamp"] as? String) ?? (object["_audit_timestamp"] as? String)
        guard let timestamp = timestampText.flatMap(parseDate) else { return nil }

        return UsageRecord(
            source: source,
            timestamp: timestamp,
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
