// NotchWindowController.swift
// Places the notch island on the main display, keeps it there when displays change (REQ-01),
// and sizes the panel to the island so the rest of the screen stays click-through.

import AppKit
import ClawdCore

/// Owns the notch panel: screen choice, island geometry, hover expand/collapse and the right-click menu.
@MainActor
final class NotchWindowController {
    private static let expandedMinWidth: CGFloat = 360
    private static let expandedExtraHeight: CGFloat = 160
    private static let expandDelay: Duration = .milliseconds(150)
    private static let collapseDelay: Duration = .milliseconds(300)
    private static let resizeDuration: TimeInterval = 0.25

    /// The island content view; its `petSlot`, `countersSlot` and `panelSlot` are the integration points.
    let island = IslandView()

    private let panel: NotchPanel
    private var isExpanded = false
    private var hoverTask: Task<Void, Never>?

    init() {
        panel = NotchPanel(contentRect: .zero)
        panel.contentView = island
        island.menuProvider = Self.makeMenu
        island.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        layout(animated: false)
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // layout(animated: false) re-syncs hover, which also cancels any pending expand/collapse.
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
    }

    /// The main display, i.e. the one with the menu bar (not `NSScreen.main`, which follows the key window).
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    /// Expands after the mouse rests on the island and collapses after it leaves (delays from docs/06).
    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        guard inside != isExpanded else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: inside ? Self.expandDelay : Self.collapseDelay)
            guard !Task.isCancelled, let self else { return }
            isExpanded = inside
            layout(animated: true)
        }
    }

    /// Recomputes the notch on the target screen and fits the panel to the island.
    /// A non-animated layout (launch, screen change) also re-syncs hover, since a panel that moves under a still
    /// cursor gets no enter/exit event.
    private func layout(animated: Bool) {
        guard let screen = Self.targetScreen() else { return }
        let notch = NotchGeometry.compute(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea?.width,
            auxRight: screen.auxiliaryTopRightArea?.width
        ).frame
        let rowHeight = max(notch.height, IslandView.minRowHeight)
        let topRow = CGRect(x: notch.minX, y: notch.maxY - rowHeight, width: notch.width, height: rowHeight)
        island.topRowSize = topRow.size
        let frame = islandFrame(around: topRow)
        // Always go through the animator: a plain setFrame could be overwritten by an in-flight resize animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.resizeDuration : 0
            panel.animator().setFrame(frame, display: true)
        }
        if !animated {
            hoverChanged(frame.contains(NSEvent.mouseLocation))
        }
    }

    /// The island in screen coordinates: the top row plus one wing per side, grown downward when expanded.
    private func islandFrame(around topRow: CGRect) -> CGRect {
        let collapsed = topRow.insetBy(dx: -IslandView.wingWidth, dy: 0)
        guard isExpanded else { return collapsed }
        let width = max(collapsed.width, Self.expandedMinWidth)
        let height = topRow.height + Self.expandedExtraHeight
        return CGRect(x: topRow.midX - width / 2, y: topRow.maxY - height, width: width, height: height)
    }

    /// The right-click menu from docs/06. Items without an action are disabled stubs until their WP lands.
    private static func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // TODO(WP-7): hide mode toggle, launch at login and Settings.
        // TODO(WP-5): mark all read. TODO(WP-4): install/uninstall hooks.
        for title in ["Hide Mode", "Mark All Read", "Install Hooks", "Launch at Login", "Settings…"] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClawdNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}
