import SwiftUI

struct ShareButton: View {
    private enum PendingAction {
        case externalShare
        case shareToExplore(includeFieldNotes: Bool)
        case viewInExplore
    }

    let shareExternally: () -> Void
    let onShareToExplore: ((Bool) -> Void)?
    let isSharingToExplore: Bool
    var fieldNotesPreview: String?
    var sharedExplorePostId: String?
    var onViewInExplore: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingOptions = false
    @State private var pendingAction: PendingAction?
    @State private var includeFieldNotesInExplore = false

    private var showsExploreAction: Bool {
        onShareToExplore != nil || onViewInExplore != nil
    }

    private var hasFieldNotesToShare: Bool {
        fieldNotesPreview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var fieldNotesExcerpt: String? {
        guard let preview = fieldNotesPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty else {
            return nil
        }

        if preview.count <= 160 {
            return preview
        }

        return String(preview.prefix(157)) + "..."
    }

    private var exploreHeadline: String {
        sharedExplorePostId != nil ? "Published" : "Share with community"
    }

    // BUTTONS TEXT
    private var exploreActionTitle: String {
        sharedExplorePostId != nil ? "View post" : "Share discovery"
    }

    private var exploreDescription: String {
        if sharedExplorePostId != nil {
            return "This discovery is visible to the community."
        }
        return "Publish this discovery so others can learn and explore."
    }

    private var primaryBlue: Color {
        Color.accentColor
    }

    private var exploreActionFillColor: Color {
        sharedExplorePostId == nil ? (colorScheme == .dark ? .white : .black) : primaryBlue
    }

    private var exploreActionForegroundColor: Color {
        sharedExplorePostId == nil ? Color(uiColor: .systemBackground) : .white
    }

    // MARK: - Body
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
        .tint(primaryBlue)
        .onChange(of: showingOptions) { _, isPresented in
            if isPresented {
                includeFieldNotesInExplore = false
            }
        }
        .sheet(isPresented: $showingOptions, onDismiss: handlePendingAction) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // EXPLORE FEATURE PANEL
                    exploreFeaturePanel

                    // SHARE TO EXTERNAL APPS
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            pendingAction = .externalShare
                            showingOptions = false
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("More ways to share")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    Text("Send via Messages, social media, or copy the link.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 12)

                               Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
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
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

// MARK: - Explore Feature Panel
    private var exploreFeaturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 58, height: 58)

                    Image("compass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(exploreHeadline)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if sharedExplorePostId != nil {
                            Text("LIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(colorScheme == .dark ? .white : .black)
                                )
                        }
                    }

                    Text(exploreDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if sharedExplorePostId == nil, hasFieldNotesToShare {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $includeFieldNotesInExplore) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Include field notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Keep them private unless you choose to publish them with this Explore post.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)

                    if includeFieldNotesInExplore, let fieldNotesExcerpt {
                        Text(fieldNotesExcerpt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                }
            }

            Button {
                pendingAction = sharedExplorePostId != nil
                    ? .viewInExplore
                    : .shareToExplore(includeFieldNotes: includeFieldNotesInExplore)
                showingOptions = false
            } label: {
                HStack(alignment: .center) {
                    Label(
                        isSharingToExplore && sharedExplorePostId == nil
                            ? "Sharing..."
                            : exploreActionTitle,
                        systemImage: sharedExplorePostId != nil ? "eye" : "safari"
                    )
                    .font(.headline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    Capsule(style: .continuous)
                        .fill(exploreActionFillColor)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(exploreActionForegroundColor)
            .disabled(isSharingToExplore && sharedExplorePostId == nil)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
                
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.primary.opacity(0.02))
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func handlePendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        switch pendingAction {
        case .externalShare:
            shareExternally()
        case .shareToExplore(let includeFieldNotes):
            onShareToExplore?(includeFieldNotes)
        case .viewInExplore:
            onViewInExplore?()
        }
    }
}
