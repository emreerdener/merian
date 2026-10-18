import Foundation
import Testing
@testable import Merian

@Suite("Native preparation codecs")
struct SharedMediaNativePreparationCodecTests {
    @Test func nativeEnvelopeRejectsUnknownFieldsAndLegacyReaderRejectsV2() throws {
        let value = try envelope(), bytes = try value.encoded()
        #expect(try SharedMediaNativeDraftEnvelope.V2.decode(bytes).encoded() == bytes)
        #expect(throws: (any Error).self) { try PhotoPreparationPolicy.decodeDraft(bytes) }
        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["unrecognized"] = true
        let extra = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try SharedMediaNativeDraftEnvelope.V2.decode(extra) }
        let duplicate = Data(("{\"sequence\":1," + String(decoding: bytes.dropFirst(), as: UTF8.self)).utf8)
        #expect(throws: (any Error).self) { try SharedMediaNativeDraftEnvelope.V2.decode(duplicate) }
    }

    @Test func typedIntentBytesSurviveSupportingTextEdits() throws {
        let request = try attempt(), intent = try intent(request), blob = try SharedMediaNativePreparationBlob(bytes: intent.encoded())
        let value = SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: [], presentation: [], sequence: 1,
            attempt: nil, intents: [blob], frozen: nil)
        let bytes = try SharedMediaNativeDraftEnvelope.preparation(value).editing(contexts: [.init(freeText: " exact text \n")], presentation: [])
        let edited = try SharedMediaNativeDraftEnvelope.V2.decode(bytes)
        #expect(edited.intents == [blob] && edited.sequence == value.sequence)
        #expect(edited.contexts.first?.freeText == " exact text \n")
        #expect(try SharedMediaNativeDerivativeIntent.decode(blob.bytes).preparation == SharedMediaNativePreparedIdentity(attempt: request))
    }

    @Test func malformedOrDuplicatedIntentCannotBecomeAuthority() throws {
        let request = try attempt(), intent = try intent(request), blob = try SharedMediaNativePreparationBlob(bytes: intent.encoded())
        let repeated = SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: [], presentation: [], sequence: 1,
            attempt: nil, intents: [blob, blob], frozen: nil)
        #expect(throws: (any Error).self) { try repeated.encoded() }
        var json = try #require(JSONSerialization.jsonObject(with: intent.encoded()) as? [String: Any])
        var ai = try #require(json["ai"] as? [String: Any]); ai["role"] = "original"; json["ai"] = ai
        let invalid = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try SharedMediaNativeDerivativeIntent.decode(invalid) }
        var envelopeJSON = try #require(JSONSerialization.jsonObject(with: envelope().encoded()) as? [String: Any])
        var pending = try #require(envelopeJSON["attempt"] as? [String: Any]); pending["sha256"] = String(repeating: "0", count: 64)
        envelopeJSON["attempt"] = pending
        let altered = try JSONSerialization.data(withJSONObject: envelopeJSON, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try SharedMediaNativeDraftEnvelope.V2.decode(altered) }
    }

    @Test func outputFocusRoundTripsAndRemainsBoundToExactIntentBytes() throws {
        let focus = NormalizedImageFocusRegion(x: 0.25, y: 0.125, width: 0.5, height: 0.75)
        let value = try intent(attempt(), focus: focus), bytes = try value.encoded()
        #expect(try SharedMediaNativeDerivativeIntent.decode(bytes).focus == focus)
        let blob = SharedMediaNativePreparationBlob(bytes: bytes)
        let draft = SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: [], presentation: [], sequence: 1,
            attempt: nil, intents: [blob], frozen: nil)
        let edited = try SharedMediaNativeDraftEnvelope.preparation(draft).editing(contexts: [.init(freeText: "changed supporting text")], presentation: [])
        #expect(try SharedMediaNativeDraftEnvelope.V2.decode(edited).intents == [blob])
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var region = try #require(object["focus"] as? [String: Any])
        region["source"] = "unrecognized_detector"; object["focus"] = region
        let malformed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try SharedMediaNativeDerivativeIntent.decode(malformed) }
    }

    @Test(arguments: ["negative", "zero-width", "zero-height", "right-edge", "bottom-edge", "nan", "infinite"])
    func invalidOutputFocusIsRejected(_ kind: String) throws {
        let focus = NormalizedImageFocusRegion(
            x: kind == "negative" ? -0.1 : kind == "nan" ? .nan : 0.5,
            y: kind == "infinite" ? .infinity : 0.5,
            width: kind == "zero-width" ? 0 : kind == "right-edge" ? 0.6 : 0.5,
            height: kind == "zero-height" ? 0 : kind == "bottom-edge" ? 0.6 : 0.5)
        let value = try intent(attempt(), focus: focus)
        #expect(throws: (any Error).self) { try value.encoded() }
    }

    @Test func frozenSubmissionPositionIsIndependentOfStableOriginalSlot() throws {
        let request = try attempt(slot: 1), intent = try intent(request)
        let entry = try SharedMediaNativeFrozenEntry(position: 0, intent: .init(bytes: intent.encoded()),
            aiReferenceRevision: 0, displayReferenceRevision: 0, aiDescriptor: descriptor, displayDescriptor: descriptor)
        let reference = request.original.reference
        let cohort = try SharedMediaNativeFrozenCohort(format: .cohort, packageID: reference.packageID, ownerID: reference.ownerID,
            draftGeneration: reference.draftGeneration, supportingBytes: SharedMediaNativeFrozenSupporting(contexts: [], presentation: []).encoded(), entries: [entry])
        let saved = try SharedMediaNativeFrozenCohort.decode(cohort.encoded())
        #expect(saved.entries.first?.position == 0)
        #expect(try SharedMediaNativeDerivativeIntent.decode(saved.entries[0].intent.bytes).attempt().original.ordinal == 1)
        let blob = try SharedMediaNativePreparationBlob(bytes: cohort.encoded())
        let receipt = SharedMediaNativeFreezeReceipt(format: .receipt, operationID: UUID(), inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, inventoryRevision: 4, packageRevision: 4, membershipRevision: 2, cohort: blob)
        #expect(try SharedMediaNativeFreezeReceipt.decode(receipt.encoded()).cohort == blob)
    }

    @Test func preparedIdentityDoesNotRetainAncestralEnvelopes() throws {
        let base = try attempt()
        var previous = base.previousEnvelope
        var largest = 0
        // Simulate explicit replacement/pruning: only the current intent is
        // retained. Encoding must stay bounded despite many prior edits.
        for sequence in 1...128 {
            let request = replacing(base, sequence: Int64(sequence), previous: previous)
            let value = try intent(request), bytes = try value.encoded()
            try value.preparation.requireMatch(request)
            #expect(value.preparation.previousEnvelopeByteCount == previous.count)
            #expect(value.preparation.previousEnvelopeSHA256 == SharedMediaAcquisitionEncoding.digest(previous))
            let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(object["attemptBytes"] == nil)
            let projection = try #require(object["preparation"] as? [String: Any])
            #expect(projection["previousEnvelope"] == nil && projection["membershipBytes"] == nil)
            previous = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: [], presentation: [], sequence: Int64(sequence),
                attempt: nil, intents: [.init(bytes: bytes)], frozen: nil).encoded()
            largest = max(largest, previous.count)
        }
        // A bounded fixture expectation, not a new product storage limit.
        #expect(largest < 16_384)
    }

    @Test func changedBeforeStateCannotMatchPreparedIdentityAndOldIntentFormatIsRejected() throws {
        let request = try attempt(), value = try intent(request)
        let changed = try replacing(request, sequence: request.sequence,
            previous: PhotoPreparationPolicy.encodeDraft(contexts: [.init(freeText: "different draft")]))
        #expect(throws: SharedMediaStorageFailure.stale) { try value.preparation.requireMatch(changed) }
        var object = try #require(JSONSerialization.jsonObject(with: value.encoded()) as? [String: Any])
        object["format"] = "nativeDerivativeV2"
        object["attemptBytes"] = try request.encoded().base64EncodedString()
        object.removeValue(forKey: "preparation")
        let obsolete = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try SharedMediaNativeDerivativeIntent.decode(obsolete) }
    }

    private func replacing(_ value: SharedMediaNativePreparationAttempt, sequence: Int64, previous: Data) -> SharedMediaNativePreparationAttempt {
        .init(format: value.format, sequence: sequence, operationID: value.operationID, writerEpoch: value.writerEpoch,
            inventoryID: value.inventoryID, inventoryGeneration: value.inventoryGeneration, inventoryRevision: value.inventoryRevision,
            packageRevision: value.packageRevision, membershipRevision: value.membershipRevision, membershipBytes: value.membershipBytes,
            previousEnvelope: previous, original: value.original, recipe: value.recipe)
    }

    private var descriptor: SharedMediaPhotoRetirementIdentity { .init(version: 1, file: "fixture-file", parent: "fixture-parent", namespace: "fixture-namespace") }
    private func envelope() throws -> SharedMediaNativeDraftEnvelope.V2 {
        .init(version: 2, contexts: [], presentation: [], sequence: 1,
              attempt: .init(bytes: try attempt().encoded()), intents: [], frozen: nil)
    }
    private func attempt(slot: Int64 = 0) throws -> SharedMediaNativePreparationAttempt {
        let owner = UUID(), package = UUID(), asset = UUID()
        let reference = PhotoOriginalReference(ownerID: owner, packageID: package, referenceID: UUID(), assetID: asset,
            assetGeneration: UUID(), draftGeneration: UUID(), referenceRevision: 0)
        return .init(format: .attempt, sequence: 1, operationID: UUID(), writerEpoch: UUID(), inventoryID: UUID(), inventoryGeneration: UUID(),
            inventoryRevision: 1, packageRevision: 1, membershipRevision: 0, membershipBytes: try SharedMediaMembership(groups: []).encoded(),
            previousEnvelope: try PhotoPreparationPolicy.encodeDraft(contexts: []),
            original: .init(reference: reference, ordinal: slot, token: [owner, package, asset].map { $0.uuidString.lowercased() }.joined(separator: "/"),
                byteCount: 1, sha256: String(repeating: "1", count: 64), contentType: "public.jpeg", descriptor: descriptor),
            recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
    }
    private func intent(_ request: SharedMediaNativePreparationAttempt, focus: NormalizedImageFocusRegion? = nil) throws -> SharedMediaNativeDerivativeIntent {
        func output(_ role: String) -> SharedMediaDerivativeInput {
            .init(id: UUID(), role: role, assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(),
                byteCount: 1, sha256: String(repeating: "2", count: 64), contentType: "public.jpeg")
        }
        return .init(format: .intent, preparation: try .init(attempt: request), pairID: UUID(), nonce: UUID(), previousPairID: nil,
                     ai: output("aiInput"), display: output("display"), focus: focus)
    }
}
