import SwiftUI

struct ShareButton: View {
    private enum PendingAction {
        case externalShare
        case shareToExplore
        case viewInExplore
    }

    let shareExternally: () -> Void
    let onShareToExplore: (() -> Void)?
    let isSharingToExplore: Bool
    var sharedExplorePostId: String?
    var onViewInExplore: (() -> Void)?
    
    @State private var showingOptions = false
    @State private var pendingAction: PendingAction?

    private var showsExploreAction: Bool {
        onShareToExplore != nil || onViewInExplore != nil
    }

    private var exploreActionTitle: String {
        sharedExplorePostId != nil ? "View post" : "Share discovery"
    }

    private var exploreHeadline: String {
        sharedExplorePostId != nil ? "Shared to community" : "Share discovery"
    }

    private var exploreDescription: String {
        if sharedExplorePostId != nil {
            return "Your discovery is now visible to the community."
        }
        return "Publish this discovery so others can learn and explore."
    }
    
    var body: some View {
        Button(action: {
            if showsExploreAction {
                showingOptions = true
            } else {
                shareExternally()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .sheet(isPresented: $showingOptions, onDismiss: handlePendingAction) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Share")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 8)

                    exploreFeaturePanel

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Share outside Merian")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Button {
                            pendingAction = .externalShare
                            showingOptions = false
                        } label: {
                            HStack(spacing: 14) {
                                

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Messages, Mail, AirDrop, and more")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    Text("Open the native iOS share sheet")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 12)

                               Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var exploreFeaturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 58, height: 58)

                    Image("compass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exploreHeadline)
                            .font(.headline)
                            .foregroundStyle(.white)

                        if sharedExplorePostId != nil {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.96))
                                )
                        }
                    }

                    Text(exploreDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                pendingAction = sharedExplorePostId != nil ? .viewInExplore : .shareToExplore
                showingOptions = false
            } label: {
                HStack {
                    Label(
                        isSharingToExplore && sharedExplorePostId == nil
                            ? "Sharing to Explore..."
                            : exploreActionTitle,
                        systemImage: sharedExplorePostId != nil ? "arrow.up.right.square" : "safari"
                    )
                    .font(.headline)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.18))
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .disabled(isSharingToExplore && sharedExplorePostId == nil)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.55, blue: 0.46),
                            Color(red: 0.10, green: 0.33, blue: 0.49)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func handlePendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .externalShare:
            shareExternally()
        case .shareToExplore:
            onShareToExplore?()
        case .viewInExplore:
            onViewInExplore?()
        }
    }
}
