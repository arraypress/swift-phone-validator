import Foundation

/// The shape of `PhoneNumberMetadata.json`, as written by
/// `Scripts/generate-metadata.py` from a pinned libphonenumber release.
///
/// Keys are deliberately short: the same payload with readable keys and pretty
/// printing is roughly 1.6x the size, and nothing reads this file by hand.
public struct PhoneMetadata: Decodable, Sendable {

    /// Which libphonenumber release this was generated from, e.g. `v9.0.39`.
    /// Google reissues the metadata roughly every two weeks, so this is the
    /// single most useful thing to print when a number validates surprisingly.
    public let sourceRelease: String

    /// The day the JSON was generated, `yyyy-MM-dd`.
    public let generated: String

    /// Geographic regions, keyed by CLDR region code (`GB`, `US`, `DE`).
    public let regions: [String: Region]

    /// The nine non-geographical calling codes, keyed by the calling code
    /// itself (`800` freephone, `870`/`881` satellite, `979` premium rate).
    /// libphonenumber gives all nine the region id `001`, so they cannot live
    /// in `regions` without eight of them overwriting each other.
    public let nonGeographical: [String: Region]

    /// Calling code -> the regions that share it, main country first.
    /// `44` -> `["GB", "GG", "IM", "JE"]`.
    public let callingCodes: [String: [String]]

    public struct Region: Decodable, Sendable {
        /// Country calling code, without `+`.
        public let callingCode: String
        /// Whether this region owns the calling code when several share it.
        public let isMainCountry: Bool
        /// National trunk prefix, e.g. `0` in the UK.
        public let nationalPrefix: String?
        /// Pattern for the trunk prefix when parsing, which is not always the
        /// same string as `nationalPrefix`: GB is `0|180020`.
        public let nationalPrefixForParsing: String?
        /// Replacement applied after stripping the trunk prefix.
        public let nationalPrefixTransformRule: String?
        /// Prefix dialled to leave the country, e.g. `00`.
        public let internationalPrefix: String?
        /// Distinguishes regions that share a calling code.
        public let leadingDigits: String?
        /// Whether numbers here can be ported between carriers — which is why
        /// an offline carrier lookup can only ever name the ALLOCATED carrier.
        public let isMobilePortable: Bool
        /// Pattern every valid national number in the region matches.
        public let generalPattern: String?
        /// Per number type: pattern, possible lengths, example.
        public let types: [String: NumberType]
        /// Display formats, in the order they should be tried.
        public let formats: [Format]

        enum CodingKeys: String, CodingKey {
            case callingCode = "c"
            case isMainCountry = "main"
            case nationalPrefix = "np"
            case nationalPrefixForParsing = "npp"
            case nationalPrefixTransformRule = "npt"
            case internationalPrefix = "ip"
            case leadingDigits = "ld"
            case isMobilePortable = "mnp"
            case generalPattern = "gen"
            case types = "t"
            case formats = "f"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            callingCode = try c.decode(String.self, forKey: .callingCode)
            isMainCountry = try c.decodeIfPresent(Bool.self, forKey: .isMainCountry) ?? false
            nationalPrefix = try c.decodeIfPresent(String.self, forKey: .nationalPrefix)
            nationalPrefixForParsing = try c.decodeIfPresent(String.self, forKey: .nationalPrefixForParsing)
            nationalPrefixTransformRule = try c.decodeIfPresent(String.self, forKey: .nationalPrefixTransformRule)
            internationalPrefix = try c.decodeIfPresent(String.self, forKey: .internationalPrefix)
            leadingDigits = try c.decodeIfPresent(String.self, forKey: .leadingDigits)
            isMobilePortable = try c.decodeIfPresent(Bool.self, forKey: .isMobilePortable) ?? false
            generalPattern = try c.decodeIfPresent(String.self, forKey: .generalPattern)
            types = try c.decodeIfPresent([String: NumberType].self, forKey: .types) ?? [:]
            formats = try c.decodeIfPresent([Format].self, forKey: .formats) ?? []
        }
    }

    public struct NumberType: Decodable, Sendable {
        /// Anchored pattern for the national (significant) number.
        public let pattern: String
        /// Possible lengths as libphonenumber writes them: `"9,10"`, `"[4-6]"`.
        public let lengths: String?
        /// A number that this pattern matches — free ground truth, and what
        /// the generator checks itself against before writing the file.
        public let example: String?

        enum CodingKeys: String, CodingKey {
            case pattern = "p", lengths = "l", example = "e"
        }
    }

    public struct Format: Decodable, Sendable {
        public let pattern: String
        public let format: String
        public let leadingDigits: [String]
        public let nationalPrefixFormattingRule: String?
        public let carrierCodeFormattingRule: String?
        public let nationalPrefixOptional: Bool

        enum CodingKeys: String, CodingKey {
            case pattern = "p", format = "f", leadingDigits = "ld"
            case nationalPrefixFormattingRule = "npf"
            case carrierCodeFormattingRule = "ccf"
            case nationalPrefixOptional = "npo"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pattern = try c.decode(String.self, forKey: .pattern)
            format = try c.decode(String.self, forKey: .format)
            leadingDigits = try c.decodeIfPresent([String].self, forKey: .leadingDigits) ?? []
            nationalPrefixFormattingRule = try c.decodeIfPresent(String.self, forKey: .nationalPrefixFormattingRule)
            carrierCodeFormattingRule = try c.decodeIfPresent(String.self, forKey: .carrierCodeFormattingRule)
            nationalPrefixOptional = try c.decodeIfPresent(Bool.self, forKey: .nationalPrefixOptional) ?? false
        }
    }
}
