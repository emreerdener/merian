import Foundation
@testable import Merian
import Testing

@Suite("Media Staging Budget")
struct MediaStagingBudgetTests {
    @Test func ordinaryUploadValidationRejectsUnsupportedM4A() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileName = "unsupported.m4a"
        try Data(repeating: 0x41, count: 512).write(
            to: directory.appendingPathComponent(fileName)
        )
        let payload = PendingScanPayload(
            id: "unsupported-m4a",
            localImagePaths: [],
            localAudioPaths: [fileName],
            localVideoPaths: []
        )
        let uploadItems = MediaStagingContract.uploadItems(
            for: payload,
            userId: "owner",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.invalidResponse) {
            try MediaStagingContract.validateUploadBudget(uploadItems)
        }
    }

    @Test func testMediaStagingContractAllowsCanonicalVideoScanUploadShape() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageNames = (0..<5).map { "video-frame-\($0).webp" }
        let videoName = "playback.mp4"
        for imageName in imageNames {
            try Data(repeating: 0x21, count: 64).write(to: directory.appendingPathComponent(imageName))
        }
        try Data(repeating: 0x42, count: 128).write(to: directory.appendingPathComponent(videoName))

        let payload = PendingScanPayload(
            id: "scan-video-budget",
            localImagePaths: imageNames,
            localAudioPaths: [],
            localVideoPaths: [videoName]
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(items.count == 6)
        try MediaStagingContract.validateUploadBudget(items)
        let uploadFiles = try MediaStagingContract.uploadFiles(for: items)
        #expect(uploadFiles.count == 6)
        #expect(uploadFiles.filter { $0.mediaKind == .image }.count == 5)
        #expect(uploadFiles.filter { $0.mediaKind == .video }.count == 1)
    }

    @Test func testMediaStagingContractRejectsSixStillImagesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageNames = (0...MediaStagingContract.maxImageItemsPerRequest)
            .map { "still-\($0).webp" }
        for imageName in imageNames {
            try Data(repeating: 0x21, count: 64)
                .write(to: directory.appendingPathComponent(imageName))
        }
        let payload = PendingScanPayload(
            id: "scan-too-many-stills",
            localImagePaths: imageNames,
            localAudioPaths: [],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingContractRejectsDuplicateSanitizedDestinationsBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageName = "duplicate.webp"
        try Data(repeating: 0x21, count: 64)
            .write(to: directory.appendingPathComponent(imageName))
        let payload = PendingScanPayload(
            id: "scan-duplicate-media",
            localImagePaths: [imageName, imageName],
            localAudioPaths: [],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.invalidResponse) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingContractRejectsOversizedAudioBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioName = "oversized.wav"
        let audioURL = directory.appendingPathComponent(audioName)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: audioURL)
        try handle.truncate(atOffset: UInt64(ScanMediaPayloadPolicy.maxInferenceAudioBytes + 1))
        try handle.close()

        let payload = PendingScanPayload(
            id: "scan-audio-budget",
            localImagePaths: [],
            localAudioPaths: [audioName],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingContractRejectsEmptyFilesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageName = "empty.webp"
        try Data().write(to: directory.appendingPathComponent(imageName))
        let payload = PendingScanPayload(
            id: "scan-empty-media",
            localImagePaths: [imageName],
            localAudioPaths: [],
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }

    @Test func testMediaStagingContractRejectsTooManyAudioFilesBeforeUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioNames = (0...MediaStagingContract.maxAudioItemsPerRequest).map { "queued-\($0).wav" }
        for audioName in audioNames {
            try makeInferenceTestPCM16WAVData().write(
                to: directory.appendingPathComponent(audioName)
            )
        }

        let payload = PendingScanPayload(
            id: "scan-too-many-audio",
            localImagePaths: [],
            localAudioPaths: audioNames,
            localVideoPaths: []
        )
        let items = MediaStagingContract.uploadItems(
            for: payload,
            userId: "user-a",
            documentsDirectory: directory
        )

        #expect(throws: MerianError.payloadTooLarge) {
            try MediaStagingContract.validateUploadBudget(items)
        }
    }
}
