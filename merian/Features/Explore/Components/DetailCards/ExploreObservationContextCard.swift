import SwiftUI

struct ExploreObservationContextCard: View {
    let post: ExplorePost

    private var rows: [ExploreObservationContextRow] {
        var rows: [ExploreObservationContextRow] = []

        if let location = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
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
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.secondary)
                    Text("Observation")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        KeyValueRow(
                            title: row.title,
                            value: row.value,
                            valueIcon: row.valueIcon
                        )
                    }
                }
            }
            .card()
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
    let fieldNotesArePublic: Bool
    let canToggleVisibility: Bool
    let isUpdating: Bool
    let onToggleVisibility: () -> Void

    private var visibilityActionIconName: String {
        fieldNotesArePublic ? "eye.slash" : "eye"
    }

    private var visibilityActionAccessibilityLabel: String {
        fieldNotesArePublic ? "Hide field notes" : "Show field notes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.secondary)
                Text("Field notes")
                    .font(.system(.headline))
                    .foregroundColor(.primary)

                Spacer()

                if canToggleVisibility {
                    Button(action: onToggleVisibility) {
                        if isUpdating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: visibilityActionIconName)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .disabled(isUpdating)
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(visibilityActionAccessibilityLabel)
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
