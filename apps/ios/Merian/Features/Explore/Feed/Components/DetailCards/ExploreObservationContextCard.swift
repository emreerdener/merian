import MapKit
import SwiftUI

struct ExploreObservationMapPresentation: Equatable {
    static let approximateCoordinateRadiusMeters: CLLocationDistance = 10_000

    let mapPoint: ExplorePostDetailMapPoint
    let spanDelta: CLLocationDegrees
    let approximateRadiusMeters: CLLocationDistance?

    init?(post: ExplorePost, detail: ExplorePostDetail?) {
        guard post.locationSharing == .open,
              let detail,
              detail.postId == post.postId,
              let mapPoint = detail.visibleMapPoint else {
            return nil
        }

        self.mapPoint = mapPoint
        switch mapPoint.coordinateVisibility {
        case .exact:
            spanDelta = 0.05
            approximateRadiusMeters = nil
        case .obscured:
            spanDelta = 0.2
            approximateRadiusMeters = Self.approximateCoordinateRadiusMeters
        }
    }
}

struct ExploreObservationContextCard: View {
    let post: ExplorePost
    let detail: ExplorePostDetail?
    let onOpenExploreMap: ((ExploreMapFocusTarget) -> Void)?

    private var mapPresentation: ExploreObservationMapPresentation? {
        ExploreObservationMapPresentation(post: post, detail: detail)
    }

    private var focusTarget: ExploreMapFocusTarget? {
        guard mapPresentation != nil, let detail else { return nil }
        return ExploreMapFocusTarget(post: post, detail: detail)
    }

    private var rows: [ExploreObservationContextRow] {
        var rows: [ExploreObservationContextRow] = []

        if let location = post.publicDisplayLocationLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "LOCATION",
                    value: location,
                    valueIcon: nil
                )
            )
        }

        if let observationContext = post.observationContextLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "OBSERVED",
                    value: observationContext,
                    valueIcon: nil
                )
            )
        }

        if let weatherLabel = post.publicWeatherLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "WEATHER",
                    value: weatherLabel,
                    valueIcon: weatherIcon(for: post.weatherCondition)
                )
            )
        }

        if let sharedDateLabel = post.sharedDateLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "SHARED",
                    value: sharedDateLabel,
                    valueIcon: nil
                )
            )
        }

        return rows
    }

    var body: some View {
        if !rows.isEmpty || mapPresentation != nil {
            if let focusTarget, let onOpenExploreMap {
                Button {
                    onOpenExploreMap(focusTarget)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ExploreObservationMapCard")
                .accessibilityHint("Opens Explore Map centered on this observation")
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            MerianCardHeader(systemImage: "viewfinder", title: "Observation")

            VStack(spacing: 12) {
                ForEach(rows) { row in
                    KeyValueRow(
                        title: row.title,
                        value: row.value,
                        valueIcon: row.valueIcon
                    )
                }

                mapPreview
            }
        }
        .card()
    }

    @ViewBuilder
    private var mapPreview: some View {
        if let mapPresentation,
           let coordinate = mapPresentation.mapPoint.coordinate {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: mapPresentation.spanDelta,
                    longitudeDelta: mapPresentation.spanDelta
                )
            )

            Map(initialPosition: .region(region)) {
                if let approximateRadiusMeters = mapPresentation.approximateRadiusMeters {
                    MapCircle(
                        center: coordinate,
                        radius: approximateRadiusMeters
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.3))
                    .stroke(Color.accentColor, lineWidth: 1)
                } else {
                    Marker("Observation", coordinate: coordinate)
                        .tint(Color.accentColor)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .padding(.top, 4)
        }
    }

    private func weatherIcon(for condition: String?) -> String? {
        guard let condition else { return nil }

        let lower = condition.lowercased()
        if lower.contains("sun") || lower.contains("clear") { return "sun.max.fill" }
        if lower.contains("fog") || lower.contains("haze") { return "cloud.fog.fill" }
        if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") { return "cloud.rain.fill" }
        if lower.contains("snow") || lower.contains("ice") { return "snowflake" }
        if lower.contains("thunder") || lower.contains("storm") { return "cloud.bolt.rain.fill" }
        if lower.contains("wind") || lower.contains("breeze") { return "wind" }
        if lower.contains("cloud") || lower.contains("overcast") { return "cloud.fill" }
        return "cloud.sun.fill"
    }
}

struct ExploreObservationContextRow: Identifiable {
    let title: String
    let value: String
    let valueIcon: String?

    var id: String {
        "\(title)-\(value)-\(valueIcon ?? "none")"
    }
}

struct ExploreFieldNotesCard: View {
    let fieldNotes: String
    let visibility: FieldNotesVisibilityBadge.Visibility?
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.secondary)
                    Text("Field notes")
                        .font(.system(.headline))
                        .foregroundColor(.primary)

                    if let visibility {
                        FieldNotesVisibilityBadge(visibility: visibility)
                    }
                }

                Spacer(minLength: 8)

                if canEdit {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Edit field notes")
                }
            }

            Text(fieldNotes)
                .font(.system(.body))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
