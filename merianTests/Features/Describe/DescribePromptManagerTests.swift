import Testing
import Foundation
@testable import Merian

// MARK: - DescribePromptManager Unit Tests
//
// These tests cover the pure state-machine logic of DescribePromptManager in
// isolation, without any SwiftUI dependency. Each scenario maps directly to a
// user-visible flow in the Describe identification interview.

@Suite("DescribePromptManager")
struct DescribePromptManagerTests {

    // MARK: - Initial State

    @Test("Initial state is Q0 with full general question list")
    func testInitialState() {
        let manager = DescribePromptManager()
        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeSubjectId == nil)
        #expect(!manager.isFunnelActive)
        #expect(manager.activeQuestions == guidedQuestions)
        #expect(manager.interactedQuestionIndices.isEmpty)
    }

    // MARK: - Funnel Activation

    @Test("activateFunnel sets subject ID and swaps question list")
    func testActivateFunnelSetsState() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")

        #expect(manager.activeSubjectId == "subj_bird")
        #expect(manager.isFunnelActive)
        #expect(manager.activeQuestions.count > 1)
        // First question is always the subject question
        #expect(manager.activeQuestions[0].prompt == guidedQuestions[0].prompt)
        // Second question is the first funnel-specific question (not a general one)
        #expect(manager.activeQuestions[1].prompt != guidedQuestions[1].prompt)
    }

    @Test("activateFunnel advances activeQuestionIndex to 1")
    func testActivateFunnelAdvancesIndex() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        #expect(manager.activeQuestionIndex == 1)
    }

    @Test("activateFunnel resets interactedQuestionIndices")
    func testActivateFunnelResetsInteracted() {
        let manager = DescribePromptManager()
        manager.interactedQuestionIndices = [0, 1, 2]
        manager.activateFunnel(for: "subj_bird")
        #expect(manager.interactedQuestionIndices.isEmpty)
    }

    @Test("activateFunnel appends general telemetry questions")
    func testActivateFunnelAppendsGeneralTelemetry() {
        let manager = DescribePromptManager()
        guard let funnel = subjectFunnels["subj_bird"] else {
            Issue.record("subj_bird funnel missing from subjectFunnels")
            return
        }
        manager.activateFunnel(for: "subj_bird")
        // Expected layout: [Q0] + funnel + [general[1], general[2], general.last]
        let expectedCount = 1 + funnel.count + 3
        #expect(manager.activeQuestions.count == expectedCount)
    }

    @Test("activateFunnel for unknown subject ID is a no-op")
    func testActivateFunnelUnknownSubjectIsNoOp() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_unknown_xyz")
        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeSubjectId == nil)
        #expect(!manager.isFunnelActive)
        #expect(manager.activeQuestions == guidedQuestions)
    }

    @Test("All subject IDs defined in Q0 tags have matching funnel entries")
    func testAllQ0SubjectTagsHaveFunnels() {
        let q0Tags = guidedQuestions[0].tags
        for tag in q0Tags {
            // "subj_othr" intentionally has a funnel too; all subj_ tags must resolve
            if tag.tagId.hasPrefix("subj_") {
                #expect(subjectFunnels[tag.tagId] != nil,
                        "Missing funnel for tagId: \(tag.tagId)")
            }
        }
    }

    // MARK: - Funnel Reset

    @Test("resetFunnel restores initial state")
    func testResetFunnelRestoresInitialState() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        manager.activeQuestionIndex = 3
        manager.interactedQuestionIndices = [0, 1, 2]

        manager.resetFunnel()

        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeSubjectId == nil)
        #expect(!manager.isFunnelActive)
        #expect(manager.activeQuestions == guidedQuestions)
        #expect(manager.interactedQuestionIndices.isEmpty)
    }

    @Test("resetFunnel on already-reset manager is a no-op")
    func testDoubleResetIsNoOp() {
        let manager = DescribePromptManager()
        manager.resetFunnel()
        manager.resetFunnel()
        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeSubjectId == nil)
    }

    // MARK: - Funnel Re-activation (species switch)

    @Test("Switching species resets then activates new funnel")
    func testSwitchingSpeciesActivatesNewFunnel() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        let birdCount = manager.activeQuestions.count

        manager.resetFunnel()
        manager.activateFunnel(for: "subj_insec")

        #expect(manager.activeSubjectId == "subj_insec")
        #expect(manager.activeQuestionIndex == 1)
        // Insect funnel may have a different length than bird funnel
        if let birdFunnel = subjectFunnels["subj_bird"],
           let insectFunnel = subjectFunnels["subj_insec"],
           birdFunnel.count != insectFunnel.count {
            #expect(manager.activeQuestions.count != birdCount)
        }
    }

    // MARK: - Index Bounds

    @Test("activeQuestionIndex stays in valid range after activation")
    func testActiveIndexInBoundsAfterActivation() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        let idx = manager.activeQuestionIndex
        #expect(idx >= 0)
        #expect(idx < manager.activeQuestions.count)
    }

    @Test("activeQuestions[activeQuestionIndex] is accessible after activation")
    func testCurrentQuestionIsAccessible() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        let idx = manager.activeQuestionIndex
        // Should not crash
        let question = manager.activeQuestions[idx]
        #expect(!question.prompt.isEmpty)
    }

    // MARK: - isFunnelActive Derived Property

    @Test("isFunnelActive is false before any activation")
    func testIsFunnelActiveInitially() {
        let manager = DescribePromptManager()
        #expect(!manager.isFunnelActive)
    }

    @Test("isFunnelActive is true after activation")
    func testIsFunnelActiveAfterActivation() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        #expect(manager.isFunnelActive)
    }

    @Test("isFunnelActive is false after reset")
    func testIsFunnelActiveAfterReset() {
        let manager = DescribePromptManager()
        manager.activateFunnel(for: "subj_bird")
        manager.resetFunnel()
        #expect(!manager.isFunnelActive)
    }

    // MARK: - All Funnel Species

    @Test("activateFunnel works for all subject IDs in subjectFunnels")
    func testActivateFunnelForAllSubjects() {
        for subjectId in subjectFunnels.keys {
            let manager = DescribePromptManager()
            manager.activateFunnel(for: subjectId)
            #expect(manager.isFunnelActive,
                    "Funnel not active after activating subjectId: \(subjectId)")
            #expect(manager.activeSubjectId == subjectId)
            #expect(manager.activeQuestionIndex == 1)
        }
    }

    // MARK: - Reanalysis Flow

    @Test("Reanalysis flow uses reanalysis heading")
    func testReanalysisFlowUsesReanalysisHeading() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: nil)

        #expect(manager.currentPrompt == "What would you like to reanalyze?")
        #expect(manager.displayPrompt(at: 0) == "What would you like to reanalyze?")
        #expect(manager.activeQuestionIndex == 0)
    }

    @Test("Reanalysis flow preselects provided subject")
    func testReanalysisFlowPreselectsProvidedSubject() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_bird")

        #expect(manager.activeSubjectId == "subj_bird")
        #expect(manager.isFunnelActive)
        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeQuestions.count == 1)
        #expect(manager.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis flow tolerates unknown subject")
    func testReanalysisFlowToleratesUnknownSubject() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_unknown_xyz")

        #expect(manager.activeSubjectId == nil)
        #expect(!manager.isFunnelActive)
        #expect(manager.activeQuestions.count == 1)
        #expect(manager.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis flow does not include Describe prompts")
    func testReanalysisFlowDoesNotIncludeDescribePrompts() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_plan")

        #expect(manager.activeQuestions.count == 1)
        #expect(manager.activeQuestions.first?.tags.isEmpty == true)
        #expect(manager.activeQuestions.first?.prompt == "What would you like to reanalyze?")
    }

    @Test("Resetting reanalysis flow restores reanalysis heading")
    func testResettingReanalysisFlowRestoresHeading() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_mush")
        manager.activeQuestionIndex = 2
        manager.clearSubjectSelection()

        manager.resetFunnel()

        #expect(manager.activeQuestionIndex == 0)
        #expect(manager.activeSubjectId == "subj_mush")
        #expect(manager.currentPrompt == "What would you like to reanalyze?")
    }

    @Test("Reanalysis input placeholder stays general")
    func testReanalysisInputPlaceholderStaysGeneral() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_bird")

        #expect(manager.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
    }

    @Test("Unknown reanalysis subject uses same general placeholder")
    func testUnknownReanalysisSubjectUsesSameGeneralPlaceholder() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: nil)

        #expect(manager.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
    }

    @Test("Reanalysis placeholder ignores switched subject")
    func testReanalysisPlaceholderIgnoresSwitchedSubject() {
        let manager = DescribePromptManager()
        manager.configureReanalysisFlow(subjectId: "subj_bird")
        manager.activateFunnel(for: "subj_insec")

        #expect(manager.inputPlaceholder == DescribePromptCopy.reanalysisInputPlaceholder)
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
