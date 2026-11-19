// SessionMeta.swift (clawd-bridge)
// Builds the `/session-meta` body: the session plus the Claude Code process and its terminal (docs/05).

import Darwin
import Foundation

/// Returns the snake_case `SessionMeta` JSON for a SessionStart hook payload, or nil without `session_id`/`cwd`.
/// Process fields are best effort and simply omitted when the walk finds nothing.
func sessionMeta(hookInput: Data) -> Data? {
    guard let hook = try? JSONSerialization.jsonObject(with: hookInput) as? [String: Any],
          let sessionID = hook["session_id"] as? String, let cwd = hook["cwd"] as? String
    else { return nil }
    var meta: [String: Any] = ["session_id": sessionID, "cwd": cwd]
    meta["source"] = hook["source"] as? String
    meta["term_program"] = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
    let walk = ProcessWalk(from: getppid())
    meta["pid"] = walk.claudePID.map { Int($0) }
    meta["tty"] = walk.tty
    meta["terminal_bundle_id"] = walk.terminalBundleID
    return try? JSONSerialization.data(withJSONObject: meta)
}

/// What the parent process chain says about the Claude Code process and the terminal hosting it.
/// shortcut: Claude Code is found by executable path: named `claude`, or the native installer's
/// `…/claude/versions/<version>` (its kernel name is the version). Upgrade to argv matching if CC runs under node.
/// shortcut: under tmux the chain ends at the tmux server, so there is no terminal app; focus then falls back
/// to `term_program` at app level. `ITERM_SESSION_ID` is not sent because `SessionMeta` has no field for it yet.
struct ProcessWalk {
    private(set) var claudePID: pid_t?
    /// Controlling terminal of the Claude Code process, e.g. `/dev/ttys003` (the form AppleScript reports).
    private(set) var tty: String?
    /// `CFBundleIdentifier` of the nearest ancestor running from inside a `.app` bundle.
    private(set) var terminalBundleID: String?

    init(from start: pid_t) {
        var pid = start
        // The hop limit guards against a pid reused into a cycle mid-walk.
        for _ in 0..<64 where pid > 1 {
            guard let info = Self.info(pid) else { break }
            let path = Self.executablePath(pid) ?? ""
            if claudePID == nil, path.hasSuffix("/claude") || path.contains("/claude/versions/") {
                claudePID = pid
                tty = Self.ttyPath(info.kp_eproc.e_tdev)
            }
            if terminalBundleID == nil { terminalBundleID = Self.bundleID(executablePath: path) }
            if claudePID != nil, terminalBundleID != nil { break }
            pid = info.kp_eproc.e_ppid
        }
    }

    private static func info(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func ttyPath(_ device: dev_t) -> String? {
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty == "??" ? nil : "/dev/" + tty
    }

    /// The outermost `.app` in the executable path, so helper apps nested in Frameworks map to their host app.
    private static func bundleID(executablePath path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return Bundle(path: String(path[..<range.lowerBound]) + ".app")?.bundleIdentifier
    }
}
