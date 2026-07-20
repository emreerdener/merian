# Core Models

The `Models` directory contains shared entity definitions and domain models utilized across the entire application.

## Purpose

This area houses definitions that don't belong strictly to a single feature (like a standard `User` model, or generic error types). If a model is only used by `Scans`, it should live in `Features/Scans/Models`. But if it's passed between `Explore`, `Scans`, and `Profile`, it belongs here in `Core/Models`.

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
template.
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
