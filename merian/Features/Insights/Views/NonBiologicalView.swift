import SwiftUI

struct NonBiologicalView: View {
    let species: SpeciesData
    let commonName: String

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 16) {
                Text(commonName)
                    .font(.system(.largeTitle, design: .serif))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(species.insightData.description)
                    .font(.system(.body, design: .serif))
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            }
            .card()
            
            ScanInformationCard(speciesData: species)
        }
        .padding(.horizontal)
    }
}
