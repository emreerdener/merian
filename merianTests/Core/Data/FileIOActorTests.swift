import Testing
import Foundation
@testable import Merian

@Suite("File IO Actor Mocks", .serialized)
struct FileIOActorTests {

    @Test func testWriteTemporaryImagesMaintainsOrder() async throws {
        // Arrange
        let mockBuffers = [
            Data(repeating: 0x01, count: 64),
            Data(repeating: 0x02, count: 64),
            Data(repeating: 0x03, count: 64)
        ]
        
        // Act
        let writtenPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: mockBuffers)
        
        // Assert
        #expect(writtenPaths.count == 3, "FileIOActor must precisely return paths mapping index bounds perfectly")
        
        let docs = URL.documentsDirectory
        for path in writtenPaths {
            #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent(path).path) == true)
        }
        
        // Cleanup natively
        await FileIOActor.shared.deleteImages(at: writtenPaths)
    }

    @Test func testDeleteImagesDropsValidBlobs() async throws {
        // Arrange
        let mockData = Data(repeating: 0x04, count: 32)
        let filename = "mock_deletion_file_\(UUID().uuidString).webp"
        let docs = URL.documentsDirectory
        let fullPath = docs.appendingPathComponent(filename)
        
        try mockData.write(to: fullPath)
        #expect(FileManager.default.fileExists(atPath: fullPath.path) == true)
        
        // Act
        // Pass a valid file AND a completely invalid ghost file
        await FileIOActor.shared.deleteImages(at: [filename, "ghost_file_does_not_exist.webp"])
        
        // Assert
        #expect(FileManager.default.fileExists(atPath: fullPath.path) == false, "FileIOActor must natively purge files")
    }

    @Test func testValidPathsFiltersDeadPaths() async throws {
        // Arrange
        let mockData = Data(repeating: 0x05, count: 32)
        let localFilename = "mock_valid_file_\(UUID().uuidString).webp"
        let docs = URL.documentsDirectory
        try mockData.write(to: docs.appendingPathComponent(localFilename))
        
        let candidates = [
            "https://example.com/remote_image.jpg", // HTTP links are intrinsically valid
            localFilename,                          // Exists physically
            "ghost_local_fallback.webp"             // Does NOT exist physically
        ]
        
        // Act
        let filtered = await FileIOActor.shared.validPaths(from: candidates)
        
        // Assert
        #expect(filtered.count == 2)
        #expect(filtered.contains("https://example.com/remote_image.jpg"))
        #expect(filtered.contains(localFilename))
        
        // Cleanup
        await FileIOActor.shared.deleteImages(at: [localFilename])
    }
}
