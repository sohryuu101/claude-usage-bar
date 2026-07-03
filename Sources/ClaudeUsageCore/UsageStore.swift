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
        let snapshots = loadAccountSnapshots()
        let primarySnapshot = snapshots.first { $0.kind == .runBudget || $0.kind == .usage }
        let designSnapshot = snapshots.first { $0.kind == .designAllowance }
        let subSnapshot = snapshots.first { $0.kind == .subscriptionStatus }
        return UsageAggregator().aggregate(
            records: records,
            accountSnapshot: primarySnapshot,
            designSnapshot: designSnapshot,
            subscriptionSnapshot: subSnapshot,
            now: now
        )
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

    public func loadAccountSnapshots() -> [CacheSnapshot] {
        let cacheRoot = homeDirectory.appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data")
        let files = regularFiles(under: cacheRoot)
        let sortedFiles = files.sorted {
            let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return date1 > date2
        }
        var snapshots: [CacheSnapshot] = []
        for file in sortedFiles.prefix(500) {
            let parsed = CacheSnapshotParser().parseFile(at: file)
            for snapshot in parsed {
                if !snapshots.contains(where: { $0.kind == snapshot.kind }) {
                    snapshots.append(snapshot)
                }
            }
            let hasPrimary = snapshots.contains { $0.kind == .runBudget || $0.kind == .usage }
            let hasDesign = snapshots.contains { $0.kind == .designAllowance }
            let hasSub = snapshots.contains { $0.kind == .subscriptionStatus }
            if hasPrimary && hasDesign && hasSub {
                break
            }
        }
        return snapshots
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        regularFiles(under: root).filter { $0.pathExtension == "jsonl" }
    }

    private func regularFiles(under root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize < 50_000_000 // Skip files larger than 50MB
            else {
                return nil
            }
            return url
        }
    }
}
