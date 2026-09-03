import Foundation
import Testing

@testable import Merian

@Suite("Media Storage API Models")
struct MediaStorageAPIModelsTests {
    @Test func signingProjectionKeepsOptionalLifecycleFieldsAndIgnoresSuccessFlag() throws {
        let data = Data(#"{"success":false,"urls":[{"fileName":"raw","signedUrl":"raw","objectKey":"raw","requiredHeaders":{}}]}"#.utf8)
        let response = try JSONDecoder().decode(PreSignedURLResponse.self, from: data)
        #expect(response.urls.count == 1)
        #expect(response.urls[0].mediaAssetId == nil && response.urls[0].mediaSessionId == nil)
        #expect(response.urls[0].requiredHeaders.isEmpty)
    }

    @Test(arguments: ["{}", #"{"urls":null}"#, #"{"urls":[{}]}"#,
                      #"{"urls":[{"fileName":"raw","signedUrl":"raw","objectKey":"raw"}]}"#])
    func signingRequiredFieldsRemainStrict(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PreSignedURLResponse.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: ["healthy", "missing", "not_referenced", "repaired"])
    func inspectionStatusesAndDefaultCountsRemainCompatible(status: String) throws {
        let json = #"{"status":"\#(status)","replacement_url":null,"updated_scan_count":null}"#
        let value = try JSONDecoder().decode(ScanImageCloudInspection.self, from: Data(json.utf8))
        #expect(value.status.rawValue == status)
        #expect(value.replacementUrl == nil && value.updatedScanCount == 0 && value.updatedPostMediaCount == 0)
    }

    @Test func inspectionRetainsExplicitSnakeCaseProjection() throws {
        let json = #"{"status":"repaired","replacement_url":"raw","updated_scan_count":2,"updated_post_media_count":3}"#
        let value = try JSONDecoder().decode(ScanImageCloudInspection.self, from: Data(json.utf8))
        #expect(value.replacementUrl == "raw" && value.updatedScanCount == 2 && value.updatedPostMediaCount == 3)
    }

    @Test(arguments: ["{}", #"{"status":"unknown"}"#, #"{"status":null}"#,
                      #"{"status":"healthy","updated_scan_count":"1"}"#, #"{"status":"healthy","replacement_url":1}"#])
    func malformedInspectionFieldsRemainDecodingErrors(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScanImageCloudInspection.self, from: Data(json.utf8))
        }
    }
}
