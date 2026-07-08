import SwiftUI

struct CurrentUserFieldTripProfilePreview: View {
    let onOpenPublication: (String) -> Void

    @State private var summaries: FieldTripProfileSummaries?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let summaries, !summaries.isEmpty {
                FieldTripProfilePreview(
                    summaries: summaries,
                    onOpenPublication: onOpenPublication
                )
            } else if isLoading {
                FieldTripProfilePreviewSkeleton()
            }
        }
        .task {
            await load()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            guard case .fieldTripProgressUpdated = event else { return }
            Task { await load() }
        }
    }

    private func load() async {
        guard let authorUserId = SupabaseManager.shared.currentUser?.id.uuidString else { return }
        isLoading = true
        defer { isLoading = false }

        summaries = try? await MerianNetworkClient.shared.getFieldTripProfileSummaries(
            authorUserId: authorUserId,
            limit: 6
        )
    }
}

struct FieldTripProfilePreview: View {
    let summaries: FieldTripProfileSummaries
    let onOpenPublication: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Field Trips")
                    .font(.title3.weight(.bold))

                Spacer()

                let count = summaries.active.count + summaries.published.count
                Text(count.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !summaries.active.isEmpty {
                VStack(spacing: 8) {
                    ForEach(summaries.active.prefix(3)) { trip in
                        FieldTripActiveProfileRow(trip: trip)
                    }
                }
            }

            if !summaries.published.isEmpty {
                VStack(spacing: 8) {
                    ForEach(summaries.published.prefix(3)) { trip in
                        Button {
                            onOpenPublication(trip.publicationId)
                        } label: {
                            FieldTripPublishedProfileRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct FieldTripActiveProfileRow: View {
    let trip: FieldTripProfileActiveSummary

    private var fractionComplete: Double {
        guard trip.targetCount > 0 else { return 0 }
        return min(1, max(0, Double(trip.completedCount) / Double(trip.targetCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Level \(trip.currentLevelNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(trip.completedCount)/\(trip.targetCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * fractionComplete))
                }
            }
            .frame(height: 7)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripPublishedProfileRow: View {
    let trip: FieldTripProfilePublishedSummary

    var body: some View {
        HStack(spacing: 12) {
            FieldTripProfileCover(urlString: trip.coverImageUrl)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(trip.itemCount) species")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(trip.likeCount.formatted(), systemImage: "heart")
                    Label(trip.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FieldTripProfileCover: View {
    let urlString: String?

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "map")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldTripProfilePreviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 130, height: 20)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 82)
        }
        .redacted(reason: .placeholder)
    }
}
