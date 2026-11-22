// EventServer.swift
// Loopback HTTP endpoint that receives Claude Code hooks, bridge metadata and statusline payloads (docs/05).

import ClawdCore
@preconcurrency import Dispatch
import Foundation
import Network
import os

/// An `NWListener` on `127.0.0.1:<port>` that accepts `POST /hook`, `/session-meta` and `/statusline`.
/// Every connection is handled on its own and closed after one reply, which is empty except for a
/// `PermissionRequest` answered from the notch: with `notchPermissions` on, that connection is held and its
/// `PermissionResponder` is handed to `onPermission` (REQ-V2-01, ADR-0006).
/// Decoding runs on the server's serial queue; `onMessage` receives Sendable values there.
final class EventServer: Sendable {
    private static let readTimeout: DispatchTimeInterval = .seconds(2)
    /// Most ordinary (non-held) connections in flight; extra ones are cancelled at once, which Claude Code treats
    /// as a silent, non-blocking hook failure. Bursts of dozens of hooks otherwise leave the allocator holding
    /// per-connection buffers (docs/08).
    private static let maxInFlight = 16
    private static let logger = Logger(subsystem: "dev.clawdisland", category: "server")

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.clawdisland.server")
    private let token: String
    private let holdPermissions: @Sendable () -> Bool
    private let onMessage: @Sendable (Inbound) -> Void
    private let onPermission: @Sendable (ClawdEvent, PermissionResponder) -> Void
    private let onPermissionClosed: @Sendable (UUID) -> Void
    /// Non-held connections in flight. Only touched on `queue`.
    nonisolated(unsafe) private var inFlight = Set<ObjectIdentifier>()

    /// - Parameters:
    ///   - holdPermissions: Asked per request, so toggling "approve from the notch" needs no restart.
    ///   - onMessage: Called on the server queue for every decoded message.
    ///   - onPermission: Called on the server queue for a held `PermissionRequest`, instead of `onMessage`.
    ///     The receiver must eventually call `reply` on the responder (it may do so from any thread).
    ///   - onPermissionClosed: Called on the server queue with the responder's id when the hook's client hung up
    ///     while it was held (Claude Code timed out or exited); the responder is already finished.
    ///   - onFailure: Called on the server queue when the port cannot be bound (for example, it is busy).
    ///     The server never moves to another port, because hooks are written with a fixed URL.
    init(
        config: AppConfig,
        holdPermissions: @escaping @Sendable () -> Bool,
        onMessage: @escaping @Sendable (Inbound) -> Void,
        onPermission: @escaping @Sendable (ClawdEvent, PermissionResponder) -> Void,
        onPermissionClosed: @escaping @Sendable (UUID) -> Void,
        onFailure: @escaping @Sendable (NWError) -> Void
    ) throws {
        guard let raw = UInt16(exactly: config.port), raw > 0, let port = NWEndpoint.Port(rawValue: raw) else {
            throw NWError.posix(.EINVAL)
        }
        let parameters = NWParameters.tcp
        // We close first, so each request leaves a TIME_WAIT; without reuse a quick relaunch fails to bind.
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        listener = try NWListener(using: parameters)
        token = config.token
        self.holdPermissions = holdPermissions
        self.onMessage = onMessage
        self.onPermission = onPermission
        self.onPermissionClosed = onPermissionClosed
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .failed(let error), .waiting(let error):
                Self.logger.error("listener on port \(config.port) failed: \(error.localizedDescription, privacy: .public)")
                listener.cancel()
                onFailure(error)
            case .ready:
                Self.logger.info("listening on 127.0.0.1:\(config.port)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
    }

    func start() {
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        guard inFlight.count < Self.maxInFlight else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        inFlight.insert(id)
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.inFlight.remove(id) }
        }
        connection.start(queue: queue)
        // Slow or stalled clients are cut off; cancelling an already finished connection is a no-op.
        // Held permission requests cancel this item, otherwise it would kill them after 2 s.
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + Self.readTimeout, execute: timeout)
        readHead(connection, timeout: timeout, buffer: Data())
    }

    private func readHead(_ connection: NWConnection, timeout: DispatchWorkItem, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: HTTPRequestHead.terminator) else {
                if buffer.count > HTTPRequestHead.maxHeadBytes { return reply(431, on: connection) }
                if isComplete || error != nil { return connection.cancel() }
                return readHead(connection, timeout: timeout, buffer: buffer)
            }
            if end.lowerBound > HTTPRequestHead.maxHeadBytes { return reply(431, on: connection) }
            guard let head = HTTPRequestHead(buffer[..<end.lowerBound]) else { return reply(400, on: connection) }
            switch head.verdict(token: token) {
            case .reject(let status):
                reply(status, on: connection)
            case .readBody(let endpoint, let length):
                readBody(connection, timeout: timeout, endpoint: endpoint, length: length,
                         buffer: Data(buffer[end.upperBound...]))
            }
        }
    }

    private func readBody(
        _ connection: NWConnection, timeout: DispatchWorkItem, endpoint: EventEndpoint, length: Int, buffer: Data
    ) {
        guard buffer.count < length else {
            let message = endpoint.decode(buffer.prefix(length), receivedAt: .now)
            if holdPermissions(), case .event(let event)? = message, event.kind == .permissionRequest {
                return hold(connection, timeout: timeout, event: event)
            }
            if let message { onMessage(message) }
            return reply(200, on: connection)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: length - buffer.count) { [self] data, _, isComplete, error in
            guard let data, error == nil, !(isComplete && data.isEmpty) else { return connection.cancel() }
            readBody(connection, timeout: timeout, endpoint: endpoint, length: length, buffer: buffer + data)
        }
    }

    /// Keeps the connection open until the responder is used, or the client hangs up.
    private func hold(_ connection: NWConnection, timeout: DispatchWorkItem, event: ClawdEvent) {
        timeout.cancel()
        inFlight.remove(ObjectIdentifier(connection)) // held requests are never counted or dropped
        let responder = PermissionResponder { [self] decision in
            queue.async { self.reply(200, body: decision.body, on: connection) }
        }
        onPermission(event, responder)
        watchForClose(connection, responder: responder)
    }

    /// A hook client sends nothing after its request, so any receive completion means it went away.
    // shortcut: a client that only half-closes its side is treated as gone too; Claude Code's hook client does not.
    private func watchForClose(_ connection: NWConnection, responder: PermissionResponder) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [self] _, _, isComplete, error in
            if error != nil || isComplete {
                responder.reply(.none)
                connection.cancel()
                onPermissionClosed(responder.id)
            } else {
                watchForClose(connection, responder: responder)
            }
        }
    }

    /// Sends a reply and closes. The body is empty except for a permission decision, so no other hook output
    /// can be read as one.
    private func reply(_ status: Int, body: Data = Data(), on connection: NWConnection) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                      413: "Content Too Large", 431: "Request Header Fields Too Large"][status] ?? ""
        let type = body.isEmpty ? "" : "Content-Type: application/json\r\n"
        let head = "HTTP/1.1 \(status) \(reason)\r\n\(type)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
