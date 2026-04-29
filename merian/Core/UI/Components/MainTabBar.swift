import SwiftUI
import UIKit

struct MainTabBar: View {
    // MARK: - Navigation Dependencies
    @Binding var isExploreOpen: Bool
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool
    @AppStorage(UserDefaultsKeys.hasUnseenScan) private var hasUnseenScan: Bool = false
    @AppStorage(UserDefaultsKeys.hasSeenExploreNewChip) private var hasSeenExploreNewChip: Bool = false
    @AppStorage(UserDefaultsKeys.hasUnseenExplorePost) private var hasUnseenExplorePost: Bool = false
    @AppStorage(UserDefaultsKeys.lastSeenExplorePostSharedAt) private var lastSeenExplorePostSharedAt: String = ""
    
    // MARK: - Visual Layout
    var body: some View {
        HStack(spacing: 48) {
            
            // 1. Map/Explore Network
            TabBarButton(
                iconName: "safari",
                title: "Explore",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    hasSeenExploreNewChip = true
                    isExploreOpen = true
                },
                showBadge: hasUnseenExplorePost,
                chipText: hasUnseenExplorePost || hasSeenExploreNewChip ? nil : "NEW"
            )

            // 2. Local Taxonomy Library
            TabBarButton(
                iconName: "rectangle.stack",
                title: "Scans",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    isScansOpen = true
                },
                showBadge: hasUnseenScan
            )

            // 3. User Identity Profile 
            TabBarButton(
                iconName: "person",
                title: "Profile",
                action: { 
                    HapticManager.shared.triggerSheetSpring()
                    isUserProfileOpen = true 
                }
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 32)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 8)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .task {
            await refreshExploreBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshExploreBadge()
            }
        }
    }

    private func refreshExploreBadge() async {
        do {
            let latestPost = try await MerianNetworkClient.shared.getExploreFeed(limit: 1).first

            guard let latestPost else {
                hasUnseenExplorePost = false
                return
            }

            guard let latestPostDate = latestPost.sharedAtDate else { return }
            guard !lastSeenExplorePostSharedAt.isEmpty else { return }

            guard let lastSeenPostDate = DateUtilities.iso8601FractionalFormatter.date(from: lastSeenExplorePostSharedAt)
                ?? DateUtilities.iso8601Formatter.date(from: lastSeenExplorePostSharedAt) else {
                return
            }

            hasUnseenExplorePost = latestPostDate > lastSeenPostDate
        } catch {
            MerianLog.network.debug(
                "Failed to refresh Explore tab badge: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}

// MARK: - Internal Component Layout Wrappers

private struct TabBarButton: View {
    // MARK: - Properties
    let iconName: String
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var showBadge: Bool = false
    var chipText: String?

    // MARK: - Visual Layout
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }

                        if let chipText {
                            Text(chipText)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green)
                                )
                                .fixedSize()
                                .offset(x: 16, y: -10)
                        }
                    }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.primary)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}
