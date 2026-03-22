import SwiftUI

// MARK: - Core Discovery Grid Component
struct ScansGrid<MenuContent: View>: View {
    // MARK: - State Properties
    let scans: [LocalScanRecord]
    
    // MARK: - Component Callbacks
    let onSelect: (LocalScanRecord) -> Void
    var onDelete: ((LocalScanRecord) -> Void)? = nil
    var isSelected: ((LocalScanRecord) -> Bool)? = nil
    
    // MARK: - Generic View Builders
    @ViewBuilder var customMenuItems: ((LocalScanRecord) -> MenuContent)
    
    // MARK: - User Preferences
    var isSelectionMode: Bool = false
    @AppStorage("gridColumns") private var gridColumns: Int = 3
    
    // MARK: - Layout Engines
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns)
    }
    
    // MARK: - Visual Layout
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(scans) { scan in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(scan)
                }) {
                    ScanThumbnail(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl)
                        .overlay(
                            ZStack {
                                if isSelectionMode {
                                    if isSelected?(scan) == true {
                                        Color.blue.opacity(0.6)
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 24))
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.white.opacity(0.8))
                                            .font(.system(size: 24))
                                    }
                                } else if isSelected?(scan) == true {
                                    Color.blue.opacity(0.6)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 24))
                                }
                            }
                        )
                        .contextMenu {
                            customMenuItems(scan)
                            if let onDelete = onDelete {
                                Button(role: .destructive) {
                                    onDelete(scan)
                                } label: {
                                    Label("Delete scan permanently", systemImage: "trash")
                                }
                            }
                        }
                }
                .buttonStyle(.plain) // Prevent underlying iOS UI button highlight hijacking natively
            }
        }
    }
}

// MARK: - Empty Context Menu Extensions

extension ScansGrid where MenuContent == EmptyView {
    init(scans: [LocalScanRecord], onSelect: @escaping (LocalScanRecord) -> Void, onDelete: ((LocalScanRecord) -> Void)? = nil, isSelectionMode: Bool = false, isSelected: ((LocalScanRecord) -> Bool)? = nil) {
        self.scans = scans
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.customMenuItems = { _ in EmptyView() }
    }
}
