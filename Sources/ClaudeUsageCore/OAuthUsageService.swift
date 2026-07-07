import Foundation

public enum OAuthUsageError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case invalidResponse
}

public protocol OAuthUsageClient: Sendable {
    func fetchUsage(accessToken: String, now: Date) async throws -> OAuthUsageSnapshot
}

public protocol OAuthCredentialProvider: Sendable {
    func accessToken() -> String?
}

public struct StaticOAuthCredentialProvider: OAuthCredentialProvider {
    private let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func accessToken() -> String? {
        token
    }
}

public struct ClaudeCodeOAuthCredentialProvider: OAuthCredentialProvider, @unchecked Sendable {
    public var homeDirectory: URL
    public var environment: [String: String]
    public var fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.fileManager = fileManager
    }

    public func accessToken() -> String? {
        for file in candidateFiles() {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }
            if let token = findAccessToken(in: object) {
                return token
            }
        }
        return nil
    }

    private func candidateFiles() -> [URL] {
        var directories = [homeDirectory.appendingPathComponent(".claude")]
        if let configDir = environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
            directories.insert(URL(fileURLWithPath: configDir), at: 0)
        }

        let names = [
            ".credentials.json",
            "credentials.json",
            "oauth.json",
            "auth.json",
            "settings.json"
        ]

        var files: [URL] = []
        var seen: Set<String> = []
        appendCandidate(homeDirectory.appendingPathComponent(".claude.json"), to: &files, seen: &seen)
        for directory in directories {
            for name in names {
                appendCandidate(directory.appendingPathComponent(name), to: &files, seen: &seen)
            }
        }
        return files
    }

    private func appendCandidate(_ file: URL, to files: inout [URL], seen: inout Set<String>) {
        let path = file.standardizedFileURL.path
        if seen.insert(path).inserted, fileManager.fileExists(atPath: file.path) {
            files.append(file)
        }
    }

    private func findAccessToken(in value: Any) -> String? {
        if let object = value as? [String: Any] {
            for key in ["accessToken", "access_token", "oauthAccessToken", "oauth_access_token"] {
                if let token = object[key] as? String, !token.isEmpty {
                    return token
                }
            }

            if let nested = object["claudeAiOauth"] ?? object["claude_ai_oauth"] ?? object["oauth"] {
                if let token = findAccessToken(in: nested) {
                    return token
                }
            }

            for nested in object.values {
                if let token = findAccessToken(in: nested) {
                    return token
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let token = findAccessToken(in: nested) {
                    return token
                }
            }
        }
        return nil
    }
}

public struct OAuthUsageService: OAuthUsageClient {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func fetchUsage(accessToken: String, now: Date = Date()) async throws -> OAuthUsageSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthUsageError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            let response = try JSONDecoder.oauthUsage.decode(OAuthUsageResponse.self, from: data)
            return response.snapshot(fetchedAt: now)
        case 401:
            throw OAuthUsageError.unauthorized
        case 429:
            throw OAuthUsageError.rateLimited
        default:
            throw OAuthUsageError.invalidResponse
        }
    }
}

private struct OAuthUsageResponse: Decodable {
    var fiveHour: OAuthQuotaBucketResponse?
    var sevenDay: OAuthQuotaBucketResponse?
    var sevenDayOAuthApps: OAuthQuotaBucketResponse?
    var sevenDayOpus: OAuthQuotaBucketResponse?
    var sevenDaySonnet: OAuthQuotaBucketResponse?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    func snapshot(fetchedAt: Date) -> OAuthUsageSnapshot {
        OAuthUsageSnapshot(
            fiveHour: fiveHour?.bucket,
            sevenDay: sevenDay?.bucket,
            sevenDayOAuthApps: sevenDayOAuthApps?.bucket,
            sevenDayOpus: sevenDayOpus?.bucket,
            sevenDaySonnet: sevenDaySonnet?.bucket,
            fetchedAt: fetchedAt
        )
    }
}

private struct OAuthQuotaBucketResponse: Decodable {
    var utilization: Double
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var bucket: OAuthQuotaBucket {
        OAuthQuotaBucket(utilization: utilization, resetsAt: resetsAt)
    }
}

private extension JSONDecoder {
    static var oauthUsage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: text)
                ?? ISO8601DateFormatter.internetDateTime.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
        }
        return decoder
    }
}
