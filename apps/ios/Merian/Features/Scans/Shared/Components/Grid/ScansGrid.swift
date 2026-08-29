import SwiftUI

@MainActor
struct ScansGrid<MenuContent: View>: View {
    let scans: [LocalScanRecord]
    var queuedScans: [QueuedScanSnapshot]

    let onSelect: (LocalScanRecord) -> Void
    var onDelete: ((LocalScanRecord) -> Void)?
    var isSelected: ((LocalScanRecord) -> Bool)?
    var onAddScans: (() -> Void)?
    var onQueuedScanTapped: ((QueuedScanSnapshot) -> Void)?
    var onQueuedScanRetry: ((QueuedScanSnapshot) -> Void)?
    var onQueuedScanDelete: ((QueuedScanSnapshot) -> Void)?

    @ViewBuilder var customMenuItems: (LocalScanRecord) -> MenuContent

    var isSelectionMode: Bool

    @Environment(AppSettings.self) private var appSettings
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    private let interactions: ScansGridInteractions

    init(
        scans: [LocalScanRecord],
        queuedScans: [QueuedScanSnapshot] = [],
        onSelect: @escaping (LocalScanRecord) -> Void,
        onDelete: ((LocalScanRecord) -> Void)? = nil,
        isSelected: ((LocalScanRecord) -> Bool)? = nil,
        onAddScans: (() -> Void)? = nil,
        onQueuedScanTapped: ((QueuedScanSnapshot) -> Void)? = nil,
        onQueuedScanRetry: ((QueuedScanSnapshot) -> Void)? = nil,
        onQueuedScanDelete: ((QueuedScanSnapshot) -> Void)? = nil,
        @ViewBuilder customMenuItems: @escaping (
            LocalScanRecord
        ) -> MenuContent,
        isSelectionMode: Bool = false,
        interactions: ScansGridInteractions? = nil
    ) {
        self.scans = scans
        self.queuedScans = queuedScans
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.isSelected = isSelected
        self.onAddScans = onAddScans
        self.onQueuedScanTapped = onQueuedScanTapped
        self.onQueuedScanRetry = onQueuedScanRetry
        self.onQueuedScanDelete = onQueuedScanDelete
        self.customMenuItems = customMenuItems
        self.isSelectionMode = isSelectionMode
        self.interactions = interactions ?? ScansGridInteractions()
    }

    var body: some View {
        let gridColumns = appSettings.gridColumns
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 2),
            count: gridColumns
        )
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = (
            screenWidth - CGFloat(2 * (gridColumns - 1))
        ) / CGFloat(gridColumns)
        let thumbnailSize = Int(cellWidth * UIScreen.main.scale)
        let completedScanIDs = Set(scans.map(\.id))
        let visibleQueuedScans = queuedScans.filter {
            !completedScanIDs.contains($0.id)
        }

        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(visibleQueuedScans, id: \.gridId) { queued in
                queuedScanTile(
                    queued,
                    thumbnailSize: thumbnailSize
                )
            }

            ForEach(scans) { scan in
                completedScanTile(
                    scan,
                    thumbnailSize: thumbnailSize
                )
            }

            if onAddScans != nil {
                addScansTile
            }
        }
    }

    private func queuedScanTile(
        _ queued: QueuedScanSnapshot,
        thumbnailSize: Int
    ) -> some View {
        Button {
            interactions.selectQueuedScan(
                queued,
                onSelect: onQueuedScanTapped
            )
        } label: {
            ScanThumbnail(
                isOnline: offlineQueueManager.isOnline,
                imagePath: queued.imagePath,
                fallbackImageUrl: nil,
                maxDimension: thumbnailSize
            )
            .overlay {
                queuedScanStatusOverlay(queued)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("QueuedScanTile_\(queued.id)")
        .contextMenu {
            if queued.canRetryNow,
               let onQueuedScanRetry {
                Button {
                    onQueuedScanRetry(queued)
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

    @ViewBuilder
    private func queuedScanStatusOverlay(
        _ queued: QueuedScanSnapshot
    ) -> some View {
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
                Image(
                    systemName:
                    "antenna.radiowaves.left.and.right.slash"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            }
        }
    }

    private func completedScanTile(
        _ scan: LocalScanRecord,
        thumbnailSize: Int
    ) -> some View {
        Button {
            interactions.selectCompletedScan(
                scan,
                onSelect: onSelect
            )
        } label: {
            ScanThumbnail(
                record: scan,
                isOnline: offlineQueueManager.isOnline,
                maxDimension: thumbnailSize,
                prefersReferenceForAudio: true,
                showsAudioBadge: true
            )
            .overlay {
                completedScanStatusOverlay(scan)
            }
            .contextMenu {
                customMenuItems(scan)
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete(scan)
                    } label: {
                        Label(
                            "Delete scan permanently",
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ScanTile_\(scan.id)")
    }

    @ViewBuilder
    private func completedScanStatusOverlay(
        _ scan: LocalScanRecord
    ) -> some View {
        ZStack {
            if !scan.hasBeenViewed {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle().strokeBorder(
                            Color.white,
                            lineWidth: 1.5
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
                    .padding(6)
            }

            if isSelectionMode {
                if isSelected?(scan) == true {
                    selectedScanOverlay
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 24))
                }
            } else if isSelected?(scan) == true {
                selectedScanOverlay
            }
        }
    }

    private var selectedScanOverlay: some View {
        ZStack {
            Color.blue.opacity(0.6)
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 24))
        }
    }

    private var addScansTile: some View {
        Button {
            interactions.selectAddScans(onSelect: onAddScans)
        } label: {
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
        onQueuedScanRetry: ((QueuedScanSnapshot) -> Void)? = nil,
        onQueuedScanDelete: ((QueuedScanSnapshot) -> Void)? = nil,
        interactions: ScansGridInteractions? = nil
    ) {
        self.init(
            scans: scans,
            queuedScans: queuedScans,
            onSelect: onSelect,
            onDelete: onDelete,
            isSelected: isSelected,
            onAddScans: onAddScans,
            onQueuedScanTapped: onQueuedScanTapped,
            onQueuedScanRetry: onQueuedScanRetry,
            onQueuedScanDelete: onQueuedScanDelete,
            customMenuItems: { _ in EmptyView() },
            isSelectionMode: isSelectionMode,
            interactions: interactions
        )
    }
}
