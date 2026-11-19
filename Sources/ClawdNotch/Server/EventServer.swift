// EventServer.swift
// Loopback HTTP endpoint that receives Claude Code hooks, bridge metadata and statusline payloads (docs/05).

import ClawdCore
import Foundation
import Network
import os

/// An `NWListener` on `127.0.0.1:<port>` that accepts `POST /hook`, `/session-meta` and `/statusline`.
/// Every connection is handled on its own and closed after one empty reply, so nothing assumes requests
/// finish immediately (a long-lived `/permission` endpoint stays possible, REQ-V2-01).
/// Decoding runs on the server's serial queue; `onMessage` receives Sendable values there.
final class EventServer: Sendable {
    private static let readTimeout: DispatchTimeInterval = .seconds(2)
    private static let logger = Logger(subsystem: "dev.clawdnotch", category: "server")

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.clawdnotch.server")
    private let token: String
    private let onMessage: @Sendable (Inbound) -> Void

    /// - Parameters:
    ///   - onMessage: Called on the server queue for every decoded message.
    ///   - onFailure: Called on the server queue when the port cannot be bound (for example, it is busy).
    ///     The server never moves to another port, because hooks are written with a fixed URL.
    init(
        config: AppConfig,
        onMessage: @escaping @Sendable (Inbound) -> Void,
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
        self.onMessage = onMessage
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
        connection.start(queue: queue)
        // Slow or stalled clients are cut off; cancelling an already finished connection is a no-op.
        queue.asyncAfter(deadline: .now() + Self.readTimeout) { connection.cancel() }
        readHead(connection, buffer: Data())
    }

    private func readHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: HTTPRequestHead.terminator) else {
                if buffer.count > HTTPRequestHead.maxHeadBytes { return reply(431, on: connection) }
                if isComplete || error != nil { return connection.cancel() }
                return readHead(connection, buffer: buffer)
            }
            if end.lowerBound > HTTPRequestHead.maxHeadBytes { return reply(431, on: connection) }
            guard let head = HTTPRequestHead(buffer[..<end.lowerBound]) else { return reply(400, on: connection) }
            switch head.verdict(token: token) {
            case .reject(let status):
                reply(status, on: connection)
            case .readBody(let endpoint, let length):
                readBody(connection, endpoint: endpoint, length: length, buffer: Data(buffer[end.upperBound...]))
            }
        }
    }

    private func readBody(_ connection: NWConnection, endpoint: EventEndpoint, length: Int, buffer: Data) {
        guard buffer.count < length else {
            if let message = endpoint.decode(buffer.prefix(length), receivedAt: .now) { onMessage(message) }
            return reply(200, on: connection)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: length - buffer.count) { [self] data, _, isComplete, error in
            guard let data, error == nil, !(isComplete && data.isEmpty) else { return connection.cancel() }
            readBody(connection, endpoint: endpoint, length: length, buffer: buffer + data)
        }
    }

    /// Sends an empty reply and closes; the body is always empty so no hook output is read as a decision.
    private func reply(_ status: Int, on connection: NWConnection) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                      413: "Content Too Large", 431: "Request Header Fields Too Large"][status] ?? ""
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}
