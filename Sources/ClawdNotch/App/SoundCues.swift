// SoundCues.swift
// A short system sound on the edge into attention (REQ-12).

import AppKit
import ClawdCore

/// Plays "Funk" when a session newly needs input and "Glass" for any other attention edge (an unread `done`).
/// Callers invoke it only when `popToken` advanced, so it fires once per edge and never for changes the user caused.
/// The sound plays in a short-lived `afplay` process: `NSSound` loads the audio stack into this process
/// (+7 MB RSS, +6 MB footprint, never released), `afplay` costs nothing while it is not running (docs/08).
@MainActor
final class SoundCues {
    private var playing: Process?

    /// Plays the cue for the pop-out edge between `old` and `new`.
    func playEdge(from old: Snapshot, to new: Snapshot) {
        let name = new.statusCounts.needsInput > old.statusCounts.needsInput ? "Funk" : "Glass"
        // A cue still playing from a moments-ago edge restarts instead of being dropped.
        if playing?.isRunning == true { playing?.terminate() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["/System/Library/Sounds/\(name).aiff"]
        do {
            try process.run()
            playing = process
        } catch {
            playing = nil // no sound is not worth an error
        }
    }
}
