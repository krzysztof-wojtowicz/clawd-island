// NewSessionTests.swift
// Quoting of the launcher command and the recent-projects list (REQ-18).

import Foundation
import Testing
@testable import ClawdCore

@Suite("NewSession")
struct NewSessionTests {
    @Test("Shell quoting neutralises spaces, quotes, dollars and backslashes")
    func shellQuote() {
        #expect(NewSessionCommand.shellQuote("/tmp/a b") == "'/tmp/a b'")
        #expect(NewSessionCommand.shellQuote("/tmp/it's") == #"'/tmp/it'\''s'"#)
        #expect(NewSessionCommand.shellQuote("/tmp/$HOME `x`") == "'/tmp/$HOME `x`'")
        #expect(NewSessionCommand.shellQuote(#"/tmp/a\b"#) == #"'/tmp/a\b'"#)
    }

    @Test("AppleScript text escapes backslash and double quote after shell quoting")
    func scriptText() {
        #expect(NewSessionCommand.scriptText(directory: "/tmp/p") == "cd '/tmp/p' && claude")
        #expect(NewSessionCommand.scriptText(directory: #"/tmp/a"b"#) == #"cd '/tmp/a\"b' && claude"#)
        #expect(NewSessionCommand.scriptText(directory: #"/tmp/a\b"#) == #"cd '/tmp/a\\b' && claude"#)
        #expect(NewSessionCommand.scriptText(directory: "/tmp/it's") == #"cd '/tmp/it'\\''s' && claude"#)
    }

    @Test("Control characters and relative paths are rejected")
    func rejected() {
        #expect(NewSessionCommand.scriptText(directory: "/tmp/a\nrm -rf ~") == nil)
        #expect(NewSessionCommand.scriptText(directory: "/tmp/a\u{15}b") == nil)
        #expect(NewSessionCommand.scriptText(directory: "/tmp/a\u{1b}b") == nil)
        #expect(NewSessionCommand.scriptText(directory: "/tmp/a\u{7f}b") == nil)
        #expect(NewSessionCommand.scriptText(directory: "relative/dir") == nil)
        #expect(NewSessionCommand.scriptText(directory: "") == nil)
    }

    @Test("Recent projects keep the newest first, without duplicates, capped at five")
    func recents() {
        var config = AppConfig(token: "t")
        for name in ["a", "b", "c", "d", "e", "f"] { config.noteRecentProject("/\(name)") }
        #expect(config.recentProjects == ["/f", "/e", "/d", "/c", "/b"])
        config.noteRecentProject("/d")
        #expect(config.recentProjects == ["/d", "/f", "/e", "/c", "/b"])
    }

    @Test("recentProjects defaults to empty for old files and round-trips")
    func recentsDecode() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"port":1,"token":"t"}"#.utf8))
        #expect(old.recentProjects.isEmpty)
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        try AppConfig(token: "t", recentProjects: ["/x"]).write(to: url)
        #expect(AppConfig.load(from: url)?.recentProjects == ["/x"])
    }
}
