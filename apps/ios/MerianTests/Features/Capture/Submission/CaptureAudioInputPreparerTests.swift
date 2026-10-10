import Foundation
@testable import Merian
import os
import Testing

@MainActor
struct CaptureAudioInputPreparerTests {
    @Test(arguments: ["success", "failure", "cancel"], [false, true])
    func scopeEndsAfterCleanupForEveryOutcome(mode: String, acquired: Bool) async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("prepared")
        let events = OSAllocatedUnfairLock(initialState: [String]())
        let scope = CaptureAudioInputPreparer.SecurityScope(start: { _ in
            events.withLock { $0.append("start") }; return acquired
        }, stop: { _ in
            let empty = (try? FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty) == true
            events.withLock { $0.append(empty ? "stop-clean" : "stop-dirty") }
        })
        let preparer = CaptureAudioInputPreparer(directory: output, securityScope: scope, transcode: { _, directory in
            events.withLock { $0.append("convert") }
            let file = directory.appendingPathComponent("output.wav")
            try makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) }).write(to: file)
            if mode == "failure" { throw MerianError.invalidResponse }
            if mode == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return file
        })
        let task = Task { try await preparer.prepare(root.appendingPathComponent("source.wav")) }
        let result = await task.result
        switch result {
        case let .success(bytes): #expect(mode == "success" && ObservationAudioContainer.isValid(bytes))
        case .failure: #expect(mode != "success")
        }
        #expect(events.withLock { $0 } == (acquired ? ["start", "convert", "stop-clean"] : ["start", "convert"]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test func realConversionPreservesSourceAndCleansTemporaryOutput() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.wav"), output = root.appendingPathComponent("prepared")
        let input = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 128, sampleAt: { Int16($0) })
        try input.write(to: source)
        let bytes = try await CaptureAudioInputPreparer(directory: output).prepare(source)
        #expect(ObservationAudioContainer.isValid(bytes))
        #expect(try inferenceTestWAVPCMData(bytes) == inferenceTestWAVPCMData(input))
        #expect(try Data(contentsOf: source) == input)
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test(arguments: ["malformed", "oversized", "outside", "symlink", "throw"])
    func invalidOutputNeverReturnsBytesAndRemovesOwnedDirectory(mode: String) async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.wav"), output = root.appendingPathComponent("prepared")
        let input = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
        try input.write(to: source)
        let preparer = CaptureAudioInputPreparer(directory: output, transcode: { _, directory in
            let file = directory.appendingPathComponent("output.wav")
            if mode == "outside" { return source }
            if mode == "symlink" {
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: source)
            } else {
                try Data(repeating: 0, count: mode == "oversized" ? 2_700_001 : 48).write(to: file)
            }
            if mode == "throw" { throw MerianError.invalidResponse }
            return file
        })
        await #expect(throws: (any Error).self) { try await preparer.prepare(source) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
        #expect(try Data(contentsOf: source) == input)
    }
}
