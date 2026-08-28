import SwiftUI

struct PrivateScanMapScanListSheet: View {
    let points: [PrivateScanMapPoint]
    let isOnline: Bool
    let onSelectPoint: (String) -> Void
    let onReferenceImageNeeded: @MainActor (String) -> Void
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Group {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No scans in view",
                        systemImage: "map",
                        description: Text(
                            "Pan the map or choose Show scans to find your saved locations."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(points) { point in
                                Button {
                                    onSelectPoint(point.id)
                                } label: {
                                    PrivateScanMapSheetRow(
                                        point: point,
                                        isOnline: isOnline,
                                        onReferenceImageNeeded: {
                                            onReferenceImageNeeded(point.id)
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "PrivateScanMapSheetRow-\(point.id)"
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Your scans")
                            .font(.headline)
                        Text("Private")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("PrivateScanMapSheetHeader")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}

private struct PrivateScanMapSheetRow: View {
    let point: PrivateScanMapPoint
    let isOnline: Bool
    let onReferenceImageNeeded: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnail(
                isOnline: isOnline,
                imagePath: point.thumbnail.imagePath,
                fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                audioPath: point.thumbnail.audioPath,
                hasVideo: point.thumbnail.hasVideo,
                hasAudio: point.thumbnail.hasAudio,
                prefersReferenceForAudio: true,
                maxDimension: 180,
                placeholderStyle: point.thumbnail.placeholderStyle,
                onReferenceImageNeeded: onReferenceImageNeeded
            )
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(point.privateMapDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(point.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(point.privateMapMetadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
