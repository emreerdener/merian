import SwiftUI

// MARK: - Queued Scan Management Sheet

private struct QueuedScanManagementSheet: View {
    let queuedScan: OfflineQueuedScan
    let isOnline: Bool
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var thumbnail: UIImage?

    private var statusIcon: String {
        guard isOnline else { return "wifi.slash" }
        switch queuedScan.queueState {
        case .pending:   return "arrow.up.circle"
        case .uploading: return "arrow.up.circle.fill"
        case .staged:    return "cpu"
        case .inferencing: return "sparkles"
        case .failed:    return "exclamationmark.circle"
        }
    }

    private var statusText: String {
        guard isOnline else { return "Waiting for network connection" }
        switch queuedScan.queueState {
        case .pending:     return "Queued for upload"
        case .uploading:   return "Uploading image..."
        case .staged:      return "Preparing analysis..."
        case .inferencing: return "AI identifying subject..."
        case .failed:      return "Upload failed"
        }
    }

    private var isActivelyProcessing: Bool {
        isOnline && (queuedScan.queueState == .uploading || queuedScan.queueState == .inferencing)
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: queuedScan.timestamp, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Thumbnail Header
            ZStack(alignment: .bottom) {
                Group {
                    if let img = thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(height: 200)
                .clipped()

                // Bottom gradient so status badge is always legible
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // Status badge
                HStack(spacing: 6) {
                    if isActivelyProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // MARK: Metadata
            VStack(spacing: 4) {
                Text("Pending analysis")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 14) {
                    Label(relativeTimestamp, systemImage: "clock")
                    if let location = queuedScan.locationName {
                        Label(location, systemImage: "location")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            Spacer(minLength: 24)

            // MARK: Actions
            VStack(spacing: 10) {
                Button(role: .destructive, action: onDelete) {
                    Text("Cancel analysis & delete")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: onClose) {
                    Text("Close")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
        .task {
            guard let fileName = queuedScan.localImagePaths.first else { return }
            let url = URL.documentsDirectory.appendingPathComponent(fileName)
            guard let cgImage = ImageDownsampler.shared.downsample(url: url, maxSize: 400) else { return }
            thumbnail = UIImage(cgImage: cgImage)
        }
    }
}

// MARK: - Library View

struct LibraryView: View {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - App State Context
    let filterCategories: [String]
    let isSearchFocused: Bool
    var queuedScans: [OfflineQueuedScan] = []

    // MARK: - Component Callbacks
    var isSelectionMode: Bool = false
    var isSelected: ((LocalScanRecord) -> Bool)?
    let onSelect: (LocalScanRecord) -> Void
    let onDelete: (LocalScanRecord) -> Void

    // MARK: - Component State
    @State private var toastMessage: String?
    @State private var scanToManage: OfflineQueuedScan?

    // MARK: - Visual Layout
    var body: some View {
        VStack(spacing: 8) {
            // 1. Dynamic Header Constraints
            if searchManager.searchQuery.isEmpty && !isSearchFocused {
                CategoryFilterBar(
                    filterCategories: filterCategories,
                    activeCategory: Binding(
                        get: { searchManager.activeCategoryFilter },
                        set: { searchManager.activeCategoryFilter = $0 }
                    ),
                    onCategorySelected: { category in
                        if !searchManager.searchQuery.isEmpty {
                            searchManager.searchQuery = ""
                        } else {
                            searchManager.performSearch(query: "", category: category)
                        }
                    }
                )
            } else {
                HStack {
                    Text(searchManager.searchQuery.isEmpty ? "Search library" : "Search results")
                        .font(.title3)
                        .fontWeight(.bold)

                    Spacer()

                    Text("\(searchManager.filteredScans.count) found")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            // 2. Main Discovery Scroll Container
            let hasContent = !searchManager.filteredScans.isEmpty || !queuedScans.isEmpty
            ZStack(alignment: .bottom) {
                ScrollView {
                    if hasContent {
                        ScansGrid(
                            scans: searchManager.filteredScans,
                            queuedScans: queuedScans,
                            onSelect: onSelect,
                            onDelete: onDelete,
                            isSelectionMode: isSelectionMode,
                            isSelected: isSelected,
                            onQueuedScanTapped: { queuedScan in
                                scanToManage = queuedScan
                            },
                            onQueuedScanDelete: { queuedScan in
                                Task {
                                    await offlineQueueManager.deleteQueuedScan(scanId: queuedScan.id)
                                    await MainActor.run {
                                        withAnimation { toastMessage = "Scan cancelled & deleted" }
                                    }
                                }
                            }
                        )
                    } else if searchManager.isFiltering {
                        Color.clear
                            .frame(maxWidth: .infinity, idealHeight: 400)
                    } else {
                        EmptyStateView(
                            iconName: "viewfinder",
                            title: "No scans found",
                            message: {
                                if !searchManager.searchQuery.isEmpty {
                                    return "No results for \"\(searchManager.searchQuery)\" in \(searchManager.activeCategoryFilter)"
                                } else if searchManager.activeCategoryFilter != "All" {
                                    return "You haven't documented any \(searchManager.activeCategoryFilter.lowercased()) yet"
                                } else {
                                    return "Start exploring and capture your first scan!"
                                }
                            }()
                        ) {
                            if searchManager.searchQuery.isEmpty {
                                Button {
                                    dismiss()
                                } label: {
                                    Text("Start scanning")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                        }
                    }
                }

                if let message = toastMessage {
                    ToastBanner(onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toastMessage = nil
                        }
                    }) {
                        Text(message)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .sheet(item: $scanToManage) { queuedScan in
                QueuedScanManagementSheet(
                    queuedScan: queuedScan,
                    isOnline: offlineQueueManager.isOnline,
                    onDelete: {
                        Task {
                            await offlineQueueManager.deleteQueuedScan(scanId: queuedScan.id)
                            await MainActor.run {
                                withAnimation { toastMessage = "Scan cancelled & deleted" }
                            }
                        }
                        scanToManage = nil
                    },
                    onClose: { scanToManage = nil }
                )
            }
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
            .onChange(of: offlineQueueManager.isOnline) { _, isOnline in
                if isOnline && !queuedScans.isEmpty {
                    withAnimation { toastMessage = "Back online, uploading scans..." }
                }
            }
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.library)
    }
}
