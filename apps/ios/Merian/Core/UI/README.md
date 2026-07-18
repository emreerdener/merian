# Core UI

The `UI` directory contains the foundational visual components and design system for the app.

## Purpose
This area houses reusable view modifiers, generic controls (e.g., primary action buttons, custom toggles), typography extensions, and complex visual treatments like glassmorphism shaders. Code placed here ensures visual consistency across all feature modules and prevents duplication of fundamental UI elements.

## Shared Goal Progress

`Components/GoalProgressRing.swift` renders the compact circular
`completedCount/targetCount` treatment shared by the visual Scan target capsule
and the active Field-trip level header. Feature callers own their accessibility
label/value and frame; the primitive owns clamping, track/progress drawing, and
the centered count text. Keep it domain-neutral so future goal providers can
reuse it without importing Capture or Field-trip models.
