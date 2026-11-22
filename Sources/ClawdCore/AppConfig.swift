// AppConfig.swift
// The app's config file contract (docs/03): shared by the event server, the installer and, by key name, the bridge.

import Foundation

/// Contents of `~/Library/Application Support/ClawdIsland/config.json`. Keys are the property names;
/// the bridge reads `port`, `token` and `originalStatusLine` from the same file without linking ClawdCore.
public struct AppConfig: Codable, Equatable, Sendable {
    public static let defaultPort = 47474

    public var port: Int
    /// Shared secret sent by hooks and the bridge as `X-Clawd-Token`.
    public var token: String
    /// The user's own statusLine command, saved on install so the bridge can wrap it and uninstall can restore it.
    public var originalStatusLine: String?
    /// Mini mode (REQ-05): Clawd tucks under the notch and pops out on state changes.
    public var miniMode: Bool
    /// How a terminal coming to the front marks sessions read (REQ-10).
    public var focusReadMode: FocusReadMode

    /// How focusing a terminal marks sessions read.
    public enum FocusReadMode: String, Codable, CaseIterable, Sendable {
        /// The selected Terminal.app / iTerm2 tab's session only; other terminals fall back to the dwell.
        case tab
        /// Every finished session of the frontmost terminal app after a short dwell; no AppleScript.
        case app
        /// Never mark on activation.
        case off
    }

    /// Hold `PermissionRequest` hooks so the notch can allow or deny them (REQ-V2-01). Off means every hook gets an empty reply.
    public var notchPermissions: Bool
    /// Play a short system sound on the edge into needs-input or an unread done (REQ-12).
    public var soundCues: Bool
    /// Directories of recently seen sessions for the "New session" menu: newest first, at most `maxRecentProjects` (REQ-V2-03).
    public var recentProjects: [String]
    public static let maxRecentProjects = 5

    public init(
        port: Int = AppConfig.defaultPort,
        token: String,
        originalStatusLine: String? = nil,
        miniMode: Bool = false,
        focusReadMode: FocusReadMode = .tab,
        notchPermissions: Bool = true,
        soundCues: Bool = true,
        recentProjects: [String] = []
    ) {
        self.port = port
        self.token = token
        self.originalStatusLine = originalStatusLine
        self.miniMode = miniMode
        self.focusReadMode = focusReadMode
        self.notchPermissions = notchPermissions
        self.soundCues = soundCues
        self.recentProjects = recentProjects
    }

    /// Keys of earlier versions, read only as a fallback.
    private enum LegacyKeys: String, CodingKey {
        /// Renamed to `miniMode` in v5.
        case hideMode
    }

    /// Files written before a key existed lack it, so they decode to the defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decode(Int.self, forKey: .port)
        token = try container.decode(String.self, forKey: .token)
        originalStatusLine = try container.decodeIfPresent(String.self, forKey: .originalStatusLine)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        miniMode = try container.decodeIfPresent(Bool.self, forKey: .miniMode)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .hideMode) ?? false
        focusReadMode = try container.decodeIfPresent(FocusReadMode.self, forKey: .focusReadMode) ?? .tab
        notchPermissions = try container.decodeIfPresent(Bool.self, forKey: .notchPermissions) ?? true
        soundCues = try container.decodeIfPresent(Bool.self, forKey: .soundCues) ?? true
        recentProjects = try container.decodeIfPresent([String].self, forKey: .recentProjects) ?? []
    }

    /// Puts `directory` first in `recentProjects`, dropping an earlier copy and anything beyond the cap.
    public mutating func noteRecentProject(_ directory: String) {
        recentProjects.removeAll { $0 == directory }
        recentProjects.insert(directory, at: 0)
        recentProjects = Array(recentProjects.prefix(Self.maxRecentProjects))
    }

    /// A fresh config with the default port and a random token.
    public static func makeDefault() -> AppConfig {
        AppConfig(token: UUID().uuidString)
    }

    /// `~/Library/Application Support/ClawdIsland/config.json`.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ClawdIsland/config.json")
    }

    /// One-time move of the pre-rename `Application Support/ClawdNotch` folder to `ClawdIsland` (ADR-0009),
    /// keeping the token, port and saved statusline. Does nothing unless only the old folder exists.
    /// - Returns: whether the folder was moved.
    @discardableResult
    public static func migrateLegacySupportFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let support = home.appending(path: "Library/Application Support")
        let old = support.appending(path: "ClawdNotch")
        let new = support.appending(path: "ClawdIsland")
        let files = FileManager.default
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return false }
        // shortcut: a failed move falls back to a fresh config (new token; the old statusline backup stays behind).
        return (try? files.moveItem(at: old, to: new)) != nil
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
