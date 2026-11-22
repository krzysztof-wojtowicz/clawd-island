// SoundCues.swift
// A short system sound on the edge into attention (REQ-12).

import AppKit
import ClawdCore

/// Plays "Funk" when a session newly needs input and "Glass" for any other attention edge (an unread `done`).
/// Callers invoke it only when `popToken` advanced, so it fires once per edge and never for changes the user caused.
@MainActor
final class SoundCues {
    // Looked up on first use and then kept, so a cue costs no disk access.
    private lazy var needsInput = NSSound(named: "Funk")
    private lazy var done = NSSound(named: "Glass")

    /// Plays the cue for the pop-out edge between `old` and `new`.
    func playEdge(from old: Snapshot, to new: Snapshot) {
        let sound = new.statusCounts.needsInput > old.statusCounts.needsInput ? needsInput : done
        // A cue still playing from a moments-ago edge restarts instead of being dropped.
        sound?.stop()
        sound?.play()
    }
}
