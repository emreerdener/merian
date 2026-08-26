import Foundation
@testable import Merian
import Testing
import UIKit

@MainActor
struct ActiveCaptureGoalStoreTests {
    @Test func fieldTripsUsesOutingsAndEventsFeatureLabels() {
        #expect(FieldTripsSection.fieldTrips.title == "Outings")
        #expect(FieldTripsSection.seasonal.title == "Events")
        #expect(FieldTripsSection.allCases == [.fieldTrips, .seasonal])
    }

    @Test func fieldTripProviderFlattensServerOrderIntoGenericGoals() async throws {
        let outings = [
            makeOuting(id: "recent", targetIds: ["butterfly", "bird"]),
            makeOuting(id: "older", targetIds: ["cat"])
        ]
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { outings },
            fetchTemplate: { _ in throw CaptureGoalContextQueue.TestError.expected }
        )

        let context = try await provider.fetchCaptureGoalContext()
        let goals = context.goals

        #expect(context.introduction == nil)
        #expect(goals.map(\.id) == [
            "field_trip:butterfly",
            "field_trip:bird",
            "field_trip:cat"
        ])
        #expect(goals[0].source.kind == .fieldTrip)
        #expect(goals[0].source.title == "Field trip recent")
        #expect(goals[0].destination == .fieldTrip(
            templateId: "template-recent",
            checklistItemId: "butterfly"
        ))
        #expect(goals[0].artwork == .bundledImage(name: "fieldtrip-backyard-butterfly"))
    }

    @Test func fieldTripProviderBuildsBackyardIntroductionFromAnUnstartedTemplate() async throws {
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { slug in
                #expect(slug == "backyard_safari")
                return makeTemplate()
            }
        )

        let context = try await provider.fetchCaptureGoalContext()
        let introduction = try #require(context.introduction)

        #expect(context.goals.isEmpty)
        #expect(introduction.headline == "Start an outing")
        #expect(introduction.subheadline == "Backyard Safari · 2 goals")
        #expect(introduction.progress == CaptureGoalProgress(completedCount: 0, targetCount: 2))
        #expect(introduction.artworks == [
            .bundledImage(name: "fieldtrip-backyard-cardinal"),
            .bundledImage(name: "fieldtrip-backyard-dog")
        ])
        #expect(introduction.destination == .fieldTripTemplate(slug: "backyard_safari"))
        #expect(introduction.accessibilityLabel == "Start an outing. Backyard Safari, 2 goals.")
        #expect(introduction.accessibilityValue == "0 of 2 goals complete.")
        #expect(introduction.accessibilityHint == "Opens outing details.")
    }

    @Test func fieldTripProviderSuppressesIntroductionForUnavailableStartedStoppedOrEmptyTemplates() async throws {
        let unavailableProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(viewerHasAccess: false) }
        )
        let startedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(activeProgress: makeProgress()) }
        )
        let completedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(activeProgress: makeProgress(isComplete: true)) }
        )
        let stoppedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in
                makeTemplate(stoppedProgress: makeProgress(stoppedAt: "2026-07-19T10:00:00Z"))
            }
        )
        let emptyProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(prompts: []) }
        )

        #expect(try await unavailableProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await startedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await completedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await stoppedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await emptyProvider.fetchCaptureGoalContext().introduction == nil)
    }

    @Test func fieldTripProviderRequiresACompleteSuccessfulIntroductionLookup() async {
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in throw CaptureGoalContextQueue.TestError.expected }
        )

        await #expect(throws: CaptureGoalContextQueue.TestError.self) {
            try await provider.fetchCaptureGoalContext()
        }
    }

    @Test func preservesProviderOrderAndWrapsInBothDirections() async throws {
        let defaults = makeDefaults()
        let goals = [makeGoal(id: "a"), makeGoal(id: "b"), makeGoal(id: "c")]
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: goals, introduction: nil)
        }

        await store.refresh(accountId: "ACCOUNT-A", force: true)

        #expect(store.goals.map(\.id) == ["a", "b", "c"])
        #expect(store.selectedGoal?.id == "a")
        store.selectPrevious()
        #expect(store.selectedGoal?.id == "c")
        store.selectNext()
        #expect(store.selectedGoal?.id == "a")
    }

    @Test func overlappingStartupRefreshesShareOneProviderFetch() async {
        let defaults = makeDefaults()
        let fetcher = SuspendedCaptureGoalContextFetcher(
            snapshot: CaptureGoalContextSnapshot(
                goals: [makeGoal(id: "a")],
                introduction: nil
            )
        )
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            await fetcher.fetch()
        }

        let firstRefresh = Task {
            await store.refreshIfStale(accountId: "account")
        }
        while !store.isLoading {
            await Task.yield()
        }
        while await fetcher.callCount == 0 {
            await Task.yield()
        }

        await store.refreshIfStale(accountId: "account")
        await fetcher.resume()
        await firstRefresh.value
        await Task.yield()

        #expect(await fetcher.callCount == 1)
        #expect(store.selectedGoal?.id == "a")
    }

    @Test func completionAdvancesToTheNextTargetAtTheSameFlattenedPosition() async throws {
        let defaults = makeDefaults()
        let queue = CaptureGoalContextQueue([
            [makeGoal(id: "a"), makeGoal(id: "b"), makeGoal(id: "c")],
            [makeGoal(id: "a", completedCount: 1), makeGoal(id: "c", completedCount: 1)]
        ])
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            try await queue.next()
        }

        await store.refresh(accountId: "account", force: true)
        store.selectNext()
        #expect(store.selectedGoal?.id == "b")

        await store.refresh(accountId: "account", force: true)
        #expect(store.selectedGoal?.id == "c")
    }

    @Test func cacheIsAccountIsolatedAndSurvivesRefreshFailure() async throws {
        let defaults = makeDefaults()
        let cachedGoals = [makeGoal(id: "a"), makeGoal(id: "b")]
        let writer = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: cachedGoals, introduction: nil)
        }
        await writer.refresh(accountId: "account-a", force: true)
        writer.selectNext()

        let reader = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }
        reader.activate(accountId: "account-a")
        #expect(reader.selectedGoal?.id == "b")

        await reader.refresh(accountId: "account-a", force: true)
        #expect(reader.selectedGoal?.id == "b")
        #expect(reader.goals.map(\.id) == ["a", "b"])

        reader.activate(accountId: "account-b")
        #expect(reader.goals.isEmpty)
        #expect(reader.selectedGoal == nil)
    }

    @Test func introductionWaitsForSuccessCachesPerAccountAndSurvivesFailure() async throws {
        let defaults = makeDefaults()
        let introduction = makeIntroduction()
        let writer = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: [], introduction: introduction)
        }

        writer.activate(accountId: "account-a")
        #expect(writer.presentation == nil)

        await writer.refresh(accountId: "account-a", force: true)
        #expect(writer.presentation == .introduction(introduction))

        let reader = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }
        reader.activate(accountId: "ACCOUNT-A")
        #expect(reader.presentation == .introduction(introduction))

        await reader.refresh(accountId: "account-a", force: true)
        #expect(reader.presentation == .introduction(introduction))

        reader.activate(accountId: "account-b")
        #expect(reader.presentation == nil)
    }

    @Test func activeGoalsReplaceAnIntroductionSnapshot() async throws {
        let defaults = makeDefaults()
        let introduction = makeIntroduction()
        let queue = CaptureGoalContextQueue(snapshots: [
            CaptureGoalContextSnapshot(goals: [], introduction: introduction),
            CaptureGoalContextSnapshot(goals: [makeGoal(id: "a")], introduction: introduction)
        ])
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            try await queue.next()
        }

        await store.refresh(accountId: "account", force: true)
        #expect(store.presentation == .introduction(introduction))

        await store.refresh(accountId: "account", force: true)
        #expect(store.presentation == .goal(makeGoal(id: "a")))
        #expect(store.introduction == nil)
    }

    @Test func legacyGoalOnlyCacheStillDecodesWithoutAnIntroduction() throws {
        let defaults = makeDefaults()
        let accountId = "legacy-account"
        let cachedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let envelope = LegacyCaptureGoalCacheEnvelope(
            goals: [makeGoal(id: "legacy")],
            selectedGoalId: "legacy",
            refreshedAt: cachedAt
        )
        defaults.set(
            try JSONEncoder().encode(envelope),
            forKey: UserDefaultsKeys.captureGoalContextPrefix + accountId
        )
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }

        store.activate(accountId: accountId)

        #expect(store.selectedGoal?.id == "legacy")
        #expect(store.introduction == nil)
        #expect(store.lastSuccessfulRefreshAt == cachedAt)
    }

    @Test func focusedRouteKeepsExistingCallSitesCompatible() {
        #expect(FieldTripTemplateRoute(templateId: "template").focusedChecklistItemId == nil)
        #expect(
            FieldTripTemplateRoute(
                templateId: "template",
                focusedChecklistItemId: "target"
            ).focusedChecklistItemId == "target"
        )
        #expect(FieldTripTemplateRoute(slug: "backyard_safari").reference == .slug("backyard_safari"))
    }

    @Test func inlineTipsAppearOnlyForTheCurrentIncompleteLevel() {
        #expect(FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 1,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 3,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: true,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: false
        ))
    }

    @Test func fieldTripLevelStatusUsesLifecycleForCurrentAndOverridesOtherLevels() {
        let notStarted = FieldTripTemplateStatusPresentation(
            kind: .notStarted,
            title: "Not started"
        )
        let active = FieldTripTemplateStatusPresentation(kind: .active, title: "Active")
        let stopped = FieldTripTemplateStatusPresentation(kind: .stopped, title: "Stopped")

        #expect(
            FieldTripLevelStatusPresentation.status(
                for: .current,
                currentStatus: notStarted
            ) == notStarted
        )
        #expect(
            FieldTripLevelStatusPresentation.status(
                for: .current,
                currentStatus: active
            ) == active
        )
        #expect(
            FieldTripLevelStatusPresentation.status(
                for: .current,
                currentStatus: stopped
            ) == stopped
        )
        #expect(
            FieldTripLevelStatusPresentation.status(
                for: .completed,
                currentStatus: active
            ) == FieldTripTemplateStatusPresentation(kind: .completed, title: "Completed")
        )
        #expect(
            FieldTripLevelStatusPresentation.status(
                for: .locked,
                currentStatus: active
            ) == FieldTripTemplateStatusPresentation(kind: .locked, title: "Locked")
        )
    }

    @Test func fieldTripLevelProgressResolvesNumericZeroCompletionAndLocking() throws {
        let unstarted = try #require(FieldTripLevelProgressResolver.resolve(
            presentationState: .current,
            currentProgress: nil,
            itemCount: 2,
            usesNumericRing: true
        ))
        #expect(unstarted.completedCount == 0)
        #expect(unstarted.targetCount == 2)

        let partial = FieldTripLevelProgressPresentation(completedCount: 1, targetCount: 2)
        let active = try #require(FieldTripLevelProgressResolver.resolve(
            presentationState: .current,
            currentProgress: partial,
            itemCount: 2,
            usesNumericRing: true
        ))
        #expect(active.completedCount == 1)
        #expect(active.targetCount == 2)

        let completed = try #require(FieldTripLevelProgressResolver.resolve(
            presentationState: .completed,
            currentProgress: nil,
            itemCount: 2,
            usesNumericRing: true
        ))
        #expect(completed.completedCount == 2)
        #expect(completed.targetCount == 2)

        #expect(FieldTripLevelProgressResolver.resolve(
            presentationState: .locked,
            currentProgress: nil,
            itemCount: 3,
            usesNumericRing: true
        ) == nil)
        #expect(FieldTripLevelProgressResolver.resolve(
            presentationState: .current,
            currentProgress: nil,
            itemCount: 2,
            usesNumericRing: false
        ) == nil)
    }

    @Test func fieldTripDetailGoalLayoutScrollsOnlyAboveTwoItems() {
        #expect(
            FieldTripLevelGoalLayoutPresentation.resolvedLayout(forItemCount: 1)
                == .equalWidthGrid
        )
        #expect(
            FieldTripLevelGoalLayoutPresentation.resolvedLayout(forItemCount: 2)
                == .equalWidthGrid
        )
        #expect(
            FieldTripLevelGoalLayoutPresentation.resolvedLayout(forItemCount: 3)
                == .fixedScrollable
        )
    }

    @Test func fieldTripGoalTipsUseOneToggleableSelection() {
        #expect(FieldTripGoalTipSelection.toggledSelection(
            currentItemId: nil,
            tappedItemId: "bird",
            hasGuide: true
        ) == "bird")
        #expect(FieldTripGoalTipSelection.toggledSelection(
            currentItemId: "bird",
            tappedItemId: "bird",
            hasGuide: true
        ) == nil)
        #expect(FieldTripGoalTipSelection.toggledSelection(
            currentItemId: "bird",
            tappedItemId: "butterfly",
            hasGuide: true
        ) == "butterfly")
        #expect(FieldTripGoalTipSelection.toggledSelection(
            currentItemId: "bird",
            tappedItemId: "flower",
            hasGuide: false
        ) == "bird")
    }

    @Test func fieldTripGoalTipsDefaultToFirstIncompleteGuidedItem() {
        func item(
            id: String,
            hasGuide: Bool,
            isCompleted: Bool
        ) -> FieldTripChecklistItem {
            FieldTripChecklistItem(
                itemId: id,
                prompt: id.capitalized,
                matchType: "taxonomy",
                guideTip: hasGuide ? "Look nearby." : nil,
                guide: nil,
                referenceSpecies: nil,
                isCompleted: isCompleted,
                completedAt: isCompleted ? "2026-08-23T12:00:00Z" : nil,
                completedCommonName: nil,
                completedScientificName: nil,
                completedScanId: nil
            )
        }

        let items = [
            item(id: "completed", hasGuide: true, isCompleted: true),
            item(id: "unguided", hasGuide: false, isCompleted: false),
            item(id: "bird", hasGuide: true, isCompleted: false),
            item(id: "dog", hasGuide: true, isCompleted: false)
        ]

        #expect(FieldTripGoalTipSelection.defaultItemId(in: items) == "bird")
        #expect(
            FieldTripGoalTipSelection.defaultItemId(
                in: Array(items.prefix(2))
            ) == nil
        )
    }

    @Test func captureIndicatorPolicyRequiresIdleVisualScanningAndRealData() {
        let visible = ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        )
        #expect(visible)

        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: false,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: false,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: false,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: true,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: true
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: false,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
    }

    @Test func captureIndicatorExpansionIsScopedToVisualVisitsAndVisibility() {
        #expect(
            CaptureGoalIndicatorExpansionState.collapsed.toggled == .expanded
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.toggled == .collapsed
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.preservingOnly(
                in: .visual
            ) == .expanded
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.preservingOnly(
                in: .audio
            ) == .collapsed
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.preservingOnly(
                in: .describe
            ) == .collapsed
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.preservingOnly(
                whenVisible: true
            ) == .expanded
        )
        #expect(
            CaptureGoalIndicatorExpansionState.expanded.preservingOnly(
                whenVisible: false
            ) == .collapsed
        )
    }

    @Test func captureIndicatorPlacementUsesTrailingCompactSelectorRow() {
        #expect(CaptureGoalIndicatorLayoutPolicy.compactSize == 50)
        #expect(CaptureGoalIndicatorLayoutPolicy.expandedSize == 56)
        #expect(CaptureGoalIndicatorLayoutPolicy.compactArtworkSize == 42)
        #expect(CaptureGoalIndicatorLayoutPolicy.expandedArtworkSize == 36)
        #expect(
            CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                isExpanded: false
            ) == 50
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.surfaceSize(
                isExpanded: true
            ) == 56
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.artworkSize(
                isExpanded: false
            ) == 42
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.artworkSize(
                isExpanded: true
            ) == 36
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                containerWidth: 402
            ) == 32
        )
        let narrowTrailingMargin =
            CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                containerWidth: 375
            )
        #expect(narrowTrailingMargin == 29.5)
        #expect(
            ((375 - CaptureModeSelectorStyle.controlWidth) / 2)
                - narrowTrailingMargin
                - CaptureGoalIndicatorLayoutPolicy.compactSize == 8
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.verticalOffset(
                isExpanded: false
            ) == -65
        )
        #expect(
            CaptureGoalIndicatorLayoutPolicy.verticalOffset(
                isExpanded: true
            ) == 0
        )
    }

    @Test func selectedStandardGoalRemainsPreferredAfterCameraMediaIsStaged() {
        let goal = makeGoal(id: "butterfly")

        let preferred = CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: goal
        )

        #expect(preferred == FieldTripPreferredGoal(
            userFieldTripId: "outing",
            itemId: "butterfly"
        ))
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: false,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: goal
        ) == nil)
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: true,
            selectedGoal: goal
        ) == nil)

        let challengeGoal = CaptureGoal(
            id: "challenge",
            source: goal.source,
            prompt: goal.prompt,
            progress: goal.progress,
            artwork: goal.artwork,
            destination: .fieldTripChallenge(challengeId: "challenge")
        )
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: challengeGoal
        ) == nil)
    }

    @Test func captureIndicatorOnlyClaimsHorizontalDominantSwipes() {
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: -60, vertical: 8) == .next)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 60, vertical: 8) == .previous)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 20, vertical: 2) == nil)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 50, vertical: 60) == nil)
    }

    @Test func captureIndicatorUsesOnlyExactBundledGoalArtwork() {
        #expect(
            FieldTripGoalArtwork.exactImageName(
                for: "Butterfly",
                templateSlug: "backyard_safari"
            ) == "fieldtrip-backyard-butterfly"
        )
        #expect(
            FieldTripGoalArtwork.exactImageName(
                for: "Dog",
                templateSlug: "backyard_safari"
            ) == "fieldtrip-backyard-dog"
        )
        #expect(
            FieldTripGoalArtwork.exactImageName(
                for: "Spider",
                templateSlug: "park_pollinators"
            ) == "fieldtrip-park-spider"
        )
        #expect(
            FieldTripGoalArtwork.exactImageName(
                for: "Meadow plant",
                templateSlug: "park_pollinators"
            ) == "fieldtrip-park-habitat"
        )
        #expect(
            FieldTripGoalArtwork.exactImageName(
                for: "Unknown future target",
                templateSlug: "backyard_safari"
            ) == nil
        )
    }

    @Test func captureIntroductionArtworkAssetsAreBundled() {
        let appBundle = Bundle(for: AppDelegate.self)
        let imageNames = [
            "fieldtrip-backyard-cardinal",
            "fieldtrip-backyard-dog"
        ]

        for imageName in imageNames {
            #expect(
                UIImage(
                    named: imageName,
                    in: appBundle,
                    compatibleWith: nil
                ) != nil
            )
        }
    }

    @Test func captureIntroductionArtworkRotationAlwaysResolvesAVisibleItem() {
        let bird = CaptureGoalArtwork.bundledImage(name: "fieldtrip-backyard-cardinal")
        let dog = CaptureGoalArtwork.bundledImage(name: "fieldtrip-backyard-dog")
        let artworks = [bird, dog]

        #expect(CaptureGoalArtworkRotation.artwork(at: 0, in: artworks) == bird)
        #expect(CaptureGoalArtworkRotation.artwork(at: 1, in: artworks) == dog)
        #expect(CaptureGoalArtworkRotation.artwork(at: 2, in: artworks) == bird)
        #expect(CaptureGoalArtworkRotation.artwork(at: -1, in: artworks) == dog)
        #expect(CaptureGoalArtworkRotation.nextIndex(after: 0, count: 2) == 1)
        #expect(CaptureGoalArtworkRotation.nextIndex(after: 1, count: 2) == 0)
        #expect(
            CaptureGoalArtworkRotation.artwork(at: 4, in: [])
                == .systemSymbol(name: "binoculars.fill")
        )
    }

    @Test func levelArtworkMapsBundledPatchesByOutingAndLevel() {
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 1
            ) == "fieldtrip-backyard-level-1-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 2
            ) == "fieldtrip-backyard-level-2-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 3
            ) == "fieldtrip-backyard-level-3-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 1
            ) == "fieldtrip-park-level-1-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 2
            ) == "fieldtrip-park-level-2-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 3
            ) == "fieldtrip-park-level-3-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "forest_edges",
                levelNumber: 1
            ) == nil
        )
    }

    @Test func captureIndicatorFramesExactPromptsAsOutingGoals() {
        #expect(
            ["Bird", "Butterfly or moth", "Moss or lichen"].map(
                ActiveCaptureGoalIndicatorCopy.instruction(for:)
            ) == [
                "Goal: Bird",
                "Goal: Butterfly or moth",
                "Goal: Moss or lichen"
            ]
        )
        #expect(
            ActiveCaptureGoalIndicatorCopy.accessibilityLabel(for: "Fungus") ==
                "Outing goal. Fungus."
        )
        #expect(
            CaptureGoalIndicatorAccessibilityCopy.progressValue(
                sourceTitle: "Backyard Safari",
                completedCount: 3,
                targetCount: 4
            ) == "Backyard Safari, 3 of 4 complete"
        )
        #expect(
            CaptureGoalIndicatorAccessibilityCopy.goalExpandHint ==
                "Expands goal details. Swipe up or down to change target."
        )
        #expect(
            CaptureGoalIndicatorAccessibilityCopy.goalOpenHint ==
                "Opens outing details for this target. Swipe up or down to change target."
        )
        #expect(
            CaptureGoalIndicatorAccessibilityCopy.introductionExpandHint ==
                "Expands the outing details."
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "merian.tests.capture-goal-context.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeGoal(
        id: String,
        completedCount: Int = 0
    ) -> CaptureGoal {
        CaptureGoal(
            id: id,
            source: CaptureGoalSource(
                kind: .fieldTrip,
                id: "outing",
                title: "Backyard Safari"
            ),
            prompt: id.uppercased(),
            progress: CaptureGoalProgress(
                completedCount: completedCount,
                targetCount: 3
            ),
            artwork: .systemSymbol(name: "binoculars.fill"),
            destination: .fieldTrip(
                templateId: "template",
                checklistItemId: id
            )
        )
    }

    private func makeIntroduction() -> CaptureGoalIntroduction {
        CaptureGoalIntroduction(
            id: "field_trip_introduction:backyard_safari",
            sourceKind: .fieldTrip,
            headline: "Start an outing",
            subheadline: "Backyard Safari · 2 goals",
            progress: CaptureGoalProgress(completedCount: 0, targetCount: 2),
            artworks: [
                .bundledImage(name: "fieldtrip-backyard-cardinal"),
                .bundledImage(name: "fieldtrip-backyard-dog")
            ],
            destination: .fieldTripTemplate(slug: "backyard_safari"),
            accessibilityLabel: "Start an outing. Backyard Safari, 2 goals.",
            accessibilityValue: "0 of 2 goals complete.",
            accessibilityHint: "Opens outing details."
        )
    }

    nonisolated private func makeTemplate(
        viewerHasAccess: Bool = true,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil,
        prompts: [String] = ["Bird", "Dog"]
    ) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: "template-backyard",
            slug: "backyard_safari",
            title: "Backyard Safari",
            subtitle: FieldTripTemplatePresentation.backyardSafariSubtitle,
            description: "Find familiar animals and small wild neighbors.",
            coverImageUrl: nil,
            estimatedDurationMinutes: 30,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: ["global"],
            seasonTags: ["spring", "summer", "fall"],
            habitatTags: ["urban", "yard"],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: true,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : "locked",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: prompts.isEmpty ? [] : [
                FieldTripLevel(
                    levelId: "level-1",
                    levelNumber: 1,
                    title: "Level 1",
                    description: "A compact neighborhood checklist.",
                    items: prompts.enumerated().map { index, prompt in
                        FieldTripChecklistItem(
                            itemId: "item-\(index)",
                            prompt: prompt,
                            matchType: "taxonomy",
                            guideTip: nil,
                            guide: nil,
                            referenceSpecies: nil,
                            isCompleted: false,
                            completedAt: nil,
                            completedCommonName: nil,
                            completedScientificName: nil,
                            completedScanId: nil
                        )
                    }
                )
            ]
        )
    }

    nonisolated private func makeProgress(
        isComplete: Bool = false,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: "outing-backyard",
            startedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: 1,
            completedAt: isComplete ? "2026-07-18T13:00:00Z" : nil,
            isProfileVisible: false,
            completedCount: isComplete ? 4 : 0,
            targetCount: 4,
            publicationId: nil,
            publishedAt: nil,
            stoppedAt: stoppedAt
        )
    }

    private func makeOuting(
        id: String,
        completedCount: Int = 0,
        targetIds: [String]
    ) -> FieldTripCaptureOuting {
        FieldTripCaptureOuting(
            userFieldTripId: id,
            templateId: "template-\(id)",
            templateSlug: "backyard_safari",
            outingTitle: "Field trip \(id)",
            lastEngagedAt: "2026-07-17T18:00:00Z",
            levelNumber: 1,
            levelTitle: "Level 1",
            completedCount: completedCount,
            targetCount: completedCount + targetIds.count,
            targets: targetIds.enumerated().map { index, itemId in
                FieldTripCaptureTarget(
                    itemId: itemId,
                    prompt: itemId.uppercased(),
                    sortOrder: (index + 1) * 10,
                    hasGuide: true
                )
            }
        )
    }
}

private actor CaptureGoalContextQueue {
    enum TestError: Error {
        case expected
        case exhausted
    }

    private var values: [CaptureGoalContextSnapshot]

    init(_ values: [[CaptureGoal]]) {
        self.values = values.map {
            CaptureGoalContextSnapshot(goals: $0, introduction: nil)
        }
    }

    init(snapshots: [CaptureGoalContextSnapshot]) {
        values = snapshots
    }

    func next() throws -> CaptureGoalContextSnapshot {
        guard !values.isEmpty else { throw TestError.exhausted }
        return values.removeFirst()
    }
}

private actor SuspendedCaptureGoalContextFetcher {
    private(set) var callCount = 0
    private let snapshot: CaptureGoalContextSnapshot
    private var continuation: CheckedContinuation<Void, Never>?

    init(snapshot: CaptureGoalContextSnapshot) {
        self.snapshot = snapshot
    }

    func fetch() async -> CaptureGoalContextSnapshot {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return snapshot
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct LegacyCaptureGoalCacheEnvelope: Codable {
    let goals: [CaptureGoal]
    let selectedGoalId: String?
    let refreshedAt: Date
}
