import XCTest
@testable import RCF

final class DNSModelTests: XCTestCase {
    func testUnknownRecordTypeAndMissingMetadataDecodeWithoutFailingList() throws {
        let response = """
        {"success":true,"errors":[],"messages":[],"result":[
          {"id":"r1","type":"OPENPGPKEY","name":"user.example.com","content":"encoded-value"}
        ]}
        """
        let envelope = try JSONDecoder().decode(CloudflareResponse<[DNSRecord]>.self, from: Data(response.utf8))
        let record = try XCTUnwrap(envelope.result?.first)
        XCTAssertEqual(record.type, .unknown)
        XCTAssertEqual(record.name, "user.example.com")
        XCTAssertEqual(record.ttl, 1)
        XCTAssertFalse(record.proxiable)
        XCTAssertFalse(record.locked)
    }

    func testKnownRecordTypesRemainAvailableForEditors() {
        XCTAssertTrue(DNSRecordType.allCases.contains(.a))
        XCTAssertTrue(DNSRecordType.allCases.contains(.https))
        XCTAssertFalse(DNSRecordType.allCases.contains(.unknown))
    }
}
