// main.swift
// Entry point: starts ClawdNotch as an accessory app (no Dock icon, no Cmd-Tab entry).

import AppKit
import ClawdCore

// `--uninstall-hooks` is the reversible uninstaller used by scripts/uninstall.sh: no UI, exit code 0 or 1.
// CLAWD_SETTINGS_PATH and CLAWD_CONFIG_PATH redirect it for tests; scripts never set them.
if CommandLine.arguments.contains("--uninstall-hooks") {
    let environment = ProcessInfo.processInfo.environment
    let bridge = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "clawd-bridge").path ?? ""
    var installer = HookInstaller(bridgePath: bridge)
    if let path = environment["CLAWD_SETTINGS_PATH"] { installer.settingsURL = URL(fileURLWithPath: path) }
    if let path = environment["CLAWD_CONFIG_PATH"] { installer.configURL = URL(fileURLWithPath: path) }
    do {
        try installer.uninstall()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("uninstall-hooks failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

BundledFonts.register()
let app = NSApplication.shared
// NSApplication.delegate is weak; this top-level constant keeps the delegate alive.
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
