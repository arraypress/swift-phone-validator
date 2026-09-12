import Foundation

/// Turns a human-written phone number into a `PhoneNumber`.
///
/// The algorithm follows libphonenumber's, because the metadata is shaped for
/// it and any other reading of the same table gets different answers.
public enum PhoneNumberParser {

    /// The shortest national number in any plan. Below this nothing can be a
    /// phone number, so it is rejected before any table lookup.
    static let minimumDigits = 2
    /// Country calling codes are one to three digits. Nothing longer exists.
    static let maximumCallingCodeDigits = 3

    /// Parse a number, optionally against a default region for national forms.
    ///
    /// - Parameters:
    ///   - raw: the number as written — spaces, dashes, brackets and dots are
    ///     all fine, as are unicode digits.
    ///   - defaultRegion: CLDR code (`"GB"`) used only when `raw` is NOT in
    ///     international form. An international number ignores it.
    public static func parse(_ raw: String, defaultRegion: String? = nil) throws -> PhoneNumber {
        let metadata = try MetadataStore.metadata()
        let (digits, hadPlus) = extract(raw)

        guard !digits.isEmpty else { throw PhoneParseError.noDigits }

        var region = defaultRegion?.uppercased()
        if let region, metadata.regions[region] == nil {
            throw PhoneParseError.unknownRegion(region)
        }

        var national = digits
        var callingCode: String

        if hadPlus {
            // International form: the calling code is in the string.
            guard let (code, rest) = splitCallingCode(digits, metadata: metadata) else {
                throw PhoneParseError.unknownCallingCode(digits)
            }
            callingCode = code
            national = rest
            region = nil                                   // resolved from the number below
        } else if let region, let entry = metadata.regions[region] {
            // National form, or international written with a trunk-dialled
            // international prefix like `00` instead of `+`.
            if let ip = entry.internationalPrefix,
               let stripped = stripInternationalPrefix(digits, pattern: ip),
               let (code, rest) = splitCallingCode(stripped, metadata: metadata) {
                callingCode = code
                national = rest
            } else {
                callingCode = entry.callingCode
                national = digits
            }
        } else {
            throw PhoneParseError.regionRequired
        }

        guard national.count >= minimumDigits else { throw PhoneParseError.tooShort }

        // Resolve which region owns this number, then strip its trunk prefix.
        // Order matters: several regions share a calling code and they do not
        // share a national prefix, so the region has to be settled first.
        let candidates = metadata.callingCodes[callingCode] ?? []
        let nonGeo = metadata.nonGeographical[callingCode]

        var resolvedRegion: String?
        var entry: PhoneMetadata.Region?

        // Strip the trunk prefix ONCE, using the main country's rules, before
        // any candidate is considered.
        //
        // Doing it per-candidate looks equivalent and is not. A transform rule
        // can ADD digits: Barbados parses with `([2-9]\d{6})$|1` and rewrites
        // to `246$1`, expanding a local seven-digit number to a full one. Run
        // that speculatively over every candidate and a Canadian 310-xxxx
        // service number comes back as `+12463101234` — Barbados claimed it by
        // rewriting it into its own area code.
        if let main = candidates.first.flatMap({ metadata.regions[$0] }) ?? nonGeo {
            national = stripNationalPrefix(national, region: main)
        }

        if candidates.isEmpty, let nonGeo {
            entry = nonGeo
            resolvedRegion = nil
        } else {
            // How libphonenumber picks between regions sharing a calling code,
            // and it cannot be simplified to "does the general pattern match".
            //
            // 25 territories share +1, and the US — which is first, being the
            // main country — has NO leadingDigits and a generalDesc of
            // `[2-9]\d{9}` that swallows every NANP number including
            // Dominica's. Resolving on generalDesc sends all of the Caribbean
            // to the US, where the type patterns then reject it: 80 real
            // numbers reported invalid, measured.
            //
            // So: a region with leadingDigits is chosen when the number BEGINS
            // with them; a region without is chosen only when the number
            // resolves to an actual TYPE there.
            for candidate in candidates {
                guard let region = metadata.regions[candidate] else { continue }
                if let leading = region.leadingDigits, !leading.isEmpty {
                    if RegexCache.shared.matchesPrefix(national, pattern: leading) {
                        resolvedRegion = candidate
                        entry = region
                        break
                    }
                } else if PhoneNumberValidator.type(of: national, in: region) != .unknown {
                    resolvedRegion = candidate
                    entry = region
                    break
                }
            }
            // Nothing matched — keep the main country so the number still
            // reports a calling code and a region rather than nothing at all.
            if entry == nil, let first = candidates.first {
                resolvedRegion = first
                entry = metadata.regions[first]
            }
        }

        guard let entry else { throw PhoneParseError.unknownCallingCode(digits) }

        let type = PhoneNumberValidator.type(of: national, in: entry)
        let valid = PhoneNumberValidator.isValid(national, in: entry)
        let possible = PhoneNumberValidator.isPossible(national, in: entry)

        return PhoneNumber(
            e164: "+\(callingCode)\(national)",
            callingCode: callingCode,
            nationalNumber: national,
            region: resolvedRegion,
            type: type,
            isPossible: possible,
            isValid: valid,
            isMobilePortable: entry.isMobilePortable
        )
    }

    // MARK: - Pieces

    /// Keep the digits, remember whether the number announced itself as
    /// international. `wholeNumberValue` is used rather than an ASCII range so
    /// that full-width and other unicode digits survive — they turn up in real
    /// data pasted from CJK locales.
    static func extract(_ raw: String) -> (digits: String, hadPlus: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = ""
        for character in trimmed {
            if let value = character.wholeNumberValue, value >= 0, value <= 9,
               character.isNumber {
                digits.append(String(value))
            }
        }
        return (digits, trimmed.hasPrefix("+") || trimmed.hasPrefix("＋"))
    }

    /// Longest-first match of a 1–3 digit calling code.
    ///
    /// Longest-first is not decoration: `1` (North America) is a prefix of
    /// `1242` style numbers and `7` (Russia) of `7xx`, so a shortest-first
    /// scan silently assigns numbers to the wrong country.
    static func splitCallingCode(_ digits: String, metadata: PhoneMetadata) -> (String, String)? {
        let maximum = min(maximumCallingCodeDigits, digits.count)
        guard maximum >= 1 else { return nil }
        for length in stride(from: maximum, through: 1, by: -1) {
            let candidate = String(digits.prefix(length))
            if metadata.callingCodes[candidate] != nil || metadata.nonGeographical[candidate] != nil {
                return (candidate, String(digits.dropFirst(length)))
            }
        }
        return nil
    }

    /// Remove a trunk-dialled international prefix (`00`, `011`, `810`).
    static func stripInternationalPrefix(_ digits: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))") else { return nil }
        let range = NSRange(digits.startIndex..., in: digits)
        guard let match = regex.firstMatch(in: digits, range: range), match.range.length > 0,
              let matched = Range(match.range, in: digits) else { return nil }
        let rest = String(digits[matched.upperBound...])
        return rest.isEmpty ? nil : rest
    }

    /// Remove the national trunk prefix, applying the transform rule if there
    /// is one.
    ///
    /// The trap here is assuming this is the same string as `nationalPrefix`.
    /// For GB, `nationalPrefix` is `0` but `nationalPrefixForParsing` is
    /// `0|180020` — the second is a carrier-selection prefix that also has to
    /// come off. Strip with the wrong one and those numbers keep six extra
    /// leading digits and read as invalid.
    ///
    /// A strip is only kept if what is left still looks like a number for the
    /// region; otherwise the original is returned, because over-stripping
    /// turns a valid number into a shorter invalid one.
    static func stripNationalPrefix(_ national: String, region: PhoneMetadata.Region) -> String {
        guard let pattern = region.nationalPrefixForParsing ?? region.nationalPrefix,
              !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))") else { return national }

        let range = NSRange(national.startIndex..., in: national)
        guard let match = regex.firstMatch(in: national, range: range),
              match.range.length > 0,
              let matched = Range(match.range, in: national) else { return national }

        var stripped: String
        if let rule = region.nationalPrefixTransformRule, !rule.isEmpty, match.numberOfRanges > 1 {
            stripped = regex.stringByReplacingMatches(
                in: national, range: match.range, withTemplate: rule
            )
            // stringByReplacingMatches returns the whole string with the match
            // replaced, which is what we want, but only over the matched range.
            stripped += String(national[matched.upperBound...])
        } else {
            stripped = String(national[matched.upperBound...])
        }

        guard !stripped.isEmpty else { return national }
        // Keep the strip only if it did not destroy the number.
        if matchesGeneral(stripped, region: region) || !matchesGeneral(national, region: region) {
            return stripped
        }
        return national
    }

    static func matchesGeneral(_ national: String, region: PhoneMetadata.Region) -> Bool {
        guard let pattern = region.generalPattern else { return false }
        return RegexCache.shared.matches(national, pattern: pattern)
    }
}
