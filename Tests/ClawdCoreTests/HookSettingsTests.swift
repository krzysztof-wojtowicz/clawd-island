// HookSettingsTests.swift
// Install/uninstall merge of ClawdNotch entries into Claude Code settings (docs/05, REQ-09 AC1).

import Foundation
import Testing
@testable import ClawdCore

@Suite("HookSettings")
struct HookSettingsTests {
    let bridge = "/Applications/Clawd Notch.app/Contents/MacOS/clawd-bridge"

    /// Parses JSON text the way the installer does, so comparisons see what would be on disk.
    func settings(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

    func install(_ s: [String: Any], port: Int = 47474) -> HookSettings.Installed {
        HookSettings.install(into: s, port: port, token: "tok", bridgePath: bridge)
    }

    let rich = """
    {
      "model": "opus", "permissions": {"allow": ["Bash(ls)"]},
      "hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "lint.sh"}]}],
        "Stop": [{"hooks": [{"type": "http", "url": "http://127.0.0.1:9000/hook"}]}],
        "SessionStart": [{"hooks": [{"type": "command", "command": "echo hi"}]}]
      },
      "statusLine": {"type": "command", "command": "~/bin/status.sh", "padding": 1}
    }
    """

    @Test("Install then uninstall restores the original settings", arguments: ["{}", #"{"model":"opus"}"#])
    func roundTripPlain(json: String) throws {
        let original = try settings(json)
        let installed = install(original)
        #expect(HookSettings.isInstalled(installed.settings))
        let restored = HookSettings.uninstall(from: installed.settings, originalStatusLine: installed.foreignStatusLine)
        #expect(same(restored, original))
        #expect(!HookSettings.isInstalled(restored))
    }

    @Test("Round-trip keeps foreign hooks, unknown keys and the user's statusLine")
    func roundTripRich() throws {
        let original = try settings(rich)
        let installed = install(original)
        #expect(installed.foreignStatusLine == "~/bin/status.sh")
        let statusLine = try #require(installed.settings["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == "'\(bridge)' statusline")
        #expect(statusLine["padding"] as? Int == 1)
        let restored = HookSettings.uninstall(from: installed.settings, originalStatusLine: installed.foreignStatusLine)
        #expect(same(restored, original))
    }

    @Test("Installing twice gives the same settings and never reports our own statusLine as foreign")
    func idempotent() throws {
        let first = install(try settings(rich))
        let second = install(first.settings)
        #expect(same(first.settings, second.settings))
        #expect(second.foreignStatusLine == nil)
    }

    @Test("Reinstalling on a new port replaces the old entries instead of adding more")
    func portChange() throws {
        let moved = install(install(try settings("{}")).settings, port: 50000).settings
        let hooks = try #require(moved["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 1)
        let handler = try #require((stop[0]["hooks"] as? [[String: Any]])?.first)
        #expect(handler["url"] as? String == "http://127.0.0.1:50000/hook")
    }

    @Test("Install writes an http hook per event and an async SessionStart command")
    func shape() throws {
        let hooks = try #require(install(try settings("{}")).settings["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookSettings.httpEvents + ["SessionStart"]))
        let start = try #require((hooks["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        #expect(start.first?["command"] as? String == "'\(bridge)' hook session-start")
        #expect(start.first?["async"] as? Bool == true)
    }

    @Test("A localhost hook without our token header is not ours")
    func foreignLocalhostHook() throws {
        let s = try settings(#"{"hooks":{"Stop":[{"hooks":[{"type":"http","url":"http://127.0.0.1:9000/hook"}]}]}}"#)
        #expect(!HookSettings.isInstalled(s))
        #expect(same(HookSettings.uninstall(from: s, originalStatusLine: nil), s))
    }

    @Test("Uninstall leaves a statusLine the user changed after install")
    func userChangedStatusLine() throws {
        let s = try settings(#"{"statusLine":{"type":"command","command":"mine.sh"}}"#)
        #expect(same(HookSettings.uninstall(from: s, originalStatusLine: "old.sh"), s))
    }

    @Test("Invalid or non-object settings are rejected", arguments: ["{", "// c\n{}", "[]", ""])
    func invalid(json: String) {
        #expect(throws: HookSettings.InvalidSettings.self) { try HookSettings.parse(Data(json.utf8)) }
    }

    @Test("A missing settings file parses as empty")
    func missing() throws {
        #expect(try HookSettings.parse(nil).isEmpty)
    }

    @Test("Shell quoting escapes single quotes")
    func quoting() {
        #expect(HookSettings.shellQuoted("/a b/it's") == #"'/a b/it'\''s'"#)
    }
}
