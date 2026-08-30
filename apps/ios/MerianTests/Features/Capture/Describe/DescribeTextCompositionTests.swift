import Testing

@testable import Merian

@Suite("Describe text composition")
struct DescribeTextCompositionTests {
    private let birdTag = GuidedQuestion.Tag(
        tagId: "subj_bird",
        label: "Bird",
        aiText: "a bird",
        defaultWeight: 100
    )

    @Test("First tag capitalizes its natural-language fragment")
    func firstTagCapitalizesFragment() {
        #expect(DescribeTextComposer.applying(
            birdTag,
            to: "  \n",
            isRemoving: false
        ) == "A bird")
    }

    @Test("Tag after an unfinished thought uses comma composition")
    func unfinishedThoughtUsesCommaComposition() {
        #expect(DescribeTextComposer.applying(
            birdTag,
            to: "Small and blue",
            isRemoving: false
        ) == "Small and blue, a bird")
    }

    @Test("Tag after a sentence starts a capitalized sentence")
    func completedSentenceStartsNewSentence() {
        #expect(DescribeTextComposer.applying(
            birdTag,
            to: "It was calling!",
            isRemoving: false
        ) == "It was calling! A bird.")
    }

    @Test("Removing a selected subject preserves surrounding description")
    func removingSubjectPreservesDescription() {
        #expect(DescribeTextComposer.applying(
            birdTag,
            to: "Small and blue, a bird",
            isRemoving: true
        ) == "Small and blue")
        #expect(DescribeTextComposer.applying(
            birdTag,
            to: "A bird. Near a pond.",
            isRemoving: true
        ) == "Near a pond.")
    }

    @Test("Empty tag fragment leaves text unchanged")
    func emptyTagFragmentLeavesTextUnchanged() {
        let other = GuidedQuestion.Tag(
            tagId: "subj_othr",
            label: "Other",
            aiText: "",
            defaultWeight: 20
        )
        #expect(DescribeTextComposer.applying(
            other,
            to: "Unknown organism",
            isRemoving: false
        ) == "Unknown organism")
    }

    @Test("Dictation keeps the original baseline and ignores blank updates")
    func dictationUsesBaseline() {
        #expect(DescribeTextComposer.dictationText(
            baseText: "  Existing note  ",
            transcription: "a green beetle"
        ) == "Existing note a green beetle")
        #expect(DescribeTextComposer.dictationText(
            baseText: "Existing note",
            transcription: " \n "
        ) == nil)
    }

    @Test("Tag ranking uses frequency, default weight, then source order")
    func tagRankingUsesStablePriority() {
        let tags = [
            GuidedQuestion.Tag(
                tagId: "first",
                label: "First",
                aiText: "first",
                defaultWeight: 10
            ),
            GuidedQuestion.Tag(
                tagId: "frequent",
                label: "Frequent",
                aiText: "frequent",
                defaultWeight: 0
            ),
            GuidedQuestion.Tag(
                tagId: "weighted",
                label: "Weighted",
                aiText: "weighted",
                defaultWeight: 20
            )
        ]

        let ranked = DescribeTagRanking.ranked(
            tags,
            frequencies: ["frequent": 2]
        )
        #expect(ranked.map(\.tagId) == ["frequent", "weighted", "first"])
    }
}
