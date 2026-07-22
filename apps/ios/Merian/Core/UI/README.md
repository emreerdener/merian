# Core UI

The `UI` directory contains the foundational visual components and design system for the app.

## Purpose
This area houses reusable view modifiers, generic controls (e.g., primary action buttons, custom toggles), typography extensions, and complex visual treatments like glassmorphism shaders. Code placed here ensures visual consistency across all feature modules and prevents duplication of fundamental UI elements.

## Capture control layout

`Components/CaptureControlBar.swift` exposes `CaptureControlBarLayout` as the
fixed chrome contract shared with `CaptureWorkspaceView`: an 80 pt primary
control, a 124 pt bottom inset, and a 204 pt reserved height. The workspace
publishes that fixed reservation without measuring the rendered bar with a
preference key. Full-screen Camera and Audio overlays use the separate fixed
`fullScreenOverlayClearance` value of 250 pt, preserving the position used before
child measurement was removed. The full-screen pager reports a zero bottom
safe-area inset, so its geometry must not be used to derive this clearance.
The shared capture row center-aligns its 80 pt primary control with the 50 pt
secondary controls in Camera, Audio, and Describe. Describe's UIKit-hosted
editor uses the 204 pt `describeContentBottomClearance` reservation, matching
the row's actual reserved height. The editor's flexible interior consumes the
remaining viewport height, and its own 24 pt bottom padding separates the
rounded field from the fixed row instead of leaving blank page space.
Camera crop composition keeps its separately documented framing margin.

Do not reintroduce child-size-to-parent-state feedback for this fixed chrome.
If the control dimensions change, update the constants and verify Camera-,
Audio-, and Description-first cold launches with strict AttributeGraph cycle
logging. `testCameraHintPreservesClearanceAboveShutter` also verifies the real
rendered hint and shutter frames retain at least 8 pt of separation.
`testDescribeFirstLaunchRendersAndOpensPrompts` verifies both the Describe
control-row centerline and 8...32 pt of rendered clearance below the editor.
It also requires 8...32 pt between the `CaptureModeToggle` and Describe question
navigation, catching both overlap and duplicate top-safe-area padding.
The Describe table-of-contents control exposes the accessibility label
**Show prompts** and stable UI-test identifier `DescribePrompts`.

## Shared Goal Progress

`Components/GoalProgressRing.swift` renders the compact circular
`completedCount/targetCount` treatment shared by the visual Scan target capsule
the active Field-trip level header, and each persistent Insight contribution
row.
Feature callers own their accessibility label/value and frame; the primitive
owns clamping, track/progress drawing, and the centered count text. Keep it
domain-neutral so future goal providers can reuse it without importing Capture
or Field-trip models.

## Milestone feedback

`ToastBanner` and the compact Scans snackbar share an adaptive inverse-glass
surface. Light mode uses strongly tinted dark glass with light semantic content;
dark mode uses strongly tinted light glass with dark semantic content. When
Reduce Transparency is enabled, the surface becomes opaque. Toast callers own
their content and placement, but should use the shared surface instead of
introducing feature-local material, borders, or color-scheme overrides.

Queued milestone notifications render as a collapsed FIFO stack. The active
toast remains the only interactive and accessible surface; up to two scaled,
downward-offset backplates indicate pending items. Dismissing or opening the
front toast reveals the next item, and VoiceOver announces the full pending
count without exposing the decorative layers as separate elements.

`Feedback/AchievementToastPresenter.swift` retains its legacy filename for
project continuity but defines the generic `MilestoneToastPresenter`,
`FieldTripMilestonePayload`, and `ScanMilestoneCoordinator`. The coordinator is
the per-scan business boundary; the presenter is only a FIFO visual queue.
Foreground and background completion both key coordination by final saved scan
ID and enqueue standard outings, Seasonal Challenges, achievements, then
`New to Naturebook` after the progress attempt finishes.

`MilestoneToastBanner` preserves the shared 3.5-second timeout, haptics,
swipe/close dismissal, queue transition, and VoiceOver announcement. Field trip
payloads use the completed objective artwork, goal-complete title, and outing
name in the same compact layout as other milestones, and publish their typed
capture-goal destination when tapped. Other views must not show a second plain
progress message in response to the same refresh event.
