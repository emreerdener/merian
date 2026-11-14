import Foundation

/// Public-facing product identity. Stable engineering identifiers intentionally remain Merian.
enum PublicBrand {
    static let name = "Naturebook"
    static let proName = "Naturebook Pro"
    static let aiName = "Naturebook AI"
    static let websiteURL = URL(string: "https://naturebook.earth")!
    static let supportEmail = "support@naturebook.earth"
    #if MERIAN_HISTORY_QUALIFICATION
    static let canonicalScheme = "naturebook-history-qualification"
    static let acceptedSchemes: Set<String> = [canonicalScheme, "merian-history-qualification"]
    static let acceptedWebHosts: Set<String> = []
    #else
    static let canonicalScheme = "naturebook"
    static let acceptedSchemes: Set<String> = [canonicalScheme, "merian"]
    static let acceptedWebHosts: Set<String> = ["naturebook.earth", "merian.earth"]
    #endif

    static func websiteURL(path: String) -> URL {
        websiteURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
