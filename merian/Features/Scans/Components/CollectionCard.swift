import SwiftData
import SwiftUI

struct CollectionCard: View {
    let collection: ScanCollection
    
    var body: some View {
        ZStack {
            if let firstScan = collection.scans?.first {
                GeometryReader { geo in
                    ScanThumbnail(imagePath: firstScan.coverImagePath, fallbackImageUrl: firstScan.referenceImageUrl)
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                }
                .aspectRatio(1.0, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1.0, contentMode: .fill)
                    .overlay(
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                            // Natively shifts the icon mathematically up exactly half the height
                            // of the bottom text panel, centering it perfectly within the visible area.
                            .offset(y: -24)
                    )
            }
            
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(collection.scans?.count ?? 0) Scans")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
        }
        .cornerRadius(12)
        .clipped()
    }
}
