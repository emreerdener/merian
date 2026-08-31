import SwiftUI

struct FlayedCandidateThumbnail: View {
    let candidate: IdentificationCandidate
    @State private var imageFetcher: SimilarSpeciesImageFetcher

    init(
        candidate: IdentificationCandidate,
        imageDependencies: SimilarSpeciesImageDependencies
    ) {
        self.candidate = candidate
        self._imageFetcher = State(
            initialValue: SimilarSpeciesImageFetcher(
                dependencies: imageDependencies
            )
        )
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            
            if let img = imageFetcher.images.first {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if imageFetcher.isLoading {
                ProgressView()
                    .tint(.secondary)
            } else {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 32))
            }
        }
        .frame(width: 164, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .task { _ = await imageFetcher.fetchImage(for: candidate.scientificName) }
    }
}
