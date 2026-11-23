// SettingsWindow.swift
// The Settings window: a normal window, created on demand and released when closed.

import AppKit
import ClawdCore

/// Plain AppKit on purpose: linking SwiftUI for a few controls would blow the RSS budget (docs/08).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private var window: NSWindow?
    private var miniCheck: NSButton?
    private var loginCheck: NSButton?
    private var hooksLabel: NSTextField?
    private var hooksButton: NSButton?
    private var permissionCheck: NSButton?
    private var soundCheck: NSButton?
    private var focusPopUp: NSPopUpButton?
    /// Set while the window shows the first-run welcome; Install is then the default button (REQ-09 AC5).
    private var welcomeLabel: NSTextField?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    /// Shows the window, building it first if needed, and activates the app (it is an accessory app).
    /// - Parameter welcome: adds the first-run welcome line when the window is built now.
    func show(welcome: Bool = false) {
        if window == nil { window = makeWindow(welcome: welcome) }
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closes the window, releasing its views (`windowWillClose`).
    func close() { window?.close() }

    /// Syncs the controls with the current settings, e.g. after the menu toggled mini mode.
    func refresh() {
        miniCheck?.state = preferences.miniMode ? .on : .off
        loginCheck?.state = LoginItem.isEnabled ? .on : .off
        let installed = Self.installer.isInstalled
        hooksLabel?.stringValue = "Claude Code hooks: " + (installed ? "Installed" : "Not installed")
        hooksButton?.title = installed ? "Uninstall" : "Install"
        hooksButton?.keyEquivalent = welcomeLabel != nil && !installed ? "\r" : ""
        soundCheck?.state = preferences.soundCues ? .on : .off
        permissionCheck?.state = preferences.notchPermissions.withLock { $0 } ? .on : .off
        if let index = AppConfig.FocusReadMode.allCases.firstIndex(of: preferences.focusReadMode) {
            focusPopUp?.selectItem(at: index)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        miniCheck = nil
        loginCheck = nil
        hooksLabel = nil
        hooksButton = nil
        permissionCheck = nil
        soundCheck = nil
        focusPopUp = nil
        welcomeLabel = nil
    }

    private func makeWindow(welcome: Bool) -> NSWindow {
        let mini = NSButton(checkboxWithTitle: "Mini mode: Clawd peeks from under the notch", target: self, action: #selector(miniChanged(_:)))
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(loginChanged(_:)))
        let permissions = NSButton(
            checkboxWithTitle: "Approve permissions from the notch", target: self, action: #selector(permissionsChanged(_:))
        )
        let hooksText = NSTextField(labelWithString: "")
        let hooksAction = NSButton(title: "", target: self, action: #selector(hooksClicked(_:)))
        let sound = NSButton(checkboxWithTitle: "Sound cues", target: self, action: #selector(soundChanged(_:)))
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        let focusLabel = NSTextField(labelWithString: "Mark as read on terminal focus:")
        for control in [mini, login, permissions, sound, popUp, focusLabel, hooksText, hooksAction] as [NSControl] {
            control.font = HUDStyle.font(size: 13)
        }
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
        let focusRow = NSStackView(views: [focusLabel, popUp])
        let hooksRow = NSStackView(views: [hooksText, hooksAction])
        var rows: [NSView] = [mini, focusRow, permissions, sound, login, hooksRow]
        if welcome {
            let label = NSTextField(labelWithString: "Install the Claude Code hooks to connect Clawd")
            label.font = HUDStyle.font(size: 13, weight: .bold)
            rows.insert(label, at: rows.count - 1)  // just above the hooks row (docs/06)
            welcomeLabel = label
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClawdIsland Settings"
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        window.delegate = self
        miniCheck = mini
        loginCheck = login
        hooksLabel = hooksText
        hooksButton = hooksAction
        permissionCheck = permissions
        soundCheck = sound
        focusPopUp = popUp
        return window
    }

    @objc private func miniChanged(_ sender: NSButton) {
        preferences.setMiniMode(sender.state == .on)
    }

    @objc private func permissionsChanged(_ sender: NSButton) {
        preferences.setNotchPermissions(sender.state == .on)
    }

    @objc private func soundChanged(_ sender: NSButton) {
        preferences.setSoundCues(sender.state == .on)
    }

    @objc private func loginChanged(_ sender: NSButton) {
        LoginItem.setEnabled(sender.state == .on)
        refresh()
    }

    /// Installer pointed at the `clawd-bridge` shipped next to the app's main executable.
    private static var installer: HookInstaller {
        HookInstaller(bridgePath: Bundle.main.executableURL?.deletingLastPathComponent()
            .appending(path: "clawd-bridge").path ?? "/Applications/ClawdIsland.app/Contents/MacOS/clawd-bridge")
    }

    @objc private func hooksClicked(_ sender: NSButton) {
        let installer = Self.installer
        do {
            if installer.isInstalled { try installer.uninstall() } else { try installer.install() }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    @objc private func focusChanged(_ sender: NSPopUpButton) {
        preferences.setFocusReadMode(AppConfig.FocusReadMode.allCases[sender.indexOfSelectedItem])
    }
}
