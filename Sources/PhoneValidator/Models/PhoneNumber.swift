import Foundation

/// A parsed phone number, and everything the numbering plan can say about it.
public struct PhoneNumber: Sendable, Equatable {

    /// Canonical international form, e.g. `+447700900123`.
    public let e164: String
    /// Country calling code without `+`, e.g. `44`.
    public let callingCode: String
    /// The national significant number — trunk prefix already removed.
    public let nationalNumber: String
    /// CLDR region code, e.g. `GB`. Nil for the non-geographical codes
    /// (+800 freephone, +870 satellite) which belong to no country.
    public let region: String?
    /// What kind of line the allocated block is for.
    public let type: PhoneNumberType

    /// The number is the right LENGTH for its region — a cheap check that
    /// does not run any pattern.
    public let isPossible: Bool
    /// The number matches a real allocated pattern for its region.
    /// Stronger than `isPossible`, and the one that goes stale first when the
    /// metadata is behind: a brand-new block is possible before it is valid.
    public let isValid: Bool
    /// Whether the region permits number portability — if true, any carrier
    /// inferred from the prefix is the ALLOCATED carrier, not necessarily the
    /// current one.
    public let isMobilePortable: Bool

    /// Whether this number belongs to one of the nine non-geographical
    /// calling codes rather than a country.
    public var isNonGeographical: Bool { region == nil }
}
