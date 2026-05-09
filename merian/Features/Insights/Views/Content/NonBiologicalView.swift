import SwiftUI

struct NonBiologicalView: View {
    @Bindable var viewModel: InsightSheetViewModel
    let species: SpeciesData
    let commonName: String
    var timestamp: Date?

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .center, spacing: 8) {           
                Text(commonName)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                if !species.insightData.aiReasoning.isEmpty {
                    VStack(spacing: 12) {
                         Text(species.insightData.aiReasoning)
                                .font(.system(.body))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                    }
                    .padding(.top, 8) // Separates the text distinctively from the bold title
                }
             }
            .frame(maxWidth: .infinity)
            .card()

            FieldNotesCard(
                previewText: viewModel.fieldNotesText,
                promptContext: viewModel.fieldNotesPromptContext,
                isPublished: viewModel.state.exploreFieldNotesArePublic,
                action: {
                    viewModel.state.isFieldNotesSheetPresented = true
                }
            )
            
            ScanInformationCard(speciesData: species, timestamp: timestamp)
            
            if let scanId = species.scanId {
                UserTagsCard(scanId: scanId)
            }
        }
        .padding(.horizontal)
    }
}
