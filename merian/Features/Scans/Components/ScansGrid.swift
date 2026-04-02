import SwiftUI

// MARK: - Core Discovery Grid Component
struct ScansGrid<MenuContent: View>: View {
    // MARK: - State Properties
    let scans: [LocalScanRecord]
    var queuedScans: [OfflineQueuedScan] = []

    // MARK: - Component Callbacks
    let onSelect: (LocalScanRecord) -> Void
    var onDelete: ((LocalScanRecord) -> Void)?
    var isSelected: ((LocalScanRecord) -> Bool)?
    var onAddScans: (() -> Void)?
    var onQueuedScanTapped: (() -> Void)?

    // MARK: - Generic View Builders
    @ViewBuilder var customMenuItems: ((LocalScanRecord) -> MenuContent)

    // MARK: - User Preferences
    var isSelectionMode: Bool = false
    @AppStorage("gridColumns") private var gridColumns: Int = 3
    
    // MARK: - Layout Engines
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns)
    }

    private var thumbnailSize: Int {
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = (screenWidth - CGFloat(2 * (gridColumns - 1))) / CGFloat(gridColumns)
        return Int(cellWidth * UIScreen.main.scale)
    }
    
    // MARK: - Visual Layout
    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            // Offline-queued scans render first — they have no AI analysis yet and
            // are excluded from selection mode. Tapping them shows a toast via the
            // onQueuedScanTapped callback rather than opening InsightSheet.
            ForEach(queuedScans) { queued in
                Button(action: {
                    HapticManager.shared.triggerMediumPulse()
                    onQueuedScanTapped?()
                }) {
                    ScanThumbnail(
                        imagePath: queued.localImagePaths.first,
                        fallbackImageUrl: nil,
                        maxDimension: thumbnailSize
                    )
                    .overlay(
                        ZStack {
                            Color.black.opacity(0.45)
                            Image(systemName: "cloud.arrow.up.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(scans) { scan in
                Button(action: {
                    HapticManager.shared.triggerSheetSpring()
                    onSelect(scan)
                }) {
                    ScanThumbnail(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl, maxDimension: thumbnailSize)
                        .overlay(
                            ZStack {
                                if !scan.hasBeenViewed {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 12, height: 12)
                                        .overlay(
                                            Circle().strokeBorder(Color.white, lineWidth: 1.5)
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .padding(6)
                                }
                                
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
            
            if let onAddScans = onAddScans {
                Button(action: {
                    HapticManager.shared.triggerSheetSpring()
                    onAddScans()
                }) {
                    ZStack {
                        Color(uiColor: .secondarySystemFill)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .aspectRatio(1.0, contentMode: .fill)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Empty Context Menu Extensions

extension ScansGrid where MenuContent == EmptyView {
    init(
        scans: [LocalScanRecord],
        queuedScans: [OfflineQueuedScan] = [],
        onSelect: @escaping (LocalScanRecord) -> Void,
        onDelete: ((LocalScanRecord) -> Void)? = nil,
        isSelectionMode: Bool = false,
        isSelected: ((LocalScanRecord) -> Bool)? = nil,
        onAddScans: (() -> Void)? = nil,
        onQueuedScanTapped: (() -> Void)? = nil
    ) {
        self.scans = scans
        self.queuedScans = queuedScans
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onAddScans = onAddScans
        self.onQueuedScanTapped = onQueuedScanTapped
        self.customMenuItems = { _ in EmptyView() }
    }
}
