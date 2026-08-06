# Onboarding Steps

The `Steps` directory contains the individual, user-facing screens that make up the onboarding flow.

## Structure

- **Welcome**: The initial greeting screen introducing the user to Merian.
- **CameraPermission**: The screen explaining the need for camera access to capture organisms.
- **LocationPermission**: The screen explaining the need for location access to provide accurate ecological context.
- **Ready**: The final disclosure names Google Gemini as the recipient of
  observation data for AI-powered identification. Three left-aligned switches
  appear in the product-owner-selected internal-testing order: optional
  usage/diagnostics, required 18+ self-attestation, and required
  Terms/data-sharing permission with an inline Terms link. Only the two required
  switches gate **Start scanning**. Completion first appends exact, versioned
  adult, Terms, Gemini, and optional analytics evidence locally, then
  synchronizes immutable rows to the active Supabase account. Existing beta
  users route directly here without repeating Camera or Location only after
  launch reconciliation establishes that current required account evidence is
  genuinely absent; while that result is pending, `MerianApp` keeps the
  onboarding shell unmounted.
- **Shared**: Common UI elements used across multiple steps (e.g., standard layout templates, primary action buttons).
- **Models**: Defines the data structures or enums representing the different onboarding steps.

## Release status

The screen order and copy above are approved for internal testing, not frozen
for production. The two P1 analytics-withdrawal and ghost-handoff defects are
closed in source, as are account restoration, Realtime retry/repair, and OAuth
account replacement. The final synchronization merge also rechecks task
cancellation, observed account, Supabase SDK session, and synchronization
generation before it can persist evidence or apply analytics. AI and analytics
actions also carry the provider head observed when they were created; the
database atomically rejects a delayed offline grant if another device has
already changed that head. A revocation instead rebases onto the locked current
head so a stale device cannot leave permission enabled; the server-only
revision orders accepted state.
Internal test
builds may continue; same-SHA hosted iOS/Supabase validation, counsel approval,
and operator evidence still block public production. The
canonical status and exit evidence are recorded in
[Production Consent Readiness](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

## Purpose
This area houses the actual UI that the user interacts with during their first launch. Each step is designed to be a standalone view that communicates its specific purpose clearly, relying on the `Shell` to handle the transition between them.
