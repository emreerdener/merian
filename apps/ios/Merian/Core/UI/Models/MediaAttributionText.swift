import Foundation

/// Keeps provider credit text intact while giving embedded links readable titles.
enum MediaAttributionText {
    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func formatted(_ credit: String) -> AttributedString {
        var result = AttributedString()
        var cursor = credit.startIndex
        for match in linkDetector.matches(in: credit, range: NSRange(credit.startIndex..., in: credit)) {
            guard let range = Range(match.range, in: credit), let url = match.url else { continue }
            // Email addresses can be the creator's credit, rather than a website.
            if url.scheme?.lowercased() == "mailto", !credit[range].lowercased().hasPrefix("mailto:") { continue }
            result.append(AttributedString(String(credit[cursor..<range.lowerBound])))
            var link = AttributedString(label(for: url))
            if ["http", "https", "ftp", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                link.link = url
            }
            result.append(link)
            cursor = range.upperBound
        }
        result.append(AttributedString(String(credit[cursor...])))
        return result
    }

    private static func label(for url: URL) -> String {
        let host = url.host?.lowercased()
        guard host == "creativecommons.org" || host == "www.creativecommons.org" else {
            return url.scheme?.lowercased() == "mailto" ? "Contact" : "Website"
        }
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "licenses",
           ["by", "by-sa", "by-nd", "by-nc", "by-nc-sa", "by-nc-nd"].contains(parts[1]),
           parts[2].range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil {
            let jurisdiction = parts.count > 3 && parts[3].count == 2 ? " \(parts[3].uppercased())" : ""
            return "CC \(parts[1].uppercased()) \(parts[2])\(jurisdiction)"
        }
        if parts.count >= 3, parts[0] == "publicdomain" {
            if parts[1] == "zero", parts[2] == "1.0" { return "CC0 1.0" }
            if parts[1] == "mark", parts[2] == "1.0" { return "Public domain" }
        }
        return "License"
    }
}
