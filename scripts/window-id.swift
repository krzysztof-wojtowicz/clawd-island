// window-id.swift
// Prints "<CGWindowID> <x>" for ClawdNotch's on-screen window, x being its left edge in points (exit 1 if none).
// Used by record-gif.sh so screencapture -l captures only the app, never other screen content.
import AppKit

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let target = windows.first { $0[kCGWindowOwnerName as String] as? String == "ClawdNotch" }
guard let number = target?[kCGWindowNumber as String] as? Int else { exit(1) }
let x = Int((target?[kCGWindowBounds as String] as? [String: CGFloat])?["X"] ?? 0)
print(number, x)
