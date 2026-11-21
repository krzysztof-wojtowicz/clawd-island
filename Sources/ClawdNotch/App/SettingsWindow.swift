// SettingsWindow.swift
// The Settings window: a normal window, created on demand and released when closed.

import AppKit
import ClawdCore

/// Plain AppKit on purpose: linking SwiftUI for three controls would blow the 40 MB RSS budget (docs/08).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var window: NSWindow?
    private var hideCheck: NSButton?
    private var loginCheck: NSButton?
    private var focusPopUp: NSPopUpButton?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    /// Shows the window, building it first if needed, and activates the app (it is an accessory app).
    func show() {
        if window == nil { window = makeWindow() }
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Syncs the controls with the current settings, e.g. after the menu toggled hide mode.
    func refresh() {
        hideCheck?.state = preferences.hideMode ? .on : .off
        loginCheck?.state = LoginItem.isEnabled ? .on : .off
        if let index = AppConfig.FocusReadMode.allCases.firstIndex(of: preferences.focusReadMode) {
            focusPopUp?.selectItem(at: index)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        hideCheck = nil
        loginCheck = nil
        focusPopUp = nil
    }

    private func makeWindow() -> NSWindow {
        let hide = NSButton(checkboxWithTitle: "Hide Clawd under the notch", target: self, action: #selector(hideChanged(_:)))
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(loginChanged(_:)))
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        // Titles follow `FocusReadMode.allCases` order; `focusChanged` and `refresh` index by it.
        popUp.addItems(withTitles: AppConfig.FocusReadMode.allCases.map { mode in
            switch mode {
            case .tab: "Selected tab"
            case .app: "Terminal app"
            case .off: "Off"
            }
        })
        popUp.target = self
        popUp.action = #selector(focusChanged(_:))
        let focusRow = NSStackView(views: [NSTextField(labelWithString: "Mark as read on terminal focus:"), popUp])
        let stack = NSStackView(views: [hide, focusRow, login])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClawdNotch Settings"
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        window.delegate = self
        hideCheck = hide
        loginCheck = login
        focusPopUp = popUp
        return window
    }

    @objc private func hideChanged(_ sender: NSButton) {
        preferences.setHideMode(sender.state == .on)
    }

    @objc private func loginChanged(_ sender: NSButton) {
        LoginItem.setEnabled(sender.state == .on)
        refresh()
    }

    @objc private func focusChanged(_ sender: NSPopUpButton) {
        preferences.setFocusReadMode(AppConfig.FocusReadMode.allCases[sender.indexOfSelectedItem])
    }
}
