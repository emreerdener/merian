# Contributing to Merian 🦋

Thank you for your interest in contributing to Merian! Our goal is to build the world's fastest, most resilient native iOS ecological identification engine. Because Merian sits at the intersection of heavy edge-compute API inference, hardware-accelerated LiDAR processing, and robust GDPR compliance, we enforce stringent contribution guidelines.

## Code Architecture & Philosophy

Before contributing, please review our core architectural tenets. Refactoring code that violates these principles will not be merged.

1.  **Thermal Management is King**: iOS is hostile to apps that run the GPU and CPU concurrently at full load. Any feature added to the viewfinder MUST interface with `HardwareOrchestrator`. Frame rates must dynamically drop behind modals or when the device hits `.fair` or `.serious` thermal states.
2.  **Zero-OOM Edge Infrastructure**: Deno Edge Functions crash violently when handed 20MB Base64 strings. Merian processes media _exclusively_ via Gemini File URIs or Cloudflare R2 pointers. Do not attempt to reintroduce Base64 image bloat into the network payload arrays.
3.  **Offline-First Paradigm**: Network availability in the field is chaotic. Any user-generated action (e.g., snapping a photo) must first natively write to the `NWPathMonitor` SwiftData queue rather than awaiting network validations globally. The paused `MerianShareExtension` prototype is the narrow exception pattern for a future rebuild: it must remain network/upload-only, must not open SwiftData, and may record only an App Group receipt for the containing app to reconcile later. It is not embedded in current app builds.
4.  **Accessibility (a11y)**: If a feature presents visual data natively, it must possess native SwiftUI `.accessibilityLabel` arrays explicitly reading components in a human-friendly format (e.g., using `.combine` on Grid tables).

## Setting Up the Development Environment

1.  **Xcode**: Use Xcode 16 or later. The app deploys to iOS 17.2+, but the codebase relies on Swift 6-era concurrency diagnostics and modern SDK APIs such as `AVCaptureEventInteraction`.
2.  **Supabase CLI**: For testing edge functions locally, you will need the Supabase CLI installed.
3.  **Project Generation**: `project.yml` is the source of truth. `Merian.xcodeproj` is committed for convenience, but you should regenerate it after changing targets, packages, entitlements, build settings, or source-group layout:
    ```bash
    cp Signing.local.example.xcconfig Signing.local.xcconfig
    make xcodegen
    open Merian.xcodeproj
    ```
    Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your personal Apple Developer Team ID. Do not hardcode a real team ID into `project.yml` or the shared `Signing.xcconfig`.
4.  **Client Config**: App-facing runtime values live in `Config.xcconfig`. These values ship in the app bundle and are not backend-only secrets. Backend secrets, including Gemini and service-role keys, belong only in Supabase Edge Function secrets.
5.  **Backend Operations**: Production Supabase deploys run through GitHub Actions using token-based CLI auth, not a developer's interactive local login. See [`docs/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md) for the CI path, required secrets, and smoke checks. From the repo root, the local emergency fallback remains:
    ```bash
    make db-push
    make functions-deploy
    ```

## Testing Protocol

- **Swift/iOS**: All `@MainActor` lifecycle boundaries must not block the main thread.
- **Edge Functions**: You must write and validate code natively using Deno testing frameworks. Before opening a PR targeting `services/supabase/functions`, run:
  ```bash
  cd services/supabase/functions
  deno task test
  ```

## Submitting a Pull Request 🚀

1.  Fork the repository and create your feature branch: `git checkout -b feature/my-amazing-feature`.
2.  Format your code. Swift code must naturally adhere to Apple's general styling limits. TypeScript should be linted natively before committing.
3.  Commit your changes following standard imperative structures.
4.  Push to the branch locally.
5.  Open a Pull Request describing the changes, explicitly mentioning if you changed any core network layer boundaries or AVFoundation settings.

We look forward to building this amazing open ecosystem with you!
