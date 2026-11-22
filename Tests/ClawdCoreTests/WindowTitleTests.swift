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

    @Test("JetBrains: the first segment is the project, with en dash, bracketed path and dashed names")
    func jetbrains() {
        let j = WindowTitle.Family.jetbrains
        #expect(WindowTitle.matches("claude-pet – AppDelegate.swift", project: "claude-pet", family: j))
        #expect(WindowTitle.matches("claude-pet – [~/Documents/claude-pet] – main.rs", project: "claude-pet", family: j))
        #expect(WindowTitle.matches("app - file.kt", project: "app", family: j))
        // A file named like the project in another project's window is not an exact match.
        #expect(WindowTitle.bestMatch(project: "app", in: ["web – app", "app – x.kt"], family: j) == 1)
        #expect(WindowTitle.bestMatch(project: "claude", in: ["other – a", "claude-pet – b"], family: j) == 1)
        #expect(!WindowTitle.matches("anything", project: "", family: j))
    }

    @Test("Family is chosen by bundle ID prefix")
    func family() {
        #expect(WindowTitle.Family(bundleID: "com.jetbrains.CLion") == .jetbrains)
        #expect(WindowTitle.Family(bundleID: "com.microsoft.VSCode") == .vscode)
    }
}
