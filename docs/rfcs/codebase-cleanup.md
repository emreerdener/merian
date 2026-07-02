# Codebase Cleanup Plan

This RFC defines the cleanup path for Merian after the public web share-page
work lands. The goal is easier navigation and safer future changes, not a broad
architecture rewrite.

## Principles

- Land product work before moving files. Refactors should not be mixed into
  feature commits unless the move is required for the feature.
- Keep behavior-preserving file splits separate from behavior changes.
- Prefer small, reviewable slices with one domain owner per slice.
- Move code toward the narrowest honest owner: feature code under
  `apps/ios/Merian/Features/<Feature>/`, shared app code under `apps/ios/Merian/Core/`, persistent
  models under `apps/ios/Merian/Models/`, public web code under `apps/web/`, and backend code
  under `services/supabase/`.
- Prefer product-area-first feature folders over broad type buckets. For large
  features, start with the user-facing surface (`Feed/`, `Map/`, `Identify/`,
  `Catalog/`, `Tree/`) and place that area's `Views`, `Components`,
  `ViewModels`, `Models`, and helpers inside it. Use `Shared/` only for code
  that is genuinely reused by more than one product area.
- Keep tests and docs aligned in the same change when public contracts, file
  ownership, or route shapes move.

## Phase 0: Commit Current Product Work

Before cleanup begins, land the current public web/legal work as its own commit.
That keeps the Next.js app scaffold, `merian.earth` link updates, and policy
pages reviewable without unrelated file movement.

Expected verification:

```bash
cd apps/web && npm run typecheck && npm run build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

## Phase 1: Repo Hygiene And Boundaries

1. Keep generated artifacts ignored:
   - Xcode build output and derived data
   - Next.js `.next/`, cache, coverage, and hosting metadata
   - `node_modules/` and TypeScript incremental state
2. Document root ownership:
   - `apps/ios/Merian/`: native iOS source
   - `apps/web/`: public Next.js frontend
   - `services/supabase/`: migrations, Edge Functions, and backend tests
   - `docs/`: source-of-truth architecture and contract docs
3. Keep `docs/codebase-map.md` and this RFC updated when moving folders or
   changing ownership rules.

## Phase 2: Behavior-Preserving File Splits

Start with files whose size makes local reasoning expensive. Split by existing
responsibility, keep symbols internal/private where possible, and run the build
after each slice.

For Explore and Species Dictionary, keep the vertical product folders intact:

```text
apps/ios/Merian/Features/Explore/
  Shell/
  Feed/
  Map/
  Identify/
  Notifications/
  AuthorProfile/
  Shared/
  Widgets/

apps/ios/Merian/Features/SpeciesDictionary/
  Detail/
  Catalog/
  Tree/

apps/ios/Merian/Features/Scans/
  Shell/
  Library/
  Collections/
  NonBiological/
  Shared/

apps/ios/Merian/Features/Profile/
  Shell/
  UserProfile/
  Settings/
    Plan/
    Notifications/
    Changelog/
    Feedback/
  Shared/
```

When working on the Explore feed, start in `Explore/Feed/`; that folder owns the
observations feed, post cards, post detail, comments, hashtag presentation, feed
formatting, and feed view-model extensions. Map and Community ID logic should
not be placed there.

When working on the Scans private library, start in `Scans/Library/`; that folder
owns individual scan browsing, search/index state, and queued scan snapshots.
Collection grids, smart collections, and collection detail/editing belong in
`Scans/Collections/`. Cross-surface Scans-only UI belongs in `Scans/Shared/`,
while controls reused outside Scans, such as `CategoryFilterBar`, belong in
`Core/UI/Components/`.

When working on the Profile tab, start in `Profile/UserProfile/`; that folder owns
identity, published scans, achievements, persona, terrarium, heatmap, and the
profile stats actor. Settings rows and account actions belong in
`Profile/Settings/`; plan/paywall surfaces live in `Profile/Settings/Plan/`, push toggles in
`Profile/Settings/Notifications/`, bundled release notes in
`Profile/Settings/Changelog/`, beta survey flows in `Profile/Settings/Feedback/`,
and cross-area profile state lives in `Profile/Shared/`.

Suggested first targets:

| File | Cleanup Direction |
|---|---|
| `apps/ios/Merian/Core/AI/InferenceEngine.swift` | Split hydration, reference image loading, local classification, persistence, and result mapping into focused extensions. |
| `apps/ios/Merian/Core/Network/MerianNetworkClient.swift` | Move feature-specific endpoint groups into extension files or feature-owned network helpers while keeping shared transport in Core. |
| `apps/ios/Merian/Features/Explore/Feed/Views/ExplorePostDetailView.swift` | Keep the root route/container in place and extract detail sections, comments, toolbar, media, and UIKit gesture adapters. |
| `apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift` | Separate keys, typed settings store, migration helpers, and cloud sync preference code. |

Rules for this phase:

- Do not rename public API at the same time as splitting files.
- Preserve call sites unless the old shape forces circular ownership.
- Prefer extensions in sibling files first; move types across folders only after
  the split compiles cleanly.
- Commit each large file split independently.

## Phase 3: Ownership Cleanup

After the large files are split, move code to clearer long-term homes:

- Explore-specific network DTOs and endpoint wrappers should live under
  the narrowest Explore product area when only one area uses them, or under
  `apps/ios/Merian/Features/Explore/Shared/Network/` when reused across
  multiple Explore areas. Only move them outside Explore when another feature
  depends on the same contract.
- Insight-specific export, carousel, and result-rendering helpers should stay
  under `apps/ios/Merian/Features/Insights/`.
- Capture modality code should stay under
  `apps/ios/Merian/Features/Capture/<Scan|Record|Describe>/`.
- `Core/UI` should contain reusable primitives only; one-off feature chrome
  should move back into the feature.
- `Core/Utilities` should shrink over time. New utilities belong there only when
  at least two features use them.

## Validation Gates

Every cleanup PR should run the narrowest relevant checks, plus the full app
build for moved Swift files:

```bash
git diff --check
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For web changes:

```bash
cd apps/web
npm run typecheck
npm run build
```

For Supabase function changes:

```bash
cd services/supabase/functions
deno check <changed-entrypoint>.ts
deno task test
```

## Stop Conditions

Pause the cleanup slice and make a smaller plan when:

- a file move requires behavior changes,
- a split touches more than one feature boundary,
- generated Xcode project changes become noisy,
- tests need large rewrites just to follow a mechanical move,
- or an in-progress product bug would become harder to isolate.
