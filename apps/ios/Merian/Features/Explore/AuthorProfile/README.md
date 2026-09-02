# Explore Author Profile

This directory owns the privacy-scoped public Explore author profile, its
published-scan library, follow interaction, and user-report form. The canonical
product, privacy, API, navigation, and verification contract is
[`docs/features-and-hardware/14-explore-author-profiles.md`](../../../../../../docs/features-and-hardware/14-explore-author-profiles.md).

## Ownership

```text
AuthorProfile/
  Models/       Typed routes and deterministic presentation policy
  Services/     Live endpoint, image-prefetch, error, and feedback adapters
  ViewModels/   Profile/library/follow state and report-form state
  Views/        Sheet navigation host and profile/library presentation
  Components/
    Profile/       Avatar, identity, counts, patches, and follow control
    Publications/ Published preview, paginated library, and scan grid
    Reporting/    Report-user form
    Shared/       Loading skeletons
```

`ExploreAuthorProfileViewModel` is the single owner of profile loading, preview
seeding, cursor pagination, refresh/append generation fencing, stable post
deduplication, and optimistic follow mutation with rollback.
`ExploreReportUserViewModel` owns the typed report reason, 1,000-character
details bound, submission state, and recoverable error. Both are
`@MainActor @Observable` and receive small closure-based dependency structs.
Only `Services/ExploreAuthorProfileViewModelDependencies.swift` resolves
`MerianNetworkClient`, `LocalImageLoader`, and haptic feedback.

The stateless profile/posts wire methods live in
`Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`; follow and
report mutations live in
`Core/Network/Endpoints/MerianNetworkClient+ExploreInteractions.swift`. Core
owns payloads and DTOs, not profile presentation or pagination state.

Views and components call no endpoint. They retain UI-only state and timing: the
profile/library transition, toolbar and report-sheet presentation, navigation
path callbacks, SwiftData-backed local thumbnail fallback, scroll pagination
trigger, and app-event dismissal/reload handoff. The current viewer and
subscription are read from SwiftUI environment values rather than singleton
lookups. Loaded posts are still registered with `ExploreFeedViewModel` before
detail navigation so the shared post store remains authoritative.

The automatically enrolled Backyard Safari Level 1 row follows the existing
profile-visible status contract, so a new or backfilled account can have an
author-profile surface at `0/N` progress. Stopping or resetting the unfinished
outing hides that active status; no scan evidence becomes public.

For a non-self reportable profile, `viewer_can_report` enables **Report user**.
Reporting does not automatically block, unfollow, hide, or navigate away, and
the endpoint revalidates self-report and profile visibility; the decoded flag is
not the authorization boundary.

## Shared primitives

Cross-area media rendering remains under `Explore/Shared/Media`. The Pro badge
lives under `Core/UI` because Feed, Author Profile, and Profile consume it. The
published-scan grid corner/layout policy also lives there because Author
Profile, Profile, and Species Dictionary share it. Feature-specific profile
rules remain here.

## Tests

Mirrored tests live under
`apps/ios/MerianTests/Features/Explore/AuthorProfile/`:

- `ExploreAuthorProfilePresentationTests` owns route depth, title, entitlement,
  and stable-deduplication policy.
- `ExploreAuthorProfileViewModelTests` owns profile load/error recovery,
  latest-author fencing, prefetch projection, cursor pagination/fallback,
  refresh supersession of in-flight pagination, authoritative follow success,
  and optimistic rollback.
- `ExploreReportUserViewModelTests` owns details validation and report
  success/error restoration.

`MerianTests/Core/Network/Endpoints/ExploreBrowsingEndpointTests.swift` rehomes
profile projection and author-post cursor request tests from the aggregate
network suite. `ExploreBrowsingEndpointTransportTests.swift` covers their
transport failure/replay boundary. `ExploreInteractionEndpointTests.swift`
rehomes the follow-state request regression and covers both Boolean values and
user-report trimming/omission; `ExploreInteractionEndpointTransportTests.swift`
guards mutation replay refusal and body-ignoring report success. DTO-only
regressions remain with their existing Core owners. Run the
[Core Network browsing matrix](../../../Core/Network/README.md#endpoint-verification)
and
[interaction matrix](../../../Core/Network/README.md#explore-interaction-verification)
when changing their respective wire methods; do not move JSON DTO ownership into
this feature.
