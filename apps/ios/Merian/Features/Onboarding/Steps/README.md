# Onboarding Steps

The `Steps` directory contains the individual, user-facing screens that make up the onboarding flow.

## Structure

- **Welcome**: The initial greeting screen introducing the user to Merian.
- **CameraPermission**: The screen explaining the need for camera access to capture organisms.
- **LocationPermission**: The screen explaining the need for location access to provide accurate ecological context.
- **Ready**: The final disclosure screen with three left-aligned switches: required 18+ self-attestation, required Terms and Google Gemini third-party data-sharing permission with an inline Terms link, and optional PostHog analytics. Only the first two gate **Start scanning**. Completion first appends exact, versioned adult, Terms, Gemini, and optional analytics evidence locally, then synchronizes immutable rows to the active Supabase account. Existing beta users missing current required evidence route directly here without repeating Camera or Location.
- **Shared**: Common UI elements used across multiple steps (e.g., standard layout templates, primary action buttons).
- **Models**: Defines the data structures or enums representing the different onboarding steps.

## Release status

The screen order and copy above are the intended production experience. They do
not by themselves establish production readiness: local/account merge defects,
analytics shutdown and synchronization defects, and a consent unit-test compile
failure remain open. The canonical status and exit evidence are recorded in
[Production Consent Readiness](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

## Purpose
This area houses the actual UI that the user interacts with during their first launch. Each step is designed to be a standalone view that communicates its specific purpose clearly, relying on the `Shell` to handle the transition between them.
