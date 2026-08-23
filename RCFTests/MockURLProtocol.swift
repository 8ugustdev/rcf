import Foundation
import XCTest
@testable import RCF

/// URLProtocol mock capturing requests and replaying canned responses.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var data: Data
    }

    nonisolated(unsafe) static var stubs: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        stubs = []
        requests = []
    }

    static func enqueue(_ stub: Stub) {
        lock.lock(); defer { lock.unlock() }
        stubs.append(stub)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        var captured = request
        normalizeBody(of: &captured)
        Self.requests.append(captured)
        let stub = Self.stubs.isEmpty ? Stub(data: Data("{}".utf8)) : Self.stubs.removeFirst()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: captured.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLSession moves httpBody into httpBodyStream; drain it back so tests can read httpBody.
    private func normalizeBody(of request: inout URLRequest) {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return }
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        request.httpBody = data
    }

    override func stopLoading() {}
}
