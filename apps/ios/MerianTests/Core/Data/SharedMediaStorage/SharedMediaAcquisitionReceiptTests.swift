import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native acquisition receipt codec")
@MainActor
struct SharedMediaAcquisitionReceiptTests {
    @Test func canonicalIntentAndResultRoundtrip() throws {
        let request = intent(), result = try completion(request)
        let bytes = try request.encoded()
        #expect(try SharedMediaAcquisitionIntent.decode(bytes) == request)
        #expect(try SharedMediaAcquisitionResult.decode(result.encoded(request: request), request: request) == result)
        #expect(request.finalToken == [request.ownerID, request.packageID, request.assetID].map { $0.uuidString.lowercased() }.joined(separator: "/"))
        #expect(request.partialToken == request.finalToken + ".partial")
        #expect(try request.fingerprint() == SharedMediaAcquisitionEncoding.digest(bytes))
    }

    @Test(arguments: ["unknown", "duplicate", "whitespace", "lowercaseUUID", "format", "version", "kind", "role", "maximum", "ordinal", "path", "partial", "referenceRevision", "inventoryOverflow", "packageOverflow", "alias"])
    func invalidIntentEncodingFails(_ change: String) throws {
        let request = intent(), data = try request.encoded()
        var object = try dictionary(data)
        var bytes: Data
        switch change {
        case "unknown": object["sourceIdentity"] = "unadmitted-source"
        case "duplicate":
            bytes = Data(("{\"version\":1," + String(decoding: data, as: UTF8.self).dropFirst()).utf8)
            #expect(throws: (any Error).self) { try SharedMediaAcquisitionIntent.decode(bytes) }; return
        case "whitespace":
            #expect(throws: (any Error).self) { try SharedMediaAcquisitionIntent.decode(data + Data(" ".utf8)) }; return
        case "lowercaseUUID": object["inventoryID"] = request.inventoryID.uuidString.lowercased()
        case "format": object["format"] = "nativeOriginalRequestV2"
        case "version": object["version"] = 2
        case "kind": object["kind"] = "sharedInbox"
        case "role": object["role"] = "aiInput"
        case "maximum": object["maximumBytes"] = PhotoPreparationPolicy.original + 1
        case "ordinal": object["ordinal"] = 2
        case "path": object["finalToken"] = request.finalToken + "/.."
        case "partial": object["partialToken"] = request.finalToken
        case "referenceRevision": object["initialReferenceRevision"] = 1
        case "inventoryOverflow": object["expectedInventoryRevision"] = Int64.max
        case "packageOverflow": object["packageExpectation"] = ["kind": "revision", "revision": Int64.max]
        default: object["referenceID"] = request.assetID.uuidString
        }
        bytes = try canonical(object)
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionIntent.decode(bytes) }
    }

    @Test(arguments: ["operationID", "inventoryID", "inventoryGeneration", "ownerID", "packageID", "draftGeneration", "assetID", "assetGeneration", "referenceID", "writerEpoch", "ordinal", "kind", "maximumBytes", "expectedInventoryRevision", "packageExpectation"])
    func changedSameOperationIntentCannotReadSavedReceipt(_ field: String) throws {
        let original = intent(), row = try receipt(original)
        var object = try dictionary(original.encoded())
        switch field {
        case "ordinal": object[field] = 1
        case "kind": object[field] = "camera"
        case "maximumBytes": object[field] = original.maximumBytes + 1
        case "expectedInventoryRevision": object[field] = 1
        case "packageExpectation": object[field] = ["kind": "revision", "revision": 0]
        default: object[field] = UUID().uuidString
        }
        // Keep dependent tokens canonical so the changed request is itself valid.
        let token = ["ownerID", "packageID", "assetID"].map { (object[$0] as! String).lowercased() }.joined(separator: "/")
        object["finalToken"] = token; object["partialToken"] = token + ".partial"
        let changed = try SharedMediaAcquisitionIntent.decode(canonical(object))
        #expect(try changed.fingerprint() != original.fingerprint())
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(row, expected: changed) }
    }

    @Test(arguments: ["format", "version", "requestFingerprint", "operationID", "assetID", "assetGeneration", "referenceID", "leaseID", "referenceRevision", "counterLiveCount", "counterRevision", "leaseClosed", "acquisitionWorkRemoved", "inventoryRevision", "packageRevision", "membershipRevision", "byteCount", "sha256", "contentType", "descriptor", "unknown"])
    func changedCompletionPostconditionsFail(_ field: String) throws {
        let request = intent(), result = try completion(request)
        var object = try dictionary(result.encoded(request: request))
        switch field {
        case "version", "referenceRevision", "counterRevision": object[field] = 2
        case "counterLiveCount", "inventoryRevision", "packageRevision", "membershipRevision", "byteCount": object[field] = 0
        case "leaseClosed", "acquisitionWorkRemoved": object[field] = false
        case "requestFingerprint", "sha256": object[field] = String(repeating: "G", count: 64)
        case "contentType": object[field] = String(repeating: "a", count: 129)
        case "descriptor": object[field] = ["version": 1, "file": "1:2:2:0:0:0:0", "parent": "1:3", "namespace": "1:4"]
        case "unknown": object[field] = true
        default: object[field] = UUID().uuidString
        }
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionResult.decode(canonical(object), request: request) }
    }

    @Test(arguments: ["held", "completed"], ["revision", "request", "result", "outcome"])
    func incompatibleNonterminalRowsFail(_ phase: String, _ change: String) throws {
        let request = intent(), row = try receipt(request)
        row.phaseRaw = phase; row.revision = 1
        if phase == "completed" { row.resultData = try completion(request).encoded(request: request) }
        switch change {
        case "revision": row.revision = 2
        case "request": row.requestData = Data()
        case "result": row.resultData = phase == "held" ? Data() : nil
        default: row.terminalOutcomeRaw = "released"
        }
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(row, expected: request) }
    }

    @Test func corruptFingerprintAndChangedHistoricalResultFailWithoutMutation() throws {
        let request = intent()
        let row = try SharedMediaAcquisitionReceiptRecord(operationID: request.operationID,
            inventoryID: request.inventoryID, inventoryGeneration: request.inventoryGeneration,
            ownerID: request.ownerID, requestFingerprint: String(repeating: "b", count: 64),
            packageID: request.packageID, assetID: request.assetID, requestData: request.encoded())
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(row, expected: request) }
        let good = try receipt(request), result = try completion(request)
        good.phaseRaw = "completed"; good.revision = 1
        good.resultData = try result.encoded(request: request) + Data(" ".utf8)
        let bytes = good.resultData
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(good, expected: request) }
        #expect(good.resultData == bytes && good.revision == 1)
    }

    @Test func exactPhasesDoNotMutateOrReopenTerminalReceipt() throws {
        let request = intent(), row = try receipt(request), result = try completion(request)
        #expect(try SharedMediaAcquisitionReceipt.read(row, expected: request) == .reserved(request))
        row.phaseRaw = "held"; row.revision = 1
        #expect(try SharedMediaAcquisitionReceipt.read(row, expected: request) == .held(request))
        row.phaseRaw = "completed"; row.resultData = try result.encoded(request: request)
        let saved = row.resultData
        for _ in 0..<3 {
            #expect(try SharedMediaAcquisitionReceipt.read(row, expected: request) == .completed(request, result))
            #expect(row.resultData == saved && row.revision == 1)
        }
        row.phaseRaw = "terminal"; row.revision = 2; row.terminalOutcomeRaw = "released"
        row.packageID = nil; row.assetID = nil; row.requestData = nil; row.resultData = nil
        #expect(try SharedMediaAcquisitionReceipt.read(row, expected: request) == .released(terminal(request)))
        #expect(row.phaseRaw == "terminal" && row.requestData == nil && row.revision == 2)
    }

    @Test(arguments: ["reserved", "held", "completed", "terminal"])
    func persistedRowAloneRecoversWithoutCallerIntent(_ phase: String) throws {
        let request = intent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-codec-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.store")
        let expected: SharedMediaAcquisitionReceipt
        do {
            let container = try makeContainer(url), context = ModelContext(container)
            context.autosaveEnabled = false
            let row = try receipt(request); row.phaseRaw = phase
            switch phase {
            case "held": row.revision = 1; expected = .held(request)
            case "completed":
                let result = try completion(request)
                row.revision = 1; row.resultData = try result.encoded(request: request)
                expected = .completed(request, result)
            case "terminal":
                row.revision = 2; row.terminalOutcomeRaw = "released"
                row.requestData = nil; row.resultData = nil; row.packageID = nil; row.assetID = nil
                expected = .released(try terminal(request))
            default: expected = .reserved(request)
            }
            context.insert(row); try context.save()
        }
        let reopened = try makeContainer(url), context = ModelContext(reopened)
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(); query.fetchLimit = 2
        let rows = try context.fetch(query)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        // A fresh container supplies only the persisted row to recovery.
        #expect(try SharedMediaAcquisitionReceipt.read(row) == expected)
        #expect(!context.hasChanges)
    }

    @Test(arguments: ["legacy", "missing", "extra", "null", "unknown"])
    func explicitPackagePreconditionRejectsCrossShapes(_ change: String) throws {
        var object = try dictionary(intent().encoded())
        switch change {
        case "legacy": object["packageExpectation"] = ["revision": ["_0": 0]]
        case "missing": object["packageExpectation"] = ["kind": "revision"]
        case "extra": object["packageExpectation"] = ["kind": "absent", "revision": 0]
        case "null": object["packageExpectation"] = ["kind": "absent", "revision": NSNull()]
        default: object["packageExpectation"] = ["kind": "future"]
        }
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionIntent.decode(canonical(object)) }
    }

    @Test(arguments: ["schema", "phase", "revision", "request", "result", "outcome", "package", "asset", "owner", "generation", "inventory"])
    func incompatibleReservedRowsFail(_ change: String) throws {
        let request = intent(), row = try receipt(request)
        switch change {
        case "schema": row.schemaVersion = 2
        case "phase": row.phaseRaw = "unknown"
        case "revision": row.revision = 1
        case "request": row.requestData = nil
        case "result": row.resultData = Data()
        case "outcome": row.terminalOutcomeRaw = "released"
        case "package": row.packageID = nil
        case "asset": row.assetID = UUID()
        case "owner": row.ownerID = UUID()
        case "generation": row.inventoryGeneration = UUID()
        default: row.inventoryID = UUID()
        }
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(row, expected: request) }
    }

    @Test(arguments: ["request", "result", "package", "asset", "outcome", "revision"])
    func terminalRowsMustShedPayloadAndKeepExactOutcome(_ change: String) throws {
        let request = intent(), row = try receipt(request)
        row.phaseRaw = "terminal"; row.revision = 2; row.terminalOutcomeRaw = "released"
        row.requestData = nil; row.resultData = nil; row.packageID = nil; row.assetID = nil
        switch change {
        case "request": row.requestData = try request.encoded()
        case "result": row.resultData = Data()
        case "package": row.packageID = request.packageID
        case "asset": row.assetID = request.assetID
        case "outcome": row.terminalOutcomeRaw = "cancelled"
        default: row.revision = 1
        }
        #expect(throws: (any Error).self) { try SharedMediaAcquisitionReceipt.read(row, expected: request) }
    }

    @Test func worstShapeCompletionFitsReservedHeadroomWithoutUTIRegistryLookup() throws {
        let request = intent(maximumBytes: PhotoPreparationPolicy.original)
        let descriptor = SharedMediaPhotoRetirementIdentity(version: 1,
            file: "-2147483648:18446744073709551615:33554432:-9223372036854775808:999999999:-9223372036854775808:999999999",
            parent: "-2147483648:18446744073709551615", namespace: "-2147483648:18446744073709551615")
        let result = try SharedMediaAcquisitionResult(request: request, inventoryRevision: .max,
            packageRevision: .max, membershipRevision: .max, byteCount: PhotoPreparationPolicy.original,
            sha256: String(repeating: "f", count: 64), contentType: String(repeating: "\u{0001}", count: 128), descriptor: descriptor)
        let bytes = try result.encoded(request: request)
        #expect(bytes.count <= SharedMediaAcquisitionResult.reservedEncodingBytes)
        #expect(try SharedMediaAcquisitionResult.decode(bytes, request: request) == result)
        #expect(try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: nil)
            == Int64(request.encoded().count + SharedMediaAcquisitionResult.reservedEncodingBytes))
        #expect(try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result)
            == Int64(request.encoded().count + bytes.count))
        // An opaque synthetic historical type is valid encoding, not valid media.
        let historical = try completion(request, contentType: "example.retired-decoder")
        #expect(try SharedMediaAcquisitionResult.decode(historical.encoded(request: request), request: request).contentType == "example.retired-decoder")
    }

    @Test func oversizeBuffersFailBeforeDecode() throws {
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try SharedMediaAcquisitionIntent.decode(Data(repeating: 0, count: Int(PhotoPreparationPolicy.metadata) + 1))
        }
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try SharedMediaAcquisitionResult.decode(Data(repeating: 0, count: SharedMediaAcquisitionResult.reservedEncodingBytes + 1), request: intent())
        }
    }

    private func intent(maximumBytes: Int64 = 1) -> SharedMediaAcquisitionIntent {
        .init(operationID: UUID(), inventoryID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-AAAA-AAAAAAAAAAAA")!,
            inventoryGeneration: UUID(), ownerID: UUID(), expectedInventoryRevision: 0,
            packageID: UUID(), draftGeneration: UUID(), packageExpectation: .absent,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: 0,
            kind: .picker, writerEpoch: UUID(), maximumBytes: maximumBytes)
    }

    private func completion(_ request: SharedMediaAcquisitionIntent, contentType: String = "public.jpeg") throws -> SharedMediaAcquisitionResult {
        try .init(request: request, inventoryRevision: 2, packageRevision: 1, membershipRevision: 1,
            byteCount: 1, sha256: String(repeating: "a", count: 64), contentType: contentType,
            descriptor: .init(version: 1, file: "1:2:1:0:0:0:0", parent: "1:3", namespace: "1:4"))
    }

    private func receipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceiptRecord {
        try .init(operationID: request.operationID, inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID,
            requestFingerprint: request.fingerprint(), packageID: request.packageID,
            assetID: request.assetID, requestData: request.encoded())
    }

    private func terminal(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt.TerminalIdentity {
        try .init(operationID: request.operationID, inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID,
            requestFingerprint: request.fingerprint())
    }

    private func makeContainer(_ url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: url, cloudKitDatabase: .none)])
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
