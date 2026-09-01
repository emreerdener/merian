#if DEBUG
import SwiftUI

struct SettingsDeveloperSection: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(MilestoneToastPresenter.self)
    private var milestoneToastPresenter

    @Binding var showPaywall: Bool
    @Binding var showTestExploreOnboarding: Bool

    private let dependencies = SettingsDeveloperDependencies.live

    var body: some View {
        FeatureFlagDeveloperControls()

        Section {
            Button(action: dependencies.previewAnalyzingState) {
                Label("Preview analyzing state", systemImage: "play.circle")
            }

            #if targetEnvironment(simulator)
            Button {
                appSettings.hasCompletedOnboarding = false
            } label: {
                Label(
                    "View onboarding",
                    systemImage: "arrow.counterclockwise.circle"
                )
            }

            NavigationLink {
                ComplimentaryScansDeveloperPreview()
            } label: {
                Label(
                    "Preview Pro scans",
                    systemImage: "sparkles.rectangle.stack"
                )
            }
            .accessibilityIdentifier("Settings_PreviewComplimentaryScans")
            #endif

            Button {
                showTestExploreOnboarding = true
            } label: {
                Label("Test Explore Onboarding", systemImage: "safari")
            }

            Button {
                previewAchievementToast(.domesticCat)
            } label: {
                Label("Preview achievement toast", systemImage: "trophy.fill")
            }
            .accessibilityIdentifier("Settings_PreviewAchievementToast")

            Button {
                previewAchievementToast(.domesticDog)
            } label: {
                Label("Preview dog achievement toast", systemImage: "pawprint")
            }

            Button {
                previewAchievementToast(.nocturnal)
            } label: {
                Label(
                    "Preview long achievement toast",
                    systemImage: "moon.stars.fill"
                )
            }

            Button {
                milestoneToastPresenter.previewNewToMerianMilestone()
            } label: {
                Label(
                    "Preview New to Naturebook notification",
                    systemImage: "sparkles"
                )
            }
            .accessibilityIdentifier(
                "Settings_PreviewNewToMerianNotification"
            )

            Button {
                milestoneToastPresenter.previewFieldTripProgress()
            } label: {
                Label(
                    "Preview Field trip progress toast",
                    systemImage: "map.fill"
                )
            }
            .accessibilityIdentifier("Settings_PreviewFieldTripProgressToast")

            Button {
                milestoneToastPresenter.previewMilestoneStack()
            } label: {
                Label(
                    "Preview notification stack",
                    systemImage: "square.3.layers.3d"
                )
            }
            .accessibilityIdentifier("Settings_PreviewNotificationStack")

            NavigationLink {
                FieldTripCommunityCardDeveloperPreview()
            } label: {
                Label(
                    "Preview field trip community card",
                    systemImage: "person.3.fill"
                )
            }
            .accessibilityIdentifier("Settings_PreviewFieldTripCommunityCard")

            Button {
                showPaywall = true
            } label: {
                Label("Show Paywall", systemImage: "creditcard")
            }
        } header: {
            Text("Developer")
        }
    }

    private func previewAchievementToast(_ type: AchievementType) {
        milestoneToastPresenter.previewAchievementUnlock(
            AwardPayload(
                type: type,
                currentCount: type.definition.targetCount,
                lastInteractionDate: Date()
            )
        )
    }
}

private struct FeatureFlagDeveloperControls: View {
    @State private var refreshToken = 0

    private let dependencies = SettingsDeveloperDependencies.live

    var body: some View {
        Section {
            ForEach(FeatureFlag.allCases) { flag in
                SettingsToggleRow(
                    title: flag.title,
                    description: description(for: flag),
                    isOn: binding(for: flag),
                    icon: icon(for: flag),
                    iconColor: color(for: flag)
                )
                .accessibilityIdentifier(
                    "Settings_FeatureFlag_\(flag.rawValue)"
                )
            }

            if hasOverrides {
                Button {
                    FeatureFlags.resetDebugOverrides()
                    dependencies.reevaluateDailyUsage()
                    refreshToken += 1
                } label: {
                    Label(
                        "Use code defaults",
                        systemImage: "arrow.uturn.backward.circle"
                    )
                }
                .accessibilityIdentifier("Settings_ResetFeatureFlags")
            }
        } header: {
            Text("Feature Flags")
        } footer: {
            Text("Debug-only overrides are stored on this device. Relaunch to refresh every surface. Release builds ignore them.")
        }
        .id(refreshToken)
    }

    private var hasOverrides: Bool {
        FeatureFlag.allCases.contains {
            FeatureFlags.debugOverride(for: $0) != nil
        }
    }

    private func binding(for flag: FeatureFlag) -> Binding<Bool> {
        Binding(
            get: { FeatureFlags.isEnabled(flag) },
            set: { newValue in
                FeatureFlags.setDebugOverride(newValue, for: flag)
                if flag == .unlimitedFreeScans {
                    dependencies.reevaluateDailyUsage()
                }
                refreshToken += 1
            }
        )
    }

    private func description(for flag: FeatureFlag) -> String {
        let stateDescription: String
        if let override = FeatureFlags.debugOverride(for: flag) {
            stateDescription = "Debug override: \(override ? "On" : "Off")."
        } else {
            stateDescription = "Code default: \(flag.defaultValue ? "On" : "Off")."
        }
        return "\(flag.summary) \(stateDescription)"
    }

    private func icon(for flag: FeatureFlag) -> String {
        switch flag {
        case .fieldTrips:
            "map.fill"
        case .dwcaExports:
            "shippingbox.fill"
        case .unlimitedFreeScans:
            "infinity.circle.fill"
        }
    }

    private func color(for flag: FeatureFlag) -> Color {
        switch flag {
        case .fieldTrips:
            .indigo
        case .dwcaExports:
            .teal
        case .unlimitedFreeScans:
            .blue
        }
    }
}

private struct FieldTripCommunityCardDeveloperPreview: View {
    private static let samplePublication: FieldTripRecentPublication? = {
        let json = """
        {
          "publicationId": "community-card-preview",
          "templateId": "backyard-safari-preview",
          "title": "A Morning in My Backyard",
          "description": "A few familiar visitors showed up before breakfast.",
          "publishedAt": "2026-08-02T12:00:00Z",
          "likeCount": 24,
          "commentCount": 6,
          "slug": "backyard_safari",
          "templateTitle": "Backyard Safari",
          "regionTags": ["North America"],
          "seasonTags": ["Summer"],
          "habitatTags": ["Backyard"],
          "coverImageUrl": null,
          "itemCount": 4,
          "viewerHasLiked": true,
          "authorUserId": "community-preview-author",
          "authorName": "Nature Neighbor",
          "authorUsername": "nature_neighbor",
          "authorAvatarUrl": null,
          "isPinned": false,
          "pinPosition": null,
          "rankBucket": 1,
          "communityReason": "near_you",
          "viewerIsFollowingAuthor": false
        }
        """

        return try? JSONDecoder().decode(
            FieldTripRecentPublication.self,
            from: Data(json.utf8)
        )
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Production card with representative preview data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let publication = Self.samplePublication {
                    FieldTripCommunityPublicationCard(
                        publication: publication,
                        onOpenPublication: { _ in },
                        onOpenAuthorProfile: { _ in }
                    )
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            "The sample Community card could not be created."
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Community Card")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if targetEnvironment(simulator)
private struct ComplimentaryScansDeveloperPreview: View {
    private enum Scenario: Int, CaseIterable, Identifiable {
        case three = 3
        case two = 2
        case one = 1
        case exhausted = 0

        var id: Int { rawValue }

        var pickerLabel: String {
            switch self {
            case .three, .two, .one:
                "\(rawValue)"
            case .exhausted:
                "Used"
            }
        }

        var displayState: ComplimentaryScanDisplayState {
            switch self {
            case .three, .two, .one:
                .available(scansRemaining: rawValue)
            case .exhausted:
                .exhausted
            }
        }
    }

    @Environment(RevenueCatManager.self) private var revenueCatManager
    @State private var scenario = Scenario.three
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("Pro scan state", selection: $scenario) {
                    ForEach(Scenario.allCases) { scenario in
                        Text(scenario.pickerLabel).tag(scenario)
                    }
                }
                .pickerStyle(.segmented)

                previewSection("Settings") {
                    PlanCard(
                        showPaywall: $showPaywall,
                        complimentaryDetailContext: .settings,
                        complimentaryDisplayOverride: scenario.displayState
                    )
                }

                previewSection("Results") {
                    ModelTierBadge(
                        presentation: ModelTierBadgePresentation(
                            text: scenario.rawValue == 1
                                ? "1 Pro scan remains"
                                : scenario.rawValue > 1
                                    ? "\(scenario.rawValue) Pro scans remain"
                                    : "Upgrade for advanced analysis"
                        ),
                        onUpgrade: { showPaywall = true }
                    )
                }

                Text("Preview data is local to this screen and does not change your account, server ledger, or purchase state.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Pro Scans")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(revenueCatManager)
        }
    }

    private func previewSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
#endif
