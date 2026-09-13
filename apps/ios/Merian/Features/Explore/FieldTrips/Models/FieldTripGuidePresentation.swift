import Foundation

extension FieldTripChecklistItem {
    var hasGuide: Bool {
        guide?.hasContent == true || guideTip?.fieldTripNonBlank != nil
    }

    var guidePreview: String? {
        guide?.preview ?? guideTip?.fieldTripNonBlank
    }
}

extension FieldTripChecklistItemGuide {
    var hasContent: Bool {
        preview != nil
    }

    var preview: String? {
        whereToLook?.fieldTripNonBlank
            ?? bestConditions?.fieldTripNonBlank
            ?? whatToNotice?.fieldTripNonBlank
            ?? scanSafely?.fieldTripNonBlank
    }
}

private extension String {
    var fieldTripNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
