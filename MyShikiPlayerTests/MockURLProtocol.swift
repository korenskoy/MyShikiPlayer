//
//  MockURLProtocol.swift
//  MyShikiPlayerTests
//

import Foundation

/// Stub URL loader for tests.
///
/// Handlers are scoped to the session that issues the request: `MockURLSession.make()` stamps
/// every request from its session with a unique token, and `startLoading` resolves the handler
/// by that token. Suites running in parallel therefore cannot overwrite each other's stubs.
/// A single shared handler could not give that guarantee — `.serialized` only orders the tests
/// inside one suite, not across suites, and not across the XCTest/Swift Testing split.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    /// Handlers routinely capture mutable locals to record what was requested, so this stays
    /// deliberately non-`@Sendable`; the lock below is what makes the storage itself safe.
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Injected into every request by `MockURLSession.make()`. Tests never set it themselves.
    static let sessionTokenHeader = "X-MSHP-Mock-Session"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlersByToken: [String: Handler] = [:]

    // MARK: - Per-session handlers

    static func sessionHandler(for token: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlersByToken[token]
    }

    static func setSessionHandler(_ handler: Handler?, for token: String) {
        lock.lock()
        defer { lock.unlock() }
        handlersByToken[token] = handler
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.resolveHandler(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(Self.withMaterialisedBody(request))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession converts a request body into `httpBodyStream` before the request reaches a
    /// URLProtocol, so `httpBody` is nil here no matter how the caller built the request.
    /// Handlers assert on the body both ways, so hand them one that carries it in the obvious
    /// place — otherwise a body assertion silently reads an empty string and never fires.
    private static func withMaterialisedBody(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, request.httpBodyStream != nil else { return request }
        var materialised = request
        materialised.httpBody = request.mshpInterceptedBody()
        return materialised
    }

    /// A session is the only thing that can own a stub — there is no global slot to fall back
    /// to, so an unstubbed session fails its requests instead of quietly picking up whatever
    /// another suite happened to install.
    private static func resolveHandler(for request: URLRequest) -> Handler? {
        guard let token = request.value(forHTTPHeaderField: sessionTokenHeader) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return handlersByToken[token]
    }
}

enum MockURLSession {
    /// Session whose requests are served by `handler` and nothing else. Preferred form: the
    /// stub is bound to this one session, so no other suite can observe or replace it.
    static func make(handler: @escaping MockURLProtocol.Handler) -> URLSession {
        let session = make()
        session.mshpMockHandler = handler
        return session
    }

    /// Session with no stub yet — assign `session.mshpMockHandler` before issuing requests.
    /// Use this when the handler has to change between tests sharing one session.
    static func make() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [MockURLProtocol.sessionTokenHeader: UUID().uuidString]
        return URLSession(configuration: config)
    }
}

extension URLSession {
    /// Stub serving this session's requests; assigning nil removes it.
    var mshpMockHandler: MockURLProtocol.Handler? {
        get {
            guard let token = mshpMockSessionToken else { return nil }
            return MockURLProtocol.sessionHandler(for: token)
        }
        set {
            guard let token = mshpMockSessionToken else {
                preconditionFailure("mshpMockHandler requires a session built by MockURLSession.make()")
            }
            MockURLProtocol.setSessionHandler(newValue, for: token)
        }
    }

    private var mshpMockSessionToken: String? {
        configuration.httpAdditionalHeaders?[MockURLProtocol.sessionTokenHeader] as? String
    }
}

extension URLRequest {
    /// Reads the POST/PATCH body from either `httpBody` (small synchronous
    /// case) or `httpBodyStream` (URLSession converts large bodies into a
    /// stream before they reach a URLProtocol subclass — when that happens,
    /// `httpBody` is nil even though the body content is non-empty). Tests
    /// asserting on JSON bodies need to read both.
    func mshpInterceptedBody() -> Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }
        var data = Data()
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
