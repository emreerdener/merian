import MapKit
import SwiftUI

struct PrivateScanMapCollectionCard: View {
    let snapshot: PrivateScanMapSnapshot

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
    }

    private var mappedScanLabel: String {
        let noun = snapshot.points.count == 1 ? "mapped scan" : "mapped scans"
        return "\(snapshot.points.count.formatted()) \(noun)"
    }

    @ViewBuilder
    private var mapPreview: some View {
        if let region = snapshot.fullExtentRegion {
            GeometryReader { geometry in
                Map(
                    initialPosition: .region(region),
                    interactionModes: []
                ) {
                    ForEach(PrivateScanMapClusterer.annotations(
                        points: snapshot.points,
                        region: region,
                        viewportSize: geometry.size,
                        cellSize: PrivateScanMapClusterer.previewCellSize
                    )) { annotation in
                        switch annotation {
                        case .point(let point):
                            Annotation("", coordinate: point.coordinate) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 10, height: 10)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    }
                                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                            }
                            .annotationTitles(.hidden)
                        case .cluster(let cluster):
                            Annotation("", coordinate: cluster.coordinate) {
                                Text(cluster.count.formatted())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 24, minHeight: 24)
                                    .padding(2)
                                    .background(Color.accentColor)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    }
                                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .mapStyle(.standard)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(snapshot.identity)
            }
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
        }
    }
}
