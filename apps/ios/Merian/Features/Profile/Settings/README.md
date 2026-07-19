# Settings

The `Settings` directory contains the user-facing configuration screens and preference toggles for the app.

## Structure

- **Views**: Contains the primary views like `SettingsTabView.swift` and modal flows like `DeleteAccountSheet.swift`.
- **Changelog**: Components and logic for presenting the bundled feature notes and release history.
- **Plan**: UI handling the RevenueCat subscription flows (free vs pro tier) and related upsells.
- **Feedback**: Forms and routing for user support and feedback submission.
- **Notifications**: Toggles for managing local and push notification preferences (e.g., species discoveries, achievements).
- **Components**: Reusable list rows, toggles, and section headers specific to the Settings layout.

## Purpose
This area provides users with control over their app experience. It manages
general preferences, the Capture workspace, geoprivacy, data export, and account
lifecycle (signing in/out and deletion). It operates in conjunction with the
`ProfileViewModel` and updates the app's global state and preferences through
the injected `AppSettings` boundary.

## Preference layout

The top general-preferences section begins with Theme. **Open Explore on
launch** follows Theme and sits directly above Notifications. The toggle uses
`safari.fill` and the user-facing description:

> Show Explore when you launch Naturebook. Close it to return to Scan, Record,
> or Describe.

The setting is opt-in. `opensExploreOnLaunch` registers a `false` default in
`UserDefaults`, persists through `AppSettings`, and participates in
`reloadFromDefaults()` so externally changed defaults are reflected in the
running settings model.

The section previously named **Capture** is now **Workspace**. It continues to
own Camera, Audio, **Reorder modes**, Field trip goals, and confirmation
preferences; the rename does not move those controls or change their behavior.

## Fresh-launch contract

`MerianApp` samples `opensExploreOnLaunch` once when a new process is created.
It may present the generic Explore feed only after onboarding is complete.
Returning from the background never resamples the preference and never reopens
Explore.

Explicit user intent always outranks the generic launch destination. A Photos
or Files image handoff dismisses Explore and continues through the normal
staging/crop workflow. Deep links and tapped notifications replace the generic
feed with their requested Explore post, community request, scan Insight, or
Scans library destination. While the initial Explore sheet is visible, Capture
does not start camera hardware; dismissing the sheet returns to the configured
Scan, Record, or Describe mode. Presenting Explore also marks its one-time
**New** chip as seen.

## DEBUG milestone previews

Developer settings can enqueue representative payloads through the production
`MilestoneToastPresenter` without changing user progress or notification
authorization:

- achievement previews, including long-title coverage;
- `Preview New to Naturebook notification`
  (`Settings_PreviewNewToMerianNotification`); and
- `Preview Field trip progress toast`
  (`Settings_PreviewFieldTripProgressToast`), which shows the contextual copy
  and credited `GoalProgressRing` used after a saved scan.

Use the Field trip preview at compact and large widths, with VoiceOver and
Reduced Motion, to verify wrapping, ring readability, timeout, manual dismissal,
haptics, and the tap target. Preview payloads bypass RPCs, progress mutation,
achievement persistence, dictionary mutation, analytics, and local push
delivery.
