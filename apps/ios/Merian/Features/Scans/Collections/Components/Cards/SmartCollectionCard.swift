import SwiftUI

struct SmartCollectionCard: View {
    let snapshot: SmartCollectionSnapshot

    var body: some View {
        CollectionCardChrome(
            title: snapshot.title,
            count: snapshot.count,
            coverScan: snapshot.coverScan,
            emptyIconName: snapshot.iconName
        )
    }
}
