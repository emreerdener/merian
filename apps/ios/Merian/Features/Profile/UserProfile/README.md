# User Profile

`UserProfile/` owns the visible Profile tab: public identity, locally computed
stats and achievements, persona and terrarium presentation, and the signed-in
user's published-scan surfaces. The canonical product and behavior contract is
[`06-profile-and-gamification.md`](../../../../../../docs/features-and-hardware/06-profile-and-gamification.md).

## Ownership

- `Models/` contains Profile-only value types and display policy, including
  typed presentation routes, stats payloads, recovery summaries, achievement
  presentation, the bounded avatar-crop preview, and `UserPersona` progression.
- `Services/` owns every imperative live boundary: SwiftData projections and
  route lookup, Field trip progress, published-post endpoints, image loading,
  avatar preparation, app events, route requests, preferences, and haptics.
  Dependency structs expose only the closures required by their state owner.
- `ViewModels/` contains `@MainActor @Observable` asynchronous state owners for
  Profile-tab refresh, achievement detail, published-scan preview/library
  loading, and avatar selection/upload coordination.
- `Views/` contains screen and sheet hosts grouped by Achievements, Identity,
  and Publications. UI-only navigation, picker, scroll, focus, and modal state
  remains with the owning view.
- `Components/` contains presentation-only pieces grouped by Achievements,
  Identity, Publications, Shared, and Stats.
- `Utilities/` contains pure achievement calculation and avatar encoding.

Views and components do not resolve `MerianNetworkClient`, `AppDIContainer`,
`LocalImageLoader`, or haptic singletons and do not construct imperative
SwiftData fetch descriptors. The two publication grids retain a read-only
`@Query` solely to select a matching local reference-image fallback for an
already server-visible post. They receive environment-owned cross-feature state
where appropriate and call the narrow feature state owners. Live singleton and
endpoint resolution stays inside `Services/`.

## State Boundaries

`ProfileTabViewModel` generation-fences local-stat and server Field trip
progress refreshes. It publishes cached server progress immediately when
available and prevents work from an earlier account or invalidation generation
from overwriting current state.

`ProfilePublicScansPreviewViewModel` fences account replacement.
`ProfilePublishedScansViewModel` additionally owns cursor pagination,
deduplication, and refresh supersession so a stale append cannot merge after a
fresh first page. The last-tile pagination trigger uses a view-lifetime task;
canceling the still-current page clears loading state so a later appearance can
retry.

`AchievementDetailViewModel` owns foreground/background contribution loads and
telemetry timing. The current request always clears foreground loading state,
including when a background refresh supersedes an in-flight foreground load.
`UserProfileAvatarCoordinator` owns replaceable selection and serialized upload
tasks, request/account fences, staged crop previews, and deferred error
presentation. Selection completion consults the view's live typed-presentation
slot before publishing a preview or error. `UserProfile` retains only
UIKit/SwiftUI presentation admission state.

`ProfileDatabaseActor` is the feature's SwiftData projection boundary. It
returns immutable, `Sendable` stats and achievement payloads and never exposes
live `LocalScanRecord` instances to feature state. Its post-inference
`calculateAwards()` entry point invalidates projection caches before reading so
in-place inference writes cannot reuse a stale award projection; the long-lived
actor cache is replaced when the owning `ModelContainer` changes.

## Compatibility Guardrails

- Keep Profile, achievement-detail, username/display-name editor, published
  library, and public component initializer signatures stable unless a product
  contract explicitly changes.
- Preserve visible copy, accessibility identifiers, navigation, loading/error
  states, avatar lifecycle timing, Field trip achievement semantics, and Explore
  publication behavior.
- `ProfileViewModel` remains the shared account/cloud-identity owner. Do not
  absorb auth, geoprivacy, or public-identity network operations into this
  folder's presentation view models.
- Keep every production Swift file in this folder below the hygiene pass's
  600-line review guard.

## Tests

Feature-focused coverage lives in
`apps/ios/MerianTests/Features/Profile/UserProfile/` and mirrors the production
owner. The `OfflineQueueManager` integration guard remains with its Core owner
in `apps/ios/MerianTests/Core/Data/OfflineSync/ProfileActorCacheTests.swift`.
Together they cover:

- achievement calculation, mutation-aware projections, and detail loading;
- Profile SwiftData projections and container-scoped actor cache behavior;
- Profile-tab local/server refresh and account-generation fencing;
- published preview/library loading, cursor deduplication, refresh versus
  pagination overlap, and cancellation retry;
- avatar selection/upload cancellation, live presentation admission, and account
  fencing;
- publication-recovery presentation and persona tier boundaries.

After `make xcodegen` and a successful build-for-testing, run the complete
focused matrix against the same built products:

```bash
xcodebuild test-without-building \
  -scheme Merian \
  -project Merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  -only-testing:merianTests/AchievementsCalculatorTests \
  -only-testing:merianTests/ProfileDatabaseActorTests \
  -only-testing:merianTests/ProfileActorCacheTests \
  -only-testing:merianTests/ProfileTabViewModelTests \
  -only-testing:merianTests/ProfilePublicationsViewModelTests \
  -only-testing:merianTests/AchievementDetailViewModelTests \
  -only-testing:merianTests/UserProfileAvatarCoordinatorTests \
  -only-testing:merianTests/ProfilePublicationRecoverySummaryTests \
  -only-testing:merianTests/UserPersonaTests
```

Then run the complete `merianTests` target. The focused matrix proves value,
actor, and asynchronous state contracts; it does not prove SwiftUI navigation,
framework-picker dismissal timing, animation, accessibility, or layout.

Manual regression should cover Profile loading and event refresh, persona and
terrarium tiers, achievement sorting/detail navigation, Field trip badge links,
avatar picker/crop/upload/error timing, username/display-name editing,
published-scan preview/library pagination and recovery, VoiceOver, and large
Dynamic Type.
