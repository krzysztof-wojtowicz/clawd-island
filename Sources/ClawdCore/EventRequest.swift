// EventRequest.swift
// Pure HTTP request handling for the event server: head parsing, auth/size/route checks and body decoding (docs/05).

import Foundation

/// The request line and headers of one HTTP/1.1 request, as received by the event server.
public struct HTTPRequestHead: Equatable, Sendable {
    /// Bodies above this size are rejected with 413 before they are read.
    public static let maxBodyBytes = 64 * 1024
    /// Heads above this size are rejected, so a client cannot grow the buffer without ever sending a body.
    public static let maxHeadBytes = 8 * 1024
    /// Marks the end of the head.
    public static let terminator = Data("\r\n\r\n".utf8)

    public let method: String
    public let path: String
    /// Header values keyed by lowercased name, since HTTP header names are case-insensitive.
    public let headers: [String: String]

    /// Parses the bytes before `\r\n\r\n`. Nil when the request line is malformed.
    public init?(_ data: Data) {
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }

    /// Decides what to do with the request before reading its body.
    /// The token is checked first so unauthenticated clients learn nothing about routes or limits.
    // shortcut: a missing Content-Length means an empty body (no chunked encoding), fine for Claude Code's axios and the bridge.
    public func verdict(token: String) -> HeadVerdict {
        // shortcut: non-constant-time compare; acceptable because the server is loopback-only.
        guard !token.isEmpty, headers["x-clawd-token"] == token else { return .reject(status: 401) }
        guard method == "POST", let endpoint = EventEndpoint(rawValue: path) else { return .reject(status: 404) }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return .reject(status: 400) }
        guard length <= Self.maxBodyBytes else { return .reject(status: 413) }
        return .readBody(endpoint, length: length)
    }
}

/// Outcome of checking a request head.
public enum HeadVerdict: Equatable, Sendable {
    /// Read exactly `length` body bytes, then decode them for `endpoint`.
    case readBody(EventEndpoint, length: Int)
    /// Reply with this status and an empty body, without reading the body.
    case reject(status: Int)
}

/// The event server's endpoints.
public enum EventEndpoint: String, Sendable {
    case hook = "/hook"
    case sessionMeta = "/session-meta"
    case statusline = "/statusline"

    /// Decodes a body for this endpoint. Nil when there is nothing to apply (malformed JSON,
    /// or a statusline with neither `rate_limits` nor `session_id`); the server still replies 200 so hooks never fail.
    public func decode(_ body: Data, receivedAt: Date) -> Inbound? {
        switch self {
        case .hook: ClawdEvent(json: body, receivedAt: receivedAt).map(Inbound.event)
        case .sessionMeta: SessionMeta(json: body).map(Inbound.meta)
        case .statusline: Self.statusline(body)
        }
    }

    private static func statusline(_ body: Data) -> Inbound? {
        let usage = UsageSnapshot(statusline: body)
        let stats = SessionStats(statusline: body)
        guard usage != nil || stats != nil else { return nil }
        return .statusline(usage: usage, stats: stats)
    }
}

/// A decoded message on its way from the server queue to the main actor.
public enum Inbound: Equatable, Sendable {
    case event(ClawdEvent)
    case meta(SessionMeta)
    /// One statusline payload: the global usage windows and this session's context and cost, either may be absent.
    case statusline(usage: UsageSnapshot?, stats: SessionStats?)
}

extension SessionStore {
    /// Applies any inbound message.
    public mutating func apply(_ inbound: Inbound, now: Date) {
        switch inbound {
        case .event(let event): apply(event, now: now)
        case .meta(let meta): apply(meta: meta, now: now)
        case .statusline(let usage, let stats):
            // A payload without `rate_limits` keeps the last usage (ADR-0004).
            if let usage { apply(usage: usage) }
            if let stats { apply(stats: stats, now: now) }
        }
    }
}
