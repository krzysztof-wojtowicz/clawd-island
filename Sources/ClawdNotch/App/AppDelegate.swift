// AppDelegate.swift
// Owns the app's long-lived objects and wires them together at launch.

import AppKit
import ClawdCore
import os

/// Application lifecycle owner. It holds the notch window controller, the pet, the model and the event server
/// for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.clawdnotch", category: "app")

    private var notchController: NotchWindowController?
    private let pet = PetView(frame: .zero)
    /// The session model every UI piece reads from.
    let model = AppModel()
    private lazy var hud = HUDController(model: model, focus: { [unowned self] in focusWatcher.focus($0) })
    private var server: EventServer?
    /// Read first after `startServer()`, which creates config.json on first launch.
    private let sounds = SoundCues()
    private lazy var preferences = Preferences()
    private lazy var settings = SettingsWindowController(preferences: preferences)
    private lazy var focusWatcher = TerminalFocusWatcher(
        sessions: { [model] in model.snapshot.sessions },
        markRead: { [model] in model.markRead($0) },
        mode: { [preferences] in preferences.focusReadMode })

    private lazy var nowPlayingWatcher = NowPlayingWatcher { [model] in model.receive(nowPlaying: $0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.recordProject = { [unowned self] in preferences.noteRecentProject($0) }  // lazy: not created before startServer()
        startServer()
        let controller = NotchWindowController()
        controller.needsInput = { [model] in model.snapshot.aggregate == .needsInput }
        controller.serverError = { [model] in model.serverError }
        controller.hideMode = preferences.hideMode
        preferences.onHideModeChange = { [controller, settings] hidden in
            controller.hideMode = hidden
            settings.refresh()
        }
        preferences.onNotchPermissionsOff = { [model] in model.releaseAllPermissions() }
        controller.onToggleHideMode = { [preferences] in preferences.setHideMode(!preferences.hideMode) }
        controller.onToggleLaunchAtLogin = { LoginItem.setEnabled(!LoginItem.isEnabled) }
        controller.launchAtLoginEnabled = { LoginItem.isEnabled }
        controller.onOpenSettings = { [settings] in settings.show() }
        controller.onMarkAllRead = { [model] in model.markAllRead() }
        controller.hasAttention = { [model] in model.snapshot.attentionCount > 0 }
        Self.embed(pet, in: controller.island.petSlot)
        Self.embed(hud.counters, in: controller.island.countersSlot)
        controller.island.panelProvider = { [hud] in hud.makePanel() }
        PetDemo.startIfRequested(on: pet)
        notchController = controller
        pausePetWhileUnseen()
        bindSnapshot(controller)
        focusWatcher.start()
        if preferences.headphones { nowPlayingWatcher.start() }
        preferences.onHeadphonesChange = { [nowPlayingWatcher, pet] on in
            if on {
                nowPlayingWatcher.start()
            } else {
                nowPlayingWatcher.stop()
                pet.setHeadphones(false)
            }
        }
    }

    private static func embed(_ view: NSView, in slot: NSView) {
        view.frame = slot.bounds
        view.autoresizingMask = [.width, .height]
        slot.addSubview(view)
    }

    /// States whose entry pops a hidden island out (REQ-05 AC1); other changes only re-pose the peeking pet.
    private static let popsOut: Set<PetState> = [.talking, .done, .needsInput, .juggling]

    /// Renders every new snapshot: the pet's state (REQ-03 AC2), a pop-out on each new `popToken`, and the HUD.
    private func bindSnapshot(_ controller: NotchWindowController) {
        pet.setState(model.snapshot.aggregate)
        hud.render(model.snapshot)
        model.onSnapshotChange = { [pet, hud, controller, focusWatcher, model, preferences, sounds] old, new in
            focusWatcher.snapshotChanged(from: old.sessions, to: new.sessions)
            pet.setState(new.aggregate)
            if new.nowPlaying?.isPlaying != old.nowPlaying?.isPlaying {
                pet.setHeadphones(preferences.headphones && new.nowPlaying?.isPlaying == true)
            }
            if new.popToken > old.popToken {
                pet.popOut()
                if preferences.soundCues { sounds.playEdge(from: old, to: new) }
            }
            let entered = new.aggregate != old.aggregate && Self.popsOut.contains(new.aggregate)
            if entered || new.popToken > old.popToken {
                controller.popOut(hold: new.aggregate == .needsInput)
            } else if old.aggregate == .needsInput && new.aggregate != .needsInput {
                controller.popOut(hold: false)  // resolved: the held pop-out now runs its 3 s out
            }
            hud.render(new)
            #if DEBUG
            Self.debugDecide(new, model: model)
            #endif
        }
    }

    #if DEBUG
    /// End-to-end test hook: with `--debug-auto-allow`, `--debug-auto-always` or `--debug-auto-deny`, answers the newest pending permission
    /// 3 s after it appears, standing in for a click on the card.
    private static func debugDecide(_ snapshot: Snapshot, model: AppModel) {
        let args = CommandLine.arguments
        let choice: AppModel.PermissionChoice
        if args.contains("--debug-auto-always") { choice = .alwaysAllow }
        else if args.contains("--debug-auto-allow") { choice = .allow }
        else if args.contains("--debug-auto-deny") { choice = .deny }
        else { return }
        guard let id = snapshot.pendingPermissions.first?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { model.decide(permissionID: id, choice) } }
    }
    #endif

    /// Starts the event server from the config file, creating a default config (random token) on first launch.
    private func startServer() {
        guard let config = loadOrCreateConfig() else { return }
        let holdFlag = preferences.notchPermissions
        do {
            let server = try EventServer(
                config: config,
                holdPermissions: { holdFlag.withLock { $0 } },
                onMessage: { [model] message in
                    // main.async keeps arrival order, which the state machine depends on.
                    DispatchQueue.main.async { MainActor.assumeIsolated { model.receive(message) } }
                },
                onPermission: { [model] event, responder in
                    DispatchQueue.main.async { MainActor.assumeIsolated { model.receive(permission: event, responder: responder) } }
                },
                onPermissionClosed: { [model] id in
                    DispatchQueue.main.async { MainActor.assumeIsolated { model.permissionClosed(id) } }
                },
                onFailure: { [model] error in
                    let text = "Port \(config.port) unavailable: \(error.localizedDescription)"
                    DispatchQueue.main.async { MainActor.assumeIsolated { model.serverError = text } }
                }
            )
            server.start()
            self.server = server
        } catch {
            Self.logger.error("event server not started: \(error.localizedDescription, privacy: .public)")
            model.serverError = error.localizedDescription
        }
    }

    private func loadOrCreateConfig() -> AppConfig? {
        if let config = AppConfig.load() { return config }
        // Never overwrite a config we failed to parse: it may hold the user's original statusline.
        guard !FileManager.default.fileExists(atPath: AppConfig.defaultURL.path) else {
            Self.logger.error("config.json is unreadable; event server not started")
            model.serverError = "config.json is unreadable"
            return nil
        }
        let config = AppConfig.makeDefault()
        do {
            try config.write()
        } catch {
            Self.logger.error("cannot write config.json: \(error.localizedDescription, privacy: .public)")
        }
        return config
    }

    /// Freezes the pet's loops and the liveness timer while the screen sleeps or the user session
    /// is switched away (docs/08 rule 4).
    private func pausePetWhileUnseen() {
        let center = NSWorkspace.shared.notificationCenter
        let pauses: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        for (name, paused) in pauses {
            center.addObserver(forName: name, object: nil, queue: .main) { [pet, model] _ in
                MainActor.assumeIsolated {
                    pet.setPaused(paused)
                    model.setPaused(paused)
                }
            }
        }
    }
}
