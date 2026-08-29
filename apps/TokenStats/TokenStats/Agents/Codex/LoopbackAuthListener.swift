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
            localizedDescription(using: AppLocalizer(locale: .current))
        }

        func localizedDescription(using localizer: AppLocalizer) -> String {
            switch self {
            case .noPort:
                return localizer.localized(
                    LocalizedStringResource.accountSignInErrorLocalPort
                )
            case .badRequest:
                return localizer.localized(
                    LocalizedStringResource.accountSignInErrorMalformedRedirect
                )
            case .closed:
                return localizer.localized(
                    LocalizedStringResource.accountSignInErrorCancelled
                )
            case .timedOut:
                return localizer.localized(
                    LocalizedStringResource.accountSignInErrorTimedOut
                )
            case .authorization(let message):
                return localizer.localized(
                    LocalizedStringResource.accountSignInErrorAuthorization(message)
                )
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
    private let localizer: AppLocalizer

    init(
        timeout: TimeInterval = 300,
        localizer: AppLocalizer = AppLocalizer(locale: .current)
    ) throws {
        self.timeout = timeout
        self.localizer = localizer
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
                self.respond(
                    connection,
                    html: Self.callbackHTML(succeeded: false, localizer: self.localizer)
                )
                // Distinguish a provider error redirect (?error=access_denied…)
                // from a malformed request so the user sees the real reason.
                if let message = Self.parseError(httpRequest: requestLine) {
                    self.deliver(.failure(ListenerError.authorization(message)))
                } else {
                    self.deliver(.failure(ListenerError.badRequest))
                }
                return
            }
            self.respond(
                connection,
                html: Self.callbackHTML(succeeded: true, localizer: self.localizer)
            )
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

    /// Pure: reduce an OAuth error redirect to a known protocol code. The
    /// provider-controlled `error_description` is deliberately ignored: it is
    /// an untrusted raw authentication response and may contain account detail
    /// or other sensitive text that must not reach diagnostics.
    static func parseError(httpRequest: String) -> String? {
        guard let firstLine = httpRequest.split(separator: "\r\n", maxSplits: 1).first
            ?? httpRequest.split(separator: "\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://localhost\(String(parts[1]))"),
              let rawError = components.queryItems?.first(where: { $0.name == "error" })?.value
        else { return nil }
        let normalized = rawError
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let knownCodes: Set<String> = [
            "access_denied",
            "account_selection_required",
            "consent_required",
            "interaction_required",
            "invalid_request",
            "invalid_request_object",
            "invalid_request_uri",
            "invalid_scope",
            "login_required",
            "request_not_supported",
            "request_uri_not_supported",
            "server_error",
            "temporarily_unavailable",
            "unauthorized_client",
            "unsupported_response_type",
        ]
        return knownCodes.contains(normalized) ? normalized : "unknown_error"
    }

    static func callbackHTML(succeeded: Bool, localizer: AppLocalizer) -> String {
        let heading: String
        let body: String
        if succeeded {
            heading = localizer.localized(
                LocalizedStringResource.accountSignInCallbackSuccessHeading
            )
            body = localizer.localized(
                LocalizedStringResource.accountSignInCallbackSuccessBody
            )
        } else {
            heading = localizer.localized(
                LocalizedStringResource.accountSignInCallbackFailureHeading
            )
            body = localizer.localized(
                LocalizedStringResource.accountSignInCallbackFailureBody
            )
        }
        return """
        <!doctype html><html lang="\(htmlEscaped(localizer.htmlLanguageTag))"><head><meta charset="utf-8"><title>TokenStats</title></head>
        <body style="font-family:-apple-system,sans-serif;text-align:center;padding:3rem">
        <h2>\(htmlEscaped(heading))</h2><p>\(htmlEscaped(body))</p></body></html>
        """
    }

    private static func htmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
