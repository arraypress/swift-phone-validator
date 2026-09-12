import Foundation

/// Reads libphonenumber's `possibleLengths` notation into a set of lengths.
///
/// The notation is compact and mixes two forms in one string:
/// `"10"`, `"9,10"`, `"[4-6]"`, `"7,9,10"`, `"6,[8-10]"`.
///
/// This matters because a length check is a cheap way to reject a number
/// before compiling or running any regex, and "possible" is a weaker, more
/// useful answer than "valid" when the metadata might be a fortnight stale:
/// a number can be possible-but-not-valid, and that is worth saying out loud
/// rather than flattening to false.
enum PossibleLengths {

    static func parse(_ raw: String?) -> Set<Int> {
        guard let raw, !raw.isEmpty else { return [] }
        var out: Set<Int> = []

        for piece in raw.split(separator: ",") {
            let token = piece.trimmingCharacters(in: .whitespaces)
            if token.hasPrefix("["), token.hasSuffix("]") {
                let inner = token.dropFirst().dropLast()
                let bounds = inner.split(separator: "-")
                if bounds.count == 2,
                   let lower = Int(bounds[0]), let upper = Int(bounds[1]), lower <= upper {
                    out.formUnion(lower...upper)
                }
            } else if let value = Int(token) {
                out.insert(value)
            }
        }
        return out
    }
}
