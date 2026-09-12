import Foundation

/// Why the bundled metadata could not be read.
///
/// These are packaging failures, not user input failures — a caller cannot
/// recover from them, but the message has to say which one it is, because
/// `.resourceMissing` almost always means the resource bundle did not travel
/// with the binary rather than anything wrong with this library.
public enum PhoneMetadataError: Error, CustomStringConvertible {
    case resourceMissing
    case unreadable(underlying: Error)

    public var description: String {
        switch self {
        case .resourceMissing:
            return """
            PhoneNumberMetadata.json could not be found. Install \
            PhoneValidator_PhoneValidator.bundle beside the executable — \
            Homebrew's bin.install takes the binary and leaves the bundle \
            behind, which is the usual cause. Reaching the executable through \
            a symlink is NOT the cause; that case was tested and works.
            """
        case .unreadable(let underlying):
            return "PhoneNumberMetadata.json could not be decoded: \(underlying)"
        }
    }
}
