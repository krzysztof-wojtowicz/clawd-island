// SessionPanelView.swift
// The expanded panel: one row per session, the usage line and "Mark all read" (REQ-04 AC1, REQ-10 b).

import AppKit
import ClawdCore

/// Lists the sessions of one `Snapshot`. Rows are rebuilt only while the panel is visible; the latest snapshot is
/// kept and drawn when the panel is shown, which is also when the reset countdown is computed.
final class SessionPanelView: NSView {
    // shortcut: the panel has a fixed height, so extra sessions collapse into "+n more"; scroll if users run more.
    private static let maxRows = 5

    /// Called with a session id when its row is clicked.
    var onSelect: ((String) -> Void)?
    /// Called when "Mark all read" is clicked.
    var onMarkAllRead: (() -> Void)?

    private let rows = NSStackView()
    private let usageLabel = HUDStyle.label(size: 11, color: .secondaryLabelColor)
    private let markAllRead = ClickableStack()
    private var snapshot: Snapshot?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 3
        rows.autoresizingMask = [.width, .minYMargin]
        let markLabel = HUDStyle.label(size: 11, weight: .medium)
        markLabel.stringValue = "Mark all read"
        markLabel.setAccessibilityElement(false)
        markAllRead.addArrangedSubview(markLabel)
        markAllRead.onClick = { [weak self] in self?.onMarkAllRead?() }
        markAllRead.setAccessibilityLabel("Mark all read")
        markAllRead.setAccessibilityRole(.button)
        markAllRead.autoresizingMask = [.minXMargin, .maxYMargin]
        usageLabel.autoresizingMask = [.width, .maxYMargin]
        for view in [rows, usageLabel, markAllRead] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Stores `snapshot` and redraws it if the panel is on screen.
    func render(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        guard !isHiddenOrHasHiddenAncestor else { return }
        rebuild(now: .now)
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        rebuild(now: .now)
    }

    override func layout() {
        super.layout()
        let footerHeight: CGFloat = 16
        markAllRead.frame.size = markAllRead.fittingSize
        markAllRead.frame.origin = CGPoint(x: bounds.maxX - markAllRead.frame.width, y: 0)
        usageLabel.frame = CGRect(x: 0, y: 0, width: markAllRead.frame.minX - 8, height: footerHeight)
        let height = min(rows.fittingSize.height, bounds.height - footerHeight - 6)
        rows.frame = CGRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    private func rebuild(now: Date) {
        guard let snapshot else { return }
        usageLabel.attributedStringValue = HUDStyle.usageLine(snapshot.usage, now: now)
        markAllRead.isHidden = snapshot.attentionCount == 0
        for view in rows.arrangedSubviews {
            view.removeFromSuperview()
        }
        for session in snapshot.sessions.prefix(Self.maxRows) {
            rows.addArrangedSubview(row(for: session))
        }
        let hidden = snapshot.sessions.count - Self.maxRows
        if snapshot.sessions.isEmpty || hidden > 0 {
            let note = HUDStyle.label(size: 11, color: .secondaryLabelColor)
            note.stringValue = hidden > 0 ? "+\(hidden) more" : "No Claude Code sessions"
            rows.addArrangedSubview(note)
        }
        needsLayout = true
    }

    private func row(for session: Session) -> NSView {
        let marker = HUDStyle.label(size: 9)
        marker.stringValue = session.needsAttention ? "●" : ""
        marker.textColor = HUDStyle.color(session.state == .needsInput ? PetTokens.badgeAlert : PetTokens.body)
        marker.widthAnchor.constraint(equalToConstant: 10).isActive = true
        let name = HUDStyle.label(size: 12, weight: .medium)
        name.stringValue = session.projectName
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let state = HUDStyle.label(size: 12, color: .secondaryLabelColor)
        state.stringValue = HUDStyle.stateText(session)
        // The row speaks for its labels as one button.
        for label in [marker, name, state] {
            label.setAccessibilityElement(false)
        }
        let row = ClickableStack(views: [marker, name, state])
        row.onClick = { [weak self] in self?.onSelect?(session.id) }
        let unread = session.needsAttention ? ", needs attention" : ""
        row.setAccessibilityLabel("\(session.projectName), \(state.stringValue)\(unread)")
        row.setAccessibilityRole(.button)
        return row
    }
}

/// A horizontal stack that takes every click inside it, including the first click on the never-key panel.
private final class ClickableStack: NSStackView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Swallow the press so mouseUp comes here; acting on release matches buttons.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
