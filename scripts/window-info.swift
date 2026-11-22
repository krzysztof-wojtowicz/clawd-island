// window-info.swift
// Prints ClawdIsland's on-screen windows (level and bounds) plus screen geometry.
// Works without the Screen Recording permission, unlike screencapture. Run: swift scripts/window-info.swift
import AppKit

for screen in NSScreen.screens {
    print("screen \(screen.localizedName) frame=\(screen.frame) safeTop=\(screen.safeAreaInsets.top)")
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where window[kCGWindowOwnerName as String] as? String == "ClawdIsland" {
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    // Bounds are top-left based global coordinates, unlike AppKit's bottom-left screen frames.
    print("window layer=\(window[kCGWindowLayer as String] ?? "?") x=\(bounds["X"] ?? 0) y=\(bounds["Y"] ?? 0) w=\(bounds["Width"] ?? 0) h=\(bounds["Height"] ?? 0)")
}
