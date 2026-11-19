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

    @Test("Missing file loads as nil")
    func missing() {
        #expect(AppConfig.load(from: URL(filePath: "/nonexistent/clawd/config.json")) == nil)
    }
}
