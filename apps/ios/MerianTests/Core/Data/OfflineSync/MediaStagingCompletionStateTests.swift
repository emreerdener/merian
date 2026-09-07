@testable import Merian
import XCTest

final class MediaStagingCompletionStateTests: XCTestCase {
    func test_processUploadCompletion_defersInferenceUntilEveryKeySucceeds() {
        let generation = UUID()
        let firstKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_0.webp"
        let secondKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_1.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)

        completion.recordSuccess(objectKey: secondKey)

        XCTAssertFalse(
            completion.matchesExactly(expectedObjectKeys: [firstKey, secondKey]),
            "Task disappearance is not success evidence for the missing first key."
        )
    }

    func test_processUploadCompletion_acceptsOutOfOrderSuccessForEveryExactKey() {
        let generation = UUID()
        let firstKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_0.webp"
        let secondKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_1.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)

        completion.recordSuccess(objectKey: secondKey)
        completion.recordSuccess(objectKey: firstKey)

        XCTAssertTrue(
            completion.matchesExactly(expectedObjectKeys: [firstKey, secondKey])
        )
    }

    func test_processUploadCompletion_rejectsSuccessfulKeysOutsideExactManifest() {
        let generation = UUID()
        let firstKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_0.webp"
        let secondKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image_1.webp"
        let staleKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/stale_image.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)

        completion.recordSuccess(objectKey: firstKey)
        completion.recordSuccess(objectKey: secondKey)
        completion.recordSuccess(objectKey: staleKey)

        XCTAssertFalse(
            completion.matchesExactly(expectedObjectKeys: [firstKey, secondKey]),
            "A successful stale upload must not be silently omitted from the durable manifest."
        )
    }

    func test_processUploadCompletion_rejectsDuplicateExpectedKeys() {
        let generation = UUID()
        let objectKey = "staging/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/scan_image.webp"
        var completion = MediaStagingUploadCompletionState(generation: generation)
        completion.recordSuccess(objectKey: objectKey)

        XCTAssertFalse(
            completion.matchesExactly(expectedObjectKeys: [objectKey, objectKey]),
            "Expected manifests must remain duplicate-free rather than collapsing through Set."
        )
    }
}
