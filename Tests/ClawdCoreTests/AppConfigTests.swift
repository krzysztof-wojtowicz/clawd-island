// AppConfigTests.swift
// Round-trip of the config file the app, installer and bridge share.

import Foundation
import Testing
@testable import ClawdCore

@Suite("AppConfig")
struct AppConfigTests {
    @Test("Config survives a write and load round-trip")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        let config = AppConfig(port: 50000, token: "t", originalStatusLine: "echo hi")
        try config.write(to: url)
        #expect(AppConfig.load(from: url) == config)
    }

    @Test("notchPermissions defaults to on for old files and round-trips when off")
    func notchPermissions() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"port":1,"token":"t"}"#.utf8))
        #expect(old.notchPermissions)
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        try AppConfig(token: "t", notchPermissions: false).write(to: url)
        #expect(AppConfig.load(from: url)?.notchPermissions == false)
    }

    @Test("soundCues defaults to on for old files and round-trips when off")
    func soundCues() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"port":1,"token":"t"}"#.utf8))
        #expect(old.soundCues)
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        try AppConfig(token: "t", soundCues: false).write(to: url)
        #expect(AppConfig.load(from: url)?.soundCues == false)
    }

    @Test("Missing file loads as nil")
    func missing() {
        #expect(AppConfig.load(from: URL(filePath: "/nonexistent/clawd/config.json")) == nil)
    }

    @Test("A config written before mini mode existed decodes with defaults")
    func legacyDefaults() throws {
        let json = #"{"port": 1234, "token": "t", "originalStatusLine": "echo"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config == AppConfig(port: 1234, token: "t", originalStatusLine: "echo", miniMode: false, focusReadMode: .tab))
    }

    @Test("The legacy hideMode key is read when miniMode is absent, and miniMode wins when both exist")
    func legacyHideModeKey() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"port": 1, "token": "t", "hideMode": true}"#.utf8))
        #expect(old.miniMode)
        let both = try JSONDecoder().decode(
            AppConfig.self, from: Data(#"{"port": 1, "token": "t", "hideMode": true, "miniMode": false}"#.utf8))
        #expect(!both.miniMode)
    }

    @Test("A config file that still holds the removed headphones key decodes")
    func legacyHeadphonesKey() throws {
        let json = #"{"port": 1, "token": "t", "headphones": true}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.token == "t")
    }

    @Test("Mini mode and focus-read mode survive a round-trip")
    func newKeysRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        let config = AppConfig(token: "t", miniMode: true, focusReadMode: .off)
        try config.write(to: url)
        #expect(AppConfig.load(from: url) == config)
    }
}
