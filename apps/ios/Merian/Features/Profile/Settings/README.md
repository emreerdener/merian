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
This area provides users with control over their app experience. It manages camera preferences, theme selection, geoprivacy toggles, data export, and account lifecycle (signing in/out and deletion). It operates in conjunction with the `ProfileViewModel` and updates the app's global state and preferences.

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
