enum FieldTripTemplateReference: Hashable {
    case id(String)
    case slug(String)
}

struct FieldTripTemplateRoute: Hashable {
    let reference: FieldTripTemplateReference
    let focusedChecklistItemId: String?

    init(templateId: String, focusedChecklistItemId: String? = nil) {
        reference = .id(templateId)
        self.focusedChecklistItemId = focusedChecklistItemId
    }

    init(slug: String, focusedChecklistItemId: String? = nil) {
        reference = .slug(slug)
        self.focusedChecklistItemId = focusedChecklistItemId
    }
}

struct FieldTripPublicationRoute: Hashable {
    let publicationId: String
}

struct FieldTripChallengeRoute: Hashable {
    let challengeId: String
}

struct FieldTripChallengeEntryRoute: Hashable {
    let entryId: String
}
