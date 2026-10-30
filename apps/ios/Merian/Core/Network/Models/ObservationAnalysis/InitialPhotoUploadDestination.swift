import Foundation

/// Explicit trusted composition input, never constructed from a ticket or flag.
/// No profile is installed. This value is not provider qualification or authority.
struct InitialPhotoUploadDestination: Equatable, Sendable {
    let backendGeneration: UUID
    let configurationDigest: String
    private let endpoint: String
    private let bucket: String

    init(backendGeneration: UUID, configurationDigest: String, endpoint: String, bucket: String) throws {
        guard SharedMediaAcquisitionEncoding.isHash(configurationDigest),
              Self.matches(endpoint, #"https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com"#),
              Self.matches(bucket, "[a-z0-9][a-z0-9-]{1,61}[a-z0-9]") else { throw MerianError.invalidResponse }
        self.backendGeneration = backendGeneration; self.configurationDigest = configurationDigest
        self.endpoint = endpoint; self.bucket = bucket
    }

    func unsignedURL(scan: UUID, object: UUID) -> String {
        "\(endpoint)/\(bucket)/initial-preparation/v2/\(scan.uuidString.lowercased())/\(object.uuidString.lowercased())"
    }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }

    func validateSignedURL(_ raw: String, scan: UUID, object: UUID, created: Int64,
                           signedExpiry: Int64, now: Int64) throws -> URL {
        guard raw.utf8.count <= 4096, let url = URL(string: raw), url.absoluteString == raw,
              let components = URLComponents(string: raw), components.scheme == "https",
              components.user == nil, components.password == nil, components.fragment == nil,
              components.port == nil, let queryStart = raw.firstIndex(of: "?"),
              String(raw[..<queryStart]) == unsignedURL(scan: scan, object: object),
              let items = components.queryItems, items.count == 6 else { throw MerianError.invalidResponse }
        let keys: Set<String> = ["X-Amz-Algorithm", "X-Amz-Credential", "X-Amz-Date", "X-Amz-Expires", "X-Amz-Signature", "X-Amz-SignedHeaders"]
        guard Set(items.map(\.name)) == keys, items.allSatisfy({ $0.value != nil }) else { throw MerianError.invalidResponse }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard query["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256",
              query["X-Amz-SignedHeaders"] == "cache-control;content-length;content-type;host;if-none-match;x-amz-content-sha256",
              Self.matches(query["X-Amz-Signature"]!, "[a-f0-9]{64}"),
              let dateText = query["X-Amz-Date"], Self.matches(dateText, "[0-9]{8}T[0-9]{6}Z"),
              let ttlText = query["X-Amz-Expires"], Self.matches(ttlText, "[1-9][0-9]{0,2}"),
              let ttl = Int64(ttlText), ttl <= 600,
              Self.matches(query["X-Amz-Credential"]!, "[A-Za-z0-9/+_=.-]{16,256}/" + String(dateText.prefix(8)) + "/auto/s3/aws4_request") else {
            throw MerianError.invalidResponse
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; formatter.isLenient = false
        guard let date = formatter.date(from: dateText), formatter.string(from: date) == dateText else { throw MerianError.invalidResponse }
        let signedAt = Int64((date.timeIntervalSince1970 * 1000).rounded())
        guard signedAt >= (created / 1000) * 1000, signedAt <= now,
              signedAt + ttl * 1000 == signedExpiry, signedExpiry > now else { throw MerianError.invalidResponse }
        return url
    }
}
