// AppDelegate.swift
// Owns the app's long-lived objects and wires them together at launch.

import AppKit
import ClawdCore
import os

/// Application lifecycle owner. It holds the notch window controller, the pet, the model and the event server
/// for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.clawdisland", category: "app")

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.recordProject = { [unowned self] in preferences.noteRecentProject($0) }  // lazy: not created before startServer()
        startServer()
        let controller = NotchWindowController()
        controller.holdsPopOut = { [model] in Self.holdsPopOut.contains(model.snapshot.aggregate) }
        controller.serverError = { [model] in model.serverError }
        // The pet must be in its slot first, or the tilt of a persisted mini mode is lost.
        Self.embed(pet, in: controller.island.petSlot)
        pet.setStyle(preferences.petStyle)
        preferences.onPetStyleChange = { [pet] in pet.setStyle($0) }
        controller.miniMode = preferences.miniMode
        preferences.onMiniModeChange = { [controller, settings] mini in
            controller.miniMode = mini
            settings.refresh()
        }
        controller.dnd = preferences.dnd
        preferences.onDNDChange = { [controller, settings] dnd in
            controller.dnd = dnd
            settings.refresh()
        }
        preferences.onNotchPermissionsOff = { [model] in model.releaseAllPermissions() }
        controller.onToggleMiniMode = { [preferences] in preferences.setMiniMode(!preferences.miniMode) }
        controller.onToggleDND = { [preferences] in preferences.setDND(!preferences.dnd) }
        controller.onOpenSettings = { [settings] in settings.show() }
        controller.onMarkAllRead = { [model] in model.markAllRead() }
        controller.hasAttention = { [model] in model.snapshot.attentionCount > 0 }
        Self.embed(hud.counters, in: controller.island.countersSlot)
        controller.island.panelProvider = { [hud] in hud.makePanel() }
        PetDemo.startIfRequested(on: pet)
        notchController = controller
        pausePetWhileUnseen()
        bindSnapshot(controller)
        focusWatcher.start()
        openSettingsIfRequested()
        onboardIfNeeded()
    }

    /// First launch without hooks: open Settings once with a welcome line (REQ-09 AC5).
    private func onboardIfNeeded() {
        // `--open-settings` (perf-suite) already built the window without the welcome; `isInstalled` ignores the bridge path.
        guard !CommandLine.arguments.contains("--open-settings"), !preferences.onboarded,
            !HookInstaller(bridgePath: "").isInstalled
        else { return }
        settings.show(welcome: true)
        preferences.markOnboarded()
    }

    /// `--open-settings` opens Settings once after launch; `--close-settings-after <s>` closes it again (perf-suite.sh).
    private func openSettingsIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--open-settings") else { return }
        settings.show()
        if let flag = args.firstIndex(of: "--close-settings-after"), args.indices.contains(flag + 1),
            let seconds = Double(args[flag + 1])
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [settings] in MainActor.assumeIsolated { settings.close() } }
        }
    }

    private static func embed(_ view: NSView, in slot: NSView) {
        view.frame = slot.bounds
        view.autoresizingMask = [.width, .height]
        slot.addSubview(view)
    }

    /// States whose entry pops a hidden island out (REQ-05 AC1); other changes only re-pose the peeking pet.
    private static let popsOut: Set<PetState> = [.talking, .done, .needsInput]
    /// States that keep a pop-out held until the aggregate leaves them: unread `done` and `needsInput` (REQ-05 AC2).
    private static let holdsPopOut: Set<PetState> = [.done, .needsInput]

    /// Renders every new snapshot: the pet's state (REQ-03 AC2), a pop-out on each new `popToken` unless Do Not Disturb is on (REQ-23), and the HUD.
    private func bindSnapshot(_ controller: NotchWindowController) {
        pet.setState(model.snapshot.aggregate)
        hud.render(model.snapshot)
        model.onSnapshotChange = { [pet, hud, controller, focusWatcher, model, preferences, sounds] old, new in
            focusWatcher.snapshotChanged(from: old.sessions, to: new.sessions)
            pet.setState(new.aggregate)
            // DND (REQ-23) mutes the spring and the sound; the controller itself ignores pop-outs under DND.
            if new.popToken > old.popToken, !preferences.dnd {
                pet.popOut()
                if preferences.soundCues { sounds.playEdge(from: old, to: new) }
            }
            let entered = new.aggregate != old.aggregate && Self.popsOut.contains(new.aggregate)
            if entered || new.popToken > old.popToken {
                controller.popOut(hold: Self.holdsPopOut.contains(new.aggregate))
            } else if Self.holdsPopOut.contains(old.aggregate) && !Self.holdsPopOut.contains(new.aggregate) {
                controller.popOut(hold: false)  // read or resolved: the held pop-out now runs its 3 s out
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
