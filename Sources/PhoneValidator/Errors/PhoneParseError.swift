import Foundation

/// Why a string could not be read as a phone number.
public enum PhoneParseError: Error, Equatable, CustomStringConvertible {
    /// Nothing digit-like in the input at all.
    case noDigits
    /// Fewer digits than the shortest number anywhere (a plan minimum of 2).
    case tooShort
    /// Had a `+`, but the digits after it start with no calling code we know.
    case unknownCallingCode(String)
    /// Written in national form with no region to interpret it against.
    /// The fix is a default region, not a different number.
    case regionRequired
    /// A default region was given that is not in the metadata.
    case unknownRegion(String)

    public var description: String {
        switch self {
        case .noDigits:
            return "no digits in the input"
        case .tooShort:
            return "too short to be a phone number"
        case .unknownCallingCode(let digits):
            return "no country calling code matches +\(digits.prefix(4))…"
        case .regionRequired:
            return "number is in national format — pass a default region (e.g. \"GB\") to read it"
        case .unknownRegion(let region):
            return "unknown region \"\(region)\""
        }
    }
}
