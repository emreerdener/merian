import SwiftUI
import UIKit

struct PrivateScanMapCollectionCard: View {
    let snapshot: PrivateScanMapPreviewSnapshot

    @Environment(PrivateScanMapStore.self) private var privateScanMapStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    @State private var previewImage: UIImage?
    @State private var renderedRequestID: PreviewRequestID?

    private struct PreviewRequestID: Hashable {
        let sensitiveResetGeneration: UInt64
        let revision: UInt64
        let widthPixels: Int
        let heightPixels: Int
        let userInterfaceStyle: Int
    }

    var body: some View {
        ZStack {
            mapPreview

            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan map")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text(mappedScanLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Spacer(minLength: 8)

                    Label("Private", systemImage: "lock.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Capsule(style: .continuous))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(
            RoundedRectangle(
                cornerRadius: CollectionGridCardMetrics.cornerRadius,
                style: .continuous
            )
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: CollectionGridCardMetrics.cornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan map, \(mappedScanLabel), Private")
        .accessibilityHint("Shows all of your mapped scans")
        .accessibilityIdentifier("PrivateScanMapCollectionCard")
        .onChange(of: privateScanMapStore.sensitiveResetGeneration) {
            previewImage = nil
            renderedRequestID = nil
        }
    }

    private var mappedScanLabel: String {
        let noun = snapshot.points.count == 1 ? "mapped scan" : "mapped scans"
        return "\(snapshot.points.count.formatted()) \(noun)"
    }

    private var mapPreview: some View {
        GeometryReader { geometry in
            let requestID = previewRequestID(size: geometry.size)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(uiColor: .tertiarySystemGroupedBackground),
                        Color(uiColor: .secondarySystemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "map")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: requestID) {
                await loadPreview(
                    requestID: requestID,
                    size: geometry.size
                )
            }
        }
    }

    private func previewRequestID(size: CGSize) -> PreviewRequestID {
        PreviewRequestID(
            sensitiveResetGeneration:
                privateScanMapStore.sensitiveResetGeneration,
            revision: privateScanMapStore.snapshot.spatialRevision,
            widthPixels: Int((size.width * displayScale).rounded()),
            heightPixels: Int((size.height * displayScale).rounded()),
            userInterfaceStyle: userInterfaceStyle.rawValue
        )
    }

    @MainActor
    private func loadPreview(
        requestID: PreviewRequestID,
        size: CGSize
    ) async {
        guard size.width > 0, size.height > 0 else { return }
        if renderedRequestID != requestID {
            previewImage = nil
        }
        let image = await privateScanMapStore.previewImage(
            size: size,
            displayScale: displayScale,
            userInterfaceStyle: userInterfaceStyle
        )
        guard !Task.isCancelled else { return }
        previewImage = image
        renderedRequestID = requestID
    }

    private var userInterfaceStyle: UIUserInterfaceStyle {
        colorScheme == .dark ? .dark : .light
    }
}
