import Foundation

public extension String {

    /// Whether this parses as a valid number.
    ///
    /// - Parameter region: CLDR code used only when the string is in national
    ///   form. An international number (`+44…`) ignores it.
    ///
    /// Returns false for anything unparseable, so it is safe on raw input.
    /// When you need to know WHY, use `phoneNumber(in:)`.
    func isPhoneNumber(in region: String? = nil) -> Bool {
        (try? PhoneNumberParser.parse(self, defaultRegion: region))?.isValid ?? false
    }

    /// The number is the right shape for its region, without insisting the
    /// exact block is one the metadata knows about.
    ///
    /// Worth preferring to `isPhoneNumber` when rejecting a customer's input:
    /// the metadata is reissued fortnightly, so a genuinely new mobile block
    /// is possible before it is valid, and turning someone away is worse than
    /// accepting a number that turns out to be dead.
    func isPossiblePhoneNumber(in region: String? = nil) -> Bool {
        (try? PhoneNumberParser.parse(self, defaultRegion: region))?.isPossible ?? false
    }

    /// Parse into a full `PhoneNumber`, throwing a `PhoneParseError` that says
    /// what was wrong.
    func phoneNumber(in region: String? = nil) throws -> PhoneNumber {
        try PhoneNumberParser.parse(self, defaultRegion: region)
    }

    /// Canonical `+447700900123` form, or nil if it does not parse.
    func e164(in region: String? = nil) -> String? {
        (try? PhoneNumberParser.parse(self, defaultRegion: region))?.e164
    }
}

public extension Collection where Element == String {

    /// Only the entries that parse as valid numbers, normalised to E.164.
    /// Order is preserved; duplicates are not removed, because two spellings
    /// of one number collapsing is usually the point.
    func validE164Numbers(in region: String? = nil) -> [String] {
        compactMap { $0.e164(in: region) != nil && $0.isPhoneNumber(in: region) ? $0.e164(in: region) : nil }
    }

    /// How many entries are valid numbers.
    func validPhoneNumberCount(in region: String? = nil) -> Int {
        reduce(0) { $0 + ($1.isPhoneNumber(in: region) ? 1 : 0) }
    }
}
