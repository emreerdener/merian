import Foundation

struct FieldNotesEditChanges: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let content = FieldNotesEditChanges(rawValue: 1 << 0)
    static let visibility = FieldNotesEditChanges(rawValue: 1 << 1)
}

enum FieldNotesEditPolicy {
    static func changes(
        initialText: String,
        initialIsPublic: Bool,
        draftText: String,
        draftIsPublic: Bool
    ) -> FieldNotesEditChanges {
        var changes: FieldNotesEditChanges = []

        if initialText != draftText {
            changes.insert(.content)
        }

        let initialEffectiveVisibility = initialIsPublic && normalizedText(initialText) != nil
        let draftEffectiveVisibility = draftIsPublic && normalizedText(draftText) != nil
        if initialEffectiveVisibility != draftEffectiveVisibility {
            changes.insert(.visibility)
        }

        return changes
    }

    static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func successMessage(
        wasPublic: Bool,
        isPublic: Bool,
        contentChanged: Bool
    ) -> String? {
        if wasPublic != isPublic {
            return isPublic
                ? "Field notes are now public on Explore"
                : "Field notes are now private"
        }

        return contentChanged ? "Field notes updated" : nil
    }
}
