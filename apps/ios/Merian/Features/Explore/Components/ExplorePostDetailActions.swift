import SwiftUI

struct ExplorePostDetailMenuButton: View {
    let isOwnedByCurrentUser: Bool
    let allowsInsightPresentation: Bool
    let onOpenInsight: () -> Void
    let onEditPost: () -> Void
    let onUnpublish: () -> Void
    let onBlockAuthor: () -> Void
    let onReportPost: () -> Void

    var body: some View {
        Menu {
            if isOwnedByCurrentUser {
                ownedPostActions
            } else {
                moderationActions
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(.primary)
    }

    @ViewBuilder
    private var ownedPostActions: some View {
        if allowsInsightPresentation {
            Button(action: onOpenInsight) {
                Label("Open insight", systemImage: "sparkles")
            }
        }

        Button(action: onEditPost) {
            Label("Edit post", systemImage: "square.and.pencil")
        }

        Button(role: .destructive, action: onUnpublish) {
            Label("Unpublish post", systemImage: "minus.circle")
        }
        .tint(.red)
    }

    private var moderationActions: some View {
        Group {
            Button(role: .destructive, action: onBlockAuthor) {
                Label("Block user", systemImage: "person.crop.circle.badge.xmark")
            }
            .tint(.red)

            Button(role: .destructive, action: onReportPost) {
                Label("Report post", systemImage: "flag")
            }
            .tint(.red)
        }
    }
}

struct ExploreFieldNotesVisibilityOverlay: View {
    let fieldNotesArePublic: Bool
    let isUpdating: Bool
    let onCancel: () -> Void
    let onConfirm: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fieldNotesArePublic ? "Hide field notes?" : "Show field notes?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(fieldNotesArePublic
                        ? "Your post stays live, but these notes will be hidden."
                        : "These notes will be visible on your Explore post.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )

                    Button {
                        onConfirm(!fieldNotesArePublic)
                    } label: {
                        Text(fieldNotesArePublic ? "Hide" : "Show")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary)
                    )
                    .disabled(isUpdating)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(100)
    }
}
