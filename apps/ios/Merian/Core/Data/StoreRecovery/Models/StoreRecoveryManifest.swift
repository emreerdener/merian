import Foundation

struct ModelStoreRecoveryManifest: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: String
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let archiveReason: String
    let reasonDomain: String?
    let reasonCode: Int?
    let reasonDescription: String?
    let reasonFailureReason: String?
    let movedArtifacts: [String]

    init(
        schemaVersion: Int = 2,
        timestamp: String,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        archiveReason: String,
        reasonDomain: String?,
        reasonCode: Int?,
        reasonDescription: String?,
        reasonFailureReason: String?,
        movedArtifacts: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.archiveReason = archiveReason
        self.reasonDomain = reasonDomain
        self.reasonCode = reasonCode
        self.reasonDescription = reasonDescription
        self.reasonFailureReason = reasonFailureReason
        self.movedArtifacts = movedArtifacts
    }
}
