import Foundation

public struct UsageJSONLParser: Sendable {
    private let source: UsageSource

    public init(source: UsageSource) {
        self.source = source
    }

    public func parseLines(_ lines: [String]) -> [UsageRecord] {
        var records: [UsageRecord] = []
        var indexesByKey: [String: Int] = [:]

        for line in lines {
            guard let record = parseLine(line) else {
                continue
            }

            if let key = dedupeKey(for: record) {
                if let existingIndex = indexesByKey[key] {
                    records[existingIndex] = record
                } else {
                    indexesByKey[key] = records.count
                    records.append(record)
                }
            } else {
                records.append(record)
            }
        }

        return records
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
        let cacheCreation = cacheCreationTokens(from: usage)
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
            tokens: tokens,
            messageID: message["id"] as? String,
            requestID: object["requestId"] as? String ?? object["request_id"] as? String,
            sessionID: object["sessionId"] as? String ?? object["session_id"] as? String
        )
    }

    private func dedupeKey(for record: UsageRecord) -> String? {
        if let messageID = record.messageID, !messageID.isEmpty {
            return "message:\(messageID)"
        }
        if let requestID = record.requestID, !requestID.isEmpty {
            return "request:\(requestID)"
        }
        return nil
    }

    private func cacheCreationTokens(from usage: [String: Any]) -> Int {
        if let nested = usage["cache_creation"] as? [String: Any] {
            let ephemeral5m = intValue(nested["ephemeral_5m_input_tokens"])
            let ephemeral1h = intValue(nested["ephemeral_1h_input_tokens"])
            if ephemeral5m > 0 || ephemeral1h > 0 {
                return ephemeral5m + ephemeral1h
            }
        }
        return intValue(usage["cache_creation_input_tokens"])
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
