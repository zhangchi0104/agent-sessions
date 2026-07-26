//
//  LoopbackAuthListener.swift
//  TokenStats
//
//  A short-lived localhost HTTP listener for Codex's loopback OAuth redirect
//  (see docs/codex-integration.md). It binds a port, hands it to the caller so
//  the authorize URL's redirect_uri matches, then resolves the `code`/`state`
//  from the single GET /auth/callback request the browser makes.
//
//  Unverified end-to-end: completing it requires a real ChatGPT approval in the
//  browser. The HTTP parsing and lifecycle are covered by unit tests via the
//  pure `parseCallback` helper.
//

import Foundation
import Network

final class LoopbackAuthListener {
    struct Callback: Equatable { let code: String; let state: String }

    enum ListenerError: Error, LocalizedError {
        case noPort, badRequest, closed, timedOut
        case authorization(String)

        var errorDescription: String? {
            switch self {
            case .noPort: return "Could not open a local port for sign-in."
            case .badRequest: return "The sign-in redirect was malformed."
            case .closed: return "Sign-in was cancelled."
            case .timedOut: return "Sign-in timed out. Approve in the browser, then try again."
            case .authorization(let message): return message
            }
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.otakuma.TokenStats.codex.loopback")
    private let lock = NSLock()
    private var codeContinuation: CheckedContinuation<Callback, Error>?
    private var pending: Result<Callback, Error>?
    private var connection: NWConnection?
    private let timeout: TimeInterval
    private var timeoutWorkItem: DispatchWorkItem?
    private var didTimeout = false

    init(timeout: TimeInterval = 300) throws {
        self.timeout = timeout
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Prefer the CLI's port for redirect-URI compatibility; otherwise let
        // the OS pick an ephemeral port (RFC 8252 loopback redirect).
        if let onPreferred = try? NWListener(using: params, on: 1455) {
            listener = onPreferred
        } else {
            listener = try NWListener(using: params)
        }
    }

    /// Start listening and resolve the bound port once ready.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    if let port = self.listener.port?.rawValue {
                        resumed = true
                        cont.resume(returning: port)
                    } else {
                        resumed = true
                        cont.resume(throwing: ListenerError.noPort)
                    }
                case .failed(let error):
                    resumed = true
                    cont.resume(throwing: error)
                case .waiting(let error):
                    // Port unavailable (e.g. a prior sign-in still holds 1455).
                    // Fail fast with the reason instead of hanging the login.
                    resumed = true
                    cont.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: self.didTimeout ? ListenerError.timedOut : ListenerError.closed)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(on: connection)
            }
            listener.start(queue: queue)
            armTimeout()
        }
    }

    /// Bound the whole flow so an abandoned browser approval can't hang the
    /// login Task (and pin the port) forever.
    private func armTimeout() {
        let workItem = DispatchWorkItem { [weak self] in self?.fireTimeout() }
        timeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func fireTimeout() {
        didTimeout = true
        deliver(.failure(ListenerError.timedOut))
    }

    /// Await the browser's redirect, yielding the authorization code and state.
    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let pending {
                lock.unlock()
                cont.resume(with: pending)
            } else {
                codeContinuation = cont
                lock.unlock()
            }
        }
    }

    func cancel() {
        listener.cancel()
        connection?.cancel()
        deliver(.failure(ListenerError.closed))
    }

    private func receive(on connection: NWConnection) {
        self.connection = connection
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.deliver(.failure(error))
                return
            }
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            guard let callback = Self.parseCallback(httpRequest: requestLine) else {
                self.respond(connection, html: Self.failureHTML)
                // Distinguish a provider error redirect (?error=access_denied…)
                // from a malformed request so the user sees the real reason.
                if let message = Self.parseError(httpRequest: requestLine) {
                    self.deliver(.failure(ListenerError.authorization(message)))
                } else {
                    self.deliver(.failure(ListenerError.badRequest))
                }
                return
            }
            self.respond(connection, html: Self.successHTML)
            self.deliver(.success(callback))
        }
    }

    private func respond(_ connection: NWConnection, html: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func deliver(_ result: Result<Callback, Error>) {
        timeoutWorkItem?.cancel()
        lock.lock()
        if let cont = codeContinuation {
            codeContinuation = nil
            lock.unlock()
            cont.resume(with: result)
        } else if pending == nil {
            pending = result
            lock.unlock()
        } else {
            lock.unlock()
        }
        listener.cancel()
    }

    /// Pure: pull `code` and `state` out of the HTTP request's start line
    /// (`GET /auth/callback?code=…&state=… HTTP/1.1`).
    static func parseCallback(httpRequest: String) -> Callback? {
        guard let firstLine = httpRequest.split(separator: "\r\n", maxSplits: 1).first
            ?? httpRequest.split(separator: "\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(path)"),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              !code.isEmpty
        else { return nil }
        return Callback(code: code, state: state)
    }

    /// Pure: pull an OAuth `error` (and optional `error_description`) out of an
    /// error redirect so a denied/failed approval reports the real reason
    /// rather than a generic "no authorization code" message.
    static func parseError(httpRequest: String) -> String? {
        guard let firstLine = httpRequest.split(separator: "\r\n", maxSplits: 1).first
            ?? httpRequest.split(separator: "\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost\(String(parts[1]))"),
              let error = components.queryItems?.first(where: { $0.name == "error" })?.value
        else { return nil }
        let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value
        return description.map { "\(error): \($0)" } ?? error
    }

    private static let successHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>TokenStats</title></head>
    <body style="font-family:-apple-system,sans-serif;text-align:center;padding:3rem">
    <h2>Signed in to Codex</h2><p>You can close this tab and return to TokenStats.</p></body></html>
    """

    private static let failureHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>TokenStats</title></head>
    <body style="font-family:-apple-system,sans-serif;text-align:center;padding:3rem">
    <h2>Sign-in failed</h2><p>No authorization code was found. Return to TokenStats and try again.</p></body></html>
    """
}
