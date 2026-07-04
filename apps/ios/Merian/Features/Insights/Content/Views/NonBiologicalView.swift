import SwiftUI

struct NonBiologicalView: View {
    @Bindable var viewModel: InsightSheetViewModel
    let species: SpeciesData
    let commonName: String
    var timestamp: Date?

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .center, spacing: 12) {
                nonBiologicalPill

                Text(commonName)
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

                nonBiologicalRetentionBanner
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .card()

            if viewModel.shouldShowFieldNotesCard {
                FieldNotesCard(
                    previewText: viewModel.fieldNotesText,
                    promptContext: viewModel.fieldNotesPromptContext,
                    isPublished: viewModel.state.exploreFieldNotesArePublic,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.dismissFieldNotesCard()
                        }
                    },
                    action: {
                        viewModel.state.isFieldNotesSheetPresented = true
                    }
                )
            }
            
            ScanInformationCard(speciesData: species, timestamp: timestamp)
            
            if let scanId = species.scanId {
                UserTagsCard(scanId: scanId)
            }
        }
        .padding(.horizontal)
    }

    private var nonBiologicalPill: some View {
        Label("Non-biological", systemImage: "circle.slash")
            .font(.system(.caption, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.red.opacity(0.24), lineWidth: 1)
            )
            .accessibilityLabel("Non-biological scan")
    }

    private var nonBiologicalRetentionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)
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
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
