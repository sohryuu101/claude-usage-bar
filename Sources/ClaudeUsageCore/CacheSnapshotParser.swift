import Foundation

public struct CacheSnapshotParser: Sendable {
    public init() {}

    public func parse(text: String, capturedAt: Date? = nil) -> CacheSnapshot? {
        if text.contains("/v1/code/routines/run-budget") {
            if let payload = findJSONObject(in: text, requiring: ["used", "limit"]),
               let used = doubleValue(payload["used"]),
               let limit = doubleValue(payload["limit"]) {
                return CacheSnapshot(kind: .runBudget, used: used, limit: limit, capturedAt: capturedAt)
            }
        }

        if text.contains("/usage") {
            let usedKeys = ["used", "amount_used", "current_spend", "spent"]
            let limitKeys = ["limit", "spend_limit", "monthly_limit", "amount_limit"]
            if let payload = findJSONObject(in: text, requiringOneOf: usedKeys, andOneOf: limitKeys),
               let used = firstDouble(in: payload, keys: usedKeys),
               let limit = firstDouble(in: payload, keys: limitKeys) {
                return CacheSnapshot(kind: .usage, used: used, limit: limit, capturedAt: capturedAt)
            }
        }

        return nil
    }

    public func parseFile(at url: URL) -> CacheSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        return parse(text: text, capturedAt: modifiedAt)
    }

    private func findJSONObject(in text: String, requiring keys: [String]) -> [String: Any]? {
        return findJSONObject(in: text, requiringOneOf: keys, andOneOf: [])
    }

    private func findJSONObject(in text: String, requiringOneOf set1: [String], andOneOf set2: [String]) -> [String: Any]? {
        let scalars = Array(text.unicodeScalars)
        for start in scalars.indices where scalars[start] == "{" {
            var depth = 0
            for end in start..<scalars.count {
                if scalars[end] == "{" { depth += 1 }
                if scalars[end] == "}" { depth -= 1 }
                if depth == 0 {
                    let candidate = String(String.UnicodeScalarView(scalars[start...end]))
                    if let data = candidate.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        let hasSet1 = set1.isEmpty || set1.contains(where: { object.keys.contains($0) })
                        let hasSet2 = set2.isEmpty || set2.contains(where: { object.keys.contains($0) })
                        
                        if hasSet1 && hasSet2 {
                            return object
                        }
                    }
                    break
                }
            }
        }
        return nil
    }

    private func firstDouble(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = doubleValue(object[key]) {
                return value
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any],
               let match = firstDouble(in: nested, keys: keys) {
                return match
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}
