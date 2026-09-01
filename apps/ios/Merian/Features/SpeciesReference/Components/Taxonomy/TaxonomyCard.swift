import SwiftUI

struct TaxonomyCard: View {
    let taxonomyData: TaxonomyData?
    let scientificName: String?

    var body: some View {
        if let taxonomy = taxonomyData {
            VStack(alignment: .leading, spacing: 16) {
                MerianCardHeader(
                    systemImage: "square.stack.3d.down.right",
                    title: "Taxonomy"
                )

                VStack(spacing: 12) {
                    if let kingdom = taxonomy.kingdom {
                        KeyValueRow(
                            title: "KINGDOM",
                            value: kingdom,
                            isValueItalic: true
                        )
                    }
                    if let phylum = taxonomy.phylum {
                        KeyValueRow(
                            title: "PHYLUM",
                            value: phylum,
                            isValueItalic: true
                        )
                    }
                    if let className = taxonomy.className {
                        KeyValueRow(
                            title: "CLASS",
                            value: className,
                            isValueItalic: true
                        )
                    }
                    if let order = taxonomy.order {
                        KeyValueRow(
                            title: "ORDER",
                            value: order,
                            isValueItalic: true
                        )
                    }
                    if let family = taxonomy.family {
                        KeyValueRow(
                            title: "FAMILY",
                            value: family,
                            isValueItalic: true
                        )
                    }
                    if let genus = taxonomy.genus {
                        KeyValueRow(
                            title: "GENUS",
                            value: genus,
                            isValueItalic: true
                        )
                    }
                    if let scientificName {
                        KeyValueRow(
                            title: "SPECIES",
                            value: scientificName,
                            valueFontWeight: .semibold,
                            isValueItalic: false
                        )
                    }
                }
            }
            .card()
        }
    }
}
