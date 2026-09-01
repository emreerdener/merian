# Onboarding Steps

The `Steps` directory contains the individual, user-facing screens that make up
the onboarding flow.

## Structure

- **Welcome**: The initial greeting screen introducing the user to Merian.
- **CameraPermission**: The screen explaining the need for camera access to
  capture organisms. It invokes an injected permission request closure and
  contains no AVFoundation work.
- **LocationPermission**: The screen explaining the need for location access to
  provide accurate ecological context. It invokes an injected permission request
  closure and contains no Core Location work.
- **Ready**: The final **One last step** screen names Google Gemini as the
  recipient of observation data for AI-powered identification. Three
  switch-and-label rows share a common leading edge in one continuous stack
  without section titles or a divider. The three labels omit terminal periods.
  The 18+ self-attestation and Terms/data-sharing permission with an inline
  Terms link are required; usage/diagnostics remains optional and changeable in
  Settings. Only the two required switches gate **Start scanning**, and
  VoiceOver hints preserve that distinction. Completion first appends exact,
  versioned adult, Terms, Gemini, and optional analytics evidence locally, then
  synchronizes immutable rows to the active Supabase account. Before the first
  Identify request, the app must fetch back the same account's current adult and
  Terms rows plus its granted all-version Gemini stream head; the local
  completion flag is not provider authorization. Existing beta users route
  directly here without repeating Camera or Location only after the initial
  session establishes no active account or an authenticated, identity-fenced
  merge establishes that current required account evidence is genuinely absent.
  An expired cached session is still a known account awaiting refresh, so it
  retains the launch-matched neutral surface until Auth emits a refreshed
  session or a signed-out result. Synchronization failures keep the
  launch-matched neutral surface mounted with bounded automatic and explicit
  retry; they never mount this step as a substitute for authoritative absence.
- **Shared**: Common UI elements used across multiple steps (e.g., standard
  layout templates, primary action buttons, and the normalized illustration
  stage).
- **Models**: Defines the data structures or enums representing the different
  onboarding steps.

Within `Ready`, `Models` owns deterministic disclosure and enablement policy,
`ViewModels` owns the editable projection of current consent, and `Components`
owns the shared switch-and-label row. `ReadyStepView` retains bindings, layout,
accessibility, and a read-only reactive `ConsentManager` environment projection;
the durable consent write remains a Shell service effect.

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
head so a stale device cannot leave permission enabled; the server-only revision
orders accepted state. Internal test builds may continue; same-SHA hosted
iOS/Supabase validation, counsel approval, and operator evidence still block
public production. The canonical status and exit evidence are recorded in
[Production Consent Readiness](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

An exact provider-admission `403 ai_consent_required` is not a no-scans-left
state. It durably returns only the affected completed account to this Ready
step, preserves the queued observation and media, and stops automatic inference
retry. Reapproval creates fresh evidence whose Gemini grant extends the provider
head fetched after rejection; another authoritative fetch is required before the
original scan ID may retry.

## Purpose

This area houses the actual UI that the user interacts with during their first
launch. Each step is designed to be a standalone view that communicates its
specific purpose clearly, relying on the `Shell` to handle the transition
between them.
