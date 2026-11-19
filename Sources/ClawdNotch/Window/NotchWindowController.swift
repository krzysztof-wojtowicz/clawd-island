// NotchWindowController.swift
// Places the black notch island on the right screen and keeps it there when displays change (REQ-01).

import AppKit
import ClawdCore

/// Creates the notch panel and positions it over the physical or virtual notch.
@MainActor
final class NotchWindowController {
    /// Width each black "wing" adds on either side of the notch; the pet and the counters live there in WP-2/WP-5.
    private static let wingWidth: CGFloat = 44
    private static let cornerRadius: CGFloat = 10

    private let panel: NotchPanel

    init() {
        panel = NotchPanel(contentRect: .zero)
        panel.contentView = Self.makeIslandView()
        layout()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    /// The main display, i.e. the one with the menu bar (not `NSScreen.main`, which follows the key window).
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    private func layout() {
        guard let screen = Self.targetScreen() else { return }
        let notch = NotchGeometry.compute(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea?.width,
            auxRight: screen.auxiliaryTopRightArea?.width
        )
        panel.setFrame(notch.frame.insetBy(dx: -Self.wingWidth, dy: 0), display: true)
    }

    private static func makeIslandView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        guard let layer = view.layer else { return view }
        layer.backgroundColor = NSColor.black.cgColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        // Layer coordinates are bottom-up here, so "MinY" corners are the bottom ones.
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return view
    }
}
