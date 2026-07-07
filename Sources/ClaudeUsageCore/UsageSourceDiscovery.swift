import Foundation

public struct UsageSourceDiscovery {
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

    public func claudeCodeProjectRoots() -> [URL] {
        var roots: [URL] = []

        appendIfDirectory(homeDirectory.appendingPathComponent(".claude/projects"), to: &roots)

        if let configDir = environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
            appendIfDirectory(URL(fileURLWithPath: configDir).appendingPathComponent("projects"), to: &roots)
        }

        if let entries = try? fileManager.contentsOfDirectory(
            at: homeDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            for entry in entries where entry.lastPathComponent.hasPrefix(".claude-") {
                appendIfDirectory(entry.appendingPathComponent("projects"), to: &roots)
            }
        }

        appendIfDirectory(
            homeDirectory.appendingPathComponent("Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects"),
            to: &roots
        )

        return deduplicated(roots)
    }

    public func desktopCoworkRoot() -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions")
    }

    private func appendIfDirectory(_ url: URL, to roots: inout [URL]) {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            roots.append(url)
        }
    }

    private func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(url)
            }
        }
        return result
    }
}
