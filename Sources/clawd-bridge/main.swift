// main.swift (clawd-bridge)
// CLI run by Claude Code's SessionStart hook and statusLine; forwards data to the app (docs/05, ADR-0002, ADR-0004).
// Contract: never slow or fail Claude Code. It always exits 0, and every POST gives up after 300 ms.

import Darwin
import Foundation

/// The bridge's view of the app's `config.json` (`AppConfig` keys, read without linking ClawdCore to keep startup fast).
struct BridgeConfig {
    let port: Int
    let token: String
    let originalStatusLine: String?

    /// Loads `CLAWD_CONFIG` (a test override) or `~/Library/Application Support/ClawdNotch/config.json`;
    /// nil when missing or malformed, which makes the bridge a silent no-op.
    static func load() -> BridgeConfig? {
        let path = ProcessInfo.processInfo.environment["CLAWD_CONFIG"]
            ?? NSHomeDirectory() + "/Library/Application Support/ClawdNotch/config.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let port = json["port"] as? Int, let token = json["token"] as? String
        else { return nil }
        return BridgeConfig(port: port, token: token, originalStatusLine: json["originalStatusLine"] as? String)
    }
}

/// Starts a POST of `body` to the app; `wait()` on the result blocks until it completes or the 300 ms deadline.
func post(_ body: Data, to path: String, config: BridgeConfig) -> DispatchSemaphore {
    let done = DispatchSemaphore(value: 0)
    guard let url = URL(string: "http://127.0.0.1:\(config.port)\(path)") else { done.signal(); return done }
    var request = URLRequest(url: url, timeoutInterval: 0.3)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.token, forHTTPHeaderField: "X-Clawd-Token")
    let session = URLSession(configuration: .ephemeral)
    session.dataTask(with: request) { _, _, _ in done.signal() }.resume()
    return done
}

let deadline = DispatchTime.now() + .milliseconds(300)
// A wrapped statusline that exits early must not kill the bridge with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
let arguments = Array(CommandLine.arguments.dropFirst())
let config = BridgeConfig.load()

// stdin is read only for known subcommands, so a bare `clawd-bridge` exits instead of waiting for EOF.
switch arguments {
case ["hook", "session-start"]:
    let input = FileHandle.standardInput.readDataToEndOfFile()
    if let config, let meta = sessionMeta(hookInput: input) {
        _ = post(meta, to: "/session-meta", config: config).wait(timeout: deadline)
    }
case ["statusline"]:
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let sent = config.map { post(input, to: "/statusline", config: $0) }
    printStatusLine(input: input, original: config?.originalStatusLine)
    _ = sent?.wait(timeout: deadline)
default:
    break
}
exit(0)
