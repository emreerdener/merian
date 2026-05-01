import Foundation
import Testing
@testable import Merian

@Suite("Insight Media Export Tests")
struct InsightMediaExportManagerTests {
    
    @Test("SavePhotosPayload natively formats transport strings")
    func testSavePhotosPayloadNativelyFramesStrings() async throws {
        let payload = InsightMediaExportManager.SavePhotosPayload(
            localImagePath: "primary.webp",
            additionalImagePaths: ["secondary.webp", "tertiary.webp"],
            approvedRemoteURLs: [
                try #require(URL(string: "https://media.merian.app/cdn/test.jpg"))
            ]
        )
        
        #expect(payload.localImagePath == "primary.webp")
        #expect(payload.additionalImagePaths?.count == 2)
        #expect(payload.approvedRemoteURLs.count == 1)
        #expect(payload.approvedRemoteURLs.first?.host == "media.merian.app")
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
