// StatusLine.swift (clawd-bridge)
// Prints the statusline: the user's original command's output, or a minimal Clawd line (ADR-0004).

import Foundation

/// Prints the user's wrapped statusline if one is configured and runs, otherwise `◆ <model> · HP <left>%`.
func printStatusLine(input: Data, original: String?) {
    if let original, let output = run(original, input: input) {
        FileHandle.standardOutput.write(output)
    } else {
        print(minimalStatusLine(input))
    }
}

/// Runs `command` through `/bin/sh -c` with `input` on stdin and returns its stdout; nil if it cannot start.
/// shortcut: stdin is written before stdout is drained, fine while statusline JSON fits the 64 KiB pipe buffer.
private func run(_ command: String, input: Data) -> Data? {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-c", command]
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    guard (try? process.run()) != nil else { return nil }
    try? stdin.fileHandleForWriting.write(contentsOf: input)
    try? stdin.fileHandleForWriting.close()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return output
}

/// The model's display name plus the remaining 5-hour budget when `rate_limits` carries it.
private func minimalStatusLine(_ input: Data) -> String {
    let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
    let model = (json?["model"] as? [String: Any])?["display_name"] as? String ?? "Claude"
    let fiveHour = (json?["rate_limits"] as? [String: Any])?["five_hour"] as? [String: Any]
    guard let used = fiveHour?["used_percentage"] as? Double else { return "◆ \(model)" }
    return "◆ \(model) · HP \(Int((100 - used).rounded()))%"
}
