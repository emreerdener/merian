import SwiftUI

struct NonBiologicalView: View {
    @Bindable var viewModel: InsightSheetViewModel
    let species: SpeciesData
    let commonName: String
    var timestamp: Date?

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .center, spacing: 12) {
                if !species.isInferenceErrorPlaceholder {
                    nonBiologicalPill
                }

                Text(displayTitle)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if !species.insightData.aiReasoning.isEmpty {
                    Text(species.insightData.aiReasoning)
                        .font(.system(.body))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 8)
                }

                if !species.isInferenceErrorPlaceholder {
                    nonBiologicalRetentionBanner
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .card()

            ScanInformationCard(speciesData: species, timestamp: timestamp)
        }
        .padding(.horizontal)
    }

    private var displayTitle: String {
        let trimmed = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if species.isInferenceErrorPlaceholder {
            return trimmed.isEmpty ? "Analysis unavailable" : trimmed
        }
        return trimmed.capitalized
    }

    private var nonBiologicalPill: some View {
        Label("Non-biological", systemImage: "cube")
            .font(.system(.caption, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .accessibilityLabel("Non-biological scan")
    }

    private var nonBiologicalRetentionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text("You can find this scan in the Non-biological collection. Merian automatically deletes non-biological scans after \(MerianConfig.nonBiologicalRetentionDays) days.")
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.yellow.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
