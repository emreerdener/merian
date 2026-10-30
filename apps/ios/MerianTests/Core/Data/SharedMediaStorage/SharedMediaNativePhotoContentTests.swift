import Foundation
import Testing
@testable import Merian

@Suite("Inactive photo content declaration parity", .serialized)
@MainActor
struct SharedMediaNativePhotoContentTests {
    typealias Content = SharedMediaNativePhotoContent
    typealias Recipe = SharedMediaNativePreparationRecipe
    typealias Fixture = SharedMediaNativeReceivingTestFixture

    @Test func closedWireTypesPreserveLocalSpellings() throws {
        for (local, mime) in [("public.jpeg", "image/jpeg"), ("public.png", "image/png"),
                              ("org.webmproject.webp", "image/webp"), ("public.heic", "image/heic"), ("public.heif", "image/heif")] {
            #expect(try Content.wireContentType(local) == mime)
            #expect(try Content.wireContentType(mime) == mime)
        }
        for type in ["", "public.image", "public.gif", "IMAGE/JPEG", "image/jpeg; charset=utf-8", "audio/mp4"] {
            #expect(throws: (any Error).self) { _ = try Content.wireContentType(type) }
        }
    }

    @Test func independentDenoGoldenBytesAndDigest() throws {
        let value = try content(contexts: [.init(freeText: " \u{feff}a\0e\u{301}🦭\n")])
        #expect(value.canonicalBytes == Data(Self.golden.utf8))
        #expect(value.unverifiedDigest == "d75caa6fdc3c9f374149c666cb2bb3b153934bc6dc4040589fa418ee7e41c806")
        var callerCopy = value.canonicalBytes
        callerCopy.removeAll()
        #expect(value.canonicalBytes == Data(Self.golden.utf8))
    }

    @Test func scalarEscapingAndExactContextOrder() throws {
        let mime = "\"\\/\u{8}\t\n\u{c}\r\u{1}\u{1f}\u{2028}\u{2029}é e\u{301}🦭\u{feff}"
        let texts = ["\u{feff}", "\0", "é", "e\u{301}", "", " \t\n", "🦭"]
        let value = try content(photos: [photo(mime: mime)], contexts: texts.map { .init(freeText: $0) })
        let json = try object(value)
        let contexts = try #require(json["contexts"] as? [[String: String]])
        #expect(contexts.compactMap { Data(base64Encoded: $0["text_utf8_base64"] ?? "!") } == texts.map { Data($0.utf8) })
        let wire = try #require(String(data: value.canonicalBytes, encoding: .utf8))
        #expect(wire.contains(#"\"\\/\b\t\n\f\r\u0001\u001f"# + "\u{2028}\u{2029}é e\u{301}🦭\u{feff}"))
        #expect(value.unverifiedDigest == Self.scalarDigest)
        #expect(try content(photos: [photo(mime: mime)], contexts: texts.reversed().map { .init(freeText: $0) }).unverifiedDigest != value.unverifiedDigest)
    }

    @Test func multiplicityAndPhotoOrderSurviveEqualHashes() throws {
        let a = photo(), b = photo(firstID: 6)
        let original = try content(photos: [a, b]), reversed = try content(photos: [b, a])
        #expect(original.unverifiedDigest != reversed.unverifiedDigest)
        let rows = try #require(try object(reversed)["photos"] as? [[String: Any]])
        #expect(rows.count == 2 && (rows[0]["ordinal"] as? Int) == 0 && (rows[1]["ordinal"] as? Int) == 1)
        #expect((rows[0]["source"] as? [String: Any])?["reference_id"] as? String == id(6).uuidString.lowercased())
        #expect(throws: (any Error).self) { _ = try content(photos: [a, a]) }
        #expect(throws: (any Error).self) { _ = try content(photos: [.init(source: a.source, ai: a.source, display: a.display, recipe: a.recipe)]) }
    }

    @Test(arguments: ["zero", "negative", "overflow", "original", "ai", "display", "hash", "upperHash", "emptyType", "longType", "nulType", "emptyPhotos", "threePhotos"])
    func invalidDeclarationsAreRejected(_ fault: String) throws {
        var bytes: Int64 = 1, sha = String(repeating: "a", count: 64), mime = "image/jpeg"
        switch fault {
        case "zero": bytes = 0
        case "negative": bytes = -1
        case "overflow": bytes = .max
        case "original": bytes = PhotoPreparationPolicy.original + 1
        case "ai": bytes = PhotoPreparationPolicy.aiCohort + 1
        case "display": bytes = PhotoPreparationPolicy.display + 1
        case "hash": sha = "not-a-hash"
        case "upperHash": sha = String(repeating: "A", count: 64)
        case "emptyType": mime = ""
        case "longType": mime = String(repeating: "é", count: 65)
        case "nulType": mime = "image/\0jpeg"
        default: break
        }
        var p = photo(mime: mime, count: bytes, hash: sha)
        if fault == "ai" || fault == "display" {
            let normal = photo()
            p = .init(source: normal.source, ai: fault == "ai" ? role(4, bytes: bytes) : normal.ai,
                      display: fault == "display" ? role(5, bytes: bytes) : normal.display, recipe: normal.recipe)
        }
        let photos = fault == "emptyPhotos" ? [] : (fault == "threePhotos" ? [p, photo(firstID: 6), photo(firstID: 9)] : [p])
        #expect(throws: (any Error).self) { _ = try content(photos: photos) }
    }

    @Test func exactLimitsAndAggregateDenials() throws {
        func wide(_ start: Int, ai: Int64) -> Content.Photo {
            .init(source: role(start, bytes: PhotoPreparationPolicy.original), ai: role(start + 1, bytes: ai),
                  display: role(start + 2, bytes: PhotoPreparationPolicy.display), recipe: recipe())
        }
        let texts = (0..<4).map { _ in ObservationContext(freeText: String(repeating: "🦭", count: 4000)) }
        _ = try content(photos: [wide(3, ai: PhotoPreparationPolicy.aiCohort / 2), wide(6, ai: PhotoPreparationPolicy.aiCohort / 2)], contexts: texts)
        #expect(throws: (any Error).self) { _ = try content(photos: [wide(3, ai: PhotoPreparationPolicy.aiCohort / 2 + 1), wide(6, ai: PhotoPreparationPolicy.aiCohort / 2)]) }
        _ = try content(contexts: [.init(freeText: String(repeating: "🦭", count: 8192))])
        _ = try content(contexts: (0..<64).map { _ in .init(freeText: "") })
        _ = try content(photos: [photo(mime: String(repeating: "é", count: 64))])
        for contexts in [[ObservationContext(freeText: String(repeating: "a", count: 8193))],
                         (0..<65).map { _ in ObservationContext(freeText: "") }, texts + [.init(freeText: "x")]] {
            #expect(throws: (any Error).self) { _ = try content(contexts: contexts) }
        }
    }

    @Test func recipeBitsAndInvalidCombinations() throws {
        let camera = Recipe(format: .cameraStill, isPro: true, cropDisplaySize: nil, quarterTurns: 0,
                            scale: 1, offsetX: -0.0, offsetY: 0, cameraVerticalCenter: -0.0)
        let value = try content(photos: [photo(recipe: camera)])
        let wire = try #require(String(data: value.canonicalBytes, encoding: .utf8))
        #expect(wire.contains("\"camera_vertical_center_bits\":\"8000000000000000\""))
        #expect(wire.contains("\"is_pro\":true"))
        let invalid = [recipe(scale: .infinity), recipe(scale: .nan), recipe(scale: 0.9), recipe(turns: 4),
                       recipe(turns: 1), Recipe(format: .cameraStill, isPro: false, cropDisplaySize: nil,
                           quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0),
                       Recipe(format: .stillImage, isPro: false, cropDisplaySize: 0, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0)]
        for r in invalid { #expect(throws: (any Error).self) { _ = try content(photos: [photo(recipe: r)]) } }
    }

    @Test(arguments: [1, 2])
    func savedNativeMappingPreservesIdentityAndFrozenOrder(_ count: Int) async throws {
        let (_, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count, staged: true)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        let saved = try prepared.encoded()
        let value = try Content(prepared: prepared), frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let rows = try #require(try object(value)["photos"] as? [[String: Any]])
        #expect(try object(value)["scan_id"] as? String == prepared.observationID.uuidString.lowercased())
        #expect(try object(value)["package_id"] as? String == frozen.packageID.uuidString.lowercased())
        for (entry, row) in zip(frozen.entries, rows) {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            #expect(row["ordinal"] as? Int == entry.position)
            #expect((row["source"] as? [String: Any])?["reference_id"] as? String == intent.preparation.original.reference.referenceID.uuidString.lowercased())
            #expect((row["ai"] as? [String: Any])?["byte_count"] as? Int64 == intent.ai.byteCount)
            #expect((row["display"] as? [String: Any])?["sha256"] as? String == intent.display.sha256)
            for (role, local) in [("source", intent.preparation.original.contentType), ("ai", intent.ai.contentType), ("display", intent.display.contentType)] {
                #expect((row[role] as? [String: Any])?["declared_content_type"] as? String == (try Content.wireContentType(local)))
                #expect(!local.hasPrefix("image/"))
            }
            #expect(intent.preparation.original.contentType == "public.png")
        }
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            frozen.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        let textRows = try #require(try object(value)["contexts"] as? [[String: String]])
        #expect(textRows.map { $0["text_utf8_base64"] } == supporting.contexts.map { Data($0.freeText.utf8).base64EncodedString() })
        if count == 2 {
            let reverse = frozen.entries.reversed().enumerated().map { i, e in
                SharedMediaNativeFrozenEntry(position: i, intent: e.intent, aiReferenceRevision: e.aiReferenceRevision,
                    displayReferenceRevision: e.displayReferenceRevision, aiDescriptor: e.aiDescriptor, displayDescriptor: e.displayDescriptor)
            }
            let next = try Fixture.copy(frozen, changes: ["entries": reverse.map(Fixture.object)])
            let changed = try Fixture.copy(prepared, changes: ["cohort": Fixture.object(SharedMediaNativePreparationBlob(bytes: next.encoded()))])
            let reversed = try Content(prepared: changed)
            #expect(reversed.unverifiedDigest != value.unverifiedDigest)
            let reversedRows = try #require(try object(reversed)["photos"] as? [[String: Any]])
            #expect((reversedRows[0]["source"] as? [String: Any])?["reference_id"] as? String
                == (rows[1]["source"] as? [String: Any])?["reference_id"] as? String)
        }
        #expect(try Content(prepared: .decode(saved)).canonicalBytes == value.canonicalBytes)
        #expect(try prepared.encoded() == saved)
        let wrong = try Fixture.copy(prepared, changes: ["eventID": prepared.queueID.uuidString])
        #expect(throws: (any Error).self) { _ = try Content(prepared: wrong) }
        let legacy = try Fixture.copy(prepared, changes: ["format": "nativeReceivingIntentV1", "version": 1, "intentRevision": NSNull()])
        _ = try legacy.encoded()
        #expect(throws: (any Error).self) { _ = try Content(prepared: legacy) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
    private func role(_ n: Int, bytes: Int64 = 1, mime: String = "image/jpeg", hash: String = String(repeating: "a", count: 64)) -> Content.Role {
        .init(referenceID: id(n), byteCount: bytes, sha256: hash, contentType: mime)
    }
    private func recipe(scale: Double = 1, turns: Int = 0) -> Recipe {
        .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: turns, scale: scale, offsetX: -0.0, offsetY: 0)
    }
    private func photo(firstID: Int = 3, mime: String = "image/jpeg", count: Int64 = 1,
                       hash: String = String(repeating: "a", count: 64), recipe: Recipe? = nil) -> Content.Photo {
        .init(source: role(firstID, bytes: count, mime: mime, hash: hash), ai: role(firstID + 1, bytes: count),
              display: role(firstID + 2, bytes: count), recipe: recipe ?? self.recipe())
    }
    private func content(photos: [Content.Photo]? = nil, contexts: [ObservationContext] = []) throws -> Content {
        try .init(scanID: id(1), packageID: id(2), photos: photos ?? [photo()], contexts: contexts)
    }
    private func object(_ value: Content) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: value.canonicalBytes) as? [String: Any])
    }
    // Exact independent Deno fixture; host preflight checks this literal against its source.
    private static let golden = #"{"contexts":[{"text_utf8_base64":"IO+7v2EAZcyB8J+mrQo="}],"contract":"client_prepared_media_v1","kind":"initial_photo","package_id":"00000000-0000-4000-8000-000000000002","photos":[{"ai":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000004","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"display":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000005","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"ordinal":0,"recipe":{"camera_vertical_center_bits":null,"crop_display_size_bits":null,"format":"nativeStillImageV1","is_pro":false,"offset_x_bits":"8000000000000000","offset_y_bits":"0000000000000000","quarter_turns":0,"scale_bits":"3ff0000000000000"},"source":{"byte_count":1,"declared_content_type":"image/jpeg","reference_id":"00000000-0000-4000-8000-000000000003","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}],"resource_profile":"P1-L1","scan_id":"00000000-0000-4000-8000-000000000001","version":1}"#
    private static let scalarDigest = "4c1813d3c47e89e3acf98dba8d2717057605ea4358f447484ebe93ad7a2f7e58"
}
