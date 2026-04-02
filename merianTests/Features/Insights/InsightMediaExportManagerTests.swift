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
            referenceImageUrl: "https://merian.app/cdn/test.jpg"
        )
        
        #expect(payload.localImagePath == "primary.webp")
        #expect(payload.additionalImagePaths?.count == 2)
        #expect(payload.referenceImageUrl == "https://merian.app/cdn/test.jpg")
    }
    
    @Test("SharePayload formats public descriptions natively")
    func testSharePayloadNativelyFramesContent() async throws {
        let payload = InsightMediaExportManager.SharePayload(
            commonName: "Test Plant",
            scientificName: "Testus plantus",
            localImagePath: nil,
            referenceImageUrl: "https://merian.app/share/UUID"
        )
        
        #expect(payload.commonName == "Test Plant")
        #expect(payload.scientificName == "Testus plantus")
        #expect(payload.localImagePath == nil)
        #expect(payload.referenceImageUrl != nil)
    }
}
