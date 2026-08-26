import SwiftUI

struct EarnedFieldTripPatchCarousel: View {
    let patches: [EarnedFieldTripPatch]
    let onOpenFieldTrip: (String) -> Void

    @State private var selectedPatch: EarnedFieldTripPatch?
    @State private var pendingFieldTripTemplateId: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(patches) { patch in
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        selectedPatch = patch
                    } label: {
                        FieldTripPatchArtwork(imageName: patch.imageName)
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(patch.title) patch")
                    .accessibilityHint("Opens the patch gallery at this patch")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
        .fullScreenCover(
            item: $selectedPatch,
            onDismiss: resumePendingFieldTrip
        ) { patch in
            FieldTripLevelArtworkExpandedView(
                items: patches.map(\.galleryItem),
                initialItemID: patch.id,
                onOpenFieldTrip: { item in
                    guard let selectedPatch = patches.first(where: { $0.id == item.id }) else {
                        return
                    }
                    pendingFieldTripTemplateId = selectedPatch.templateId
                }
            )
        }
    }

    private func resumePendingFieldTrip() {
        guard let templateId = pendingFieldTripTemplateId else { return }
        pendingFieldTripTemplateId = nil
        onOpenFieldTrip(templateId)
    }
}

/// A square canvas that preserves the silhouette supplied by each patch asset.
/// Patch artwork is intentionally not clipped to a circle so future shapes render as designed.
struct FieldTripPatchArtwork: View {
    let imageName: String

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            }
    }
}

struct EarnedFieldTripPatchCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 32)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
