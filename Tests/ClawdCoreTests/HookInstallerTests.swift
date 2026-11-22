// HookInstallerTests.swift
// File safety of the hook installer: backups, invalid input, symlinks, statusLine save/restore (docs/05, REQ-09 AC1).

import Foundation
import Testing
@testable import ClawdCore

@Suite("HookInstaller")
struct HookInstallerTests {
    /// A fresh temp directory per test; nothing here ever points at the real home directory.
    let dir: URL
    let installer: HookInstaller

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "HookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        installer = HookInstaller(
            settingsURL: dir.appending(path: "settings.json"),
            configURL: dir.appending(path: "config.json"),
            bridgePath: "/Apps/ClawdNotch.app/Contents/MacOS/clawd-bridge")
    }

    var files: [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()) ?? [] }
    var backups: [String] { files.filter { $0.hasPrefix("settings.json.clawdnotch-backup-") } }

    func put(_ text: String, at url: URL) throws { try Data(text.utf8).write(to: url) }

    func json(_ url: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test("Install backs up the original next to the settings file before writing")
    func backupBeforeWrite() throws {
        let original = #"{"model":"opus"}"#
        try put(original, at: installer.settingsURL)
        try installer.install()
        let backup = try #require(backups.first)
        #expect(backups.count == 1)
        #expect(try String(contentsOf: dir.appending(path: backup), encoding: .utf8) == original)
        #expect(installer.isInstalled)
    }

    @Test("Invalid settings JSON is left byte-identical with no backup and no config")
    func invalidSettings() throws {
        let original = "{ // comment\n \"model\": \"opus\" }"
        try put(original, at: installer.settingsURL)
        #expect(throws: HookSettings.InvalidSettings.self) { try installer.install() }
        #expect(throws: HookSettings.InvalidSettings.self) { try installer.uninstall() }
        #expect(try Data(contentsOf: installer.settingsURL) == Data(original.utf8))
        #expect(files == ["settings.json"])
    }

    @Test("A missing settings file is created without a backup")
    func missingSettings() throws {
        try installer.install()
        #expect(backups.isEmpty)
        #expect(installer.isInstalled)
        #expect(AppConfig.load(from: installer.configURL) != nil)
    }

    @Test("A symlinked settings file stays a symlink and its target is written")
    func symlink() throws {
        let real = dir.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try put("{}", at: real)
        try FileManager.default.createSymbolicLink(at: installer.settingsURL, withDestinationURL: real)
        try installer.install()
        let attributes = try FileManager.default.attributesOfItem(atPath: installer.settingsURL.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(HookSettings.isInstalled(try json(real)))
        #expect(backups.count == 1)
    }

    @Test("A foreign statusLine is saved on install, then restored and cleared on uninstall")
    func statusLineRoundTrip() throws {
        try put(#"{"statusLine":{"type":"command","command":"~/bin/status.sh"}}"#, at: installer.settingsURL)
        try installer.install()
        #expect(AppConfig.load(from: installer.configURL)?.originalStatusLine == "~/bin/status.sh")
        try installer.uninstall()
        let restored = try json(installer.settingsURL)
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "~/bin/status.sh")
        #expect(!installer.isInstalled)
        let config = try #require(AppConfig.load(from: installer.configURL))
        #expect(config.originalStatusLine == nil)
        #expect(backups.count == 2)
    }

    @Test("A corrupt config makes install and uninstall throw without writing anything")
    func corruptConfig() throws {
        try installer.install()
        let settings = try Data(contentsOf: installer.settingsURL)
        try put("not json", at: installer.configURL)
        let before = files
        #expect(throws: HookInstaller.CorruptConfig.self) { try installer.install() }
        #expect(throws: HookInstaller.CorruptConfig.self) { try installer.uninstall() }
        #expect(files == before)
        #expect(try Data(contentsOf: installer.settingsURL) == settings)
        #expect(try String(contentsOf: installer.configURL, encoding: .utf8) == "not json")
    }

    @Test("Reinstalling from a moved app replaces the old bridge path and keeps the saved statusLine")
    func bridgePathChange() throws {
        try put(#"{"statusLine":{"type":"command","command":"my-line"}}"#, at: installer.settingsURL)
        try installer.install()
        var moved = installer
        moved.bridgePath = "/Users/me/Applications/ClawdNotch.app/Contents/MacOS/clawd-bridge"
        try moved.install()
        let text = try String(contentsOf: installer.settingsURL, encoding: .utf8)
        #expect(!text.contains("/Apps/ClawdNotch.app"))
        #expect(text.contains("/Users/me/Applications/ClawdNotch.app"))
        try moved.uninstall()
        let restored = try #require(try json(installer.settingsURL)["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "my-line")
    }
}
