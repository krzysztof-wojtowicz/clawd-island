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

    @Test("onboarded defaults to off for old files and round-trips when on")
    func onboarded() throws {
        let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"port":1,"token":"t"}"#.utf8))
        #expect(!old.onboarded)
        let url = FileManager.default.temporaryDirectory.appending(path: "clawd-\(UUID().uuidString)/config.json")
        try AppConfig(token: "t", onboarded: true).write(to: url)
        #expect(AppConfig.load(from: url)?.onboarded == true)
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

    @Test("The ClawdNotch support folder moves to ClawdIsland once, keeping the config")
    func legacyMigration() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clawd-home-\(UUID().uuidString)")
        let old = home.appending(path: "Library/Application Support/ClawdNotch/config.json")
        let config = AppConfig(port: 50001, token: "t", originalStatusLine: "echo hi")
        try config.write(to: old)
        #expect(AppConfig.migrateLegacySupportFolder(home: home))
        let new = home.appending(path: "Library/Application Support/ClawdIsland/config.json")
        #expect(AppConfig.load(from: new) == config)
        #expect(!FileManager.default.fileExists(atPath: old.deletingLastPathComponent().path))
        #expect(!AppConfig.migrateLegacySupportFolder(home: home))
    }

    @Test("An existing ClawdIsland folder is never replaced by the old one")
    func legacyMigrationKeepsNew() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "clawd-home-\(UUID().uuidString)")
        let support = home.appending(path: "Library/Application Support")
        try AppConfig(token: "old").write(to: support.appending(path: "ClawdNotch/config.json"))
        try AppConfig(token: "new").write(to: support.appending(path: "ClawdIsland/config.json"))
        #expect(!AppConfig.migrateLegacySupportFolder(home: home))
        #expect(AppConfig.load(from: support.appending(path: "ClawdIsland/config.json"))?.token == "new")
    }
}
