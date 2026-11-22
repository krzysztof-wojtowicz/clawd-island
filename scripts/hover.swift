// hover.swift
// Moves the cursor onto the ClawdNotch island or away from it (perf-suite expanded-hover scenario).
// CGWarpMouseCursorPosition needs no Accessibility permission.
// Run: swift scripts/hover.swift <on|off>
//   on:  warp to the top-centre of the app's window; the cursor stays there after exit.
//   off: warp to the centre of the main display.
import AppKit

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let target = windows.first { $0[kCGWindowOwnerName as String] as? String == "ClawdNotch" }
let bounds = target?[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
let screen = CGDisplayBounds(CGMainDisplayID())

let point: CGPoint
switch CommandLine.arguments.dropFirst().first {
case "on":
    guard let x = bounds["X"], let w = bounds["Width"], let y = bounds["Y"] else {
        FileHandle.standardError.write(Data("no ClawdNotch window on screen\n".utf8))
        exit(1)
    }
    point = CGPoint(x: x + w / 2, y: y + 6) // global top-left coordinates, like window-info.swift
case "off":
    point = CGPoint(x: screen.midX, y: screen.midY)
default:
    FileHandle.standardError.write(Data("usage: hover.swift <on|off>\n".utf8))
    exit(1)
}
CGWarpMouseCursorPosition(point)
// Warping alone does not generate move events; post one so tracking areas notice.
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
