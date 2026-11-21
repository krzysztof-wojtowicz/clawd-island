// WindowTitleTests.swift
// Project-name matching against editor window titles (REQ-V2-02).

import Testing
@testable import ClawdCore

@Suite("WindowTitle")
struct WindowTitleTests {
    @Test("A project matches a whole title segment, not a prefix or a file name")
    func exactSegment() {
        #expect(WindowTitle.matches("main.swift — app — Visual Studio Code", project: "app"))
        #expect(WindowTitle.matches("app - Cursor", project: "app"))
        #expect(WindowTitle.bestMatch(project: "app", in: ["app-web — Visual Studio Code", "x — app — Visual Studio Code"]) == 1)
        #expect(WindowTitle.bestMatch(project: "app", in: ["app.swift — web — Visual Studio Code", "app — Visual Studio Code"]) == 1)
    }

    @Test("Contains is the fallback when no segment matches")
    func fallback() {
        #expect(WindowTitle.bestMatch(project: "app", in: ["other", "app-web — Visual Studio Code"]) == 1)
        #expect(WindowTitle.bestMatch(project: "zzz", in: ["other"]) == nil)
    }

    @Test("An empty project matches nothing")
    func empty() {
        #expect(!WindowTitle.matches("anything", project: ""))
    }
}
