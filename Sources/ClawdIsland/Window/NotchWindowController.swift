// NotchWindowController.swift
// Places the notch island on the main display, keeps it there when displays change (REQ-01),
// and sizes the panel to the island so the rest of the screen stays click-through.

import AppKit
import ClawdCore

/// Owns the notch panel: screen choice, island geometry, hover expand/collapse and the right-click menu.
@MainActor
final class NotchWindowController {
    private static let expandedMinWidth: CGFloat = 360
    private static let expandDelay: Duration = .milliseconds(150)
    private static let collapseDelay: Duration = .milliseconds(300)
    private static let resizeDuration: TimeInterval = 0.25
    /// How long a hidden island stays out after a state change (REQ-05 AC1).
    private static let popDuration: Duration = .seconds(3)

    /// The island content view; its `petSlot`, `countersSlot` and `panelSlot` are the integration points.
    let island = IslandView()
    /// Called by the "Mark All Read" menu item.
    var onMarkAllRead: (() -> Void)?
    /// Whether anything is unread or waiting; the "Mark All Read" item is disabled otherwise.
    var hasAttention: () -> Bool = { false }

    private let panel: NotchPanel
    private var isExpanded = false
    private var hoverTask: Task<Void, Never>?
    private var retractTask: Task<Void, Never>?
    /// Whether mini mode has the island out (a state change, or a held unread `done` / pending `needsInput`).
    private var isPopped = false

    /// Mini mode (REQ-05): Clawd tucks under the notch unless popped out or hovered.
    var miniMode = false {
        didSet {
            guard miniMode != oldValue else { return }
            retractTask?.cancel()
            isPopped = false
            // AC2: an unread done or a pending needsInput stays out even when mini mode is switched on.
            if miniMode, holdsPopOut() { popOut(hold: true) } else { layout(animated: true) }
        }
    }
    /// Whether the aggregate state holds a pop-out (`done` or `needsInput`, REQ-05 AC2).
    var holdsPopOut: () -> Bool = { false }
    /// Why the event server is not listening, shown as a disabled top menu item.
    var serverError: () -> String? = { nil }
    /// Called by the "Mini Mode" menu item.
    var onToggleMiniMode: (() -> Void)?
    /// Called by the "Settings…" menu item.
    var onOpenSettings: (() -> Void)?

    private var isTucked: Bool { miniMode && !isExpanded && !isPopped }

    init() {
        panel = NotchPanel(contentRect: .zero)
        panel.contentView = island
        island.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        island.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        layout(animated: false)
        panel.orderFrontRegardless()
        SpaceAnchor.pin(panel)
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

    /// Pops a hidden island out for 3 s (REQ-05 AC1; a new call restarts it), or until the next call when `hold` is set (AC2: `done`, `needsInput`).
    func popOut(hold: Bool) {
        guard miniMode else { return }
        retractTask?.cancel()
        isPopped = true
        layout(animated: true)
        guard !hold else { return }
        retractTask = Task { [weak self] in
            try? await Task.sleep(for: Self.popDuration)
            guard !Task.isCancelled, let self else { return }
            isPopped = false
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
        island.topRow = topRow
        island.setPetPlacement(IslandView.petPlacement(topRow: topRow, hidden: isTucked), animated: animated)
        let frame = panelFrame(around: topRow)
        let duration = animated ? Self.resizeDuration : 0
        // Always go through the animator: a plain setFrame could be overwritten by an in-flight resize animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().setFrame(frame, display: true)
            island.setExpanded(isExpanded, duration: duration)
        }
        if !animated {
            hoverChanged(frame.contains(NSEvent.mouseLocation))
        }
    }

    /// The panel in screen coordinates. Collapsed, it is exactly the island: the top row plus both wings.
    /// Expanded, it is the island centred under the notch and grown downward, plus the glow margin on the sides
    /// and bottom.
    private func panelFrame(around topRow: CGRect) -> CGRect {
        guard !isTucked else {
            let extra = IslandView.hiddenExtra
            return CGRect(
                x: topRow.minX,
                y: topRow.minY - extra.height,
                width: topRow.width + extra.width,
                height: topRow.height + extra.height
            )
        }
        guard isExpanded else {
            return CGRect(
                x: topRow.minX - IslandView.leftWingWidth,
                y: topRow.minY,
                width: IslandView.leftWingWidth + topRow.width + IslandView.rightWingWidth,
                height: topRow.height
            )
        }
        // Wide enough to keep both wings, and the three expanded counters, inside the centred island.
        let width = max(topRow.width + 2 * IslandView.expandedWingWidth, Self.expandedMinWidth)
        let height = topRow.height + IslandView.expandedExtraHeight
        let margin = IslandView.glowMargin
        return CGRect(
            x: topRow.midX - width / 2 - margin,
            y: topRow.maxY - height - margin,
            width: width + 2 * margin,
            height: height + margin
        )
    }

    /// The right-click menu from docs/06.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        if let error = serverError() {
            menu.addItem(ActionMenuItem(title: error, isEnabled: false) {})
            menu.addItem(.separator())
        }
        let mini = ActionMenuItem(title: "Mini Mode", isEnabled: true) { [weak self] in self?.onToggleMiniMode?() }
        mini.state = miniMode ? .on : .off
        menu.addItem(mini)
        menu.addItem(ActionMenuItem(title: "Mark All Read", isEnabled: hasAttention()) { [weak self] in
            self?.onMarkAllRead?()
        })
        menu.addItem(ActionMenuItem(title: "Settings…", isEnabled: true) { [weak self] in self?.onOpenSettings?() })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClawdIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}

/// A menu item that runs a closure; it is its own target, so the menu keeps it alive.
private final class ActionMenuItem: NSMenuItem, NSMenuItemValidation {
    private let handler: () -> Void
    private let isAvailable: Bool

    init(title: String, isEnabled: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        isAvailable = isEnabled
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() {
        handler()
    }

    // The menu auto-enables items, so a plain isEnabled would be overwritten.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isAvailable
    }
}
