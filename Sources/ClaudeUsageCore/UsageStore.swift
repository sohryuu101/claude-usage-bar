import Foundation

public struct UsageStore: @unchecked Sendable {
    public var homeDirectory: URL
    public var fileManager: FileManager
    public var enableOAuthLiveQuota: Bool
    public var oauthCredentialProvider: any OAuthCredentialProvider
    public var oauthClient: any OAuthUsageClient

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        enableOAuthLiveQuota: Bool = false,
        oauthCredentialProvider: (any OAuthCredentialProvider)? = nil,
        oauthClient: any OAuthUsageClient = OAuthUsageService()
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.enableOAuthLiveQuota = enableOAuthLiveQuota
        self.oauthCredentialProvider = oauthCredentialProvider ?? ClaudeCodeOAuthCredentialProvider(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        self.oauthClient = oauthClient
    }

    public func load(now: Date = Date()) -> UsageAggregate {
        loadLocal(now: now, liveQuota: nil, liveQuotaStatus: .unavailable)
    }

    public func loadAsync(now: Date = Date()) async -> UsageAggregate {
        guard enableOAuthLiveQuota, let token = oauthCredentialProvider.accessToken() else {
            return loadLocal(now: now, liveQuota: nil, liveQuotaStatus: .unavailable)
        }

        do {
            let liveQuota = try await oauthClient.fetchUsage(accessToken: token, now: now)
            return loadLocal(now: now, liveQuota: liveQuota, liveQuotaStatus: .enabled)
        } catch OAuthUsageError.unauthorized {
            return loadLocal(now: now, liveQuota: nil, liveQuotaStatus: .unauthorized)
        } catch OAuthUsageError.rateLimited {
            return loadLocal(now: now, liveQuota: nil, liveQuotaStatus: .rateLimited)
        } catch {
            return loadLocal(now: now, liveQuota: nil, liveQuotaStatus: .unavailable)
        }
    }

    public func resetKeychainAccess() {
        #if os(macOS)
        ClaudeCodeOAuthCredentialProvider.isKeychainAccessDenied = false
        #endif
    }

    private func loadLocal(
        now: Date,
        liveQuota: OAuthUsageSnapshot?,
        liveQuotaStatus: OAuthLiveQuotaStatus
    ) -> UsageAggregate {
        let records = loadRecords()
        let snapshots = loadAccountSnapshots()
        let primarySnapshot = snapshots.first { $0.kind == .runBudget || $0.kind == .usage }
        let designSnapshot = snapshots.first { $0.kind == .designAllowance }
        let subSnapshot = snapshots.first { $0.kind == .subscriptionStatus }
        
        var plan = oauthCredentialProvider.getPlanType()
        if plan == nil {
            if liveQuota?.extraUsage?.isEnabled == true {
                plan = .enterprise
            } else if let subPlan = subSnapshot?.plan?.lowercased() {
                if subPlan.contains("pro") {
                    plan = .pro
                } else if subPlan.contains("free") {
                    plan = .free
                }
            }
        }
        let planType = plan ?? .free

        return UsageAggregator().aggregate(
            records: records,
            accountSnapshot: primarySnapshot,
            designSnapshot: designSnapshot,
            subscriptionSnapshot: subSnapshot,
            liveQuota: liveQuota,
            liveQuotaStatus: liveQuotaStatus,
            planType: planType,
            now: now
        )
    }

    public func loadRecords() -> [UsageRecord] {
        let discovery = UsageSourceDiscovery(homeDirectory: homeDirectory, fileManager: fileManager)

        let codeRecords = discovery.claudeCodeProjectRoots()
            .flatMap { jsonlFiles(under: $0) }
            .flatMap { UsageJSONLParser(source: .claudeCode).parseFile(at: $0) }
        let coworkRecords = jsonlFiles(under: discovery.desktopCoworkRoot())
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
