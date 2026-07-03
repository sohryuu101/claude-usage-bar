import Foundation

public struct UsageStore {
    public var homeDirectory: URL
    public var fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func load(now: Date = Date()) -> UsageAggregate {
        let records = loadRecords()
        let snapshot = loadAccountSnapshot()
        return UsageAggregator().aggregate(records: records, accountSnapshot: snapshot, now: now)
    }

    public func loadRecords() -> [UsageRecord] {
        let codeRoot = homeDirectory.appendingPathComponent(".claude/projects")
        let coworkRoot = homeDirectory.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")

        let codeRecords = jsonlFiles(under: codeRoot)
            .flatMap { UsageJSONLParser(source: .claudeCode).parseFile(at: $0) }
        let coworkRecords = jsonlFiles(under: coworkRoot)
            .filter { $0.lastPathComponent == "audit.jsonl" }
            .flatMap { UsageJSONLParser(source: .desktopCowork).parseFile(at: $0) }

        return (codeRecords + coworkRecords).sorted { $0.timestamp > $1.timestamp }
    }

    public func loadAccountSnapshot() -> CacheSnapshot? {
        let cacheRoot = homeDirectory.appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data")
        return regularFiles(under: cacheRoot)
            .compactMap { CacheSnapshotParser().parseFile(at: $0) }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            .first
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        regularFiles(under: root).filter { $0.pathExtension == "jsonl" }
    }

    private func regularFiles(under root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
