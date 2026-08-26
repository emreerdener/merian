import SwiftUI

struct ExploreMapPreviewCard: View {
    let post: ExplorePost
    let speciesDisplayName: String
    let mediaReloadGeneration: UInt64
    let onOpen: () -> Void
    let onComments: () -> Void
    let onLike: () -> Void
    let onShare: () -> Void
    let onUnshare: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var showUnpublishConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            actions
            openButton
        }
        .card()
        .alert("Unpublish Post?", isPresented: $showUnpublishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Unpublish", role: .destructive, action: onUnshare)
        } message: {
            Text("This will remove the post from Explore. Your original scan will remain safely in your library.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onOpen()
                } label: {
                    ExploreHeroImageView(
                        imageUrl: post.gridThumbnailUrl,
                        reloadGeneration: mediaReloadGeneration
                    )
                    .frame(width: 82, height: 82)
                    .overlay(alignment: .bottomTrailing) {
                        if post.hasVideoMedia || post.hasAudioMedia {
                            ExploreMediaTypeIndicator(kind: post.hasVideoMedia ? .video : .audio)
                                .padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(speciesDisplayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(post.speciesScientificName)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let subtitle = post.publicDisplayLocationLabel {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 8)

            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            if post.isOwnedByViewer {
                Button(role: .destructive) {
                    showUnpublishConfirmation = true
                } label: {
                    Label("Unpublish post", systemImage: "minus.circle")
                }
                .tint(.red)
            } else {
                Button(role: .destructive, action: onBlock) {
                    Label("Block user", systemImage: "person.crop.circle.badge.xmark")
                }
                .tint(.red)

                Button(role: .destructive, action: onReport) {
                    Label("Report post", systemImage: "flag")
                }
                .tint(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .tint(.primary)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionPill(
                title: post.likeCount.formatted(.number.notation(.compactName)),
                systemImage: post.viewerHasLiked ? "heart.fill" : "heart",
                isHighlighted: post.viewerHasLiked,
                action: onLike
            )

            actionPill(
                title: post.commentCount.formatted(.number.notation(.compactName)),
                systemImage: "bubble.right",
                isHighlighted: false,
                action: onComments
            )

            Spacer(minLength: 0)

            actionPill(
                title: "Share",
                systemImage: "square.and.arrow.up",
                isHighlighted: false,
                action: onShare
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var openButton: some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            onOpen()
        } label: {
            Text(post.hasAudioMedia && !post.hasVideoMedia ? "Listen to discovery" : "View discovery")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                )
        }
        .buttonStyle(.plain)
    }

    private func actionPill(
        title: String,
        systemImage: String,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Color.red : Color.primary)

                Text(title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemFill))
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
