// TerminalFocusWatcher.swift
// Marks sessions read when their terminal comes to the front, and focuses a session's terminal on click (REQ-10).

import AppKit
import ClawdCore
import os

/// Observes app activation (no polling). Terminal.app and iTerm2 report the selected tab's tty through
/// AppleScript, so only that tab's session is marked read; if Automation is denied, or for any other terminal,
/// the app staying frontmost for `dwell` seconds marks its `done` sessions read.
@MainActor
final class TerminalFocusWatcher {
    nonisolated private static let logger = Logger(subsystem: "dev.clawdnotch", category: "focus")
    private static let dwell: TimeInterval = 2
    private static let terminalApp = "com.apple.Terminal"
    private static let iTerm = "com.googlecode.iterm2"

    private let sessions: () -> [Session]
    private let markRead: (String) -> Void
    private let mode: () -> AppConfig.FocusReadMode
    private var dwellTimer: Timer?
    private var observer: NSObjectProtocol?
    /// Scripts run here, never on the main thread; they can block on the Automation prompt.
    private let scriptQueue = DispatchQueue(label: "dev.clawdnotch.applescript", qos: .utility)

    /// - Parameters:
    ///   - sessions: The current sessions, read when an activation arrives.
    ///   - markRead: Marks one session read by id.
    ///   - mode: The current focus-read setting: `off` never marks, `app` skips AppleScript and uses the dwell.
    init(
        sessions: @escaping () -> [Session],
        markRead: @escaping (String) -> Void,
        mode: @escaping () -> AppConfig.FocusReadMode
    ) {
        self.sessions = sessions
        self.markRead = markRead
        self.mode = mode
    }

    /// Starts observing activations. Idempotent.
    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.didActivate(bundleID) }
        }
    }

    /// Handles "finished while watched": when a session just became `done` and its terminal is already
    /// frontmost no activation will fire, so run the same check an activation would (REQ-10 AC1).
    func snapshotChanged(from old: [Session], to new: [Session]) {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        let wasDone = Set(old.filter { $0.state == .done }.map(\.id))
        let justFinished = new.contains {
            $0.state == .done && !wasDone.contains($0.id) && $0.meta?.terminalBundleID == front
        }
        if justFinished { didActivate(front) }
    }

    /// Activates the session's terminal and, in Terminal.app or iTerm2, selects its tab. After a successful
    /// focus the session is marked read, unless the focus-read mode is `off` (REQ-10 AC2): selecting a tab in a
    /// terminal that is already frontmost fires no activation, so the watcher would not see it.
    func focus(_ session: Session) {
        // A `tell` to a terminal that has quit would relaunch it, so only focus running ones.
        guard let bundleID = session.meta?.terminalBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let id = session.id
        if EditorWindows.handles(bundleID) {
            let finish: @MainActor () -> Void = { [weak self] in
                app.activate()
                if self?.mode() != .off { self?.markRead(id) }
            }
            guard EditorWindows.requestTrust() else { finish(); return }
            // Raise before activating so the right window is frontmost when the app comes forward.
            let (project, pid, family) = (session.projectName, app.processIdentifier, WindowTitle.Family(bundleID: bundleID))
            scriptQueue.async {
                _ = EditorWindows.raise(project: project, pid: pid, family: family)
                DispatchQueue.main.async { MainActor.assumeIsolated { finish() } }
            }
            return
        }
        app.activate()
        guard let tty = session.meta?.tty, Self.isSafe(tty),
              let source = Self.selectScript(bundleID: bundleID, tty: tty) else {
            // App-level terminal: bringing its app forward is the whole focus.
            if mode() != .off { markRead(id) }
            return
        }
        runScript(source) { [weak self] result in
            guard let self, result == "selected", mode() != .off else { return }
            markRead(id)
        }
    }

    private func didActivate(_ bundleID: String?) {
        dwellTimer?.invalidate()
        dwellTimer = nil
        guard mode() != .off, let bundleID,
              sessions().contains(where: { $0.meta?.terminalBundleID == bundleID }) else { return }
        if EditorWindows.handles(bundleID), mode() == .tab {
            // Window-level: the focused window's title names the project; otherwise the plain dwell.
            // No prompt here: a plain app switch must not trigger the Accessibility dialog.
            guard EditorWindows.isTrusted(),
                  let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
            else { startDwell(bundleID); return }
            let family = WindowTitle.Family(bundleID: bundleID)
            scriptQueue.async {
                let title = EditorWindows.focusedWindowTitle(pid: pid)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        guard let self, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
                        let matches = sessions().filter { session in
                            session.meta?.terminalBundleID == bundleID
                                && title.map { WindowTitle.matches($0, project: session.projectName, family: family) } == true
                        }
                        if matches.isEmpty { startDwell(bundleID) } else { matches.forEach { markRead($0.id) } }
                    }
                }
            }
            return
        }
        guard mode() == .tab, let source = Self.currentTTYScript(bundleID: bundleID) else {
            startDwell(bundleID)
            return
        }
        runScript(source) { [weak self] result in
            // The script can block on the Automation prompt; drop the result if the user has moved on.
            guard let self, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
            if let tty = result, !tty.isEmpty {
                for session in sessions() where session.meta?.tty == tty { markRead(session.id) }
            } else {
                startDwell(bundleID)
            }
        }
    }

    private func startDwell(_ bundleID: String) {
        dwellTimer?.invalidate()
        let timer = Timer(timeInterval: Self.dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dwellElapsed(bundleID) }
        }
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func dwellElapsed(_ bundleID: String) {
        dwellTimer = nil
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
        for session in sessions() where session.state == .done && session.meta?.terminalBundleID == bundleID {
            markRead(session.id)
        }
    }

    /// Runs AppleScript on `scriptQueue` and calls `completion` on the main actor with the string result,
    /// or nil when the script failed (for example, Automation was denied).
    private func runScript(_ source: String, completion: @escaping @MainActor (String?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { Self.logger.info("applescript failed: \(error[NSAppleScript.errorNumber] as? Int ?? 0)") }
            let text = error == nil ? output?.stringValue : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(text) } }
        }
    }

    /// A tty is interpolated into script source, so only accept plain device paths.
    nonisolated private static func isSafe(_ tty: String) -> Bool {
        tty.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }
    }

    nonisolated private static func currentTTYScript(bundleID: String) -> String? {
        switch bundleID {
        case terminalApp: "tell application \"Terminal\" to return tty of selected tab of front window"
        case iTerm: "tell application \"iTerm2\" to return tty of current session of current window"
        default: nil
        }
    }

    nonisolated private static func selectScript(bundleID: String, tty: String) -> String? {
        switch bundleID {
        case terminalApp:
            """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return "selected"
                        end if
                    end repeat
                end repeat
            end tell
            """
        case iTerm:
            """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                return "selected"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default: nil
        }
    }
}
