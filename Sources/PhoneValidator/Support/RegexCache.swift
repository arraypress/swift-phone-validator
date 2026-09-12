import Foundation

/// Compiles each metadata pattern once and keeps it.
///
/// Every pattern in the table gets used repeatedly and `NSRegularExpression`
/// compilation dominates the cost of validating a number otherwise. Patterns
/// arrive already anchored-free, so anchoring happens here, in one place —
/// an un-anchored match would happily find a valid number INSIDE an invalid
/// one and report a pass.
final class RegexCache: @unchecked Sendable {

    static let shared = RegexCache()

    private var store: [String: NSRegularExpression] = [:]
    private var prefixStore: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    private init() {}

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = store[pattern] { return cached }
        guard let built = try? NSRegularExpression(pattern: "^(?:\(pattern))$") else { return nil }
        store[pattern] = built
        return built
    }

    /// Whether the whole string matches the pattern, anchored at both ends.
    func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = regex(for: pattern) else { return false }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }

    /// Whether the string BEGINS with the pattern.
    ///
    /// `leadingDigits` is the only thing read this way, and it has to be:
    /// Dominica's is `767`, which is a three-digit prefix of a ten-digit
    /// number, so an anchored-both-ends match would never fire.
    func matchesPrefix(_ string: String, pattern: String) -> Bool {
        lock.lock()
        let cached = prefixStore[pattern]
        lock.unlock()
        let regex: NSRegularExpression
        if let cached {
            regex = cached
        } else {
            guard let built = try? NSRegularExpression(pattern: "^(?:\(pattern))") else { return false }
            lock.lock(); prefixStore[pattern] = built; lock.unlock()
            regex = built
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }
}
