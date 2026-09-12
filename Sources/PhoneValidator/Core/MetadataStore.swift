import Foundation

/// Anchors a `Bundle(for:)` lookup. Needs to be a class; does nothing else.
private final class BundleToken {}

/// Loads the bundled libphonenumber metadata, once.
///
/// Decoding ~225 KB of JSON is not free and every validation needs the same
/// table, so it is parsed on first use and held. Nothing here touches the
/// network: the file ships inside the module.
public enum MetadataStore {

    /// The name the generator writes, and the name `Package.swift` copies.
    static let resourceName = "PhoneNumberMetadata"

    /// The bundle SwiftPM builds for this target's resources.
    static let bundleName = "PhoneValidator_PhoneValidator"

    /// Finds the metadata WITHOUT touching `Bundle.module`.
    ///
    /// This is deliberate and was measured. SwiftPM's generated accessor for
    /// `Bundle.module` calls `fatalError` when the resource bundle is not
    /// beside the binary — so an executable installed without its `.bundle`
    /// dies with `unable to find bundle named PhoneValidator_PhoneValidator`
    /// and a stack trace, and no error this library could throw is ever
    /// reachable. That is the likeliest packaging mistake there is: Homebrew's
    /// `bin.install` takes the binary and leaves the bundle behind.
    ///
    /// Searching by hand costs a dozen lines and turns a crash into a sentence
    /// that says what to do. Invoking through a symlink was tested separately
    /// and works, so the symlink case is not what this guards.
    private static func locate() -> URL? {
        let candidates: [URL] = [
            Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent(),
            Bundle(for: BundleToken.self).bundleURL,
            Bundle.main.bundleURL,
            Bundle.main.resourceURL,
            // The real executable, with any symlink resolved — an installed
            // tool is usually reached through one.
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
            URL(fileURLWithPath: CommandLine.arguments.first ?? "")
                .resolvingSymlinksInPath().deletingLastPathComponent()
        ].compactMap { $0 }

        for directory in candidates {
            let bundleURL = directory.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: resourceName, withExtension: "json") {
                return url
            }
            // Also accept the resource sitting loose beside the binary.
            let loose = directory.appendingPathComponent("\(resourceName).json")
            if FileManager.default.fileExists(atPath: loose.path) { return loose }
        }

        // Resources compiled directly into the enclosing bundle (an app, or a
        // test bundle that embedded them).
        return Bundle(for: BundleToken.self).url(forResource: resourceName, withExtension: "json")
    }

    private static let loaded: Result<PhoneMetadata, PhoneMetadataError> = {
        guard let url = locate() else { return .failure(.resourceMissing) }
        do {
            let data = try Data(contentsOf: url)
            return .success(try JSONDecoder().decode(PhoneMetadata.self, from: data))
        } catch {
            return .failure(.unreadable(underlying: error))
        }
    }()

    /// The metadata table, decoded once and shared.
    public static func metadata() throws -> PhoneMetadata {
        try loaded.get()
    }

    /// The libphonenumber release the bundled table was generated from.
    /// Worth surfacing in any `--version` output: when a brand-new mobile
    /// block reads as invalid, this is the first number to check.
    public static var sourceRelease: String? {
        try? metadata().sourceRelease
    }

    /// Metadata for a geographic region, by CLDR code (`GB`, `US`).
    public static func region(_ code: String) throws -> PhoneMetadata.Region? {
        try metadata().regions[code.uppercased()]
    }

    /// The regions that share a calling code, main country first.
    public static func regions(forCallingCode code: String) throws -> [String] {
        try metadata().callingCodes[code] ?? []
    }
}
