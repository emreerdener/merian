import SwiftUI

struct PrivateScanMapScanListSheet: View {
    let points: [PrivateScanMapPoint]
    let isOnline: Bool
    let onSelectPoint: (String) -> Void
    let onReferenceImageNeeded: @MainActor (String) -> Void

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
                        LazyVStack(spacing: 16) {
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
                    .transparentTopToolbar()
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
        VStack(alignment: .leading, spacing: 14) {
            ScanThumbnail(
                isOnline: isOnline,
                imagePath: point.thumbnail.imagePath,
                fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                audioPath: point.thumbnail.audioPath,
                hasVideo: point.thumbnail.hasVideo,
                hasAudio: point.thumbnail.hasAudio,
                prefersReferenceForAudio: true,
                maxDimension: 1200,
                aspectRatio: 4.0 / 3.0,
                placeholderStyle: point.thumbnail.placeholderStyle,
                onReferenceImageNeeded: onReferenceImageNeeded
            )
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(point.privateMapDisplayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(point.scientificName)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(point.privateMapMetadata)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("View scan")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Capsule(style: .continuous).fill(Color.accentColor))
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your private scan")
    }
}
