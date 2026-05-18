import SwiftUI
import UIKit

struct MessageScanLibraryExtensionView: View {
    let onInsertScan: (MessageScanShareCacheRecord, URL?, @escaping (Result<Void, Error>) -> Void) -> Void
    let onOpenMerian: (URL) -> Void
    let onClose: () -> Void
    let onRequestExpandedPresentation: () -> Void

    @State private var rootURL = MessageScanShareCacheStore.appGroupRootURL()
    @State private var snapshot = MessageScanShareCacheSnapshot.empty
    @State private var searchText = ""
    @State private var insertingRecordID: String?
    @State private var insertionErrorMessage: String?
    @State private var refreshToastMessage: String?

    private var filteredRecords: [MessageScanShareCacheRecord] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            return snapshot.records
        }

        return snapshot.records.filter { record in
            record.commonName.localizedCaseInsensitiveContains(trimmedSearch)
                || record.scientificName.localizedCaseInsensitiveContains(trimmedSearch)
                || (record.locationName?.localizedCaseInsensitiveContains(trimmedSearch) == true)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.records.isEmpty {
                    emptyState
                } else {
                    scanList
                }
            }
            .navigationTitle("Merian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshSnapshot(showFeedback: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search scans")
        .overlay(alignment: .top) {
            if let refreshToastMessage {
                MessageScanLibraryToast(message: refreshToastMessage) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.refreshToastMessage = nil
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: refreshToastMessage) {
            guard let message = refreshToastMessage else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if refreshToastMessage == message {
                withAnimation(.easeInOut(duration: 0.2)) {
                    refreshToastMessage = nil
                }
            }
        }
        .onAppear {
            onRequestExpandedPresentation()
            refreshSnapshot(showFeedback: false)
        }
    }

    private var scanList: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                if let insertionErrorMessage {
                    Text(insertionErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }

                ForEach(filteredRecords) { record in
                    Button {
                        insert(record)
                    } label: {
                        HStack(spacing: 16) {
                            MessageScanThumbnailView(url: thumbnailURL(for: record), size: 96)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.commonName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(record.scientificName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .lineLimit(1)

                                if let caption = optionalCaption(for: record) {
                                    Text(caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            if insertingRecordID == record.id {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(insertingRecordID != nil)
                }
            }
            .padding(.vertical, 28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("No cached scans")
                    .font(.headline)

                Text("Open Merian once to prepare your recent scan library for Messages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let url = MerianDeepLinkRoute.scansLibrary.url {
                Button {
                    onOpenMerian(url)
                } label: {
                    Label("Open Merian", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshSnapshot(showFeedback: Bool) {
        rootURL = MessageScanShareCacheStore.appGroupRootURL()
        snapshot = MessageScanShareCacheStore.loadSnapshot(rootURL: rootURL) ?? .empty
        if showFeedback {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                refreshToastMessage = "Library refreshed"
            }
        }
    }

    private func insert(_ record: MessageScanShareCacheRecord) {
        guard insertingRecordID == nil else {
            return
        }

        insertingRecordID = record.id
        insertionErrorMessage = nil
        onInsertScan(record, attachmentURL(for: record) ?? thumbnailURL(for: record)) { result in
            DispatchQueue.main.async {
                insertingRecordID = nil
                if case .failure = result {
                    insertionErrorMessage = "Could not add this scan to Messages."
                }
            }
        }
    }

    private func thumbnailURL(for record: MessageScanShareCacheRecord) -> URL? {
        guard let rootURL,
              let url = MessageScanShareCacheStore.thumbnailURL(for: record, rootURL: rootURL),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func attachmentURL(for record: MessageScanShareCacheRecord) -> URL? {
        guard let rootURL,
              let url = MessageScanShareCacheStore.attachmentURL(for: record, rootURL: rootURL),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func optionalCaption(for record: MessageScanShareCacheRecord) -> String? {
        let caption = MessageScanShareTextBuilder.cardCaption(for: record)
        return caption.isEmpty ? nil : caption
    }
}

private struct MessageScanLibraryToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 4)
    }
}

private struct MessageScanThumbnailView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if let url,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
