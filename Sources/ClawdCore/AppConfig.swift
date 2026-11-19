// AppConfig.swift
// The app's config file contract (docs/03): shared by the event server, the installer and, by key name, the bridge.

import Foundation

/// Contents of `~/Library/Application Support/ClawdNotch/config.json`. Keys are the property names;
/// the bridge reads `port`, `token` and `originalStatusLine` from the same file without linking ClawdCore.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let defaultPort = 47474

    public var port: Int
    /// Shared secret sent by hooks and the bridge as `X-Clawd-Token`.
    public var token: String
    /// The user's own statusLine command, saved on install so the bridge can wrap it and uninstall can restore it.
    public var originalStatusLine: String?

    public init(port: Int = AppConfig.defaultPort, token: String, originalStatusLine: String? = nil) {
        self.port = port
        self.token = token
        self.originalStatusLine = originalStatusLine
    }

    /// A fresh config with the default port and a random token.
    public static func makeDefault() -> AppConfig {
        AppConfig(token: UUID().uuidString)
    }

    /// `~/Library/Application Support/ClawdNotch/config.json`.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ClawdNotch/config.json")
    }

    /// Reads a config; nil when the file is missing or unreadable.
    public static func load(from url: URL = defaultURL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Writes the config atomically, creating the directory if needed.
    public func write(to url: URL = AppConfig.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
