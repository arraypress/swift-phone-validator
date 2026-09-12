//
//  GroundTruthTests.swift
//  PhoneValidator
//
//  The metadata ships an exampleNumber for every type in every region: 1,132
//  real numbers with a known country and a known type, free, inside the source
//  data. It is the only honest way to find out whether the parser works.
//
//  Examples are given in NATIONAL form, so they are parsed that way — which
//  also exercises trunk-prefix stripping. Concatenating "+" + callingCode +
//  example instead looks equivalent and is not: Canada's UAN example is the
//  seven-digit 310-1234, which is a real national number and not a dialable
//  international one, so that construction manufactures a number that should
//  fail and then blames the parser for failing it.
//

import XCTest
@testable import PhoneValidator

final class GroundTruthTests: XCTestCase {

    /// Every example, read in its own region, must come back valid, with the
    /// right calling code and the type it was filed under.
    func testEveryExampleParsesInItsOwnRegion() throws {
        let m = try MetadataStore.metadata()
        var checked = 0
        var notValid: [String] = []
        var wrongCode: [String] = []
        var wrongType: [String] = []

        for (code, region) in m.regions {
            for (kind, desc) in region.types {
                guard let example = desc.example,
                      let expected = PhoneNumberType(rawValue: kind) else { continue }
                checked += 1

                guard let parsed = try? PhoneNumberParser.parse(example, defaultRegion: code) else {
                    notValid.append("\(code)/\(kind): \(example) THREW"); continue
                }
                if !parsed.isValid { notValid.append("\(code)/\(kind): \(example)") }
                if parsed.callingCode != region.callingCode {
                    wrongCode.append("\(code)/\(kind): +\(parsed.callingCode)")
                }
                // fixedLineOrMobile is correct whenever a number satisfies both
                // patterns, so it stands in for either.
                let acceptable = parsed.type == expected
                    || (parsed.type == .fixedLineOrMobile && (expected == .fixedLine || expected == .mobile))
                if !acceptable { wrongType.append("\(code)/\(kind) -> \(parsed.type.rawValue)") }
            }
        }

        print("NATIONAL: \(checked) examples | invalid \(notValid.count) | "
              + "wrong code \(wrongCode.count) | wrong type \(wrongType.count)")
        if !notValid.isEmpty { print("  invalid:", notValid.prefix(8)) }
        if !wrongCode.isEmpty { print("  code:", wrongCode.prefix(8)) }
        if !wrongType.isEmpty { print("  type:", wrongType.prefix(8)) }

        XCTAssertEqual(checked, 1132, "example count moved with the metadata")
        XCTAssertTrue(notValid.isEmpty, "\(notValid.count) real example numbers reported invalid")
        XCTAssertTrue(wrongCode.isEmpty, "\(wrongCode.count) got the wrong calling code")
        XCTAssertTrue(wrongType.isEmpty,
                      "\(wrongType.count) resolved to the wrong type: \(wrongType.prefix(8))")
    }

    /// Re-parsing a number's own E.164 output must give the same number back.
    ///
    /// This is the property that matters for storing numbers: parse, save the
    /// E.164, read it back later with no region context, get the same answer.
    /// It is also what would catch the trunk prefix being stripped twice, or a
    /// transform rule being applied on the way back in.
    func testE164OutputIsIdempotent() throws {
        let m = try MetadataStore.metadata()
        var checked = 0
        var drifted: [String] = []

        for (code, region) in m.regions {
            for (_, desc) in region.types {
                guard let example = desc.example,
                      let first = try? PhoneNumberParser.parse(example, defaultRegion: code),
                      first.isValid else { continue }
                checked += 1
                guard let second = try? PhoneNumberParser.parse(first.e164) else {
                    drifted.append("\(code): \(first.e164) THREW on re-parse"); continue
                }
                if second.e164 != first.e164 {
                    drifted.append("\(code): \(first.e164) -> \(second.e164)")
                }
                if second.type != first.type {
                    drifted.append("\(code): \(first.e164) type \(first.type.rawValue) -> \(second.type.rawValue)")
                }
            }
        }

        print("IDEMPOTENT: \(checked) numbers | \(drifted.count) drifted")
        if !drifted.isEmpty { print("  ", drifted.prefix(8)) }
        XCTAssertTrue(drifted.isEmpty, "\(drifted.count) numbers changed on re-parse")
    }
}
