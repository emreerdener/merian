import SwiftUI

struct InsightTaxonomyTree: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        if let taxonomy = inferenceEngine.speciesData?.taxonomy {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taxonomy")
                    .font(.headline)
                    .padding(.horizontal)
                    
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if let kingdom = taxonomy.kingdom { TaxonomyNode(level: "Kingdom", name: kingdom) }
                        if let phylum = taxonomy.phylum { TaxonomyNode(level: "Phylum", name: phylum) }
                        if let cls = taxonomy.className { TaxonomyNode(level: "Class", name: cls) }
                        if let order = taxonomy.order { TaxonomyNode(level: "Order", name: order) }
                        if let family = taxonomy.family { TaxonomyNode(level: "Family", name: family) }
                        if let genus = taxonomy.genus { TaxonomyNode(level: "Genus", name: genus) }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
    }
}
