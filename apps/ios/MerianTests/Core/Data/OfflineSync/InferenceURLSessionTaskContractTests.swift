import Foundation
@testable import Merian
import Testing

@Suite("Inference URLSession Task Contract")
struct InferenceURLSessionTaskContractTests {
    @Test func testInferenceTaskDescriptionPreservesGenerationAndUnderscoredScanId() {
        let scanID = "queued_nonvisual_audio_only"
        let generation = UUID()
        let ownerUserID = UUID()
        let description = InferenceURLSessionTaskContract.taskDescription(
            scanId: scanID,
            generation: generation,
            ownerUserID: ownerUserID
        )

        #expect(
            InferenceURLSessionTaskContract.parse(description)
                == InferenceURLSessionTaskIdentity(
                    scanId: scanID,
                    generation: generation,
                    ownerUserID: ownerUserID
                )
        )
        #expect(
            InferenceURLSessionTaskContract.parse(
                "inference_v2|\(generation.uuidString)|\(scanID)"
            ) == InferenceURLSessionTaskIdentity(
                scanId: scanID,
                generation: generation,
                ownerUserID: nil
            )
        )
        #expect(
            InferenceURLSessionTaskContract.parse("inference_\(scanID)")
                == InferenceURLSessionTaskIdentity(
                    scanId: scanID,
                    generation: nil
                )
        )
    }
}
