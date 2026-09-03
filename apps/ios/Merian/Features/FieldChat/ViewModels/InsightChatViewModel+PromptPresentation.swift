import Foundation

extension InsightChatViewModel {
    func suggestionChips(
        for speciesData: SpeciesData,
        timestamp: Date?,
        displayName: String? = nil
    ) -> [String] {
        let fallbackChips = Self.suggestionChips(
            for: speciesData,
            timestamp: timestamp,
            displayName: displayName
        )
        let sentTexts = Set(sentAndPendingPromptTexts)
        var seen = Set<String>()
        var chips: [String] = []
        let availableConfidencePrompt = suggestedPrompts.first { prompt in
            let key = normalizedPromptKey(prompt.text)
            return prompt.category == "confidence"
                && !key.isEmpty
                && !sentTexts.contains(key)
        }
        let localConfidencePrompt = "What makes this ID uncertain?"
        let localConfidenceKey = normalizedPromptKey(localConfidencePrompt)
        let requiredConfidencePrompt: String? = if speciesData.confidenceScore < 0.7 {
            availableConfidencePrompt?.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (!sentTexts.contains(localConfidenceKey) ? localConfidencePrompt : nil)
        } else {
            nil
        }
        let requiredConfidenceKey = requiredConfidencePrompt.map(normalizedPromptKey)
        let ordinaryChipLimit = requiredConfidencePrompt == nil ? 3 : 2
        var ordinaryChipCount = 0
        var includedRequiredConfidencePrompt = false

        for prompt in suggestedPrompts.map(\.text) + fallbackChips {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedPromptKey(trimmed)
            guard !trimmed.isEmpty,
                  !sentTexts.contains(key),
                  seen.insert(key).inserted else {
                continue
            }

            if key == requiredConfidenceKey {
                chips.append(trimmed)
                includedRequiredConfidencePrompt = true
            } else if ordinaryChipCount < ordinaryChipLimit {
                chips.append(trimmed)
                ordinaryChipCount += 1
            }

            if ordinaryChipCount == ordinaryChipLimit,
               requiredConfidencePrompt == nil || includedRequiredConfidencePrompt {
                break
            }
        }

        if !includedRequiredConfidencePrompt, let requiredConfidencePrompt {
            chips.append(requiredConfidencePrompt)
        }

        return chips
    }

    func publicPostSuggestionChips(displayName: String) -> [String] {
        let name = source == .speciesDictionary
            ? Self.speciesDictionaryPromptLabel(displayName)
            : displayName.trimmedNonEmptyValue
                ?? "this species"
        let fallback = [
            "What traits are characteristic of \(name)?",
            "What habitat does \(name) prefer?",
            "What is most interesting about \(name)?"
        ]
        let sentTexts = Set(sentAndPendingPromptTexts)
        var seen = Set<String>()
        return (suggestedPrompts.map(\.text) + fallback).filter { prompt in
            let key = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !key.isEmpty && !sentTexts.contains(key) && seen.insert(key).inserted
        }.prefix(3).map { $0 }
    }

    static let speciesDictionaryPromptLabelMaxUnicodeScalars = 64

    static let speciesDictionaryPromptLabelGeneralCategories: Set<String> = [
        "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd"
    ]

    static let speciesDictionaryPromptLabelWhitespaceScalarValues: Set<UInt32> = [
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085, 0x00A0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
        0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
        0x3000
    ]

    static let speciesDictionaryPromptLabelPunctuationScalarValues: Set<UInt32> = [
        0x0027, 0x0028, 0x0029, 0x002D, 0x002E, 0x2013, 0x2019
    ]

    static func speciesDictionaryPromptLabel(_ value: String) -> String {
        var normalizedScalars: [Unicode.Scalar] = []
        var pendingSpace = false

        for scalar in value.unicodeScalars {
            if speciesDictionaryPromptLabelWhitespaceScalarValues.contains(scalar.value) {
                if !normalizedScalars.isEmpty {
                    pendingSpace = true
                }
                continue
            }

            guard speciesDictionaryPromptLabelAllows(scalar) else {
                return "this species"
            }
            if pendingSpace {
                normalizedScalars.append(" ")
                pendingSpace = false
            }
            normalizedScalars.append(scalar)
            if normalizedScalars.count > speciesDictionaryPromptLabelMaxUnicodeScalars {
                return "this species"
            }
        }

        guard !normalizedScalars.isEmpty else {
            return "this species"
        }
        return String(String.UnicodeScalarView(normalizedScalars))
    }

    private static func speciesDictionaryPromptLabelAllows(_ scalar: Unicode.Scalar) -> Bool {
        let category: String?
        switch scalar.properties.generalCategory {
        case .uppercaseLetter: category = "Lu"
        case .lowercaseLetter: category = "Ll"
        case .titlecaseLetter: category = "Lt"
        case .modifierLetter: category = "Lm"
        case .otherLetter: category = "Lo"
        case .nonspacingMark: category = "Mn"
        case .spacingMark: category = "Mc"
        case .enclosingMark: category = "Me"
        case .decimalNumber: category = "Nd"
        default:
            category = nil
        }
        if let category,
           speciesDictionaryPromptLabelGeneralCategories.contains(category) {
            return true
        }
        return speciesDictionaryPromptLabelPunctuationScalarValues.contains(scalar.value)
    }

    var sentAndPendingPromptTexts: [String] {
        messages.filter { $0.role == .user }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            + [pendingUserMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()].compactMap { $0 }
    }

    static func suggestionChips(
        for speciesData: SpeciesData,
        timestamp: Date?,
        displayName: String? = nil
    ) -> [String] {
        let speciesName = displayName?.trimmedNonEmptyValue
            ?? Self.displayName(for: speciesData)
        var candidates: [String] = []

        if let comparisonName = comparisonPromptName(for: speciesData) {
            candidates.append("How do I tell it apart from \(comparisonName)?")
        }

        if speciesData.insightData.isHazardous {
            let hazard = hazardLabel(speciesData.insightData.hazardType)
            candidates.append("What should I know about its \(hazard) risk?")
        }

        if speciesData.isInvasive {
            candidates.append("Why is \(speciesName) invasive here?")
        }

        if let traitPhrase = visualTraitPhrase(from: speciesData.aiReasoning) {
            candidates.append("Which \(traitPhrase) traits support this ID?")
        }

        if hasHabitatContext(speciesData) {
            candidates.append("Does this habitat fit \(speciesName)?")
        }

        let monthDate = timestamp ?? Date()
        let month = monthFormatter.string(from: monthDate)
        candidates.append("Is \(speciesName) typical in \(month)?")

        if speciesData.confidenceScore >= 0.8 {
            candidates.append("What makes this a strong match?")
        } else if speciesData.confidenceScore < 0.7 {
            candidates.append("What makes this ID uncertain?")
        } else {
            candidates.append("What traits support this ID?")
        }

        candidates.append("What should I look for nearby?")
        candidates.append("What traits support this ID?")

        return uniquePrompts(candidates).prefix(3).map { $0 }
    }

    static func comparisonPrompt(for speciesData: SpeciesData) -> String? {
        comparisonPromptName(for: speciesData).map { "How do I tell it apart from \($0)?" }
    }

    static func hasLookalikeContext(_ speciesData: SpeciesData) -> Bool {
        comparisonPromptName(for: speciesData) != nil
    }

    func category(forPrompt prompt: String) -> String {
        let key = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let suggestedPrompt = suggestedPrompts.first(where: {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) {
            return suggestedPrompt.category
        }
        return Self.localPromptCategory(for: prompt)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private static func comparisonPromptName(for speciesData: SpeciesData) -> String? {
        if let candidate = speciesData.candidates?.first {
            return candidate.commonName?.trimmedNonEmptyValue
                ?? candidate.scientificName
        }

        let lookalike = speciesData.similarSpecies?.filteredEntries(
            excludingScientificName: speciesData.scientificName
        ).first
        return lookalike?.displayCommonName(comparedTo: speciesData.commonName)
            ?? lookalike?.scientificName
    }

    private static func displayName(for speciesData: SpeciesData) -> String {
        let commonName = speciesData.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commonName.isEmpty, commonName.caseInsensitiveCompare("not applicable") != .orderedSame {
            return commonName
        }
        let scientificName = speciesData.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        return scientificName.trimmedNonEmptyValue ?? "this species"
    }

    private static func hazardLabel(_ hazardType: String) -> String {
        let normalized = hazardType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        return normalized.trimmedNonEmptyValue ?? "hazard"
    }

    private static func hasHabitatContext(_ speciesData: SpeciesData) -> Bool {
        if speciesData.habitatDescription?.trimmedNonEmptyValue != nil {
            return true
        }
        let ecologyType = speciesData.ecologyType.trimmingCharacters(in: .whitespacesAndNewlines)
        return !ecologyType.isEmpty && ecologyType.caseInsensitiveCompare("unknown") != .orderedSame
    }

    private static func hasObservedTraits(_ speciesData: SpeciesData) -> Bool {
        if speciesData.colors?.isEmpty == false { return true }
        if speciesData.lifeStage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.reproductiveCondition?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.sexEvidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        if speciesData.estimatedSizeCm != nil || speciesData.individualCount != nil { return true }
        return false
    }

    private static func visualTraitPhrase(from reasoning: String?) -> String? {
        guard let normalizedReasoning = reasoning?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalizedReasoning.isEmpty else {
            return nil
        }

        let traitGroups: [(label: String, keywords: [String])] = [
            ("leaf", ["leaf", "leaves", "foliage"]),
            ("flower", ["flower", "flowers", "petal", "petals", "bloom", "blooms"]),
            ("wing", ["wing", "wings"]),
            ("color", ["color", "colors", "colored", "colour", "hue"]),
            ("pattern", ["pattern", "patterns", "stripe", "stripes", "spot", "spots", "marking", "markings"]),
            ("stem", ["stem", "stems", "branch", "branches"]),
            ("cap", ["cap", "caps", "mushroom"]),
            ("gill", ["gill", "gills"]),
            ("fruit", ["fruit", "fruits", "berry", "berries"]),
            ("body", ["body", "abdomen", "thorax", "leg", "legs"])
        ]

        let matchedLabels = traitGroups.compactMap { group -> String? in
            group.keywords.contains { normalizedReasoning.contains($0) } ? group.label : nil
        }

        switch matchedLabels.count {
        case 0:
            return nil
        case 1:
            return matchedLabels[0]
        default:
            return matchedLabels.prefix(2).joined(separator: " and ")
        }
    }

    private static func localPromptCategory(for prompt: String) -> String {
        let normalized = prompt.lowercased()
        if normalized.contains("tell it apart") { return "lookalike_compare" }
        if normalized.contains("risk") { return "hazard" }
        if normalized.contains("invasive") { return "invasive" }
        if normalized.contains("traits support") { return "evidence" }
        if normalized.contains("habitat") { return "habitat" }
        if normalized.contains("typical in") { return "season" }
        if normalized.contains("strong match") || normalized.contains("uncertain") {
            return "confidence"
        }
        return "generic"
    }

    private static func uniquePrompts(_ prompts: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for prompt in prompts {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(trimmed)
        }

        return unique
    }

    private func normalizedPromptKey(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
