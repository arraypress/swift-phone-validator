import Foundation

/// Decides whether a national number is possible, valid, and what kind it is.
public enum PhoneNumberValidator {

    /// Length alone says the number could exist here. Cheap, and deliberately
    /// weaker than `isValid` — a block allocated last week is possible before
    /// the metadata knows it is valid.
    public static func isPossible(_ national: String, in region: PhoneMetadata.Region) -> Bool {
        let lengths = allPossibleLengths(in: region)
        guard !lengths.isEmpty else { return national.count >= PhoneNumberParser.minimumDigits }
        return lengths.contains(national.count)
    }

    /// The number matches a real allocated pattern for the region.
    public static func isValid(_ national: String, in region: PhoneMetadata.Region) -> Bool {
        guard PhoneNumberParser.matchesGeneral(national, region: region) else { return false }
        return type(of: national, in: region) != .unknown
    }

    /// Which kind of line the number's block is allocated for.
    ///
    /// Narrow types are tried before fixed line and mobile, because a
    /// toll-free or premium-rate number frequently also satisfies the broader
    /// fixed-line pattern for the same country — test in the other order and
    /// every 0800 number in the table comes back as a landline.
    public static func type(of national: String, in region: PhoneMetadata.Region) -> PhoneNumberType {
        for candidate in PhoneNumberType.resolutionOrder {
            guard let key = candidate.metadataKey,
                  let desc = region.types[key] else { continue }
            if RegexCache.shared.matches(national, pattern: desc.pattern) { return candidate }
        }

        let fixed = region.types["fixedLine"]
        let mobile = region.types["mobile"]
        let matchesMobile = mobile.map { RegexCache.shared.matches(national, pattern: $0.pattern) } ?? false

        if let fixed, RegexCache.shared.matches(national, pattern: fixed.pattern) {
            // `fixedLineOrMobile` is not only for plans whose two patterns are
            // written identically. It is the answer whenever THIS number
            // satisfies both — which happens in Chile, Mexico, the Dominican
            // Republic and Micronesia with patterns that differ. Requiring the
            // patterns to be equal reported five real mobile numbers as
            // landlines, measured against the metadata's own examples.
            let samePattern = mobile != nil && fixed.pattern == mobile?.pattern
            return (samePattern || matchesMobile) ? .fixedLineOrMobile : .fixedLine
        }
        if matchesMobile { return .mobile }
        return .unknown
    }

    /// Every length any type in the region accepts.
    static func allPossibleLengths(in region: PhoneMetadata.Region) -> Set<Int> {
        var lengths: Set<Int> = []
        for (_, desc) in region.types {
            lengths.formUnion(PossibleLengths.parse(desc.lengths))
        }
        return lengths
    }
}
