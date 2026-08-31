import Foundation
import Testing

@testable import Merian

@MainActor
struct InsightContentActionsTests {
    @Test func preferredNameUsesInjectedPersistenceAndFeedback() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "preferred_name_dependencies",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(record)
        try context.save()
        var preferredName: String?
        var events: [String] = []
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(
                scanId: record.id
            ),
            dependencies: InsightShellDependencies(
                selectionFeedback: { events.append("feedback") }
            ),
            contentDependencies: InsightContentDependencies(
                loadPreferredCommonName: { _, _ in
                    events.append("load")
                    return preferredName
                },
                setPreferredCommonName: { name, _, _ in
                    events.append("set")
                    preferredName = name
                    return true
                }
            )
        )
        #expect(viewModel.fetchLocalRecord(
            for: record.id,
            modelContext: context
        ))
        events.removeAll()

        viewModel.setPreferredCommonName(
            "Milkweed Butterfly",
            for: record.scientificName,
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration,
            modelContext: context
        )

        #expect(preferredName == "Milkweed Butterfly")
        #expect(viewModel.state.preferredCommonName == "Milkweed Butterfly")
        #expect(events == ["set", "load", "feedback"])
        #expect(
            viewModel.state.toastMessage?.title ==
                "Preferred name set to \"Milkweed Butterfly\""
        )
        #expect(viewModel.state.toastMessage?.severity == .success)
    }

    @Test func testPreferredNameRejectsStalePresentationGeneration() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let first = LocalScanRecord(
            speciesId: "preferred_name_generation_1",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let second = LocalScanRecord(
            speciesId: "preferred_name_generation_2",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(first)
        context.insert(second)
        try context.save()
        var saveCount = 0
        let viewModel = InsightSheetViewModel(
            contentDependencies: InsightContentDependencies(
                setPreferredCommonName: { _, _, _ in
                    saveCount += 1
                    return true
                }
            )
        )
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: first.id
        )
        #expect(viewModel.fetchLocalRecord(
            for: first.id,
            modelContext: context
        ))
        let staleGeneration = viewModel.scanBoundActionGeneration

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: second.id
        )
        #expect(viewModel.fetchLocalRecord(
            for: second.id,
            modelContext: context
        ))
        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: first.id
        )
        #expect(viewModel.fetchLocalRecord(
            for: first.id,
            modelContext: context
        ))

        viewModel.setPreferredCommonName(
            "Stale Monarch Name",
            for: first.scientificName,
            expectedScanId: first.id,
            expectedGeneration: staleGeneration,
            modelContext: context
        )

        #expect(saveCount == 0)
        #expect(viewModel.state.toastMessage == nil)
    }

    @Test func refinementUsesCurrentRecordAndTrimmedFieldNotes() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "refinement_dependencies",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(record)
        try context.save()
        var requestedScanID: String?
        var requestedNotes: String?
        var feedbackCount = 0
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(
                scanId: record.id
            ),
            dependencies: InsightShellDependencies(
                requestRefinement: { scanID, notes in
                    requestedScanID = scanID
                    requestedNotes = notes
                },
                selectionFeedback: { feedbackCount += 1 }
            )
        )
        #expect(viewModel.fetchLocalRecord(
            for: record.id,
            modelContext: context
        ))
        viewModel.state.fieldNotesText = "  Compare the wing edge.  "

        #expect(viewModel.requestRefinement(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration,
            modelContext: context
        ))
        #expect(requestedScanID == record.id)
        #expect(requestedNotes == "Compare the wing edge.")
        #expect(feedbackCount == 1)
    }

    @Test func nonBiologicalRoutePreservesFeedbackBeforeNavigation() {
        var events: [String] = []
        let viewModel = InsightSheetViewModel(
            dependencies: InsightShellDependencies(
                requestNonBiologicalScans: { events.append("route") },
                selectionFeedback: { events.append("feedback") }
            )
        )

        viewModel.openNonBiologicalScans()

        #expect(events == ["feedback", "route"])
    }
}
