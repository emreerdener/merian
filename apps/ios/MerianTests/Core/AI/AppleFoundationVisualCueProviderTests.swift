#if compiler(>=6.4)
import Foundation
import FoundationModels
import Testing
import XCTest

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
            #"{"cues":[{"kind":"shape","detail":"rounded edges"},{"kind":"marking","detail":"dark bands"},{"kind":"arrangement","detail":"radial lines"},{"kind":"tone","detail":"pale areas"},{"kind":"structure","detail":"thin branches"},{"kind":"surfaceTexture","detail":"rough surface"},{"kind":"colorPattern","detail":"green patches"}]}"#
        )
        let snapshots = AppleFoundationVisualCueGeneration.completedSnapshots(from: content)
        #expect(snapshots.map(\.index) == [0, 1, 2, 3, 4, 5])
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

/// Diagnostic-only observation. This does not qualify transport resources.
final class SimulatorRuntimeIdentityTests: XCTestCase {
    func testRecordsBootedGuestIdentity() throws {
        #if targetEnvironment(simulator) && arch(arm64)
        let environment = ProcessInfo.processInfo.environment
        let version = try XCTUnwrap(environment["SIMULATOR_RUNTIME_VERSION"])
        let build = try XCTUnwrap(environment["SIMULATOR_RUNTIME_BUILD_VERSION"])
        let model = try XCTUnwrap(environment["SIMULATOR_MODEL_IDENTIFIER"])
        guard version == "27.2", build == "24B8117",
              model.range(of: #"^iPhone[0-9]{1,2},[0-9]{1,2}$"#, options: .regularExpression) != nil else {
            throw NSError(domain: "MerianSimulatorIdentity", code: 1)
        }
        let payload = try JSONSerialization.data(withJSONObject: [
            "runtime_version": version, "runtime_build": build, "model_identifier": model
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: payload, as: UTF8.self))
        attachment.name = "merian-simulator-identity.json"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Observe guest simulator identity") { activity in
            activity.add(attachment)
        }
        #else
        XCTFail("Identity discovery requires an arm64 simulator")
        #endif
    }
}
#endif
