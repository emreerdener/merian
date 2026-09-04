import Foundation
import Testing

@testable import Merian

@Suite("Inference Media Policy")
struct InferenceMediaPolicyTests {
    @Test func budgetValidationPassesWhenUnderLimit() throws {
        let smallImage = String(repeating: "A", count: 100_000)
        let smallAudio = String(repeating: "B", count: 100_000)
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [smallImage],
            audioBase64s: [smallAudio]
        )
    }

    @Test func budgetValidationPassesWhenBothArraysEmpty() throws {
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [],
            audioBase64s: []
        )
    }

    @Test func budgetValidationPassesAtExactLimit() throws {
        let payload = String(
            repeating: "X",
            count: MerianNetworkClient.maxInlineInferenceBodyBytes
        )
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [payload],
            audioBase64s: []
        )
    }

    @Test func budgetValidationThrowsOneByteOverLimit() {
        let payload = String(
            repeating: "X",
            count: MerianNetworkClient.maxInlineInferenceBodyBytes + 1
        )
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(
                imageBase64s: [payload],
                audioBase64s: []
            )
        }
    }

    @Test func budgetValidationThrowsWhenImagesAloneExceedLimit() {
        let largeImage = String(repeating: "Z", count: 4_000_000)
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(
                imageBase64s: [largeImage],
                audioBase64s: []
            )
        }
    }

    @Test func budgetValidationThrowsWhenCombinedImagesAndAudioExceedLimit() {
        let image = String(repeating: "I", count: 2_000_000)
        let audio = String(repeating: "A", count: 2_000_000)
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(
                imageBase64s: [image],
                audioBase64s: [audio]
            )
        }
    }

    @Test func budgetValidationAccumulatesAcrossMultipleImages() throws {
        let image = String(repeating: "M", count: 1_000_000)
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [image, image, image],
            audioBase64s: []
        )
    }

    @Test func inlineAudioBudgetValidationRejectsOversizedFileBeforeEncoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let oversizedAudioURL = directory.appendingPathComponent("oversized.wav")
        FileManager.default.createFile(
            atPath: oversizedAudioURL.path,
            contents: nil
        )
        let handle = try FileHandle(forWritingTo: oversizedAudioURL)
        try handle.truncate(
            atOffset: UInt64(MerianNetworkClient.maxInlineAudioBytes + 1)
        )
        try handle.close()

        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateInlineAudioFileBudget(
                fileURLs: [oversizedAudioURL]
            )
        }
    }
}
