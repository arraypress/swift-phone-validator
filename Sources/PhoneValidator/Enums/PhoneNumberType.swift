import Foundation

/// What kind of line a number is, as far as the numbering plan says.
///
/// This comes from the ALLOCATED prefix block, not from asking the network, so
/// it survives being offline and does not survive number portability changing
/// the answer for an individual subscriber.
public enum PhoneNumberType: String, Sendable, CaseIterable {
    case fixedLine
    case mobile
    /// Some plans allocate one block to both, with identical patterns, so the
    /// two genuinely cannot be told apart. Saying so is more honest than
    /// picking whichever was tested first.
    case fixedLineOrMobile
    case pager
    case tollFree
    case premiumRate
    case sharedCost
    case personalNumber
    case voip
    /// Universal Access Number — one number that routes to an organisation.
    case uan
    case voicemail
    case unknown

    /// The key this type has in the generated metadata, if it has one.
    /// `fixedLineOrMobile` and `unknown` are derived, not stored.
    var metadataKey: String? {
        switch self {
        case .fixedLineOrMobile, .unknown: return nil
        default: return rawValue
        }
    }

    /// The order libphonenumber resolves types in: the narrow, unambiguous
    /// blocks first, because a premium-rate or toll-free number will often
    /// also satisfy the broader fixed-line pattern for the same country.
    static let resolutionOrder: [PhoneNumberType] = [
        .premiumRate, .tollFree, .sharedCost, .voip,
        .personalNumber, .pager, .uan, .voicemail
    ]
}
