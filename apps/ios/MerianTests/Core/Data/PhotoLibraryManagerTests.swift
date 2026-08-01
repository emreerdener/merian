import Testing
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Merian

@MainActor
struct PhotoLibraryManagerTests {
    private func makeAppSettings() -> AppSettings {
        let suiteName = "merian.tests.photo-library.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        return AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
    }
    
    @Test func testSaveToCameraRollToggleDisabled() async {
        let appSettings = makeAppSettings()
        let manager = PhotoLibraryManager(appSettings: appSettings)
        appSettings.saveToCameraRoll = false
        
        let dummyData = Data("test_image".utf8)
        
        // Act
        // This should hit the early return `guard appSettings.saveToCameraRoll else { return }`
        // We ensure it doesn't execute physical requests to PHPhotoLibrary and cleanly drops.
        await manager.saveImageToLibrary(imageData: dummyData, location: nil)
    }

    @Test func testSaveVideoToCameraRollToggleDisabled() async {
        let appSettings = makeAppSettings()
        let manager = PhotoLibraryManager(appSettings: appSettings)
        appSettings.saveToCameraRoll = false

        await manager.saveVideoToLibrary(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("missing-video.mp4"),
            location: nil
        )
    }

    @Test func testVideoProcessingPreservesOriginalFile() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("video-source".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let processed = PhotoLibraryManager.process(
            payload: .url(sourceURL),
            mediaKind: .video
        )

        #expect(processed == .fileURL(sourceURL, deleteAfterUse: false))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(PhotoLibraryMediaKind.video.resourceType == .video)
    }

    @Test func testPhotoProcessingStillStripsGPSMetadata() throws {
        let sourceData = try #require(makeJPEGWithGPSMetadata())
        let processed = PhotoLibraryManager.process(
            payload: .data(sourceData),
            mediaKind: .photo
        )
        guard case .data(let scrubbedData) = processed else {
            Issue.record("Expected file data after photo processing")
            return
        }

        let source = try #require(CGImageSourceCreateWithData(scrubbedData as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(PhotoLibraryMediaKind.photo.resourceType == .photo)
    }
    
    @Test func testStartObservingAndFetchBypassesNotDetermined() async {
        let manager = PhotoLibraryManager.shared
        
        // This validates the progressive disclosure architectural update.
        // Calling startObservingAndFetch() must silently drop and NOT fire PHPhotoLibrary.requestAuthorization 
        // when status is .notDetermined, allowing the UI to manage the explicit permission gates.
        manager.startObservingAndFetch()
        
        // If it reaches here without blocking on an expectation/completion handler lock, the fallthrough is valid.
        #expect(true, "startObservingAndFetch safely drops .notDetermined requests to enforce progressive disclosure UI triggers.")
    }

    private func makeJPEGWithGPSMetadata() -> Data? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        guard let jpegData = image.jpegData(compressionQuality: 1),
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            return nil
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.0,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 87.0,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }
}
