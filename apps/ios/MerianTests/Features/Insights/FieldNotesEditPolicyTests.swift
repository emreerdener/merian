import Testing

@testable import Merian

@Suite("Field Notes Edit Policy Tests")
struct FieldNotesEditPolicyTests {
    @Test func unchangedPublicAndPrivateDraftsAreNoOps() {
        let publicChanges = FieldNotesEditPolicy.changes(
            initialText: "Observed near the creek",
            initialIsPublic: true,
            draftText: "Observed near the creek",
            draftIsPublic: true
        )
        let privateChanges = FieldNotesEditPolicy.changes(
            initialText: "Observed near the creek",
            initialIsPublic: false,
            draftText: "Observed near the creek",
            draftIsPublic: false
        )

        #expect(publicChanges.isEmpty)
        #expect(privateChanges.isEmpty)
    }

    @Test func textEditIsAContentOnlyChange() {
        let changes = FieldNotesEditPolicy.changes(
            initialText: "Observed near the creek",
            initialIsPublic: true,
            draftText: "Observed beside the creek",
            draftIsPublic: true
        )

        #expect(changes == .content)
    }

    @Test func visibilityToggleIsAVisibilityOnlyChange() {
        let changes = FieldNotesEditPolicy.changes(
            initialText: "Observed near the creek",
            initialIsPublic: false,
            draftText: "Observed near the creek",
            draftIsPublic: true
        )

        #expect(changes == .visibility)
    }

    @Test func clearingPublicNotesChangesContentAndEffectiveVisibility() {
        let changes = FieldNotesEditPolicy.changes(
            initialText: "Observed near the creek",
            initialIsPublic: true,
            draftText: "",
            draftIsPublic: false
        )

        #expect(changes == [.content, .visibility])
    }

    @Test func contentAndVisibilityFeedbackAreDistinct() {
        #expect(FieldNotesEditPolicy.successMessage(
            wasPublic: true,
            isPublic: true,
            contentChanged: true
        ) == "Field notes updated")
        #expect(FieldNotesEditPolicy.successMessage(
            wasPublic: false,
            isPublic: true,
            contentChanged: true
        ) == "Field notes are now public on Explore")
        #expect(FieldNotesEditPolicy.successMessage(
            wasPublic: true,
            isPublic: false,
            contentChanged: true
        ) == "Field notes are now private")
        #expect(FieldNotesEditPolicy.successMessage(
            wasPublic: true,
            isPublic: true,
            contentChanged: false
        ) == nil)
    }
}
