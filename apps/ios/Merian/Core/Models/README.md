# Core Models

The `Models` directory contains shared entity definitions and domain models utilized across the entire application.

## Purpose

This area houses definitions that don't belong strictly to a single feature (like a standard `User` model, or generic error types). If a model is only used by `Scans`, it should live in `Features/Scans/Models`. But if it's passed between `Explore`, `Scans`, and `Profile`, it belongs here in `Core/Models`.

## Capture goal context

`CaptureGoalContext.swift` is the source-agnostic contract between Capture and
features that contribute active goals. `CaptureGoal` contains only the prompt,
source label, aggregate progress, safe artwork reference, and typed destination
needed by compact capture chrome. It does not contain evidence, media, location,
or source-specific API DTOs.

`CaptureGoalContextProviding` keeps source eligibility and ordering outside the
camera. `FieldTripCaptureGoalProvider` is the first adapter. It converts the
private Field Trip capture-context response into generic goals in server order.

`ActiveCaptureGoalStore` owns selection, bidirectional wrapping, five-minute
freshness, refresh coalescing, and a versioned cache isolated by Supabase account.
Capture keeps the last successful context when a provider refresh fails. New
goal sources should add an explicit source kind, provider mapping, and typed
destination instead of exposing their network models to Capture.

The canonical architecture decision and future composite-provider rules live in
`docs/rfcs/active-capture-goal-context.md`.
