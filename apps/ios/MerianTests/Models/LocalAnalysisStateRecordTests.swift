import Foundation
@testable import Merian
import Testing

struct LocalAnalysisStateRecordTests {
    let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let observation = "00000000-0000-4000-8000-000000000003"
    let first = Data("{\"value\":1}".utf8), second = Data("{\"value\":2}".utf8)

    @Test func authorityRevisionAndObservationOrderingAreIndependent() throws {
        let value = try LocalAnalysisStateRecord(analysisID: analysis, observationID: observation, ownerAccountID: owner,
            observationStateRevision: 10, reviewRevision: 2, reviewSnapshotData: first)
        try value.update(observationStateRevision: 11, reviewRevision: 2, reviewSnapshotData: first, displaySnapshotData: nil)
        #expect(throws: LocalAnalysisStateRecord.StorageError.staleRevision) {
            try value.update(observationStateRevision: 10, reviewRevision: 2, reviewSnapshotData: first, displaySnapshotData: nil)
        }
        #expect(throws: LocalAnalysisStateRecord.StorageError.conflictingRevision) {
            try value.update(observationStateRevision: 12, reviewRevision: 2, reviewSnapshotData: second, displaySnapshotData: nil)
        }
        #expect(throws: LocalAnalysisStateRecord.StorageError.conflictingRevision) {
            try value.update(observationStateRevision: 11, reviewRevision: 3, reviewSnapshotData: second, displaySnapshotData: nil)
        }
        #expect(value.observationStateRevision == 11 && value.reviewSnapshotData == first)
        try value.update(observationStateRevision: 12, reviewRevision: 3, reviewSnapshotData: second, displaySnapshotData: first)
        #expect(value.reviewRevision == 3 && value.reviewSnapshotData == second)
    }

    @Test func displayIsImmutableAndFailedUpdateDoesNotPartiallyChangeAuthority() throws {
        let value = try LocalAnalysisStateRecord(analysisID: analysis, observationID: observation, ownerAccountID: owner,
            observationStateRevision: 10, reviewRevision: 2, reviewSnapshotData: first, displaySnapshotData: first)
        #expect(throws: LocalAnalysisStateRecord.StorageError.conflictingDisplay) {
            try value.update(observationStateRevision: 11, reviewRevision: 3, reviewSnapshotData: second, displaySnapshotData: second)
        }
        #expect(value.reviewSnapshotData == first && value.observationStateRevision == 10)
        try value.update(observationStateRevision: 11, reviewRevision: 2, reviewSnapshotData: first, displaySnapshotData: nil)
        #expect(value.displaySnapshotData == first)
    }

    @Test func invalidBoundsAndNonobjectDataAreRejected() throws {
        for data in [Data(), Data("[]".utf8), Data(repeating: 32, count: 32_769)] {
            #expect(throws: LocalAnalysisStateRecord.StorageError.invalidState) {
                try LocalAnalysisStateRecord(analysisID: analysis, observationID: observation, ownerAccountID: owner,
                    observationStateRevision: 1, reviewRevision: 0, reviewSnapshotData: data)
            }
        }
    }

    @Test func displayReplacementClearsOldFieldsAndPreservesObservationAndAuthority() throws {
        let source = LocalScanRecord(speciesId: "", scientificName: "Fixture genus", commonName: "Fixture", isBiological: false)
        let target = LocalScanRecord(speciesId: "old", scientificName: "Old", commonName: "Old", wikipediaOverview: "Old wiki",
            taxonomyFamily: "Old family", similarSpecies: ["Old lookalike"], candidatesData: first, aiReasoning: "Old reason", fieldNotes: "Private note")
        target.lookalikesData = first
        target.customTags = ["Personal tag"]
        target.userIdentificationOverride = "Owner correction"
        let snapshot = AnalysisDisplaySnapshot(analysisID: analysis, record: source)
        let data = try snapshot.storedData()
        #expect(!String(decoding: data, as: UTF8.self).contains("fieldNotes"))
        try AnalysisDisplaySnapshot.restore(data, analysisID: analysis).apply(to: target)
        #expect(target.scientificName == "Fixture genus" && !target.isBiological)
        #expect(target.wikipediaOverview == nil && target.taxonomyFamily == nil && target.candidatesData == nil)
        #expect(target.aiReasoning == nil && target.lookalikesData == nil && target.similarSpecies == nil)
        #expect(target.fieldNotes == "Private note" && target.customTags == ["Personal tag"])
        #expect(target.userIdentificationOverride == "Owner correction")
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(object["wikipediaOverview"] is NSNull)
        object.removeValue(forKey: "wikipediaOverview")
        #expect(throws: (any Error).self) {
            try AnalysisDisplaySnapshot.restore(JSONSerialization.data(withJSONObject: object), analysisID: analysis)
        }
        object["wikipediaOverview"] = NSNull()
        object["fieldNotes"] = "Disallowed"
        #expect(throws: (any Error).self) {
            try AnalysisDisplaySnapshot.restore(JSONSerialization.data(withJSONObject: object), analysisID: analysis)
        }
        #expect(throws: (any Error).self) { try AnalysisDisplaySnapshot.restore(data, analysisID: owner) }
    }
}
