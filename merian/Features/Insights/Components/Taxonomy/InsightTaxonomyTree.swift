import SwiftUI

struct InsightTaxonomyTree: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        if let taxonomy = inferenceEngine.speciesData?.taxonomy {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .foregroundColor(.secondary)
                    Text("Taxonomy")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }
                
                VStack(spacing: 12) {
                    if let kingdom = taxonomy.kingdom { taxonomyRow(rank: "KINGDOM", value: kingdom) }
                    if let phylum = taxonomy.phylum { taxonomyRow(rank: "PHYLUM", value: phylum) }
                    if let cls = taxonomy.className { taxonomyRow(rank: "CLASS", value: cls) }
                    if let order = taxonomy.order { taxonomyRow(rank: "ORDER", value: order) }
                    if let family = taxonomy.family { taxonomyRow(rank: "FAMILY", value: family) }
                    if let genus = taxonomy.genus { taxonomyRow(rank: "GENUS", value: genus) }
                    if let species = inferenceEngine.speciesData?.scientificName { taxonomyRow(rank: "SPECIES", value: species, isSpecies: true) }
                }
            }
            .glassCard()
        }
    }
    
    @ViewBuilder
    private func taxonomyRow(rank: String, value: String, isSpecies: Bool = false) -> some View {
        HStack {
            Text(rank)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(.subheadline))
                .italic(!isSpecies)
                .fontWeight(isSpecies ? .bold : .regular)
                .foregroundColor(.primary)
        }
    }
}
