// HookInstaller.swift
// Installs and removes ClawdIsland's hooks and statusLine in Claude Code's settings file (docs/05, REQ-09 AC1).

import Foundation

/// File side of the installer: read, back up, merge with `HookSettings`, write atomically.
/// Every write is preceded by a successful parse and a backup; an unparsable file is never written.
/// Paths are injectable so tests and development never touch the real `~/.claude/settings.json`.
public struct HookInstaller {
    /// Thrown when `config.json` exists but cannot be decoded; overwriting it would lose the saved
    /// statusLine and change the token, so the installer writes nothing.
    public struct CorruptConfig: LocalizedError {
        public var errorDescription: String? {
            "ClawdIsland's config.json is not valid; nothing was changed."
        }
    }

    public var settingsURL: URL
    public var configURL: URL
    /// Absolute path of `clawd-bridge`; the app passes the one shipped next to its executable.
    public var bridgePath: String

    public init(
        settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json"),
        configURL: URL = AppConfig.defaultURL,
        bridgePath: String
    ) {
        self.settingsURL = settingsURL
        self.configURL = configURL
        self.bridgePath = bridgePath
    }

    /// Whether our entries are present; false when the file is missing or unreadable.
    public var isInstalled: Bool {
        (try? read()).map(HookSettings.isInstalled) ?? false
    }

    /// Adds or refreshes our hooks and statusLine, saving a foreign statusLine to the config first.
    /// Creates the config (default port, new token) when it is missing.
    /// - Throws: `HookSettings.InvalidSettings` or `CorruptConfig` without writing anything, or a file error.
    public func install() throws {
        let settings = try read()
        var config = try readConfig() ?? .makeDefault()
        let installed = HookSettings.install(
            into: settings, port: config.port, token: config.token, bridgePath: bridgePath)
        if let foreign = installed.foreignStatusLine { config.originalStatusLine = foreign }
        // Saved before settings change so the user's statusLine can never be lost between the two writes.
        try config.write(to: configURL)
        try write(installed.settings)
    }

    /// Removes our entries and restores the saved statusLine. A missing settings file is a no-op.
    /// - Throws: `HookSettings.InvalidSettings` or `CorruptConfig` without writing anything, or a file error.
    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let settings = try read()
        var config = try readConfig()
        try write(HookSettings.uninstall(from: settings, originalStatusLine: config?.originalStatusLine))
        if config?.originalStatusLine != nil {
            config?.originalStatusLine = nil
            try config?.write(to: configURL)
        }
    }

    /// The real file behind the settings path; a dotfiles symlink must stay a symlink after an atomic write.
    private var target: URL { settingsURL.resolvingSymlinksInPath() }

    private func read() throws -> [String: Any] {
        let path = target.path
        return try HookSettings.parse(FileManager.default.fileExists(atPath: path) ? Data(contentsOf: target) : nil)
    }

    /// The saved config, nil when absent; throws rather than let a corrupt one be replaced by a default.
    private func readConfig() throws -> AppConfig? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        guard let config = AppConfig.load(from: configURL) else { throw CorruptConfig() }
        return config
    }

    private func write(_ settings: [String: Any]) throws {
        try backup()
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    /// Copies the current file to `settings.json.clawdisland-backup-<timestamp>`; nothing to back up if it is missing.
    private func backup() throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        // Next to the settings path (not the symlink target) so backups never land in a dotfiles repo.
        let url = settingsURL.deletingLastPathComponent()
            .appending(path: "\(settingsURL.lastPathComponent).clawdisland-backup-\(formatter.string(from: Date()))")
        // shortcut: backups accumulate without limit (one per install/uninstall); prune old ones if users complain.
        // Throws on a name clash rather than overwrite an older, more valuable backup.
        try FileManager.default.copyItem(at: target, to: url)
    }
}
