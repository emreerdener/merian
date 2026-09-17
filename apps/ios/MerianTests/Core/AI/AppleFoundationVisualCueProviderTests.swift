#if compiler(>=6.4)
import FoundationModels
import Testing

@testable import Merian

/// Exercises Apple's real structured-content parser without loading a model,
/// requiring Apple Intelligence, or sending an image anywhere.
@Suite("Apple Foundation Visual Cue Mapping")
struct AppleFoundationVisualCueProviderTests {
    @available(iOS 27.0, *)
    @Test func schemaCanBeConstructed() throws {
        _ = try AppleFoundationVisualCueGeneration.schema()
    }

    @available(iOS 27.0, *)
    @Test func detailPresenceDoesNotPublishAnUnfinishedObject() throws {
        for json in [
            #"{"cues":[{"kind":"shape","detail":"rounded edg"#,
            #"{"cues":[{"kind":"shape","detail":"rounded edges""#
        ] {
            let content = try GeneratedContent(json: json)
            #expect(AppleFoundationVisualCueGeneration.completedSnapshots(from: content).isEmpty)
        }
    }

    @available(iOS 27.0, *)
    @Test func completedCuePublishesWhileTheNextCueIsStillStreaming() throws {
        let content = try GeneratedContent(json:
            #"{"cues":[{"kind":"shape","detail":"rounded edges"},{"kind":"marking","detail":"dark"#
        )
        #expect(AppleFoundationVisualCueGeneration.completedSnapshots(from: content) == [
            FoundationVisualCueSnapshot(
                index: 0, kind: .shape, detail: "rounded edges", isComplete: true
            )
        ])
    }

    @available(iOS 27.0, *)
    @Test func malformedEntriesDoNotShiftLaterCueIndices() throws {
        let content = try GeneratedContent(json:
            #"{"cues":[{"kind":"species","detail":"a bird"},{"kind":"shape"},{"kind":"marking","detail":"dark bands"}]}"#
        )
        #expect(AppleFoundationVisualCueGeneration.completedSnapshots(from: content) == [
            FoundationVisualCueSnapshot(
                index: 2, kind: .marking, detail: "dark bands", isComplete: true
            )
        ])
    }

    @available(iOS 27.0, *)
    @Test func mappingBoundsEvenAnOversizedResponse() throws {
        let content = try GeneratedContent(json:
            #"{"cues":[{"kind":"shape","detail":"rounded edges"},{"kind":"marking","detail":"dark bands"},{"kind":"arrangement","detail":"radial lines"},{"kind":"tone","detail":"pale areas"}]}"#
        )
        let snapshots = AppleFoundationVisualCueGeneration.completedSnapshots(from: content)
        #expect(snapshots.map(\.index) == [0, 1, 2])
    }

    @available(iOS 27.0, *)
    @Test func completeModelOutputStillPassesThroughIdentityValidation() throws {
        let content = try GeneratedContent(json:
            #"{"cues":[{"kind":"shape","detail":"robin wings"},{"kind":"marking","detail":"confirmed match"},{"kind":"shape","detail":"rounded edges"}]}"#
        )
        var buffer = FoundationVisualCueBuffer()
        let accepted = AppleFoundationVisualCueGeneration.completedSnapshots(from: content)
            .compactMap { buffer.consume($0) }
            .compactMap {
                FoundationVisualCueValidator.validatedCue($0, forbiddenIdentityTerms: ["robin"])
            }
        #expect(accepted == [FoundationVisualCue(kind: .shape, detail: "rounded edges")])
    }

    @available(iOS 27.0, *)
    @Test func emptyOrUnrelatedContentProducesNoCues() throws {
        for json in [#"{"cues":[]}"#, #"{"other":"content"}"#, #"{"cues":"invalid"}"#] {
            let content = try GeneratedContent(json: json)
            #expect(AppleFoundationVisualCueGeneration.completedSnapshots(from: content).isEmpty)
        }
    }
}
#endif
