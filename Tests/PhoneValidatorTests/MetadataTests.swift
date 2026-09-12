//
//  MetadataTests.swift
//  PhoneValidator
//
//  Proves the generated metadata survives the trip into the bundle intact,
//  and that ICU agrees with the generator about every pattern in it.
//

import XCTest
@testable import PhoneValidator

final class MetadataTests: XCTestCase {

    func testMetadataLoadsFromBundle() throws {
        let m = try MetadataStore.metadata()
        XCTAssertFalse(m.sourceRelease.isEmpty)
        XCTAssertFalse(m.generated.isEmpty)
    }

    /// libphonenumber v9.0.39 ships 254 `<territory>` elements: 245 geographic
    /// regions and nine sharing the id `001`. If this fails after a metadata
    /// bump the counts moved, which is information, not a defect — read the
    /// diff and update the numbers deliberately.
    func testEveryTerritoryIsAccountedFor() throws {
        let m = try MetadataStore.metadata()
        XCTAssertEqual(m.regions.count, 245)
        XCTAssertEqual(m.nonGeographical.count, 9)
        XCTAssertEqual(m.regions.count + m.nonGeographical.count, 254)
    }

    /// The nine non-geographical codes all carry region id `001`, so keying on
    /// that id keeps one and drops eight. This asserts they are all still here.
    func testNonGeographicalCodesAreNotCollapsed() throws {
        let m = try MetadataStore.metadata()
        for code in ["800", "808", "870", "878", "881", "882", "883", "888", "979"] {
            XCTAssertNotNil(m.nonGeographical[code], "lost non-geographical +\(code)")
        }
        // +870 is Inmarsat: it has a mobile type, unlike +800 freephone.
        XCTAssertNotNil(m.nonGeographical["870"]?.types["mobile"])
        XCTAssertNotNil(m.nonGeographical["800"]?.types["tollFree"])
    }

    func testGreatBritainDecodesFully() throws {
        let gb = try XCTUnwrap(MetadataStore.region("GB"))
        XCTAssertEqual(gb.callingCode, "44")
        XCTAssertTrue(gb.isMainCountry)
        XCTAssertEqual(gb.nationalPrefix, "0")
        // NOT the same string as nationalPrefix — this is the one people assume.
        XCTAssertEqual(gb.nationalPrefixForParsing, "0|180020")
        XCTAssertTrue(gb.isMobilePortable)
        XCTAssertEqual(gb.types["mobile"]?.example, "7400123456")
        XCTAssertFalse(gb.formats.isEmpty)
    }

    /// Several regions share +44; GB owns it and must be offered first.
    func testSharedCallingCodePutsMainCountryFirst() throws {
        let regions = try MetadataStore.regions(forCallingCode: "44")
        XCTAssertEqual(regions.first, "GB")
        XCTAssertTrue(regions.contains("JE"))
        let northAmerica = try MetadataStore.regions(forCallingCode: "1")
        XCTAssertEqual(northAmerica.first, "US")
        XCTAssertTrue(northAmerica.contains("CA"))
    }

    /// The one that proves the whole metadata road.
    ///
    /// The generator verifies every pattern against its own example with
    /// Python's `re` before it will write the file. Swift matches with ICU,
    /// and the two engines do NOT have to agree — so this runs the same 1,144
    /// checks again on the other side of the bundle. It is also what catches
    /// the whitespace trap: the XML pretty-prints patterns, and leaving that
    /// formatting in drops this from 1144/1144 to 488/1144.
    func testEveryExampleMatchesItsOwnPatternUnderICU() throws {
        let m = try MetadataStore.metadata()
        var checked = 0
        var failures: [String] = []

        for (name, region) in m.regions.merging(
            m.nonGeographical.map { ("+\($0.key)", $0.value) },
            uniquingKeysWith: { a, _ in a }
        ) {
            for (kind, type) in region.types {
                guard let example = type.example else { continue }
                checked += 1
                let regex = try NSRegularExpression(pattern: "^(?:\(type.pattern))$")
                let range = NSRange(example.startIndex..., in: example)
                if regex.firstMatch(in: example, range: range) == nil {
                    failures.append("\(name)/\(kind): \(example)")
                }
            }
        }

        XCTAssertEqual(checked, 1144, "example count moved with the metadata")
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) of \(checked) failed under ICU: \(failures.prefix(5))")
    }
}
