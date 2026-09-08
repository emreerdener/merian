@testable import Merian
import Testing

@Suite("Queued Inference Media Policy")
struct QueuedInferenceMediaPolicyTests {
    @Test func acceptsOnlyCoherentLocalWAVReferences() {
        let supported = CapturedMediaSnapshot(items: [
            .audio(.documents("recordings/bird.WAV")),
            .video(StoredVideoMediaReference(
                .documents("capture.mp4"),
                audio: .absolutePath("/tmp/video-audio.wav")
            )),
            .audio(.absolutePath("file:///tmp/field-audio.wav"))
        ])
        let unsupported = [
            CapturedMediaSnapshot(items: [
                .audio(.documents("recording.m4a"))
            ]),
            CapturedMediaSnapshot(items: [
                .audio(.remoteURL(
                    "https://media.example.test/recording.wav"
                ))
            ]),
            CapturedMediaSnapshot(items: [
                .audio(.documents(
                    "https://media.example.test/misclassified.wav"
                ))
            ]),
            CapturedMediaSnapshot(items: [
                .audio(.absolutePath("relative-but-misclassified.wav"))
            ]),
            CapturedMediaSnapshot(items: [
                .audio(.documents("../outside-queue.wav"))
            ]),
            CapturedMediaSnapshot(items: [
                .audio(.absolutePath(
                    "file://media.example.test/tmp/remote.wav"
                ))
            ])
        ]

        #expect(!QueuedInferenceMediaPolicy.containsUnsupportedAudio(
            in: supported
        ))
        for snapshot in unsupported {
            #expect(QueuedInferenceMediaPolicy.containsUnsupportedAudio(
                in: snapshot
            ))
        }
    }
}
