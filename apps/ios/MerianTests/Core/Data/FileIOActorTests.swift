import Testing
import Foundation
import Darwin
import SwiftData
@testable import Merian

@Suite("Legacy file ownership", .serialized)
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

    @Test func testDeleteFilesDropsBareTemporaryFilenames() async throws {
        let filename = "mock_temp_deletion_file_\(UUID().uuidString).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try Data(repeating: 0x14, count: 32).write(to: tempURL)
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == true)

        await FileIOActor.shared.deleteFiles(at: [filename])

        #expect(
            FileManager.default.fileExists(atPath: tempURL.path) == false,
            "Bare staged audio filenames may still live in NSTemporaryDirectory and must be purged"
        )
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

    @Test func testPersistAudioFileAdoptsExistingDocumentsFilename() async throws {
        let filename = "existing_audio_\(UUID().uuidString).wav"
        let docs = URL.documentsDirectory
        let destinationURL = docs.appendingPathComponent(filename)
        let audioData = Data(repeating: 0x11, count: 256)

        try audioData.write(to: destinationURL)
        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let persisted = await FileIOActor.shared.persistAudioFile(tempPath: filename)

        #expect(persisted == filename, "Existing Documents audio should be adopted without creating a duplicate file")
        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == true)
    }

    @Test func testPersistAudioFileCopiesBareTemporaryFilename() async throws {
        let filename = "temporary_audio_\(UUID().uuidString).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let audioData = Data(repeating: 0x22, count: 256)

        try audioData.write(to: tempURL)

        let persisted = try #require(await FileIOActor.shared.persistAudioFile(tempPath: filename))
        let docsURL = URL.documentsDirectory.appendingPathComponent(persisted)
        defer {
            try? FileManager.default.removeItem(at: docsURL)
        }

        #expect(FileManager.default.fileExists(atPath: docsURL.path) == true, "Temporary audio should be copied into Documents")
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false, "Original temporary audio should be removed after persistence")
    }

    @Test func testPersistAudioFileCopiesAbsoluteTemporaryPath() async throws {
        let filename = "absolute_audio_\(UUID().uuidString).wav"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let audioData = Data(repeating: 0x33, count: 256)

        try audioData.write(to: tempURL)

        let persisted = try #require(await FileIOActor.shared.persistAudioFile(tempPath: tempURL.path))
        let docsURL = URL.documentsDirectory.appendingPathComponent(persisted)
        defer {
            try? FileManager.default.removeItem(at: docsURL)
        }

        #expect(FileManager.default.fileExists(atPath: docsURL.path) == true, "Absolute temporary audio paths should also be copied into Documents")
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false, "The original absolute temporary audio file should be removed after persistence")
    }

    @Test func privateNamespacesAndDirectoriesSurviveEveryGenericEntryPoint() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        for root in [h.documents, h.temporary, h.base.appendingPathComponent("ApplicationSupport")] {
            for namespace in ["PhotoPreparation", "ReanalysisQueue", "ExternalImageImports"] {
                let directory = root.appendingPathComponent(namespace)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("original.wav")
                let bytes = Data([1, 2, 3, 4])
                try bytes.write(to: file)
                let paths = [file.path, directory.path, "\(namespace)/original.wav", namespace]
                await h.actor.deleteFiles(at: paths)
                await h.actor.deleteAudioFiles(at: paths)
                await h.actor.deleteImages(at: paths)
                #expect(await h.actor.validPaths(from: paths).isEmpty)
                #expect(await h.actor.persistAudioFile(tempPath: file.path) == nil)
                #expect(await h.actor.persistVideoFile(tempPath: file.path) == nil)
                #expect(try Data(contentsOf: file) == bytes)
            }
        }
    }

    @Test func absoluteInputNeverSubstitutesDocumentsBasename() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let doc = h.documents.appendingPathComponent("same.wav")
        let temp = h.temporary.appendingPathComponent("same.wav")
        try Data([1]).write(to: doc)
        let bytes = Data(repeating: 0x34, count: 150_001)
        try bytes.write(to: temp)
        let name = try #require(await h.actor.persistAudioFile(tempPath: temp.path))
        #expect(name != doc.lastPathComponent)
        #expect(try Data(contentsOf: h.documents.appendingPathComponent(name)) == bytes)
        #expect(try Data(contentsOf: doc) == Data([1]))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        let outside = h.base.appendingPathComponent("same.wav")
        try Data([3]).write(to: outside)
        #expect(await h.actor.persistVideoFile(tempPath: outside.path) == nil)
        #expect(await h.actor.persistAudioFile(tempPath: h.temporary.appendingPathComponent("missing.wav").path) == nil)
        #expect(try Data(contentsOf: outside) == Data([3]))
    }

    @Test func flatAbsoluteAndBareLookupRemainCompatible() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let doc = h.documents.appendingPathComponent("clip.mp4")
        let temp = h.temporary.appendingPathComponent("clip.mp4")
        try Data([1]).write(to: doc); try Data([2]).write(to: temp)
        #expect(await h.actor.persistVideoFile(tempPath: "clip.mp4") == "clip.mp4")
        #expect(await h.actor.persistVideoFile(tempPath: doc.path) == "clip.mp4")
        #expect(await h.actor.validPaths(from: [doc.path, temp.path, "clip.mp4"]).count == 3)
        await h.actor.deleteAudioFiles(at: ["clip.mp4"])
        #expect(!FileManager.default.fileExists(atPath: doc.path))
        #expect(FileManager.default.fileExists(atPath: temp.path))
        #expect(await h.actor.validPaths(from: ["clip.mp4"]).isEmpty)
        let copied = try #require(await h.actor.persistVideoFile(tempPath: "clip.mp4"))
        #expect(try Data(contentsOf: h.documents.appendingPathComponent(copied)) == Data([2]))
        await h.actor.deleteFiles(at: [h.documents.appendingPathComponent(copied).path])
        #expect(!FileManager.default.fileExists(atPath: h.documents.appendingPathComponent(copied).path))
        try Data([4]).write(to: doc); try Data([5]).write(to: temp)
        await h.actor.deleteFiles(at: ["clip.mp4"])
        #expect(!FileManager.default.fileExists(atPath: doc.path))
        #expect(!FileManager.default.fileExists(atPath: temp.path))
        try Data([6]).write(to: temp)
        await h.actor.deleteAudioFiles(at: [temp.path])
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }

    @Test func traversalLinksAndBasenameFallbackCannotEscapeOwnership() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let outside = h.base.appendingPathComponent("original.wav")
        try Data([7, 8]).write(to: outside)
        let symlink = h.documents.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let hardlink = h.temporary.appendingPathComponent("hard.wav")
        try FileManager.default.linkItem(at: outside, to: hardlink)
        let fallback = h.temporary.appendingPathComponent("linked.wav")
        try Data([9]).write(to: fallback)
        let paths = [symlink.path, hardlink.path, outside.path,
                     "../original.wav", h.documents.path + "/../original.wav", "linked.wav"]
        #expect(await h.actor.validPaths(from: paths).isEmpty)
        for path in paths {
            #expect(await h.actor.persistAudioFile(tempPath: path) == nil)
            #expect(await h.actor.persistVideoFile(tempPath: path) == nil)
        }
        #expect(try Data(contentsOf: fallback) == Data([9]))
        await h.actor.deleteFiles(at: Array(paths.dropLast()))
        await h.actor.deleteAudioFiles(at: paths)
        #expect(try Data(contentsOf: outside) == Data([7, 8]))
        #expect(try Data(contentsOf: hardlink) == Data([7, 8]))
        #expect(FileManager.default.fileExists(atPath: symlink.path))
    }

    @Test func busyDestinationAndReplacedRootRetainTemporarySource() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let temp = h.temporary.appendingPathComponent("retained.wav")
        try Data([1, 2, 3]).write(to: temp)
        let fd = Darwin.open(h.documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        #expect(fd >= 0)
        defer { Darwin.close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(await h.actor.persistAudioFile(tempPath: temp.path) == nil)
        #expect(try Data(contentsOf: temp) == Data([1, 2, 3]))
        #expect(flock(fd, LOCK_UN) == 0)
        let moved = h.base.appendingPathComponent("old-documents")
        try FileManager.default.moveItem(at: h.documents, to: moved)
        try FileManager.default.createSymbolicLink(at: h.documents, withDestinationURL: moved)
        #expect(await h.actor.persistVideoFile(tempPath: temp.path) == nil)
        #expect(try Data(contentsOf: temp) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func shortPositiveWritesPreserveExactCopiedBytes() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let source = h.temporary.appendingPathComponent("short-writes.wav")
        let bytes = Data((0..<65_543).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        var io = FileIOActor.CopyIO.live
        io.write = { fd, buffer in Darwin.write(fd, buffer.baseAddress, min(7, buffer.count)) }
        let actor = FileIOActor(documents: h.documents, temporaryDirectory: h.temporary, copyIO: io)
        let result = try #require(await actor.persistAudioFile(tempPath: source.path))
        #expect(try Data(contentsOf: h.documents.appendingPathComponent(result)) == bytes)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test(arguments: ["write", "fileFlush", "directoryFlush", "sourceReplacement", "sourceMutation"])
    func interruptedCopyRetainsSourceAndRemovesOwnedPartial(failure: String) async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let source = h.temporary.appendingPathComponent("source.wav")
        let bytes = Data(repeating: 0x5a, count: 150_001)
        try bytes.write(to: source)
        let io = FileIOActor.CopyIO(
            write: { fd, buffer in
                let offset = lseek(fd, 0, SEEK_CUR)
                if failure == "write", offset > 0 { errno = EIO; return -1 }
                if offset == 0, failure == "sourceReplacement" {
                    do { try Data([9]).write(to: source, options: .atomic) }
                    catch { return -1 }
                }
                if offset == 0, failure == "sourceMutation" {
                    do {
                        let handle = try FileHandle(forWritingTo: source)
                        try handle.truncate(atOffset: 1)
                        try handle.close()
                    } catch { return -1 }
                }
                return Darwin.write(fd, buffer.baseAddress, buffer.count)
            },
            synchronize: { fd in
                var info = stat()
                guard fstat(fd, &info) == 0 else { return -1 }
                if failure == "fileFlush", info.st_mode & S_IFMT == S_IFREG { errno = EIO; return -1 }
                if failure == "directoryFlush", info.st_mode & S_IFMT == S_IFDIR { errno = EIO; return -1 }
                return fsync(fd)
            }
        )
        let actor = FileIOActor(documents: h.documents, temporaryDirectory: h.temporary, copyIO: io)
        #expect(await actor.persistAudioFile(tempPath: source.path) == nil)
        let expected = failure == "sourceReplacement" ? Data([9]) : failure == "sourceMutation" ? Data([0x5a]) : bytes
        #expect(try Data(contentsOf: source) == expected)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.documents.path).isEmpty)
    }

    @Test func sourceMutationDuringDestinationFlushIsNotUnlinked() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let source = h.temporary.appendingPathComponent("source.mp4")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: source)
        var io = FileIOActor.CopyIO.live
        io.synchronize = { fd in
            var info = stat()
            guard fstat(fd, &info) == 0 else { return -1 }
            if info.st_mode & S_IFMT == S_IFREG {
                do {
                    let handle = try FileHandle(forWritingTo: source)
                    try handle.truncate(atOffset: 1)
                    try handle.close()
                } catch { return -1 }
            }
            return fsync(fd)
        }
        let actor = FileIOActor(documents: h.documents, temporaryDirectory: h.temporary, copyIO: io)
        let result = try #require(await actor.persistVideoFile(tempPath: source.path))
        #expect(try Data(contentsOf: h.documents.appendingPathComponent(result)) == bytes)
        #expect(try Data(contentsOf: source) == Data([1]))
    }

    @Test func postUnlinkSyncFailureKeepsFlushedDestination() async throws {
        let h = try LegacyFileFixture(); defer { h.cleanup() }
        let source = h.temporary.appendingPathComponent("source.mp4")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: source)
        var io = FileIOActor.CopyIO.live
        io.synchronize = { fd in
            if !FileManager.default.fileExists(atPath: source.path) { errno = EIO; return -1 }
            return fsync(fd)
        }
        let actor = FileIOActor(documents: h.documents, temporaryDirectory: h.temporary, copyIO: io)
        let result = try #require(await actor.persistVideoFile(tempPath: source.path))
        #expect(try Data(contentsOf: h.documents.appendingPathComponent(result)) == bytes)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test @MainActor func genericCleanupCannotReleaseSharedOriginal() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let first = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "picker", load: { bytes })
        let second = try await owner.shareOriginal(first, packageID: UUID(), draftGeneration: UUID())
        let asset = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationAsset>()).first)
        let file = h.root.appendingPathComponent("PhotoPreparation").appendingPathComponent(asset.fileToken)
        let actor = FileIOActor(documents: h.root, temporaryDirectory: FileManager.default.temporaryDirectory)
        await actor.deleteFiles(at: [file.path, "PhotoPreparation/" + asset.fileToken, h.root.appendingPathComponent("PhotoPreparation").path])
        await actor.deleteAudioFiles(at: [file.path])
        #expect(await actor.persistVideoFile(tempPath: file.path) == nil)
        #expect(try await owner.originalData(first) == bytes)
        #expect(try await owner.originalData(second) == bytes)
        let draft = try #require(try await owner.recover().first { $0.packageID == first.packageID })
        try await owner.discard(packageID: draft.packageID, revision: draft.revision)
        #expect(try await owner.originalData(second) == bytes)
        let survivor = try #require(try await owner.recover().first)
        try await owner.discard(packageID: survivor.packageID, revision: survivor.revision)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
    }

}


private struct LegacyFileFixture {
    let base: URL
    let documents: URL
    let temporary: URL
    let actor: FileIOActor

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-media-" + UUID().uuidString)
        documents = base.appendingPathComponent("Documents")
        temporary = base.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        actor = FileIOActor(documents: documents, temporaryDirectory: temporary)
    }

    func cleanup() { try? FileManager.default.removeItem(at: base) }
}
