import SwiftUI

struct ExploreMapWaypoint: View {
    let imageUrl: String
    let reloadGeneration: UInt64
    let isSelected: Bool
    let isApproximate: Bool
    let hasVideo: Bool
    let showsThumbnail: Bool
    let zoomLevel: Double
    let isNew: Bool

    var body: some View {
        Group {
            if showsThumbnail {
                thumbnailWaypoint
            } else {
                dotWaypoint
            }
        }
        .scaleEffect(isSelected ? 1.08 : 1)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .zIndex(isSelected ? 1 : 0)
    }

    private var dotWaypoint: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: isSelected ? 22 : 18, height: isSelected ? 22 : 18)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.accentColor, lineWidth: 3)
                )

            if isApproximate {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .foregroundStyle(
                        isSelected
                            ? Color.white.opacity(0.85)
                            : Color.accentColor.opacity(0.65)
                    )
                    .frame(width: isSelected ? 32 : 28, height: isSelected ? 32 : 28)
            }
        }
    }

    private var thumbnailWaypoint: some View {
        let baseZoom = ExploreMapCameraPolicy.thumbnailZoomLevel
        let maxZoom = ExploreMapCameraPolicy.maximumZoomLevel
        let zoomProgress = max(0, min((zoomLevel - baseZoom) / (maxZoom - baseZoom), 1.0))
        let sizeMultiplier = 1.0 + (zoomProgress * 0.75)
        let baseImageSize: CGFloat = isSelected ? 50 : 44
        let imageSize = baseImageSize * CGFloat(sizeMultiplier)
        let haloSize = imageSize + (isApproximate ? 12 : 8)

        return ZStack {
            Circle()
                .fill(.regularMaterial)
                .frame(width: haloSize, height: haloSize)

            ExploreHeroImageView(
                imageUrl: imageUrl,
                reloadGeneration: reloadGeneration,
                maxDimension: 160
            )
            .frame(width: imageSize, height: imageSize)
            .clipShape(Circle())
            .overlay {
                if hasVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .overlay {
                Circle()
                    .stroke(
                        isSelected ? Color.accentColor : Color.white,
                        lineWidth: isSelected ? 3 : 2.5
                    )
            }

            Circle()
                .stroke(
                    isApproximate
                        ? Color.accentColor.opacity(isSelected ? 0.95 : 0.7)
                        : Color.black.opacity(0.08),
                    style: StrokeStyle(
                        lineWidth: isApproximate ? 1.5 : 1,
                        dash: isApproximate ? [3, 2] : []
                    )
                )
                .frame(width: haloSize, height: haloSize)

            if isNew {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: haloSize / 2 * 0.707, y: -haloSize / 2 * 0.707)
            }
        }
    }
}
