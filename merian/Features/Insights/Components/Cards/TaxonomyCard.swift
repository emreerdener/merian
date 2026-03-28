import SwiftUI

struct TaxonomyCard: View {
    let taxonomyData: TaxonomyData?
    let scientificName: String?
    
    var body: some View {
        if let taxonomy = taxonomyData {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.down.right")
                        .foregroundColor(.secondary)
                    Text("Taxonomy")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }
                
                VStack(spacing: 12) {
                    if let kingdom = taxonomy.kingdom { KeyValueRow(title: "KINGDOM", value: kingdom, isValueItalic: true) }
                    if let phylum = taxonomy.phylum { KeyValueRow(title: "PHYLUM", value: phylum, isValueItalic: true) }
                    if let cls = taxonomy.className { KeyValueRow(title: "CLASS", value: cls, isValueItalic: true) }
                    if let order = taxonomy.order { KeyValueRow(title: "ORDER", value: order, isValueItalic: true) }
                    if let family = taxonomy.family { KeyValueRow(title: "FAMILY", value: family, isValueItalic: true) }
                    if let genus = taxonomy.genus { KeyValueRow(title: "GENUS", value: genus, isValueItalic: true) }
                    if let species = scientificName { KeyValueRow(title: "SPECIES", value: species, valueFontWeight: .semibold, isValueItalic: false) }
                }
            }
            .card()
        }
    }
}
