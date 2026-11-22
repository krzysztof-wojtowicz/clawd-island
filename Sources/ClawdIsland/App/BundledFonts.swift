// BundledFonts.swift
// Registers the JetBrains Mono files shipped in the app bundle (REQ-14 AC2).

import AppKit
import CoreText
import Foundation

/// Makes the bundled JetBrains Mono faces available to `NSFont(name:size:)` for this process only.
enum BundledFonts {
    /// Registers every `.ttf` in `Contents/Resources/Fonts/`, unless JetBrains Mono is already installed: the system
    /// font server then shares it for free, while a process-registered face is parsed in this process (about 3 MB of
    /// RSS per face used). A missing folder (a bare `swift run`) or a failed registration is ignored:
    /// `HUDStyle.font` falls back to the system monospaced font.
    static func register() {
        guard NSFont(name: "JetBrainsMono-Regular", size: 12) == nil else { return }
        let fonts = Bundle.main.resourceURL?.appending(path: "Fonts", directoryHint: .isDirectory)
        let files = fonts.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
