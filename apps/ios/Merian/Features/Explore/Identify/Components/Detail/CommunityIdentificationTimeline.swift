import SwiftUI

struct CommunityIdentificationTimeline: View {
    let identificationCount: Int
    let isConsensusUpdating: Bool
    let identifications: [CommunityIdentification]
    let onWithdraw: (String) -> Void
    let onRestore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Identifications")
                    .font(.headline)
                Spacer()
                Text(identificationCountLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if isConsensusUpdating {
                Label("Consensus updating", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if identifications.isEmpty {
                Text("No one has suggested an ID yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(identifications) { identification in
                        CommunityIdentificationRow(
                            identification: identification,
                            onWithdraw: onWithdraw,
                            onRestore: onRestore
                        )
                    }
                }
            }
        }
    }

    private var identificationCountLabel: String {
        identificationCount == 1 ? "1 ID" : "\(identificationCount) IDs"
    }
}

private struct CommunityIdentificationRow: View {
    let identification: CommunityIdentification
    let onWithdraw: (String) -> Void
    let onRestore: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: identification.withdrawnAt == nil
                        ? "checkmark.circle.fill"
                        : "arrow.uturn.backward.circle"
                )
                .foregroundStyle(identification.withdrawnAt == nil ? .green : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identification.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(identificationSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if identification.isViewer {
                    Button(identification.withdrawnAt == nil ? "Withdraw" : "Restore") {
                        if identification.withdrawnAt == nil {
                            onWithdraw(identification.id)
                        } else {
                            onRestore(identification.id)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            if let reasoning = identification.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(identification.withdrawnAt == nil ? 1 : 0.64)
    }

    private var identificationSubtitle: String {
        "\(identification.displayRank) by \(identification.authorName)"
    }
}
