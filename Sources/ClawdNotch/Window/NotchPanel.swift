// NotchPanel.swift
// Borderless, non-activating panel that floats over every app, Space and full-screen window (REQ-02).

import AppKit

/// The window hosting the notch island. It never takes focus.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Above the menu bar so the island can cover the notch strip; see docs/06 (Spike A).
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The app is never active, so the HP tooltip would otherwise never show.
        allowsToolTipsWhenApplicationIsInactive = true
        // The island is always black, so semantic text colours must resolve to their light variants.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would push the window below the menu bar; the island must sit flush with the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
