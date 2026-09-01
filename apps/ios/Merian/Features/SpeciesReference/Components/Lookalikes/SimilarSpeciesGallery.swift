import SwiftUI

struct SimilarSpeciesGallery: View {
    let similarData: SimilarSpecies
    let currentScientificName: String?
    let currentCommonName: String?
    var routeForSpecies: ((SimilarSpeciesEntry) -> SpeciesDictionaryRoute)?
    var onSpeciesSelected: ((SimilarSpeciesEntry) -> Void)?
    var dependencies: SimilarSpeciesGalleryDependencies = .live

    private var validEntries: [SimilarSpeciesEntry] {
        similarData.filteredEntries(
            excludingScientificName: currentScientificName,
            excludingCommonName: currentCommonName
        )
    }

    var body: some View {
        if !validEntries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                MerianCardHeader(
                    systemImage: "camera.filters",
                    title: "Similar species"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(validEntries, id: \.scientificName) { entry in
                            if let route = routeForSpecies?(entry) {
                                NavigationLink(value: route) {
                                    SimilarSpeciesCard(
                                        entry: entry,
                                        currentCommonName: currentCommonName,
                                        dependencies: dependencies
                                    )
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        dependencies.selectionFeedback()
                                    }
                                )
                            } else {
                                SimilarSpeciesCard(
                                    entry: entry,
                                    currentCommonName: currentCommonName,
                                    onSpeciesSelected: onSpeciesSelected,
                                    dependencies: dependencies
                                )
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .padding(.horizontal, 16)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SimilarSpeciesCard: View {
    let entry: SimilarSpeciesEntry
    let currentCommonName: String?
    var onSpeciesSelected: ((SimilarSpeciesEntry) -> Void)?

    @State private var imageFetcher: SimilarSpeciesImageFetcher
    @State private var remoteImageFailed = false
    private let selectionFeedback: @MainActor () -> Void

    init(
        entry: SimilarSpeciesEntry,
        currentCommonName: String?,
        onSpeciesSelected: ((SimilarSpeciesEntry) -> Void)? = nil,
        dependencies: SimilarSpeciesGalleryDependencies = .live
    ) {
        self.entry = entry
        self.currentCommonName = currentCommonName
        self.onSpeciesSelected = onSpeciesSelected
        selectionFeedback = dependencies.selectionFeedback
        _imageFetcher = State(
            initialValue: SimilarSpeciesImageFetcher(
                dependencies: dependencies.imageDependencies
            )
        )
    }

    private var displayCommonName: String? {
        entry.displayCommonName(comparedTo: currentCommonName)
    }

    @ViewBuilder
    var body: some View {
        if let onSpeciesSelected {
            cardContent
                .onTapGesture {
                    selectionFeedback()
                    onSpeciesSelected(entry)
                }
                .accessibilityAddTraits(.isButton)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .bottom) {
            imageContent
                .frame(width: 200, height: 260)
                .clipped()

            textOverlay
                .padding(10)
        }
        .frame(width: 200, height: 260)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        .task(priority: .background) {
            if entry.referenceImageUrl == nil {
                await imageFetcher.fetchImage(for: entry.scientificName)
            }
        }
        .contentShape(Rectangle())
    }

    private var imageContent: some View {
        ZStack {
            Color(UIColor.systemGray6)

            if !remoteImageFailed,
               let remoteURL = entry.referenceImageUrl {
                AsyncLocalImageView(
                    path: nil,
                    fallbackImageUrl: remoteURL,
                    onImageLoadFailed: { remoteImageFailed = true }
                )
            } else if imageFetcher.isLoading {
                ProgressView()
            } else if let image = imageFetcher.images.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var textOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let commonName = displayCommonName {
                Text(commonName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(entry.scientificName)
                .font(.caption)
                .fontWeight(
                    displayCommonName == nil ? .semibold : .regular
                )
                .italic()
                .foregroundColor(
                    displayCommonName == nil ? .primary : .secondary
                )
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0),
                            .white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
    }
}

extension SimilarSpeciesGallery {
    struct Skeleton: View {
        @State private var isPulsing = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                MerianCardHeader(
                    systemImage: "camera.filters",
                    title: "Similar species"
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonCard()
                        }
                    }
                    .padding(.bottom, 12)
                    .padding(.horizontal, 16)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, -16)
                .disabled(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: .placeholder)
            .opacity(isPulsing ? 0.4 : 1)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1).repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
    }

    struct SkeletonCard: View {
        var body: some View {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemFill)
                    .frame(width: 200, height: 260)
                    .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 100, height: 16)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: 140, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0),
                                    .white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: .black.opacity(0.15),
                    radius: 6,
                    x: 0,
                    y: 4
                )
                .padding(10)
            }
            .frame(width: 200, height: 260)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }
}
