//
//  BehaviourTests.swift
//  PhoneValidator
//
//  The numbers people actually paste, and the errors they should get back.
//

import XCTest
@testable import PhoneValidator

final class BehaviourTests: XCTestCase {

    /// Every spelling of one UK mobile has to land on the same E.164 string.
    func testUKMobileNormalisesFromEverySpelling() throws {
        // 07400 123456 is the metadata's own GB mobile example. NOT 07700
        // 900123: see testOfcomDramaRangesAreAsymmetric.
        let expected = "+447400123456"
        let spellings = [
            "+447400123456",
            "+44 7400 123456",
            "+44 (0) 7400 123456",
            "07400123456",
            "07400 123456",
            "(07400) 123-456",
            "07400.123.456",
            "0044 7400 123456"
        ]
        for spelling in spellings {
            let parsed = try PhoneNumberParser.parse(spelling, defaultRegion: "GB")
            XCTAssertEqual(parsed.e164, expected, "\(spelling) normalised to \(parsed.e164)")
            XCTAssertEqual(parsed.region, "GB")
            XCTAssertEqual(parsed.type, .mobile)
            XCTAssertTrue(parsed.isValid)
        }
    }

    /// An international number ignores the default region rather than being
    /// bent to fit it.
    func testInternationalFormIgnoresDefaultRegion() throws {
        let parsed = try PhoneNumberParser.parse("+33612345678", defaultRegion: "GB")
        XCTAssertEqual(parsed.callingCode, "33")
        XCTAssertEqual(parsed.region, "FR")
    }

    /// The failure everyone hits first: a national number with no region.
    func testNationalFormWithoutRegionSaysSo() {
        XCTAssertThrowsError(try PhoneNumberParser.parse("07400123456")) { error in
            XCTAssertEqual(error as? PhoneParseError, .regionRequired)
        }
    }

    func testGarbageIsRejectedWithAReason() {
        XCTAssertThrowsError(try PhoneNumberParser.parse("no digits here")) { error in
            XCTAssertEqual(error as? PhoneParseError, .noDigits)
        }
        XCTAssertThrowsError(try PhoneNumberParser.parse("+9999999 12345")) { error in
            XCTAssertEqual(error as? PhoneParseError, .unknownCallingCode("999999912345"))
        }
        XCTAssertThrowsError(try PhoneNumberParser.parse("07400123456", defaultRegion: "ZZ")) { error in
            XCTAssertEqual(error as? PhoneParseError, .unknownRegion("ZZ"))
        }
    }

    /// Line type is the thing people are really buying.
    func testLineTypesAreDistinguished() throws {
        XCTAssertEqual(try PhoneNumberParser.parse("+447400123456").type, .mobile)
        XCTAssertEqual(try PhoneNumberParser.parse("+442079460958").type, .fixedLine)
        XCTAssertEqual(try PhoneNumberParser.parse("+448001234567").type, .tollFree)
        XCTAssertEqual(try PhoneNumberParser.parse("+449012345678").type, .premiumRate)
    }

    /// The +1 case the parser got wrong twice: Caribbean territories share the
    /// calling code with the US and must not be swallowed by it.
    func testNorthAmericanTerritoriesResolveSeparately() throws {
        let dominica = try PhoneNumberParser.parse("+17672251234")
        XCTAssertEqual(dominica.region, "DM")
        XCTAssertTrue(dominica.isValid)

        let us = try PhoneNumberParser.parse("+12025550123")
        XCTAssertEqual(us.region, "US")
    }

    /// Non-geographical codes belong to no country and must say so rather
    /// than being filed under whichever region sorted first.
    func testSatelliteNumberHasNoRegion() throws {
        let inmarsat = try PhoneNumberParser.parse("+870301234567")
        XCTAssertEqual(inmarsat.callingCode, "870")
        XCTAssertNil(inmarsat.region)
        XCTAssertTrue(inmarsat.isNonGeographical)
    }

    /// Possible is a weaker claim than valid, and both are reported.
    func testPossibleIsWeakerThanValid() throws {
        // Right length for GB, but not an allocated block.
        let parsed = try PhoneNumberParser.parse("+441111111111")
        XCTAssertTrue(parsed.isPossible)
        XCTAssertFalse(parsed.isValid)
    }

    /// Worth a test of its own, because it wastes an afternoon otherwise.
    ///
    /// Ofcom reserves 07700 900xxx for drama, and libphonenumber EXCLUDES it
    /// from the mobile pattern — so the number everyone reaches for when they
    /// want a safe fake UK mobile reports invalid, and it looks like the
    /// parser is broken. The landline drama range 020 7946 0xxx is NOT
    /// excluded. The asymmetry is in the source data, not here.
    func testOfcomDramaRangesAreAsymmetric() throws {
        let dramaMobile = try PhoneNumberParser.parse("+447700900123")
        XCTAssertTrue(dramaMobile.isPossible, "right length for GB")
        XCTAssertFalse(dramaMobile.isValid, "libphonenumber excludes the drama mobile range")
        XCTAssertEqual(dramaMobile.type, .unknown)

        let dramaLandline = try PhoneNumberParser.parse("+442079460958")
        XCTAssertTrue(dramaLandline.isValid, "the drama LANDLINE range is not excluded")
        XCTAssertEqual(dramaLandline.type, .fixedLine)
    }

    func testStringConvenience() {
        XCTAssertTrue("+447400123456".isPhoneNumber())
        XCTAssertTrue("07400 123456".isPhoneNumber(in: "GB"))
        XCTAssertFalse("banana".isPhoneNumber(in: "GB"))
        XCTAssertEqual("07400 123456".e164(in: "GB"), "+447400123456")
        XCTAssertEqual(["07400123456", "banana", "020 7946 0958"].validPhoneNumberCount(in: "GB"), 2)
    }
}
