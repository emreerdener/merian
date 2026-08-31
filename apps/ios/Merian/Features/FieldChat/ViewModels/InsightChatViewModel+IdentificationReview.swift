import Foundation

extension InsightChatViewModel {
    static func shouldOfferConfidenceReview(for speciesData: SpeciesData) -> Bool {
        let bands = MerianConfig.confidenceBands(forInferenceTier: speciesData.inferenceTier)
        return speciesData.confidenceScore < bands.strong || hasLookalikeContext(speciesData)
    }

    func shouldOfferIdentificationReviewActions(forAssistantMessageAt index: Int) -> Bool {
        guard messages.indices.contains(index),
              messages[index].role == .assistant,
              !messages[index].isRefusal,
              index > messages.startIndex else {
            return false
        }

        let previousMessage = messages[messages.index(before: index)]
        guard previousMessage.role == .user else { return false }
        return Self.isIdentificationConcernPrompt(previousMessage.text)
    }

    static func isIdentificationConcernPrompt(_ text: String) -> Bool {
        let normalized = normalizedConcernText(text)
        guard !normalized.isEmpty else { return false }
        let padded = " \(normalized) "

        let containsAny: ([String]) -> Bool = { phrases in
            phrases.contains { normalized.contains($0) }
        }
        let containsAnyToken: ([String]) -> Bool = { tokens in
            tokens.contains { padded.contains($0) }
        }

        let explicitIdentificationConcern = [
            "identification is incorrect",
            "identification is wrong",
            "id is incorrect",
            "id is wrong",
            "this id is incorrect",
            "this id is wrong",
            "wrong identification",
            "wrong id",
            "wrong species",
            "incorrect identification",
            "incorrect id",
            "incorrect species",
            "this is the wrong species",
            "this is not the right species",
            "misidentified",
            "mis identified",
            "not the right species",
            "not the right id",
            "not the right identification",
            "disagree with this id",
            "disagree with the id",
            "disagree with this identification",
            "dont think this is",
            "do not think this is",
            "doesnt look like",
            "does not look like",
            "this doesnt look like",
            "this does not look like"
        ]

        if containsAny(explicitIdentificationConcern) {
            return true
        }

        let directDisagreement = [
            "this is wrong",
            "this is incorrect",
            "that is wrong",
            "that is incorrect",
            "thats wrong",
            "thats incorrect",
            "that s wrong",
            "that s incorrect",
            "this isnt right",
            "this is not right",
            "that isnt right",
            "that is not right",
            "that s not right",
            "it isnt right",
            "it is not right",
            "it s not right",
            "thats not it",
            "that is not it",
            "that s not it"
        ]

        if containsAny(directDisagreement) {
            return true
        }

        let softConcern = [
            "doesnt seem right",
            "does not seem right",
            "seems off",
            "looks off",
            "feels off",
            "feels wrong",
            "not convinced",
            "not sure this is correct",
            "not sure this is right",
            "are you sure this is right",
            "are you sure this is correct",
            "are you sure this is the right species",
            "are you sure about this id",
            "are you sure about the id",
            "are you sure about this identification",
            "are you sure about the identification"
        ]

        if containsAny(softConcern) {
            return true
        }

        let alternativeIdentification = [
            "i think this is something else",
            "i think it is something else",
            "i think its something else",
            "i think it s something else",
            "different species",
            "another species",
            "could this be a different",
            "could this be another",
            "could it be a different",
            "could it be another",
            "could this be something else",
            "could it be something else",
            "looks more like",
            "look more like",
            "looks like a different",
            "looks like another",
            "might be a different",
            "might be another"
        ]

        if containsAny(alternativeIdentification) {
            return true
        }

        if normalized.contains("instead"),
           containsAny([
               "could this be",
               "could it be",
               "this could be",
               "it could be",
               "might be",
               "looks like",
               "look like",
               "more like"
           ]) {
            return true
        }

        let traitMismatchSignals = [
            "dont match",
            "do not match",
            "doesnt match",
            "does not match",
            "dont fit",
            "do not fit",
            "doesnt fit",
            "does not fit",
            "seems wrong",
            "look different",
            "looks different",
            "seems unlikely"
        ]
        let traitTerms = [
            "marking",
            "markings",
            "pattern",
            "patterns",
            "color",
            "colors",
            "colour",
            "shape",
            "size",
            "habitat",
            "location",
            "spot",
            "spots",
            "stripe",
            "stripes",
            "wing",
            "wings",
            "leaf",
            "leaves",
            "flower",
            "flowers",
            "body"
        ]

        if containsAny(traitMismatchSignals) && containsAnyToken(traitTerms) {
            return true
        }

        let recheckIntent = [
            "can you check again",
            "could you check again",
            "check the id again",
            "check this id again",
            "check the identification again",
            "check this identification again",
            "try the id again",
            "try the identification again",
            "analyze this again",
            "analyse this again",
            "reanalyze this",
            "re analyze this",
            "reanalyze species",
            "reanalyze the species",
            "take another look",
            "look at this again",
            "look at the id again"
        ]

        if containsAny(recheckIntent) {
            return true
        }

        let hasIdentificationSubject = [
            " identification ",
            " id ",
            " species ",
            " match ",
            " identified "
        ].contains(where: { padded.contains($0) })

        let hasConcernSignal = [
            " wrong ",
            " incorrect ",
            " not correct ",
            " not right ",
            " off "
        ].contains(where: { padded.contains($0) })

        if hasIdentificationSubject && hasConcernSignal {
            return true
        }

        let thisIsNegated = [
            "this is not",
            "this isnt",
            "it is not",
            "it isnt",
            "not a ",
            "not an "
        ].contains(where: { normalized.contains($0) })

        return thisIsNegated && [
            "this is",
            "it is",
            "look like",
            "species"
        ].contains(where: { normalized.contains($0) })
    }

    private static func normalizedConcernText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "n't", with: "nt")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
