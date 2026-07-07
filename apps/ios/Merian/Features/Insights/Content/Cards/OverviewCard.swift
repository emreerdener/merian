import SwiftUI

struct OverviewCard: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    // Fallback dictionary for capitalizing known values if needed
    func capitalizeFirstLetter(_ string: String) -> String {
        guard let first = string.first else { return "" }
        return String(first).uppercased() + string.dropFirst()
    }

    func nonEmpty(_ string: String?) -> String? {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func invasiveRegionLabel(_ region: String?, hasInvasiveContext: Bool) -> String? {
        guard hasInvasiveContext else { return nil }
        guard let trimmed = nonEmpty(region) else { return "Region unavailable" }
        return trimmed.caseInsensitiveCompare("Unavailable") == .orderedSame ? "Region unavailable" : trimmed
    }
    
    private var iucnStatus: (text: String, isGood: Bool?)? {
        guard let rawStatus = inferenceEngine.speciesData?.iucnRedListStatus?.lowercased() else { return nil }
        if rawStatus == "not applicable" || rawStatus.isEmpty || rawStatus == "data deficient" { return nil }
        let normalizedStatus = rawStatus.replacingOccurrences(of: "_", with: " ")
        
        switch normalizedStatus {
        case _ where normalizedStatus.contains("not evaluated"): return ("Not evaluated", nil)
        case _ where normalizedStatus.contains("least concern"): return ("Not at risk", true)
        case _ where normalizedStatus.contains("near threatened"): return ("Near threatened", false)
        case _ where normalizedStatus.contains("vulnerable"): return ("Vulnerable", false)
        case _ where normalizedStatus.contains("endangered") && !normalizedStatus.contains("critically"): return ("Endangered", false)
        case _ where normalizedStatus.contains("critically endangered"): return ("Critically endangered", false)
        case _ where normalizedStatus.contains("extinct in the wild"): return ("Extinct in the wild", false)
        case _ where normalizedStatus.contains("extinct"): return ("Extinct", false)
        default: return (capitalizeFirstLetter(normalizedStatus), true)
        }
    }
    
    var body: some View {
        if let data = inferenceEngine.speciesData {
            let wikiExtract = data.wikipediaOverview
            let hasWiki = (wikiExtract?.count ?? 0) >= 60
            
            let size = data.estimatedSizeCm.map { String(format: "%.1f cm", $0) }
            let invasive = data.isInvasive ? "Invasive" : "Not invasive"
            let invasiveRationale = nonEmpty(data.invasiveRationale)
            let invasiveConfidence = data.invasiveConfidence.flatMap { confidence -> String? in
                guard confidence.isFinite, (0...1).contains(confidence) else { return nil }
                return "\(Int((confidence * 100).rounded()))% confidence"
            }
            let hasInvasiveContext = nonEmpty(data.invasiveStatusRegion) != nil || invasiveConfidence != nil || invasiveRationale != nil
            let invasiveRegion = invasiveRegionLabel(data.invasiveStatusRegion, hasInvasiveContext: hasInvasiveContext)
            let invasiveRegionDetail = invasiveRegion.map { region in
                region == "Region unavailable" ? region : "Assessed for \(region)"
            }
            let ecology = data.ecologyType == "unknown" ? nil : capitalizeFirstLetter(data.ecologyType)
            let lifeStage = data.lifeStage.flatMap { $0 == "unknown" ? nil : capitalizeFirstLetter($0) }
            let reproduction = data.reproductiveCondition.flatMap { $0 == "not_applicable" ? nil : capitalizeFirstLetter($0.replacingOccurrences(of: "_", with: " ")) }
            let sexLabel = data.sex.flatMap { raw -> String? in
                let normalized = raw.replacingOccurrences(of: "_", with: " ").lowercased()
                guard normalized != "cannot determine", normalized != "not applicable" else { return nil }
                return capitalizeFirstLetter(normalized)
            }
            let sexConfidence = data.sexConfidence.flatMap { confidence -> String? in
                guard confidence.isFinite else { return nil }
                let bounded = min(max(confidence, 0), 1)
                return "\(Int((bounded * 100).rounded()))% confidence"
            }
            let sex = sexLabel.map { label in
                [label, sexConfidence].compactMap { $0 }.joined(separator: " · ")
            }
            let sexEvidence: String? = {
                guard sexLabel != nil,
                      let trimmed = data.sexEvidence?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else {
                    return nil
                }
                return capitalizeFirstLetter(trimmed)
            }()
            
            let hasOriginalImage = inferenceEngine.activeMedia.hasUserImage
            
            let colors: String? = {
                guard hasOriginalImage, let raw = data.colors, !raw.isEmpty else { return nil }
                return raw.joined(separator: ", ").capitalized
            }()
            
            let interactions: String? = {
                guard hasOriginalImage, let raw = data.ecologicalInteractions, !raw.isEmpty else { return nil }
                return raw.map { capitalizeFirstLetter($0.replacingOccurrences(of: "_", with: " ")) }.joined(separator: ", ")
            }()
            
            let hasAnyMetadata = colors != nil || size != nil || ecology != nil || lifeStage != nil || reproduction != nil || sex != nil || sexEvidence != nil || interactions != nil || data.isInvasive || invasiveRegionDetail != nil || invasiveConfidence != nil || invasiveRationale != nil || iucnStatus != nil
            
            if hasAnyMetadata {
                VStack(alignment: .leading, spacing: 16) {
                    
                    InsightCardHeader(systemImage: "book", title: "Overview")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let val = size {
                            KeyValueRow(title: "EST. SIZE", value: val)
                        }
                        if let val = lifeStage {
                            KeyValueRow(title: "LIFE STAGE", value: val)
                        }
                        if let val = reproduction {
                            KeyValueRow(title: "REPRODUCTION", value: val)
                        }
                        if let val = sex {
                            KeyValueRow(title: "SEX", value: val)
                        }
                        if let val = sexEvidence {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SEX CUE")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(val)
                                    .font(.system(.subheadline))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 4)
                        }
                        if let val = ecology {
                            KeyValueRow(title: "ECOLOGY", value: val)
                        }
                        InvasiveStatusSummary(
                            status: invasive,
                            assessmentDetail: invasiveRegionDetail,
                            rationale: invasiveRationale,
                            confidenceLabel: invasiveConfidence,
                            scientificName: data.scientificName,
                            isInvasive: data.isInvasive
                        )
                        if let status = iucnStatus {
                            let iconName: String? = {
                                switch status.isGood {
                                case true?: return "checkmark.circle.fill"
                                case false?: return "exclamationmark.shield.fill"
                                case nil: return nil
                                }
                            }()
                            let iconColor: Color? = {
                                switch status.isGood {
                                case true?: return .green
                                case false?: return .red
                                case nil: return nil
                                }
                            }()
                            let textColor: Color? = {
                                switch status.isGood {
                                case false?: return .red
                                default: return nil
                                }
                            }()
                            
                            KeyValueRow(
                                title: "CONSERVATION",
                                value: status.text,
                                valueIcon: iconName,
                                valueIconColor: iconColor,
                                valueTextColor: textColor
                            )
                        }
                        if let val = colors, !val.isEmpty {
                            KeyValueRow(title: "DOMINANT COLORS", value: val)
                        }
                        if let val = interactions {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("INTERACTIONS")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)
                                
                                Text(val)
                                    .font(.system(.body))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    if hasWiki, let extract = wikiExtract {
                        WikipediaSummarySection(text: extract)
                    }
                    
                    if hasWiki, let wikiString = data.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                        WikipediaReadMoreButton {
                            selectedWikiURL = wikiUrl
                            isSafariPresented = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}

private struct InvasiveStatusSummary: View {
    let status: String
    let assessmentDetail: String?
    let rationale: String?
    let confidenceLabel: String?
    let scientificName: String?
    let isInvasive: Bool

    @State private var isExplanationExpanded = false

    private var statusIcon: String {
        isInvasive ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        isInvasive ? .yellow : .green
    }

    private var hasExplanation: Bool {
        rationale != nil || confidenceLabel != nil
    }

    private var explanationButtonTitle: String {
        isExplanationExpanded ? "Show less" : "Learn more"
    }

    private var formattedRationale: AttributedString? {
        guard let rationale else { return nil }
        guard let scientificName = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scientificName.isEmpty else {
            return regularRationaleRun(rationale)
        }

        var remaining = rationale[...]
        var output = AttributedString()

        while let match = remaining.range(of: scientificName, options: [.caseInsensitive, .diacriticInsensitive]) {
            let hasLeadingMarker = match.lowerBound > remaining.startIndex
                && remaining[remaining.index(before: match.lowerBound)] == "*"
            let hasTrailingMarker = match.upperBound < remaining.endIndex
                && remaining[match.upperBound] == "*"
            let usesMarkdownMarkers = hasLeadingMarker && hasTrailingMarker
            let prefixEnd = usesMarkdownMarkers ? remaining.index(before: match.lowerBound) : match.lowerBound
            let nextStart = usesMarkdownMarkers ? remaining.index(after: match.upperBound) : match.upperBound

            output += regularRationaleRun(String(remaining[..<prefixEnd]))

            var scientificNameRun = AttributedString(String(remaining[match]))
            scientificNameRun.font = .system(.subheadline, design: .monospaced)
            output += scientificNameRun

            remaining = remaining[nextStart...]
        }

        output += regularRationaleRun(String(remaining))
        return output
    }

    private var formattedExplanation: AttributedString? {
        var output = formattedRationale ?? AttributedString()

        if let confidenceLabel {
            if rationale != nil {
                output += regularRationaleRun(" · ")
            }
            output += regularRationaleRun(confidenceLabel)
        }

        return output.characters.isEmpty ? nil : output
    }

    private func regularRationaleRun(_ text: String) -> AttributedString {
        var run = AttributedString(text)
        run.font = .system(.subheadline)
        return run
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text("INVASIVE STATUS")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(1)
                    .foregroundColor(.secondary)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                        Text(status)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(.subheadline))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                }
            }

            if assessmentDetail != nil || hasExplanation {
                VStack(alignment: .leading, spacing: 6) {
                    if let assessmentDetail {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(assessmentDetail)
                                .font(.system(.caption))
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)

                            if hasExplanation {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        isExplanationExpanded.toggle()
                                    }
                                } label: {
                                    Text(explanationButtonTitle)
                                        .font(.system(.caption))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isExplanationExpanded ? "Hide invasive status explanation" : "Learn more about invasive status")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if hasExplanation {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isExplanationExpanded.toggle()
                            }
                        } label: {
                            Text(explanationButtonTitle)
                                .font(.system(.caption))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isExplanationExpanded ? "Hide invasive status explanation" : "Learn more about invasive status")
                    }

                    if isExplanationExpanded {
                        VStack(alignment: .leading, spacing: 8) {
                            if let formattedExplanation {
                                Text(formattedExplanation)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
