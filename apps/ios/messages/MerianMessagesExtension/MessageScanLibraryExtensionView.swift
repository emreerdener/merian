import SwiftUI
import UIKit

struct MessageScanLibraryExtensionView: View {
    let onInsertImage: (MessageScanShareCacheRecord, URL) -> Void
    let onInsertCard: (MessageScanShareCacheRecord, URL?) -> Void
    let onInsertDescription: (MessageScanShareCacheRecord, Bool) -> Void
    let onOpenMerian: (URL) -> Void
    let onRequestExpandedPresentation: () -> Void

    @State private var rootURL = MessageScanShareCacheStore.appGroupRootURL()
    @State private var snapshot = MessageScanShareCacheSnapshot.empty
    @State private var searchText = ""
    @State private var selectedRecord: MessageScanShareCacheRecord?

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshSnapshot()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search scans")
        .onAppear {
            onRequestExpandedPresentation()
            refreshSnapshot()
        }
        .sheet(item: $selectedRecord) { record in
            MessageScanActionSheet(
                record: record,
                thumbnailURL: thumbnailURL(for: record),
                attachmentURL: attachmentURL(for: record),
                onInsertImage: { attachmentURL in
                    onInsertImage(record, attachmentURL)
                    selectedRecord = nil
                },
                onInsertCard: {
                    onInsertCard(record, thumbnailURL(for: record))
                    selectedRecord = nil
                },
                onInsertDescription: { includeFieldNotes in
                    onInsertDescription(record, includeFieldNotes)
                    selectedRecord = nil
                },
                onOpenMerian: {
                    if let url = record.scanDeepLinkURL ?? MerianDeepLinkRoute.scansLibrary.url {
                        onOpenMerian(url)
                    }
                    selectedRecord = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var scanList: some View {
        List(filteredRecords) { record in
            Button {
                selectedRecord = record
            } label: {
                HStack(spacing: 12) {
                    MessageScanThumbnailView(url: thumbnailURL(for: record))
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.commonName)
                            .font(.headline)
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

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
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

    private func refreshSnapshot() {
        rootURL = MessageScanShareCacheStore.appGroupRootURL()
        snapshot = MessageScanShareCacheStore.loadSnapshot(rootURL: rootURL) ?? .empty
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

private struct MessageScanThumbnailView: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))

            if let url,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "leaf")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MessageScanActionSheet: View {
    let record: MessageScanShareCacheRecord
    let thumbnailURL: URL?
    let attachmentURL: URL?
    let onInsertImage: (URL) -> Void
    let onInsertCard: () -> Void
    let onInsertDescription: (Bool) -> Void
    let onOpenMerian: () -> Void

    @State private var includeFieldNotes = false

    private var hasFieldNotes: Bool {
        record.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    MessageScanThumbnailView(url: thumbnailURL)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.commonName)
                            .font(.headline)
                            .lineLimit(2)

                        Text(record.scientificName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                VStack(spacing: 10) {
                    Button {
                        if let attachmentURL {
                            onInsertImage(attachmentURL)
                        }
                    } label: {
                        Label("Image", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(attachmentURL == nil)

                    Button {
                        onInsertCard()
                    } label: {
                        Label("Merian Card", systemImage: "rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onInsertDescription(includeFieldNotes)
                    } label: {
                        Label("Description", systemImage: "text.quote")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onOpenMerian()
                    } label: {
                        Label("Open in Merian", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if hasFieldNotes {
                    Toggle(isOn: $includeFieldNotes) {
                        Label("Include field notes", systemImage: "note.text")
                    }
                    .toggleStyle(.switch)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Attach Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
