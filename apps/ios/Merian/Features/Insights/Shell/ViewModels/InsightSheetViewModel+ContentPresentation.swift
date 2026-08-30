import SwiftUI

extension InsightSheetViewModel {
    enum ContentMode: Equatable {
        case analyzing
        case queued
        case nonBiological
        case biological
    }

    /// Derives which content subtree `InsightContentView` should render.
    /// Computed from engine state so each call site switches on one value
    /// rather than duplicating the `isProcessing` / `speciesData` guard chain.
    var contentMode: ContentMode {
        if queuedContext != nil { return .queued }
        if isProcessing { return .analyzing }
        guard let data = inferenceEngine?.speciesData else { return .analyzing }
        let usesSimplifiedResultView =
            data.isInferenceErrorPlaceholder ||
            data.isClassifiedNonBiological ||
            data.commonName.lowercased() == "not applicable"
        if usesSimplifiedResultView {
            return .nonBiological
        }
        return .biological
    }

    // MARK: - Header Computed Properties

    /// The display name shown as the InsightHeader headline.
    /// Applies the resolution chain: user preference → canonical DB common name.
    var resolvedHeaderTitle: String {
        guard let species = inferenceEngine?.speciesData else {
            return "Scanning subject..."
        }
        let common = species.subjectDisplayName(
            isAudioOnlyObservation: hasStandaloneAudio && !activeMedia.hasUserImage
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if species.isInferenceErrorPlaceholder {
            return common.isEmpty ? "Analysis unavailable" : common
        }
        if species.isClassifiedNonBiological || common.lowercased() == "not applicable" {
            return "Non-biological"
        }
        if let petLabel = species.petIdentification?.label.trimmingCharacters(in: .whitespacesAndNewlines),
           !petLabel.isEmpty {
            return petLabel
        }
        if let preferred = state.preferredCommonName, !preferred.isEmpty {
            return preferred
        }
        let scientific = species.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        if common.isEmpty {
            return scientific
        } else if common.lowercased() == scientific.lowercased() {
            return common
        } else {
            return common.capitalized
        }
    }

    /// All English synonym names available for user selection, excluding whichever name
    /// is currently resolved as the headline (to avoid surfacing the active name as an option).
    /// Uses allNamesForPicker as the base so the canonical primary name is included even
    /// when the user has chosen an alternative as their preferred headline.
    var displayAlternativeCommonNames: [String]? {
        let all = allNamesForPicker
        guard !all.isEmpty else { return nil }
        let activeKey = resolvedHeaderTitle.commonNameKey
        let filtered = all.filter { $0.commonNameKey != activeKey }
        return filtered.isEmpty ? nil : filtered
    }

    /// All candidate names for the picker sheet: primary common name + alternatives,
    /// with a checkmark on the currently resolved headline.
    var allNamesForPicker: [String] {
        guard let species = inferenceEngine?.speciesData else { return [] }
        let primary = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let alternatives = species.alternativeCommonNames ?? []
        return ([primary] + alternatives).removingFuzzyDuplicateNames()
    }

    var headerSubtitle: String {
        guard let species = inferenceEngine?.speciesData else {
            return "Awaiting taxonomy"
        }
        return species.presentationScientificName
    }

    var hazardType: String {
        inferenceEngine?.speciesData?.insightData.hazardType ?? "none"
    }

    var isHazardous: Bool { hazardType != "none" }

    var headerParagraphs: [String] {
        guard let species = inferenceEngine?.speciesData, !species.insightData.aiReasoning.isEmpty else { return [] }
        return species.insightData.aiReasoning
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Layout Computations

    /// Keeps the iOS 26 top scroll-edge treatment away from the hero image, then
    /// restores it once the image clears the navigation toolbar. The separate
    /// return threshold prevents the effect from flickering at the boundary.
    func evaluateHeroScrollOffset(maxY: CGFloat) {
        let shouldHideEffect = MediaHeroTopScrollEdgeEffectPolicy.isHidden(
            heroMaxY: maxY,
            currentlyHidden: state.isTopScrollEdgeEffectHidden
        )

        guard state.isTopScrollEdgeEffectHidden != shouldHideEffect else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            state.isTopScrollEdgeEffectHidden = shouldHideEffect
        }
    }

    /// Evaluates dynamic coordinate thresholds actively against negative scroll intersections, routing structural top-bar offsets.
    func evaluateScrollOffset(minY: CGFloat) {
        guard minY != .infinity else { return }
        // The value passed is actually the Title text's 'maxY'.
        // When its bottom edge dips below the native sheet NavigationBar (44pt), it has "scrolled past" fully offscreen.
        let threshold: CGFloat = 44
        let isPast = minY < threshold

        if state.isCommonNameScrolledPast != isPast {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                state.isCommonNameScrolledPast = isPast
            }
        }
    }
}
