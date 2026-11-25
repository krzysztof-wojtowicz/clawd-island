// SettingsWindow.swift
// The Settings window: General / Pet / Advanced toolbar tabs, created on demand and released when closed (REQ-21).

import AppKit
import ClawdCore

/// Plain AppKit on purpose: linking SwiftUI for a few controls would blow the RSS budget (docs/08).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    // safe: a constant, valid URL literal.
    private static let repositoryURL = URL(string: "https://github.com/krzysztof-wojtowicz/clawd-island")!

    private let preferences: Preferences
    private var window: NSWindow?
    private var tabs: NSTabViewController?
    private var miniCheck: NSButton?
    private var loginCheck: NSButton?
    private var hooksLabel: NSTextField?
    private var hooksButton: NSButton?
    private var permissionCheck: NSButton?
    private var soundCheck: NSButton?
    private var dndCheck: NSButton?
    private var focusPopUp: NSPopUpButton?
    private var stylePopUp: NSPopUpButton?
    /// The Pet tab's live preview; paused while the window is not key (docs/08 rule 11).
    private var preview: PetView?
    /// Set while the window shows the first-run welcome; Install is then the default button (REQ-09 AC5).
    private var welcomeLabel: NSTextField?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    /// Shows the window, building it first if needed, and activates the app (it is an accessory app).
    /// - Parameter welcome: adds the first-run welcome line when the window is built now. It always opens on General.
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
        dndCheck?.state = preferences.dnd ? .on : .off
        permissionCheck?.state = preferences.notchPermissions.withLock { $0 } ? .on : .off
        if let index = AppConfig.FocusReadMode.allCases.firstIndex(of: preferences.focusReadMode) {
            focusPopUp?.selectItem(at: index)
        }
        if let index = AppConfig.PetStyle.allCases.firstIndex(of: preferences.petStyle) {
            stylePopUp?.selectItem(at: index)
        }
        preview?.setStyle(preferences.petStyle)
    }

    func windowDidBecomeKey(_ notification: Notification) { preview?.setPaused(false) }

    func windowDidResignKey(_ notification: Notification) { preview?.setPaused(true) }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        tabs = nil
        miniCheck = nil
        loginCheck = nil
        hooksLabel = nil
        hooksButton = nil
        permissionCheck = nil
        soundCheck = nil
        dndCheck = nil
        focusPopUp = nil
        stylePopUp = nil
        preview = nil
        welcomeLabel = nil
    }

    private func makeWindow(welcome: Bool) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let contents = [
            ("General", "gearshape", makeGeneral(welcome: welcome)),
            ("Pet", "pawprint", makePet()),
            ("Advanced", "slider.horizontal.3", makeAdvanced()),
        ]
        // One size for every tab (the largest), so the window never resizes and every tab fits.
        let size = NSSize(width: max(420, contents.map(\.2.fittingSize.width).max() ?? 0),
                          height: contents.map(\.2.fittingSize.height).max() ?? 0)
        for (title, symbol, content) in contents {
            tabs.addTabViewItem(Self.tab(title, symbol: symbol, content: content, size: size))
        }
        tabs.selectedTabViewItemIndex = 0
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.tabs = tabs
        return window
    }

    /// A toolbar tab around `content` at the shared window `size`.
    private static func tab(_ title: String, symbol: String, content: NSView, size: NSSize) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = content
        controller.preferredContentSize = size
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// A vertical, leading-aligned column with the window's margins.
    private static func column(_ rows: [NSView]) -> NSStackView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    /// Applies the Settings font to every control (REQ-14, REQ-21 AC6).
    private static func setFont(_ controls: [NSControl]) {
        for control in controls { control.font = HUDStyle.font(size: 13) }
    }

    /// The General tab: welcome, hooks row and the behaviour toggles (REQ-21 AC1).
    private func makeGeneral(welcome: Bool) -> NSView {
        let mini = NSButton(checkboxWithTitle: "Mini mode: Clawd peeks from under the notch", target: self, action: #selector(miniChanged(_:)))
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(loginChanged(_:)))
        let permissions = NSButton(
            checkboxWithTitle: "Approve permissions from the notch", target: self, action: #selector(permissionsChanged(_:))
        )
        let hooksText = NSTextField(labelWithString: "")
        let hooksAction = NSButton(title: "", target: self, action: #selector(hooksClicked(_:)))
        let sound = NSButton(checkboxWithTitle: "Sound cues", target: self, action: #selector(soundChanged(_:)))
        let dnd = NSButton(checkboxWithTitle: "Do Not Disturb: no pop-out and no sound", target: self, action: #selector(dndChanged(_:)))
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        let focusLabel = NSTextField(labelWithString: "Mark as read on terminal focus:")
        Self.setFont([mini, login, permissions, sound, dnd, popUp, focusLabel, hooksText, hooksAction])
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
        var rows: [NSView] = []
        if welcome {
            let label = NSTextField(labelWithString: "Install the Claude Code hooks to connect Clawd")
            label.font = HUDStyle.font(size: 13, weight: .bold)
            rows.append(label)  // just above the hooks row (docs/06)
            welcomeLabel = label
        }
        rows += [NSStackView(views: [hooksText, hooksAction]), permissions, mini,
                 NSStackView(views: [focusLabel, popUp]), sound, dnd, login]
        miniCheck = mini
        loginCheck = login
        hooksLabel = hooksText
        hooksButton = hooksAction
        permissionCheck = permissions
        soundCheck = sound
        dndCheck = dnd
        focusPopUp = popUp
        return Self.column(rows)
    }

    /// The Pet tab: the live preview with its pose picker, and the Style popup (REQ-21 AC3).
    private func makePet() -> NSView {
        let height = PetTokens.collapsedHeight * 3
        let pet = PetView(frame: NSRect(x: 0, y: 0, width: height * PetTokens.unitBox.width / PetTokens.unitBox.height, height: height))
        pet.setStyle(preferences.petStyle)
        pet.setPaused(true)  // resumes in `windowDidBecomeKey`
        // No pause per tab: the tab controller detaches unselected tab views, which stops their animations.
        // The pet is drawn for the black island, so the preview sits on the same background.
        let stage = NSView()
        stage.wantsLayer = true
        stage.layer?.backgroundColor = PetTokens.islandBackground
        stage.layer?.cornerRadius = 12
        pet.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(pet)
        NSLayoutConstraint.activate([
            stage.widthAnchor.constraint(equalToConstant: pet.frame.width + 2 * 24),
            stage.heightAnchor.constraint(equalToConstant: pet.frame.height + 2 * 16),
            pet.widthAnchor.constraint(equalToConstant: pet.frame.width),
            pet.heightAnchor.constraint(equalToConstant: pet.frame.height),
            pet.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            pet.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
        ])
        let pose = NSPopUpButton(frame: .zero, pullsDown: false)
        // Titles follow `PetState.allCases` order; `poseChanged` indexes by it. The preview starts as `sleeping`, item 0.
        pose.addItems(withTitles: PetState.allCases.map { state in
            switch state {
            case .sleeping: "Sleeping"
            case .idle: "Idle"
            case .thinking: "Thinking"
            case .talking: "Talking"
            case .usingTools: "Using tools"
            case .compacting: "Compacting"
            case .juggling: "Juggling"
            case .done: "Done"
            case .needsInput: "Needs input"
            }
        })
        pose.target = self
        pose.action = #selector(poseChanged(_:))
        let style = NSPopUpButton(frame: .zero, pullsDown: false)
        // Titles follow `PetStyle.allCases` order; `styleChanged` and `refresh` index by it.
        style.addItems(withTitles: AppConfig.PetStyle.allCases.map { $0.rawValue.capitalized })
        style.target = self
        style.action = #selector(styleChanged(_:))
        let poseLabel = NSTextField(labelWithString: "Pose:")
        let styleLabel = NSTextField(labelWithString: "Style:")
        Self.setFont([pose, style, poseLabel, styleLabel])
        preview = pet
        stylePopUp = style
        let column = Self.column([stage, NSStackView(views: [poseLabel, pose]), NSStackView(views: [styleLabel, style])])
        column.alignment = .centerX
        return column
    }

    /// The Advanced tab: port, version and the repository link (REQ-21 AC4).
    private func makeAdvanced() -> NSView {
        let port = NSTextField(labelWithString: "Port: \(AppConfig.load()?.port ?? AppConfig.defaultPort)")
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let version = NSTextField(labelWithString: "Version: \(shortVersion ?? "dev")")
        let link = NSButton(title: "github.com/krzysztof-wojtowicz/clawd-island", target: self, action: #selector(openRepository(_:)))
        link.isBordered = false
        link.contentTintColor = .linkColor
        Self.setFont([port, version, link])
        return Self.column([port, version, link])
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

    @objc private func dndChanged(_ sender: NSButton) {
        preferences.setDND(sender.state == .on)
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

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        preferences.setPetStyle(AppConfig.PetStyle.allCases[sender.indexOfSelectedItem])
        preview?.setStyle(preferences.petStyle)
    }

    @objc private func poseChanged(_ sender: NSPopUpButton) {
        preview?.setState(PetState.allCases[sender.indexOfSelectedItem])
    }

    @objc private func focusChanged(_ sender: NSPopUpButton) {
        preferences.setFocusReadMode(AppConfig.FocusReadMode.allCases[sender.indexOfSelectedItem])
    }

    @objc private func openRepository(_ sender: NSButton) {
        NSWorkspace.shared.open(Self.repositoryURL)
    }
}
