import XCTest
@testable import RCF

/// Command palette: fuzzy matcher + sectioning.
final class PaletteEngineTests: XCTestCase {
    func testFuzzyMatchBasics() {
        XCTAssertNotNil(PaletteEngine.score(query: "exm", title: "example.com"))
        XCTAssertNil(PaletteEngine.score(query: "xyz", title: "example.com"))
        XCTAssertNil(PaletteEngine.score(query: "exx", title: "example.com"))
    }

    func testEmptyQueryMatchesEverythingWithNeutralScore() {
        XCTAssertEqual(PaletteEngine.score(query: "", title: "anything"), 0)
    }

    func testWordStartBeatsInterior() {
        // 'e' hits the title's word start; 'x' is an interior char.
        let wordStart = PaletteEngine.score(query: "e", title: "example.com")!
        let interior = PaletteEngine.score(query: "x", title: "example.com")!
        XCTAssertGreaterThan(wordStart, interior)
    }

    @MainActor
    func testSectionOrderingCommandsFirst() {
        let command = PaletteItem(id: "c1", kind: .command, title: "Purge", subtitle: nil, icon: "trash") {}
        let zone = PaletteItem(id: "z1", kind: .zone, title: "example.com", subtitle: nil, icon: "globe") {}
        let sections = PaletteEngine.sections(
            query: "", commands: [command], zones: [zone], records: [], workers: []
        )
        XCTAssertEqual(sections.map(\.id), ["commands", "zones"])
    }

    @MainActor
    func testNonMatchingItemsFiltered() {
        let zone = PaletteItem(id: "z1", kind: .zone, title: "example.com", subtitle: nil, icon: "globe") {}
        let sections = PaletteEngine.sections(
            query: "zzz", commands: [], zones: [zone], records: [], workers: []
        )
        XCTAssertTrue(sections.isEmpty)
    }
}
