import SwiftUI

struct SpeciesObservationSeasonalityHeatmapView: View {
    let model: SpeciesSeasonalityHeatmapModel

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            if model.seasonalityUnavailable && !model.hasObservations {
                unavailableRow
            } else {
                monthGrid
                legendRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var legendRow: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(0..<4) { index in
                let intensity = Double(index) / 3
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(intensity: intensity))
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(0..<4) { columnIndex in
                        let index = rowIndex * 4 + columnIndex
                        if index < model.cells.count {
                            monthCell(model.cells[index])
                        }
                    }
                }
            }
        }
    }

    private func monthCell(
        _ cell: SpeciesSeasonalityHeatmapCell
    ) -> some View {
        let month = SpeciesObservationChartPresentation.monthAbbreviation(
            for: cell.month
        )
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color(intensity: cell.displayIntensity))
            .overlay {
                ZStack {
                    if cell.hasObservations {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                color(intensity: 1),
                                lineWidth: 1
                            )
                            .opacity(0.28)
                    }

                    Text(month)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(
                            cell.displayIntensity >= 0.55 ? .white : .secondary
                        )
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("\(month) \(cell.count) observations")
    }

    private var unavailableRow: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                Text("Seasonality unavailable")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(intensity: Double) -> Color {
        guard intensity > 0 else {
            return Color.secondary.opacity(0.12)
        }

        return Color.green.opacity(0.18 + (0.82 * intensity))
    }
}

#if DEBUG
#Preview("Seasonality - combined") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: [
                SpeciesObservationMonthCount(month: 4, count: 1),
                SpeciesObservationMonthCount(month: 5, count: 1)
            ],
            localTotal: 2,
            publicValues: [
                SpeciesObservationMonthCount(month: 4, count: 39),
                SpeciesObservationMonthCount(month: 5, count: 50)
            ],
            publicTotal: 89
        )
    )
    .padding()
}

#Preview("Seasonality - partial data") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: [
                SpeciesObservationMonthCount(month: 5, count: 1)
            ],
            localTotal: 1,
            publicValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            publicTotal: 89
        )
    )
    .padding()
}

#Preview("Seasonality - observations") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: [
                SpeciesObservationMonthCount(month: 7, count: 12),
                SpeciesObservationMonthCount(month: 8, count: 28),
                SpeciesObservationMonthCount(month: 9, count: 16)
            ],
            publicTotal: 56
        )
    )
    .padding()
}

#Preview("Seasonality - empty") {
    SpeciesObservationSeasonalityHeatmapView(
        model: .make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: nil,
            publicTotal: nil
        )
    )
    .padding()
}
#endif
