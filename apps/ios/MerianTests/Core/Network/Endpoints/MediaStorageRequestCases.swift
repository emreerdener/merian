import Foundation
import Testing

@testable import Merian

enum MediaStorageRequestCase: CaseIterable, Sendable {
    case signing, inspection, repair

    static let ownerID = UUID(uuid: (
        0xA1, 0xB2, 0xC3, 0xD4, 0x00, 0x00, 0x40, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))

    var function: String {
        self == .signing ? "generate-upload-urls" : "repair-scan-image"
    }

    var expectedJSON: String {
        switch self {
        case .signing:
            #"{"files":[],"user_id":"\#(Self.ownerID.uuidString.lowercased())"}"#
        case .inspection:
            #"{"source_url":"  synthetic-source  "}"#
        case .repair:
            #"{"source_url":"  synthetic-source  ","restored_object_key":"  synthetic-key  "}"#
        }
    }

    var responseJSON: String {
        self == .signing ? #"{"urls":[]}"# : #"{"data":{"status":"healthy"}}"#
    }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        try NetworkEndpointTestSupport.expectPOST(request, function: function, json: expectedJSON)
    }

    @MainActor
    func invoke(_ client: MerianNetworkClient) async throws {
        switch self {
        case .signing:
            _ = try await client.generateUploadURLs(uploadFiles: [], expectedAuthUserID: Self.ownerID)
        case .inspection:
            _ = try await client.inspectScanImageCloudStatus(sourceUrl: "  synthetic-source  ")
        case .repair:
            _ = try await client.repairScanImageCloudReference(
                sourceUrl: "  synthetic-source  ", restoredObjectKey: "  synthetic-key  "
            )
        }
    }
}
