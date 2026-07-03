import Foundation

public struct CacheSnapshotParser: Sendable {
    public init() {}

    public func parse(text: String, capturedAt: Date? = nil) -> [CacheSnapshot] {
        var results: [CacheSnapshot] = []
        
        if text.contains("/v1/code/routines/run-budget") {
            if let payload = findJSONObject(in: text, requiring: ["used", "limit"]),
               let used = doubleValue(payload["used"]),
               let limit = doubleValue(payload["limit"]) {
                results.append(CacheSnapshot(kind: .runBudget, used: used, limit: limit, capturedAt: capturedAt))
            }
        }
        
        if text.contains("/usage") || text.contains("extra_usage") || text.contains("omelette_promotional") {
            if let payload = findJSONObject(in: text, requiringOneOf: ["spend", "extra_usage"], andOneOf: []) {
                if let spend = payload["spend"] as? [String: Any],
                   let usedObj = spend["used"] as? [String: Any],
                   let limitObj = spend["limit"] as? [String: Any],
                   let usedMinor = doubleValue(usedObj["amount_minor"]),
                   let limitMinor = doubleValue(limitObj["amount_minor"]) {
                    results.append(CacheSnapshot(kind: .usage, used: usedMinor / 100.0, limit: limitMinor / 100.0, capturedAt: capturedAt))
                } else if let extraUsage = payload["extra_usage"] as? [String: Any],
                          let usedCents = doubleValue(extraUsage["used_credits"]),
                          let limitCents = doubleValue(extraUsage["monthly_limit"]) {
                    results.append(CacheSnapshot(kind: .usage, used: usedCents / 100.0, limit: limitCents / 100.0, capturedAt: capturedAt))
                }
            }
            
            if let payload = findJSONObject(in: text, requiringOneOf: ["omelette_promotional"], andOneOf: []) {
                if let omelette = payload["omelette_promotional"] as? [String: Any],
                   let utilization = doubleValue(omelette["utilization"]) {
                    results.append(CacheSnapshot(kind: .designAllowance, used: utilization, limit: 100.0, capturedAt: capturedAt))
                }
            }
        }
        
        return results
    }

    public func parseFile(at url: URL) -> [CacheSnapshot] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        
        let zstdMagic = Data([0x28, 0xb5, 0x2f, 0xfd])
        if let magicRange = data.range(of: zstdMagic) {
            let httpHeader = "HTTP/1.1".data(using: .utf8)!
            if let httpIdx = data.range(of: httpHeader, options: [], in: magicRange.lowerBound..<data.count)?.lowerBound {
                let trimmedLength = httpIdx - magicRange.lowerBound - 64
                if trimmedLength > 0 {
                    let zstdData = data.subdata(in: magicRange.lowerBound..<(magicRange.lowerBound + trimmedLength))
                    if let decompressed = decompressZstdCLI(data: zstdData),
                       let text = String(data: decompressed, encoding: .utf8) {
                        return parse(text: text, capturedAt: modifiedAt)
                    }
                }
            }
        }
        
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return parse(text: text, capturedAt: modifiedAt)
        }
        return []
    }

    private func decompressZstdCLI(data: Data) -> Data? {
        let process = Process()
        let paths = [
            "/opt/homebrew/bin/zstd",
            "/usr/local/bin/zstd",
            "/usr/bin/zstd"
        ]
        
        var zstdPath = "zstd"
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                zstdPath = path
                break
            }
        }
        
        process.executableURL = URL(fileURLWithPath: zstdPath)
        process.arguments = ["-d"]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        
        do {
            try process.run()
            try inPipe.fileHandleForWriting.write(contentsOf: data)
            try inPipe.fileHandleForWriting.close()
            
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return outData
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    private func findJSONObject(in text: String, requiring keys: [String]) -> [String: Any]? {
        return findJSONObject(in: text, requiringOneOf: keys, requireAllSet1: true, andOneOf: [])
    }

    private func findJSONObject(in text: String, requiringOneOf set1: [String], requireAllSet1: Bool = false, andOneOf set2: [String]) -> [String: Any]? {
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
                        
                        let hasSet1: Bool
                        if requireAllSet1 {
                            hasSet1 = set1.allSatisfy { object.keys.contains($0) }
                        } else {
                            hasSet1 = set1.isEmpty || set1.contains(where: { object.keys.contains($0) })
                        }
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
