import Foundation
import Testing

@testable import Merian

@Suite("Staged Video Upload Planning")
struct StagedVideoUploadPlanTests {
    @Test(arguments: [false, true])
    func absoluteAndFileURLPathsRetainWhitespaceNormalization(useFileURL: Bool) throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write(name: "synthetic clip.mp4")
        let path = useFileURL ? file.absoluteString : file.path
        let plan = try StagedVideoUploadPlan.make(videoFilePaths: [" \n\(path)\t "], scanId: "synthetic scan")
        #expect(plan.fileURLs == [file])
        #expect(plan.uploadFiles == [StagingUploadFile(
            fileName: "synthetic_scan_synthetic_clip.mp4", mediaKind: .video, contentType: "video/mp4",
            sizeBytes: MediaUploadTestFixtures.bytes.count, clientScanId: "synthetic scan", mediaRole: "playback"
        )])
    }

    @Test(arguments: [0, 1, 2])
    func emptyBlankAndAbsentInputsKeepMissingFileFailure(kind: Int) throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let absent = files.directory.appendingPathComponent("absent-\(UUID().uuidString).mp4")
        let paths = kind == 0 ? [] : kind == 1 ? [" \t\n "] : [absent.path]
        #expect(throws: CocoaError(.fileNoSuchFile)) {
            try StagedVideoUploadPlan.make(videoFilePaths: paths, scanId: "synthetic")
        }
    }

    @Test func partialAbsencePrecedesZeroSizeValidation() throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let empty = try files.write(Data())
        let absent = files.directory.appendingPathComponent("absent-\(UUID().uuidString).mp4")
        #expect(throws: CocoaError(.fileNoSuchFile)) {
            try StagedVideoUploadPlan.make(videoFilePaths: [empty.path, absent.path], scanId: "synthetic")
        }
    }

    @Test(arguments: [0, 1, 2])
    func byteBudgetKeepsEmptyMaximumAndOverMaximumBoundaries(kind: Int) throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let size = kind == 0 ? 0 : MerianConfig.videoPayloadMaxBytes + (kind == 2 ? 1 : 0)
        let file = try files.sizedFile(size)
        if kind == 1 {
            let plan = try StagedVideoUploadPlan.make(videoFilePaths: [file.path], scanId: "synthetic")
            #expect(plan.uploadFiles.first?.sizeBytes == MerianConfig.videoPayloadMaxBytes)
        } else {
            #expect(throws: MerianError.payloadTooLarge) {
                try StagedVideoUploadPlan.make(videoFilePaths: [file.path], scanId: "synthetic")
            }
        }
    }

    @Test func moreThanTheExistingVideoCapFailsWithoutDroppingEntries() throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        let paths = Array(repeating: file.path, count: MerianConfig.mediaStagingMaxVideoFilesPerRequest + 1)
        #expect(throws: MerianError.payloadTooLarge) {
            try StagedVideoUploadPlan.make(videoFilePaths: paths, scanId: "synthetic")
        }
    }

    @Test func stalePathsRetainTemporaryBasenameFallback() throws {
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let name = "merian-video-fallback-\(UUID().uuidString).mp4"
        let current = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try MediaUploadTestFixtures.bytes.write(to: current, options: .atomic)
        defer { try? FileManager.default.removeItem(at: current) }
        let stale = files.directory.appendingPathComponent("old").appendingPathComponent(name)
        let plan = try StagedVideoUploadPlan.make(videoFilePaths: [stale.path], scanId: "synthetic")
        #expect(plan.fileURLs == [current])
    }
}
