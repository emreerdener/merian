import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightShellPresentationTests {
    @Test func testEvaluateScrollOffset() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isCommonNameScrolledPast == false)

        viewModel.evaluateScrollOffset(minY: 40.0)
        #expect(viewModel.state.isCommonNameScrolledPast == true)

        viewModel.evaluateScrollOffset(minY: 60.0)
        #expect(viewModel.state.isCommonNameScrolledPast == false)
    }

    @Test func testBindPresentedScanDoesNotRestartMatchingRouteHydration() throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            id: "route-owned-record",
            speciesId: "route-owned-species",
            scientificName: "Synthetic non-biological subject",
            commonName: "Synthetic subject",
            isBiological: false
        )
        ctx.insert(record)
        try ctx.save()

        let engine = InferenceEngine()
        engine.load(from: record)
        engine.isProcessing = true
        defer { engine.cancelHistoricHydration() }

        let viewModel = InsightSheetViewModel()
        let didBind = viewModel.bindPresentedScan(
            scanId: record.id,
            modelContext: ctx,
            inferenceEngine: engine
        )

        #expect(didBind)
        #expect(engine.isProcessing)
        #expect(engine.speciesData?.scanId == record.id)
    }

    @Test func testBindPresentedScanLoadsWhenEngineOwnsDifferentRecord() throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let firstRecord = LocalScanRecord(
            id: "first-route-record",
            speciesId: "first-route-species",
            scientificName: "First synthetic subject",
            commonName: "First subject",
            isBiological: false
        )
        let secondRecord = LocalScanRecord(
            id: "second-route-record",
            speciesId: "second-route-species",
            scientificName: "Second synthetic subject",
            commonName: "Second subject",
            isBiological: false
        )
        ctx.insert(firstRecord)
        ctx.insert(secondRecord)
        try ctx.save()

        let engine = InferenceEngine()
        engine.load(from: firstRecord)
        engine.isProcessing = true
        defer { engine.cancelHistoricHydration() }

        let viewModel = InsightSheetViewModel()
        let didBind = viewModel.bindPresentedScan(
            scanId: secondRecord.id,
            modelContext: ctx,
            inferenceEngine: engine
        )

        #expect(didBind)
        #expect(!engine.isProcessing)
        #expect(engine.speciesData?.scanId == secondRecord.id)
    }

    @Test func testEvaluateHeroScrollOffsetUsesClearanceHysteresis() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 45)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 44)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: 47)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: 48)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)

        viewModel.evaluateHeroScrollOffset(maxY: 40)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.evaluateHeroScrollOffset(maxY: .infinity)
        viewModel.evaluateHeroScrollOffset(maxY: .nan)
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == false)

        viewModel.reset()
        #expect(viewModel.state.isTopScrollEdgeEffectHidden == true)
    }

    @Test func testResetMonotonicallyInvalidatesScanBoundRequests() {
        let viewModel = InsightSheetViewModel()
        viewModel.scanBoundActionGeneration = 7
        viewModel.fieldTripContributionRequestToken = 17
        let sharingRevision = viewModel.sharingOperations.revision
        let sharingRequestToken = viewModel.sharingOperations.requestToken

        viewModel.reset()

        #expect(viewModel.scanBoundActionGeneration == 8)
        #expect(viewModel.sharingOperations.revision == sharingRevision + 1)
        #expect(
            viewModel.sharingOperations.requestToken ==
                sharingRequestToken + 1
        )
        #expect(viewModel.fieldTripContributionRequestToken == 18)
    }

}
