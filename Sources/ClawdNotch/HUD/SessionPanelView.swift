// SessionPanelView.swift
// The expanded panel: one row per session, the usage line and "Mark all read" (REQ-04 AC1, REQ-10 b).

import AppKit
import ClawdCore

/// Lists the sessions of one `Snapshot`. Rows are rebuilt only while the panel is visible; the latest snapshot is
/// kept and drawn when the panel is shown, which is also when the reset countdown is computed.
final class SessionPanelView: NSView {
    // shortcut: the panel has a fixed height, so extra sessions collapse into "+n more"; scroll if users run more.
    /// Session rows by number of permission cards shown; each card takes about two and a half rows.
    private static let maxRows = [5, 3, 1]
    private static let maxCards = 2
    private static let cardHeight: CGFloat = 40
    private static let cardSpacing: CGFloat = 3

    /// Called with a session id when its row is clicked.
    var onSelect: ((String) -> Void)?
    /// Called with a permission id and `true` for Allow, `false` for Deny.
    var onDecide: ((UUID, Bool) -> Void)?
    /// Called when "Mark all read" is clicked.
    var onMarkAllRead: (() -> Void)?

    private let rows = NSStackView()
    private let usageLabel = HUDStyle.label(size: 11, color: .secondaryLabelColor)
    private let markAllRead = ClickableStack()
    private var snapshot: Snapshot?
    /// The cards on screen, newest first; rebuilt only when the pending permissions change.
    private var cards: [(permission: PendingPermission, view: NSView)] = []
    /// When the footer was last built; its text is reflowed in `layout` without recomputing the countdown.
    private var footerDate = Date.now

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
        // Shorten "resets in" to "resets" when the full line does not fit beside the button.
        if let usage = snapshot?.usage {
            let full = HUDStyle.usageLine(usage, now: footerDate)
            usageLabel.attributedStringValue = full.size().width > usageLabel.frame.width
                ? HUDStyle.usageLine(usage, now: footerDate, compact: true)
                : full
        }
        var top = bounds.maxY
        for (_, card) in cards {
            card.frame = CGRect(x: 0, y: top - Self.cardHeight, width: bounds.width, height: Self.cardHeight)
            top -= Self.cardHeight + Self.cardSpacing
        }
        let height = min(rows.fittingSize.height, top - footerHeight - 6)
        rows.frame = CGRect(x: 0, y: top - height, width: bounds.width, height: height)
    }

    private func rebuild(now: Date) {
        guard let snapshot else { return }
        footerDate = now
        usageLabel.attributedStringValue = HUDStyle.usageLine(snapshot.usage, now: now)
        markAllRead.isHidden = snapshot.attentionCount == 0
        let pending = Array(snapshot.pendingPermissions.prefix(Self.maxCards))
        if pending != cards.map(\.permission) {
            for (_, view) in cards { view.removeFromSuperview() }
            cards = pending.map { ($0, card(for: $0)) }
            for (_, view) in cards { addSubview(view) }
        }
        let maxRows = Self.maxRows[cards.count]
        for view in rows.arrangedSubviews {
            view.removeFromSuperview()
        }
        for session in snapshot.sessions.prefix(maxRows) {
            rows.addArrangedSubview(row(for: session))
        }
        let hidden = snapshot.sessions.count - maxRows
        if snapshot.sessions.isEmpty || hidden > 0 {
            let note = HUDStyle.label(size: 11, color: .secondaryLabelColor)
            note.stringValue = hidden > 0 ? "+\(hidden) more" : "No Claude Code sessions"
            rows.addArrangedSubview(note)
        }
        needsLayout = true
    }

    private func card(for permission: PendingPermission) -> NSView {
        PermissionCardView(permission: permission) { [weak self] allow in self?.onDecide?(permission.id, allow) }
    }

    private func row(for session: Session) -> NSView {
        let marker = HUDStyle.label(size: 9)
        let dot: CGColor? = switch session.state {
        case .needsInput: PetTokens.badgeAlert
        case .done where session.needsAttention: PetTokens.body
        case .thinking, .usingTools, .talking: PetTokens.badgeActive
        default: nil
        }
        marker.stringValue = dot == nil ? "" : "●"
        marker.textColor = HUDStyle.color(dot ?? PetTokens.body)
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

/// One permission card: `project · tool` over the summary, with Allow and Deny on the right (REQ-V2-01 AC1).
/// Built with plain frames; a card is a fixed 40 pt, so constraints would only add cost.
private final class PermissionCardView: NSView {
    private static let pillSize = CGSize(width: 48, height: 22)
    private static let inset: CGFloat = 8

    private let title = HUDStyle.label(size: 12, weight: .medium)
    private let summary = HUDStyle.label(size: 11, color: .secondaryLabelColor)
    private let allow: ClickableStack
    private let deny: ClickableStack

    init(permission: PendingPermission, onDecide: @escaping (Bool) -> Void) {
        let subject = permission.toolName.map { "\(permission.projectName) · \($0)" } ?? permission.projectName
        allow = Self.pill("Allow", fill: PetTokens.badgeActive, accessibility: "Allow \(subject)") { onDecide(true) }
        deny = Self.pill("Deny", fill: PetTokens.badgeEmpty, accessibility: "Deny \(subject)") { onDecide(false) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = PetTokens.bubbleFill.copy(alpha: 0.1)
        title.stringValue = subject
        summary.stringValue = permission.summary
        summary.lineBreakMode = .byTruncatingMiddle
        for view in [title, summary, allow, deny] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func pill(_ text: String, fill: CGColor, accessibility: String, action: @escaping () -> Void) -> ClickableStack {
        let label = HUDStyle.label(size: 11, weight: .semibold, color: HUDStyle.color(PetTokens.badgeGlyph))
        label.stringValue = text
        label.alignment = .center
        label.setAccessibilityElement(false)
        let button = ClickableStack(views: [label])
        button.alignment = .centerY
        button.distribution = .fill
        button.wantsLayer = true
        button.layer?.cornerRadius = pillSize.height / 2
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = fill
        button.onClick = action
        button.setAccessibilityLabel(accessibility)
        button.setAccessibilityRole(.button)
        return button
    }

    override func layout() {
        super.layout()
        let pill = Self.pillSize
        let y = (bounds.height - pill.height) / 2
        deny.frame = CGRect(x: bounds.maxX - Self.inset - pill.width, y: y, width: pill.width, height: pill.height)
        allow.frame = CGRect(x: deny.frame.minX - 6 - pill.width, y: y, width: pill.width, height: pill.height)
        let textWidth = allow.frame.minX - 2 * Self.inset
        title.frame = CGRect(x: Self.inset, y: bounds.midY, width: textWidth, height: 16)
        summary.frame = CGRect(x: Self.inset, y: bounds.midY - 16, width: textWidth, height: 15)
    }
}
