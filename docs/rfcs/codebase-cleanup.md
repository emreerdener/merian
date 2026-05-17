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
  `merian/Features/<Feature>/`, shared app code under `merian/Core/`, persistent
  models under `merian/Models/`, public web code under `web/`, and backend code
  under `supabase/`.
- Keep tests and docs aligned in the same change when public contracts, file
  ownership, or route shapes move.

## Phase 0: Commit Current Product Work

Before cleanup begins, land the current public web/legal work as its own commit.
That keeps the Next.js app scaffold, `merian.earth` link updates, and policy
pages reviewable without unrelated file movement.

Expected verification:

```bash
cd web && npm run typecheck && npm run build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

## Phase 1: Repo Hygiene And Boundaries

1. Keep generated artifacts ignored:
   - Xcode build output and derived data
   - Next.js `.next/`, cache, coverage, and hosting metadata
   - `node_modules/` and TypeScript incremental state
2. Document root ownership:
   - `merian/`: native iOS source
   - `web/`: public Next.js frontend
   - `supabase/`: migrations, Edge Functions, and backend tests
   - `docs/`: source-of-truth architecture and contract docs
3. Keep `docs/codebase-map.md` and this RFC updated when moving folders or
   changing ownership rules.

## Phase 2: Behavior-Preserving File Splits

Start with files whose size makes local reasoning expensive. Split by existing
responsibility, keep symbols internal/private where possible, and run the build
after each slice.

Suggested first targets:

| File | Cleanup Direction |
|---|---|
| `merian/Core/AI/InferenceEngine.swift` | Split hydration, reference image loading, local classification, persistence, and result mapping into focused extensions. |
| `merian/Core/Network/MerianNetworkClient.swift` | Move feature-specific endpoint groups into extension files or feature-owned network helpers while keeping shared transport in Core. |
| `merian/Features/Explore/Views/ExplorePostDetailView.swift` | Keep the root route/container in place and extract detail sections, comments, toolbar, media, and UIKit gesture adapters. |
| `merian/Core/Utilities/UserDefaultsKeys.swift` | Separate keys, typed settings store, migration helpers, and cloud sync preference code. |

Rules for this phase:

- Do not rename public API at the same time as splitting files.
- Preserve call sites unless the old shape forces circular ownership.
- Prefer extensions in sibling files first; move types across folders only after
  the split compiles cleanly.
- Commit each large file split independently.

## Phase 3: Ownership Cleanup

After the large files are split, move code to clearer long-term homes:

- Explore-specific network DTOs and endpoint wrappers should live under
  `merian/Features/Explore/Network/` unless reused by another feature.
- Insight-specific export, carousel, and result-rendering helpers should stay
  under `merian/Features/Insights/`.
- Capture modality code should stay under
  `merian/Features/CaptureWorkspace/Modalities/<Mode>/`.
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
cd web
npm run typecheck
npm run build
```

For Supabase function changes:

```bash
cd supabase/functions
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
