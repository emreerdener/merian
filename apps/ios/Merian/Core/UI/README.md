# Core UI

The `UI` directory contains the foundational visual components and design system for the app.

## Purpose
This area houses reusable view modifiers, generic controls (e.g., primary action buttons, custom toggles), typography extensions, and complex visual treatments like glassmorphism shaders. Code placed here ensures visual consistency across all feature modules and prevents duplication of fundamental UI elements.

## Shared Goal Progress

`Components/GoalProgressRing.swift` renders the compact circular
`completedCount/targetCount` treatment shared by the visual Scan target capsule
the active Field-trip level header, and Field trip progress milestone toast.
Feature callers own their accessibility label/value and frame; the primitive
owns clamping, track/progress drawing, and the centered count text. Keep it
domain-neutral so future goal providers can reuse it without importing Capture
or Field-trip models.

## Milestone feedback

`Feedback/AchievementToastPresenter.swift` retains its legacy filename for
project continuity but defines the generic `MilestoneToastPresenter`,
`FieldTripMilestonePayload`, and `ScanMilestoneCoordinator`. The coordinator is
the per-scan business boundary; the presenter is only a FIFO visual queue.
Foreground and background completion both key coordination by final saved scan
ID and enqueue standard outings, Seasonal Challenges, achievements, then
`New to Naturebook` after the progress attempt finishes.

`MilestoneToastBanner` preserves the shared 3.5-second timeout, haptics,
swipe/close dismissal, queue transition, and VoiceOver announcement. Field trip
payloads replace the leading badge with a 56-point credited progress ring and
publish their typed capture-goal destination when tapped. Other views must not
show a second plain progress message in response to the same refresh event.
