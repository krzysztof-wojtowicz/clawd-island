// main.swift
// Entry point: starts ClawdNotch as an accessory app (no Dock icon, no Cmd-Tab entry).

import AppKit

BundledFonts.register()
let app = NSApplication.shared
// NSApplication.delegate is weak; this top-level constant keeps the delegate alive.
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
