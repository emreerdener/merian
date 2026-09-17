import Foundation
@testable import Merian
import Testing

@MainActor
struct CapturedMediaValuesTests {
    @Test func observationContextNormalizesPresentationWithoutMutatingStorage() throws {
        let context = ObservationContext(freeText: "  Seen beside the creek. \n")
        let empty = ObservationContext(freeText: " \n\t ")
        let encoded = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ObservationContext.self, from: encoded)

        #expect(context.freeText == "  Seen beside the creek. \n")
        #expect(context.trimmedFreeText == "Seen beside the creek.")
        #expect(context.serialized() == "Seen beside the creek.")
        #expect(!context.isEmpty)
        #expect(empty.isEmpty)
        #expect(empty.serialized().isEmpty)
        #expect(decoded == context)
    }

    @Test func storedMediaReferenceRoundTripsOptionalSourceIdentity() throws {
        let reference = StoredMediaReference.remoteURL(
            "https://cdn.example.com/second.wav",
            sourceIndex: 1
        )

        let data = try JSONEncoder().encode(reference)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(
            StoredMediaReference.self,
            from: data
        )
        let snakeCase = try JSONDecoder().decode(
            StoredMediaReference.self,
            from: Data(
                #"{"storage":"remoteURL","path":"https://cdn.example.com/second.wav","source_index":1}"#.utf8
            )
        )
        let legacy = try JSONDecoder().decode(
            StoredMediaReference.self,
            from: Data(#""legacy.wav""#.utf8)
        )
        let malformedIdentity = try JSONDecoder().decode(
            StoredMediaReference.self,
            from: Data(
                #"{"storage":"remoteURL","path":"https://cdn.example.com/second.wav","sourceIndex":"one"}"#.utf8
            )
        )

        #expect(object["sourceIndex"] as? Int == 1)
        #expect(object["source_index"] == nil)
        #expect(decoded == reference)
        #expect(snakeCase == reference)
        #expect(legacy.sourceIndex == nil)
        #expect(malformedIdentity.sourceIndex == nil)
        #expect(malformedIdentity.serializedPath == reference.serializedPath)
    }

    @Test func canonicalManifestDecodesDescriptionsAndAudioInServerOrder() throws {
        let payload = Data(
            """
            [
              {"description":{"_0":{"freeText":"Before the call","addedAt":123456}}},
              {"audio":{"_0":{"storage":"remoteURL","path":"https://cdn.example.com/call.wav","sourceIndex":0}}},
              {"description":{"_0":{"freeText":"After the call"}}}
            ]
            """.utf8
        )
        let before = ObservationContext(freeText: "Before the call")
        let after = ObservationContext(freeText: "After the call")

        let decoded = try JSONDecoder().decode([SerializedMediaItem].self, from: payload)

        #expect(decoded == [
            .description(before),
            .audio(.remoteURL("https://cdn.example.com/call.wav", sourceIndex: 0)),
            .description(after)
        ])
    }

    @Test func audioPathsPreserveTimelineAndIgnoreUnsubmittableVideoAudio() {
        let snapshot = CapturedMediaSnapshot(items: [
            .audio(.documents("first.wav")),
            .video(StoredVideoMediaReference(
                .documents("clip.mp4"),
                audio: .documents("clip.wav")
            )),
            .video(StoredVideoMediaReference(
                .documents(""),
                audio: .documents("orphaned.wav")
            )),
            .audio(.documents("")),
            .audio(.documents("last.wav"))
        ])

        #expect(snapshot.audioPaths == ["first.wav", "clip.wav", "last.wav"])
    }
}
