import Foundation
import Testing

@testable import Merian

// MARK: - DescribePromptViewModel Unit Tests
//
// These tests cover the pure state-machine logic of DescribePromptViewModel in
// isolation, without any SwiftUI dependency. Each scenario maps directly to a
// user-visible flow in the Describe identification interview.

@Suite("DescribePromptViewModel")
@MainActor
struct DescribePromptViewModelTests {

    // MARK: - Initial State

    @Test("Initial state is Q0 with full general question list")
    func testInitialState() {
        let viewModel = DescribePromptViewModel()
        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeSubjectId == nil)
        #expect(!viewModel.isFunnelActive)
        #expect(viewModel.activeQuestions == guidedQuestions)
        #expect(viewModel.interactedQuestionIndices.isEmpty)
    }

    // MARK: - Funnel Activation

    @Test("activateFunnel sets subject ID and swaps question list")
    func testActivateFunnelSetsState() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")

        #expect(viewModel.activeSubjectId == "subj_bird")
        #expect(viewModel.isFunnelActive)
        #expect(viewModel.activeQuestions.count > 1)
        // First question is always the subject question
        #expect(viewModel.activeQuestions[0].prompt == guidedQuestions[0].prompt)
        // Second question is the first funnel-specific question (not a general one)
        #expect(viewModel.activeQuestions[1].prompt != guidedQuestions[1].prompt)
    }

    @Test("activateFunnel advances activeQuestionIndex to 1")
    func testActivateFunnelAdvancesIndex() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        #expect(viewModel.activeQuestionIndex == 1)
    }

    @Test("activateFunnel resets interactedQuestionIndices")
    func testActivateFunnelResetsInteracted() {
        let viewModel = DescribePromptViewModel()
        viewModel.interactedQuestionIndices = [0, 1, 2]
        viewModel.activateFunnel(for: "subj_bird")
        #expect(viewModel.interactedQuestionIndices.isEmpty)
    }

    @Test("activateFunnel appends general telemetry questions")
    func testActivateFunnelAppendsGeneralTelemetry() {
        let viewModel = DescribePromptViewModel()
        guard let funnel = subjectFunnels["subj_bird"] else {
            Issue.record("subj_bird funnel missing from subjectFunnels")
            return
        }
        viewModel.activateFunnel(for: "subj_bird")
        // Expected layout: [Q0] + funnel + [general[1], general[2], general.last]
        let expectedCount = 1 + funnel.count + 3
        #expect(viewModel.activeQuestions.count == expectedCount)
    }

    @Test("activateFunnel for unknown subject ID is a no-op")
    func testActivateFunnelUnknownSubjectIsNoOp() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_unknown_xyz")
        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeSubjectId == nil)
        #expect(!viewModel.isFunnelActive)
        #expect(viewModel.activeQuestions == guidedQuestions)
    }

    @Test("All subject IDs defined in Q0 tags have matching funnel entries")
    func testAllQ0SubjectTagsHaveFunnels() {
        let q0Tags = guidedQuestions[0].tags
        // "subj_othr" intentionally has a funnel too; all subj_ tags must resolve
        for tag in q0Tags where tag.tagId.hasPrefix("subj_") {
            #expect(subjectFunnels[tag.tagId] != nil,
                    "Missing funnel for tagId: \(tag.tagId)")
        }
    }

    // MARK: - Funnel Reset

    @Test("resetFunnel restores initial state")
    func testResetFunnelRestoresInitialState() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        viewModel.activeQuestionIndex = 3
        viewModel.interactedQuestionIndices = [0, 1, 2]

        viewModel.resetFunnel()

        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeSubjectId == nil)
        #expect(!viewModel.isFunnelActive)
        #expect(viewModel.activeQuestions == guidedQuestions)
        #expect(viewModel.interactedQuestionIndices.isEmpty)
    }

    @Test("resetFunnel on already-reset viewModel is a no-op")
    func testDoubleResetIsNoOp() {
        let viewModel = DescribePromptViewModel()
        viewModel.resetFunnel()
        viewModel.resetFunnel()
        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeSubjectId == nil)
    }

    // MARK: - Funnel Re-activation (species switch)

    @Test("Switching species resets then activates new funnel")
    func testSwitchingSpeciesActivatesNewFunnel() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        let birdCount = viewModel.activeQuestions.count

        viewModel.resetFunnel()
        viewModel.activateFunnel(for: "subj_insec")

        #expect(viewModel.activeSubjectId == "subj_insec")
        #expect(viewModel.activeQuestionIndex == 1)
        // Insect funnel may have a different length than bird funnel
        if let birdFunnel = subjectFunnels["subj_bird"],
           let insectFunnel = subjectFunnels["subj_insec"],
           birdFunnel.count != insectFunnel.count {
            #expect(viewModel.activeQuestions.count != birdCount)
        }
    }

    // MARK: - Index Bounds

    @Test("activeQuestionIndex stays in valid range after activation")
    func testActiveIndexInBoundsAfterActivation() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        let idx = viewModel.activeQuestionIndex
        #expect(idx >= 0)
        #expect(idx < viewModel.activeQuestions.count)
    }

    @Test("activeQuestions[activeQuestionIndex] is accessible after activation")
    func testCurrentQuestionIsAccessible() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        let idx = viewModel.activeQuestionIndex
        // Should not crash
        let question = viewModel.activeQuestions[idx]
        #expect(!question.prompt.isEmpty)
    }

    // MARK: - isFunnelActive Derived Property

    @Test("isFunnelActive is false before any activation")
    func testIsFunnelActiveInitially() {
        let viewModel = DescribePromptViewModel()
        #expect(!viewModel.isFunnelActive)
    }

    @Test("isFunnelActive is true after activation")
    func testIsFunnelActiveAfterActivation() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        #expect(viewModel.isFunnelActive)
    }

    @Test("isFunnelActive is false after reset")
    func testIsFunnelActiveAfterReset() {
        let viewModel = DescribePromptViewModel()
        viewModel.activateFunnel(for: "subj_bird")
        viewModel.resetFunnel()
        #expect(!viewModel.isFunnelActive)
    }

    // MARK: - All Funnel Species

    @Test("activateFunnel works for all subject IDs in subjectFunnels")
    func testActivateFunnelForAllSubjects() {
        for subjectId in subjectFunnels.keys {
            let viewModel = DescribePromptViewModel()
            viewModel.activateFunnel(for: subjectId)
            #expect(viewModel.isFunnelActive,
                    "Funnel not active after activating subjectId: \(subjectId)")
            #expect(viewModel.activeSubjectId == subjectId)
            #expect(viewModel.activeQuestionIndex == 1)
        }
    }

    // MARK: - Reanalysis Flow

    @Test("Reanalysis flow uses reanalysis heading")
    func testReanalysisFlowUsesReanalysisHeading() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: nil)

        #expect(viewModel.currentPrompt == "What would you like to reanalyze?")
        #expect(viewModel.displayPrompt(at: 0) == "What would you like to reanalyze?")
        #expect(viewModel.activeQuestionIndex == 0)
    }

    @Test("Reanalysis flow preselects provided subject")
    func testReanalysisFlowPreselectsProvidedSubject() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_bird")

        #expect(viewModel.activeSubjectId == "subj_bird")
        #expect(viewModel.isFunnelActive)
        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeQuestions.count == 1)
        #expect(viewModel.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis flow tolerates unknown subject")
    func testReanalysisFlowToleratesUnknownSubject() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_unknown_xyz")

        #expect(viewModel.activeSubjectId == nil)
        #expect(!viewModel.isFunnelActive)
        #expect(viewModel.activeQuestions.count == 1)
        #expect(viewModel.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis flow does not include Describe prompts")
    func testReanalysisFlowDoesNotIncludeDescribePrompts() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_plan")

        #expect(viewModel.activeQuestions.count == 1)
        #expect(viewModel.activeQuestions.first?.tags.isEmpty == true)
        #expect(viewModel.activeQuestions.first?.prompt == "What would you like to reanalyze?")
    }

    @Test("Resetting reanalysis flow restores reanalysis heading")
    func testResettingReanalysisFlowRestoresHeading() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_mush")
        viewModel.activeQuestionIndex = 2
        viewModel.clearSubjectSelection()

        viewModel.resetFunnel()

        #expect(viewModel.activeQuestionIndex == 0)
        #expect(viewModel.activeSubjectId == "subj_mush")
        #expect(viewModel.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis input placeholder stays general")
    func testReanalysisInputPlaceholderStaysGeneral() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_bird")

        #expect(viewModel.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
    }

    @Test("Unknown reanalysis subject uses same general placeholder")
    func testUnknownReanalysisSubjectUsesSameGeneralPlaceholder() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: nil)

        #expect(viewModel.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
    }

    @Test("Reanalysis placeholder ignores switched subject")
    func testReanalysisPlaceholderIgnoresSwitchedSubject() {
        let viewModel = DescribePromptViewModel()
        viewModel.configureReanalysisFlow(subjectId: "subj_bird")
        viewModel.activateFunnel(for: "subj_insec")

        #expect(viewModel.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
    }

    // MARK: - Describe Subject Resolver

    @Test("DescribeSubjectResolver maps taxonomy to subject IDs")
    func testDescribeSubjectResolverMapsTaxonomy() {
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Aves"))) == "subj_bird")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Insecta"))) == "subj_insec")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Arachnida"))) == "subj_spid")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Mammalia"))) == "subj_mamm")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Amphibia"))) == "subj_rept")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Reptilia"))) == "subj_rept")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(className: "Actinopterygii"))) == "subj_fish")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(kingdom: "Plantae"))) == "subj_plan")
        #expect(DescribeSubjectResolver.subjectId(for: species(taxonomy: taxonomy(kingdom: "Fungi"))) == "subj_mush")
    }

    @Test("DescribeSubjectResolver falls back to names and unknown stays nil")
    func testDescribeSubjectResolverNameFallbacks() {
        #expect(DescribeSubjectResolver.subjectId(for: species(commonName: "Monarch Butterfly")) == "subj_insec")
        #expect(DescribeSubjectResolver.subjectId(forText: "House Finch") == "subj_bird")
        #expect(DescribeSubjectResolver.subjectId(forText: "houseplant") == "subj_plan")
        #expect(DescribeSubjectResolver.subjectId(forText: "pothos") == "subj_plan")
        #expect(DescribeSubjectResolver.subjectId(forText: "Epipremnum aureum") == "subj_plan")
        #expect(DescribeSubjectResolver.subjectId(for: species(scientificName: "Quercus macrocarpa")) == "subj_plan")
        #expect(DescribeSubjectResolver.subjectId(
            taxonomy: taxonomy(order: "Lepidoptera", family: nil, genus: nil),
            commonName: nil,
            scientificName: nil
        ) == "subj_insec")
        #expect(DescribeSubjectResolver.subjectId(for: species(commonName: "Unknown subject", scientificName: "Taxonomy Unavailable")) == nil)
    }

    @Test("DescribeSubjectResolver uses original scan semantic tags")
    func testDescribeSubjectResolverUsesRecordSemanticTags() {
        let record = LocalScanRecord(
            speciesId: "original-species-id",
            scientificName: "Epipremnum aureum",
            commonName: "Golden Pothos",
            semanticTags: ["Houseplants"]
        )

        #expect(DescribeSubjectResolver.subjectId(for: record) == "subj_plan")
    }

    private func species(
        commonName: String = "Unknown subject",
        scientificName: String = "Taxonomy Unavailable",
        taxonomy: TaxonomyData? = nil
    ) -> SpeciesData {
        SpeciesData(
            commonName: commonName,
            scientificName: scientificName,
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0,
            taxonomy: taxonomy
        )
    }

    private func taxonomy(
        kingdom: String? = nil,
        className: String? = nil,
        order: String? = nil,
        family: String? = nil,
        genus: String? = nil
    ) -> TaxonomyData {
        TaxonomyData(
            kingdom: kingdom,
            phylum: nil,
            className: className,
            order: order,
            family: family,
            genus: genus
        )
    }
}
