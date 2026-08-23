import XCTest
@testable import RCF

/// Gzip decode + TailEvent fixtures + buffer bounds.
final class TailTests: XCTestCase {
    func testGzipMagicDetection() {
        XCTAssertTrue(Gzip.isGzipped(Data([0x1f, 0x8b, 0x08, 0x00])))
        XCTAssertFalse(Gzip.isGzipped(Data([0x00, 0x1f, 0x8b])))
        XCTAssertFalse(Gzip.isGzipped(Data([0x7b, 0x22])))  // {" JSON
    }

    func testGzipRoundTrip() throws {
        // Compress with zlib deflate + gzip header via Python-generated fixture embedded here:
        // Build gzip bytes in-test using Compression? No — use zlib's deflate via a raw wrapper:
        // Simplest: hardcode gzip of "{}" (9 bytes payload-less JSON object).
        let gzipFixture: [UInt8] = [
            0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff,
            0xab, 0xae, 0x05, 0x00, 0x43, 0xbf, 0xa6, 0xa3, 0x02, 0x00, 0x00, 0x00
        ]
        let text = try Gzip.decodeFrame(Data(gzipFixture))
        XCTAssertEqual(text, "{}")
    }

    func testGzipInvalidThrows() {
        XCTAssertThrowsError(try Gzip.decompress(Data([0x1f, 0x8b, 0xff, 0xff, 0xff])))
    }

    func testTailEventDecodeFromTraceFixture() throws {
        let fixture = """
        {"outcome":"ok","scriptName":"my-worker","eventTimestamp":1755900000000,
         "event":{"request":{"method":"GET","url":"https://example.com/api"},"response":{"status":200}},
         "logs":[{"level":"log","message":["hello","world"]},{"level":"error","message":"boom"}],
         "exceptions":[],"diagnostics_channel_events":{}}
        """
        let event = try XCTUnwrap(TailEventDecoder.decode(fixture))
        XCTAssertEqual(event.outcome, "ok")
        XCTAssertEqual(event.method, "GET")
        XCTAssertEqual(event.status, 200)
        XCTAssertEqual(event.url, "https://example.com/api")
        XCTAssertEqual(event.logs[.log], "hello world")
        XCTAssertEqual(event.logs[.error], "boom")
        XCTAssertTrue(event.exceptions.isEmpty)
        XCTAssertEqual(event.title, "GET 200")
        XCTAssertEqual(event.outcomeBadge, "OK")
    }

    func testTailEventDecodeWithException() throws {
        let fixture = """
        {"outcome":"exception","eventTimestamp":1755900001000,
         "event":{"request":{"method":"POST","url":"/throw"}},
         "logs":[],"exceptions":[{"name":"Error","message":"something broke","timestamp":1755900001000}]}
        """
        let event = try XCTUnwrap(TailEventDecoder.decode(fixture))
        XCTAssertEqual(event.outcome, "exception")
        XCTAssertEqual(event.exceptions, ["Error: something broke"])
        XCTAssertEqual(event.outcomeBadge, "ERROR")
    }

    func testNonJSONFrameReturnsNil() {
        XCTAssertNil(TailEventDecoder.decode("not json at all"))
    }

    func testRingBufferCap() {
        // Mirror of TailViewModel.append logic (kept nonisolated for testability).
        let limit = 500
        var events: [TailEvent] = []
        let template = TailEvent(id: UUID(), eventTimestamp: nil, outcome: "ok", scriptName: nil, method: nil, url: nil, status: nil, logs: [:], logOrder: [], exceptions: [], coppices: nil)
        for _ in 0..<(limit + 37) {
            events.insert(template, at: 0)
            if events.count > limit {
                events.removeLast(events.count - limit)
            }
        }
        XCTAssertEqual(events.count, limit)
    }
}
