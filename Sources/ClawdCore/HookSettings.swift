// HookSettings.swift
// Pure merge of ClawdNotch's hooks and statusLine into a Claude Code settings object (docs/05, REQ-09).

import Foundation

/// Adds and removes ClawdNotch's entries in a parsed `~/.claude/settings.json` without touching anything else.
/// Our entries are recognised by shape, not remembered: an http hook to `http://127.0.0.1:<port>/hook`
/// carrying `X-Clawd-Token`, or a command containing `clawd-bridge`. That makes install idempotent across
/// port changes and app moves, and lets uninstall remove exactly what install added.
public enum HookSettings {
    /// Hook events delivered over HTTP. `SessionStart` is absent because it accepts only command hooks (ADR-0002).
    public static let httpEvents = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch", "PostToolUseFailure",
        "PermissionRequest", "PermissionDenied", "Notification", "MessageDisplay", "SubagentStart",
        "SubagentStop", "Stop", "StopFailure", "PreCompact", "SessionEnd",
    ]

    /// The one event the server may hold open for a notch decision, so its hook timeout outlasts the 110 s cap.
    static let permissionEvent = "PermissionRequest"
    static let permissionTimeout = 120

    /// Result of `install`: the new settings, plus the user's own statusLine command if install replaced one.
    public struct Installed {
        public let settings: [String: Any]
        /// Save this as `AppConfig.originalStatusLine`; nil when there was none or it was already ours.
        public let foreignStatusLine: String?
    }

    /// Thrown when the settings file is not a JSON object; the installer must then write nothing.
    public struct InvalidSettings: LocalizedError {
        public var errorDescription: String? { "~/.claude/settings.json is not valid JSON; nothing was changed." }
    }

    /// Parses settings file contents; a missing file (`nil`) is an empty object.
    /// Throws `InvalidSettings` for anything that is not a JSON object, including JSON with comments.
    public static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidSettings()
        }
        return object
    }

    /// Returns `settings` with any old ClawdNotch entries replaced by current ones.
    /// - Parameter bridgePath: Absolute path of `clawd-bridge`; it is single-quoted into the commands.
    public static func install(into settings: [String: Any], port: Int, token: String, bridgePath: String) -> Installed {
        var result = removingHooks(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in httpEvents {
            let http: [String: Any] = [
                "type": "http", "url": "http://127.0.0.1:\(port)/hook",
                "headers": ["X-Clawd-Token": token], "timeout": event == permissionEvent ? permissionTimeout : 2,
            ]
            hooks[event] = groups(hooks[event]) + [["hooks": [http]]]
        }
        let sessionStart: [String: Any] = [
            "type": "command", "command": "\(shellQuoted(bridgePath)) hook session-start", "async": true,
        ]
        hooks["SessionStart"] = groups(hooks["SessionStart"]) + [["hooks": [sessionStart]]]
        result["hooks"] = hooks

        // Keep the user's other statusLine keys (e.g. padding) so uninstall only has to swap the command back.
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        let previous = statusLine["command"] as? String
        statusLine["type"] = "command"
        statusLine["command"] = "\(shellQuoted(bridgePath)) statusline"
        result["statusLine"] = statusLine
        let foreign = previous.flatMap { isBridgeCommand($0) ? nil : $0 }
        return Installed(settings: result, foreignStatusLine: foreign)
    }

    /// Returns `settings` without ClawdNotch entries; our statusLine is swapped back to `originalStatusLine`,
    /// or removed when there was none. A statusLine the user changed after install is left alone.
    public static func uninstall(from settings: [String: Any], originalStatusLine: String?) -> [String: Any] {
        var result = removingHooks(from: settings)
        if var statusLine = settings["statusLine"] as? [String: Any],
           let command = statusLine["command"] as? String, isBridgeCommand(command) {
            if let originalStatusLine {
                statusLine["command"] = originalStatusLine
                result["statusLine"] = statusLine
            } else {
                result["statusLine"] = nil
            }
        }
        return result
    }

    /// Whether any ClawdNotch hook or our statusLine is present.
    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hasHook = hooks.values.contains { groups($0).contains { entries(of: $0).contains(where: isOurs) } }
        let statusCommand = (settings["statusLine"] as? [String: Any])?["command"] as? String
        return hasHook || statusCommand.map(isBridgeCommand) == true
    }

    /// Wraps a path in single quotes for `/bin/sh`, escaping embedded quotes.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Removes our hook entries; matcher groups and events emptied by that removal are dropped too,
    /// while ones the user left empty and we never touched are kept.
    private static func removingHooks(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any], !hooks.isEmpty else { return settings }
        for (event, value) in hooks {
            guard let list = value as? [Any] else { continue }
            let cleaned: [Any] = list.compactMap { group in
                guard var dict = group as? [String: Any], let handlers = dict["hooks"] as? [Any] else { return group }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count { return group }
                if kept.isEmpty { return nil }
                dict["hooks"] = kept
                return dict
            }
            hooks[event] = cleaned.isEmpty && !list.isEmpty ? nil : cleaned
        }
        var result = settings
        // shortcut: a user's own empty `"hooks": {}` or `"SessionStart": []` is dropped by a round-trip because
        // nothing records it; harmless to Claude Code and the backup keeps it. Upgrade only if a user cares.
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    private static func groups(_ value: Any?) -> [Any] { value as? [Any] ?? [] }

    private static func entries(of group: Any) -> [Any] { (group as? [String: Any])?["hooks"] as? [Any] ?? [] }

    private static func isOurs(_ handler: Any) -> Bool {
        guard let handler = handler as? [String: Any] else { return false }
        if let command = handler["command"] as? String { return isBridgeCommand(command) }
        guard let url = handler["url"] as? String, (handler["headers"] as? [String: Any])?["X-Clawd-Token"] != nil,
              url.hasPrefix("http://127.0.0.1:"), url.hasSuffix("/hook")
        else { return false }
        return Int(url.dropFirst("http://127.0.0.1:".count).dropLast("/hook".count)) != nil
    }

    private static func isBridgeCommand(_ command: String) -> Bool { command.contains("clawd-bridge") }
}
