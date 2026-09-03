import Foundation

struct PreSignedURLResponse: Codable {
    let urls: [PreSignedURL]
}

struct PreSignedURL: Codable {
    let fileName: String
    let signedUrl: String
    let objectKey: String
    let requiredHeaders: [String: String]
    let mediaAssetId: String?
    let mediaSessionId: String?
}

enum ScanImageCloudStatus: String, Decodable, Equatable, Sendable {
    case healthy
    case missing
    case notReferenced = "not_referenced"
    case repaired
}

struct ScanImageCloudInspection: Decodable, Equatable, Sendable {
    let status: ScanImageCloudStatus
    let replacementUrl: String?
    let updatedScanCount: Int
    let updatedPostMediaCount: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case replacementUrl = "replacement_url"
        case updatedScanCount = "updated_scan_count"
        case updatedPostMediaCount = "updated_post_media_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(ScanImageCloudStatus.self, forKey: .status)
        replacementUrl = try container.decodeIfPresent(String.self, forKey: .replacementUrl)
        updatedScanCount = try container.decodeIfPresent(Int.self, forKey: .updatedScanCount) ?? 0
        updatedPostMediaCount = try container.decodeIfPresent(Int.self, forKey: .updatedPostMediaCount) ?? 0
    }
}
