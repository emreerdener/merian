import SwiftUI

struct CollectionCard: View {
    let collection: ScanCollection
    let summary: CollectionSummaryItem

    var body: some View {
        CollectionCardChrome(
            title: collection.name,
            count: summary.count,
            coverScan: summary.coverScan,
            emptyIconName: "photo.on.rectangle"
        )
    }
}
