# Core Models

The `Models` directory contains shared entity definitions and domain models utilized across the entire application.

## Purpose

This area houses definitions that don't belong strictly to a single feature (like a standard `User` model, or generic error types). If a model is only used by `Scans`, it should live in `Features/Scans/Models`. But if it's passed between `Explore`, `Scans`, and `Profile`, it belongs here in `Core/Models`.

## Reference media identity

`ActiveScanMedia.swift` owns the shared reference-image deduplication boundary
used by Explore and Insight. `ReferenceImageDeduplicationPolicy` compares a
reference URL with the current scan's visual media identifiers before any
carousel pages are constructed:

- Naturebook media URLs use a normalized, lowercased host plus the encoded
  object path. Scheme, query strings, and fragments do not change the media
  identity, so resized or signed variants of the same stored object match.
- External URLs keep their complete trimmed URL identity. Query strings and
  fragments remain significant because external providers may use them to
  select different assets.
- Matching is provenance/URL based. A separately uploaded copy with a different
  object path remains eligible; no perceptual image comparison is performed.

`ActiveScanMedia.removingDuplicateReferenceImages(excluding:)` applies the
policy to a loaded `ReferenceState`. It leaves `.loading` and `.empty`
unchanged, preserves the surviving reference order, and converts an emptied
`.loaded` state to `.empty` so page counts and gallery visibility remain
consistent.

## Capture goal context

`CaptureGoalContext.swift` is the source-agnostic contract between Capture and
features that contribute active goals. `CaptureGoalContextSnapshot` carries
ordered `CaptureGoal` values plus an optional non-progress-bearing
`CaptureGoalIntroduction`. `CaptureGoal` contains only the prompt,
source label, aggregate progress, safe artwork reference, and typed destination
needed by compact capture chrome. It does not contain evidence, media, location,
or source-specific API DTOs.

`CaptureGoalContextProviding` keeps source eligibility and ordering outside the
camera. `FieldTripCaptureGoalProvider` is the first adapter. It converts the
private Field trip capture-context response into generic goals in server order
and, after a validated empty response, can introduce an accessible unstarted
Backyard Safari after Reset. New and migrated accounts normally receive active
Backyard Safari Level 1 goals from server-side enrollment instead.
`CaptureGoalDestination` is also used by progress toasts: standard outings carry
the template and first credited checklist-item IDs, while Seasonal Challenges
carry the challenge ID. Capture only opens the Explore sheet; Explore owns the
conversion into its feature-local route types.

`ActiveCaptureGoalStore` owns selection, bidirectional wrapping, five-minute
freshness, refresh coalescing, and a versioned goal/introduction cache isolated by Supabase account.
Concurrent freshness checks share the active provider fetch. Only an explicit
forced invalidation received during that fetch schedules one follow-up refresh.
Capture keeps the last successful context when a provider refresh fails. New
goal sources should add an explicit source kind, provider mapping, and typed
destination instead of exposing their network models to Capture.

The canonical architecture decision and future composite-provider rules live in
`docs/rfcs/active-capture-goal-context.md`.
