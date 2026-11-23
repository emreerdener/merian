import SwiftUI

/// Rendering only. Every menu callback is resolved against this version by the
/// existing History owner before it can select, review, share or reanalyze.
struct IdentificationHistoryCard<Controls: View>: View {
    let row: IdentificationHistoryRow
    let isCurrent: Bool
    let actionsEnabled: Bool
    let action: (IdentificationHistoryViewModel.CardAction) -> Void
    var thumbnail: UIImage?
    var onViewReanalysisProgress: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if isCurrent { CurrentIdentificationBadge() }
                        if row.review == "Marked incorrect" {
                            ConfidenceStatusBadge(label: "Incorrect", style: .incorrect)
                        } else if let confidence = row.confidence {
                            ConfidenceStatusBadge(label: confidence, style: row.confidenceStyle)
                        }
                    }
                    HStack(spacing: 12) {
                        Group {
                            if let thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFill()
                            } else {
                                Image(systemName: "doc.text.image").font(.title2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            if let date = row.completedAt {
                                Text(date, format: .dateTime.month().day().year().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.title).font(.headline)
                            if let scientific = row.scientificName, scientific != row.title {
                                Text(scientific).font(.caption).italic().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                IdentificationHistoryCardMenu(row: row, isCurrent: isCurrent,
                    actionsEnabled: actionsEnabled, action: action,
                    onViewReanalysisProgress: onViewReanalysisProgress,
                    onViewCommunityRequest: onViewCommunityRequest)
            }
            if isCurrent {
                controls()
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("HistoryRow_\(row.id.uuidString.lowercased())")
        .accessibilityLabel([row.title, row.scientificName, isCurrent ? "Current" : nil, row.review].compactMap { $0 }.joined(separator: ", "))
    }

}
