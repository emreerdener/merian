import SwiftUI

struct ScanGridMatrix<Content: View>: View {
    let scans: [LocalScanRecord]
    let onSelect: (LocalScanRecord) -> Void
    @ViewBuilder let thumbnailModifier: (LocalScanRecord, ScansThumbnailView) -> Content
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(scans) { scan in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(scan)
                }) {
                    thumbnailModifier(scan, ScansThumbnailView(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl))
                }
                .buttonStyle(.plain) // Prevent underlying iOS UI button highlight hijacking natively
            }
        }
    }
}
