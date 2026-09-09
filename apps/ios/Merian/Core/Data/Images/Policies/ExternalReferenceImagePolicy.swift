import Foundation

enum ExternalReferenceImagePolicy {
    private static let suppressedHost = "inaturalist-open-data.s3.amazonaws.com"
    private static let suppressedPathPrefix = "/photos/605615444/"

    /// Suppresses the disturbing roadkill photo exposed by GBIF occurrence 5938154750.
    /// Matching its iNaturalist media directory also catches resized filename variants
    /// and query strings without affecting any other European wildcat imagery.
    static func isAllowed(_ url: URL) -> Bool {
        guard SecureTransportPolicy.isSecureRemoteURL(url) else { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host != suppressedHost || !path.hasPrefix(suppressedPathPrefix)
    }

    static func isAllowed(_ rawValue: String) -> Bool {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue) else {
            return false
        }
        return isAllowed(url)
    }

    static func sanitizedURL(_ rawValue: String?) -> String? {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue),
              isAllowed(url) else {
            return nil
        }
        return url.absoluteString
    }

    static func url(from rawValue: String?) -> URL? {
        guard let url = SecureTransportPolicy.httpsURL(from: rawValue),
              isAllowed(url) else {
            return nil
        }
        return url
    }

    static func allowedURLStrings(from rawValue: String?) -> [String] {
        rawValue?
            .components(separatedBy: ",")
            .compactMap { sanitizedURL($0) } ?? []
    }

    static func sanitizedURLList(_ rawValue: String?) -> String? {
        let joined = allowedURLStrings(from: rawValue).joined(separator: ",")
        return joined.isEmpty ? nil : joined
    }
}
