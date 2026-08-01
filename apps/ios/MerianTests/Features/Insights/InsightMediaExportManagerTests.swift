import Foundation
import Testing
@testable import Merian

@Suite("Insight Media Export Tests")
struct InsightMediaExportManagerTests {
    
    @Test("SaveMediaPayload carries local and approved remote media URLs")
    func testSaveMediaPayloadNativelyFramesURLs() async throws {
        let localVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-video.mp4")
        let payload = InsightMediaExportManager.makeSaveMediaPayload(
            imagePaths: ["primary.webp", "https://media.merian.app/cdn/test.jpg"],
            videoPaths: [
                localVideoURL.path,
                "https://media.merian.app/cdn/test.mp4",
                "https://example.com/unapproved.mp4"
            ],
            referenceImageUrl: "https://media.merian.app/cdn/reference.jpg"
        )
        
        #expect(payload.localImageURLs.map(\.lastPathComponent) == ["primary.webp"])
        #expect(payload.approvedRemotePhotoURLs.count == 2)
        #expect(payload.localVideoURLs == [localVideoURL])
        #expect(payload.approvedRemoteVideoURLs.map(\.host) == ["media.merian.app"])
        #expect(!payload.approvedRemoteVideoURLs.contains { $0.host == "example.com" })
    }

    @Test("MediaSaveResult reports photo and video counts and partial failures")
    func testMediaSaveResultFormatsMixedMedia() {
        var result = MediaSaveResult()
        result.record(.photo, success: true)
        result.record(.video, success: true)
        result.record(.video, success: false)

        #expect(result.photosSaved == 1)
        #expect(result.videosSaved == 1)
        #expect(result.totalAttempted == 3)
        #expect(result.totalSaved == 2)
        #expect(result.hasFailures)
        #expect(result.successMessage == "Saved 1 photo and 1 video to your camera roll. Some items couldn't be saved.")
    }
    
    @Test("SharePayload formats public descriptions natively")
    func testSharePayloadNativelyFramesContent() async throws {
        let payload = InsightMediaExportManager.SharePayload(
            commonName: "Test Plant",
            scientificName: "Testus plantus",
            localImagePath: nil,
            approvedRemoteURLs: [
                try #require(URL(string: "https://media.merian.app/share/UUID"))
            ]
        )
        
        #expect(payload.commonName == "Test Plant")
        #expect(payload.scientificName == "Testus plantus")
        #expect(payload.localImagePath == nil)
        #expect(payload.approvedRemoteURLs.count == 1)
    }
}
