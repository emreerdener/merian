import SwiftUI

// MARK: - Queued Scan Value Snapshot

/// A value-type snapshot of the data `ScansGrid` needs to render a queued scan tile.
///
/// Replacing the `[OfflineQueuedScan]` `@Model` reference array with this struct prevents
/// the fatal "backing data detached from context" crash: `LazyVGrid` accesses tile attributes
/// lazily, so if `context.delete()` tears down an `OfflineQueuedScan`'s backing before the
/// grid renders its row, accessing an unfaulted attribute (e.g. `localImagePaths`) crashes.
/// Because this struct copies the values at `refreshQueuedScans()` time, the SwiftData object
/// can be deleted freely without affecting anything the grid has already captured.
struct QueuedScanSnapshot: Identifiable, Equatable {
    let id: String          // raw scan UUID — used for deletion lookups and onChange tracking
    let imagePath: String?
    let capturedMediaJSON: String?
    let queueState: ScanQueueState
    let timestamp: Date
    let queueNextRetryAt: Date?
    let queueLastErrorMessage: String?
    let queueNeedsAttention: Bool
    let approximateQueuedBytes: Int64

    var capturedMediaItems: [SerializedMediaItem] {
        var items = CapturedMediaSnapshot(jsonString: capturedMediaJSON).items
        if items.isEmpty, let imagePath = imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePath.isEmpty {
            items = [.image(StoredMediaReference(legacyPath: imagePath))]
        }
        return items
    }

    /// Namespaced key for use as the `ForEach` identity within `LazyVGrid`.
    ///
    /// `LocalScanRecord.id` and `OfflineQueuedScan.id` share the same UUID
    /// (`client_scan_id` flows through to both). During the brief window where a
    /// newly inserted `LocalScanRecord` and its corresponding `QueuedScanSnapshot`
    /// coexist in the same `LazyVGrid`, SwiftUI would see duplicate `AnyHashable`
    /// keys and warn "ID is used by multiple child views". The `q_` prefix makes the
    /// queued-scan keys disjoint from the completed-scan keys.
    var gridId: String { "q_\(id)" }

    var canRetryNow: Bool {
        queueState == .failed || queueNextRetryAt != nil || queueNeedsAttention
    }
}

// MARK: - Core Discovery Grid Component
struct ScansGrid<MenuContent: View>: View {
    // MARK: - State Properties
    let scans: [LocalScanRecord]
    var queuedScans: [QueuedScanSnapshot] = []

    // MARK: - Component Callbacks
    let onSelect: (LocalScanRecord) -> Void
    var onDelete: ((LocalScanRecord) -> Void)?
    var isSelected: ((LocalScanRecord) -> Bool)?
    var onAddScans: (() -> Void)?
    var onQueuedScanTapped: ((QueuedScanSnapshot) -> Void)?
    var onQueuedScanDelete: ((QueuedScanSnapshot) -> Void)?

    // MARK: - Generic View Builders
    @ViewBuilder var customMenuItems: ((LocalScanRecord) -> MenuContent)

    // MARK: - User Preferences
    var isSelectionMode: Bool = false

    // MARK: - App State Context
    @Environment(AppSettings.self) private var appSettings
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    
    // MARK: - Visual Layout
    var body: some View {
        let gridColumns = appSettings.gridColumns
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns)
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = (screenWidth - CGFloat(2 * (gridColumns - 1))) / CGFloat(gridColumns)
        let thumbnailSize = Int(cellWidth * UIScreen.main.scale)
        let completedScanIds = Set(scans.map(\.id))
        let visibleQueuedScans = queuedScans.filter { !completedScanIds.contains($0.id) }

        LazyVGrid(columns: columns, spacing: 2) {
            // Offline-queued scans render first — they have no completed AI analysis yet and
            // are excluded from selection mode. Tapping them opens the queued insight sheet,
            // or the completed scan if the upload finished between render and tap.
            ForEach(visibleQueuedScans, id: \.gridId) { queued in
                Button(action: {
                    HapticManager.shared.triggerMediumPulse()
                    onQueuedScanTapped?(queued)
                }) {
                    ScanThumbnail(
                        imagePath: queued.imagePath,
                        fallbackImageUrl: nil,
                        maxDimension: thumbnailSize
                    )
                    .overlay(
                        ZStack {
                            Color.black.opacity(offlineQueueManager.isOnline ? 0.6 : 0.45)
                            if queued.queueNeedsAttention || queued.queueState == .failed {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            } else if queued.queueNextRetryAt != nil {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            } else if offlineQueueManager.isOnline {
                                ProgressView()
                                    .controlSize(.regular)
                                    .tint(.white)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("QueuedScanTile_\(queued.id)")
                .contextMenu {
                    if queued.canRetryNow {
                        Button {
                            _ = offlineQueueManager.retryQueuedScanNow(scanId: queued.id)
                        } label: {
                            Label("Retry now", systemImage: "arrow.clockwise")
                        }
                    }
                    Button(role: .destructive) {
                        onQueuedScanDelete?(queued)
                    } label: {
                        Label("Cancel upload & delete", systemImage: "trash")
                    }
                }
            }

            ForEach(scans) { scan in
                Button(action: {
                    HapticManager.shared.triggerSheetSpring()
                    onSelect(scan)
                }) {
                    ScanThumbnail(record: scan, maxDimension: thumbnailSize)
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
                .accessibilityIdentifier("ScanTile_\(scan.id)")
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
        queuedScans: [QueuedScanSnapshot] = [],
        onSelect: @escaping (LocalScanRecord) -> Void,
        onDelete: ((LocalScanRecord) -> Void)? = nil,
        isSelectionMode: Bool = false,
        isSelected: ((LocalScanRecord) -> Bool)? = nil,
        onAddScans: (() -> Void)? = nil,
        onQueuedScanTapped: ((QueuedScanSnapshot) -> Void)? = nil,
        onQueuedScanDelete: ((QueuedScanSnapshot) -> Void)? = nil
    ) {
        self.scans = scans
        self.queuedScans = queuedScans
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onAddScans = onAddScans
        self.onQueuedScanTapped = onQueuedScanTapped
        self.onQueuedScanDelete = onQueuedScanDelete
        self.customMenuItems = { _ in EmptyView() }
    }
}
