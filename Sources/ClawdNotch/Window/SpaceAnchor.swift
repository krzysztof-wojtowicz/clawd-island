// SpaceAnchor.swift
// Pins the notch panel to its own SkyLight Space so Space switches do not slide it (REQ-02 AC4, ADR-0005).

import AppKit

/// Moves a window into a dedicated Space above every user Space, so swipes, Ctrl+arrow and full-screen
/// transitions leave it in place like the menu bar. No public API prevents the slide, so this uses
/// private SkyLight calls (private API, see ADR-0005). Any missing symbol makes `pin` a silent no-op,
/// and the panel's `collectionBehavior` still keeps it visible on every Space.
@MainActor
enum SpaceAnchor {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    /// Above every user Space; the window's own level still orders it within this Space.
    private static let absoluteLevel: Int32 = 100
    /// The anchor Space, created on first use and kept for the process lifetime (the OS reclaims it on exit).
    private static var space: UInt64?

    /// Adds `window` to the anchor Space. Call after the window is first ordered front, so it has a window number.
    static func pin(_ window: NSWindow) {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection = symbol("SLSMainConnectionID", in: skyLight, as: MainConnectionID.self),
              let create = symbol("SLSSpaceCreate", in: skyLight, as: SpaceCreate.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", in: skyLight, as: SpaceSetAbsoluteLevel.self),
              let show = symbol("SLSShowSpaces", in: skyLight, as: ShowSpaces.self),
              let addWindows = symbol("SLSAddWindowsToSpaces", in: skyLight, as: AddWindowsToSpaces.self)
        else { return }
        let connection = mainConnection()
        let anchor: UInt64
        if let space {
            anchor = space
        } else {
            anchor = create(connection, 1, nil)
            guard anchor != 0 else { return }
            _ = setLevel(connection, anchor, absoluteLevel)
            _ = show(connection, [NSNumber(value: anchor)] as CFArray)
            space = anchor
        }
        _ = addWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: anchor)] as CFArray)
    }

    /// Resolves a C function from the loaded framework, or `nil` if this macOS lacks it.
    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
}
