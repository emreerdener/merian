# Onboarding Steps

The `Steps` directory contains the individual, user-facing screens that make up the onboarding flow.

## Structure

- **Welcome**: The initial greeting screen introducing the user to Merian.
- **CameraPermission**: The screen explaining the need for camera access to capture organisms.
- **LocationPermission**: The screen explaining the need for location access to provide accurate ecological context.
- **Ready**: The final disclosure names Google Gemini as the recipient of observation data for AI-powered identification. Three left-aligned switches appear in the product-owner-selected internal-testing order: optional usage/diagnostics, required 18+ self-attestation, and required Terms/data-sharing permission with an inline Terms link. Only the two required switches gate **Start scanning**. Completion first appends exact, versioned adult, Terms, Gemini, and optional analytics evidence locally, then synchronizes immutable rows to the active Supabase account. Existing beta users missing current required evidence route directly here without repeating Camera or Location.
- **Shared**: Common UI elements used across multiple steps (e.g., standard layout templates, primary action buttons).
- **Models**: Defines the data structures or enums representing the different onboarding steps.

## Release status

The screen order and copy above are approved for internal testing, not frozen
for production. The two P1 analytics-withdrawal and ghost-handoff defects are
closed in source; remaining account synchronization, production-copy
re-versioning, exact-SHA CI, and operator evidence still block release. The
canonical status and exit evidence are recorded in
[Production Consent Readiness](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

## Purpose
This area houses the actual UI that the user interacts with during their first launch. Each step is designed to be a standalone view that communicates its specific purpose clearly, relying on the `Shell` to handle the transition between them.
