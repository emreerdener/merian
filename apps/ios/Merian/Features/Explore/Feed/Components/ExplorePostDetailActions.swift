import SwiftUI

struct ExplorePostDetailMenuButton: View {
    let isOwnedByCurrentUser: Bool
    let allowsInsightPresentation: Bool
    let onOpenInsight: () -> Void
    let onEditPost: () -> Void
    let onUnpublish: () -> Void
    let showsFieldChatAction: Bool
    let onFieldChat: () -> Void
    let onBlockAuthor: () -> Void
    let onReportPost: () -> Void
    let audioBoostEnabled: Binding<Bool>?
    let onAudioBoostEnableRequested: () -> Void

    var body: some View {
        Menu {
            if let audioBoostEnabled {
                Button {
                    if !audioBoostEnabled.wrappedValue {
                        onAudioBoostEnableRequested()
                    }
                    audioBoostEnabled.wrappedValue.toggle()
                    if audioBoostEnabled.wrappedValue {
                        HapticManager.shared.triggerMediumPulse(
                            source: "media.explore.detail.audioBoost.enabled"
                        )
                    } else {
                        HapticManager.shared.triggerLightImpact(
                            intensity: 0.5,
                            source: "media.explore.detail.audioBoost.disabled"
                        )
                    }
                } label: {
                    Label(
                        audioBoostEnabled.wrappedValue ? "Turn off audio boost" : "Boost audio",
                        systemImage: audioBoostEnabled.wrappedValue ? "speaker.wave.2" : "speaker.wave.3"
                    )
                }
            }

            if showsFieldChatAction {
                Button(action: onFieldChat) {
                    Label("Field chat", systemImage: "sparkles")
                }

                Divider()
            }

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
                Label("View insight", systemImage: "sparkles")
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

    @ViewBuilder
    private var moderationActions: some View {
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
