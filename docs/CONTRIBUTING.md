# Contributing to Merian 🦋

Thank you for your interest in contributing to Merian! Our goal is to build the world's fastest, most resilient native iOS ecological identification engine. Because Merian sits at the intersection of heavy edge-compute API inference, hardware-accelerated LiDAR processing, and robust GDPR compliance, we enforce stringent contribution guidelines.

## Code Architecture & Philosophy

Before contributing, please review our core architectural tenets. Refactoring code that violates these principles will not be merged.

1.  **Thermal Management is King**: iOS is hostile to apps that run the GPU and CPU concurrently at full load. Any feature added to the viewfinder MUST interface with `HardwareOrchestrator`. Frame rates must dynamically drop behind modals or when the device hits `.fair` or `.serious` thermal states.
2.  **Zero-OOM Edge Infrastructure**: Deno Edge Functions crash violently when handed 20MB Base64 strings. Merian processes media _exclusively_ via Gemini File URIs or Cloudflare R2 pointers. Do not attempt to reintroduce Base64 image bloat into the network payload arrays.
3.  **Offline-First Paradigm**: Network availability in the field is chaotic. Any user-generated action (e.g., snapping a photo) must first natively write to the `NWPathMonitor` SwiftData queue rather than awaiting network validations globally. Extension targets must stay lightweight: they may read explicit App Group snapshots, but must not open the app's SwiftData store or run scan reconciliation work.
4.  **Accessibility (a11y)**: If a feature presents visual data natively, it must possess native SwiftUI `.accessibilityLabel` arrays explicitly reading components in a human-friendly format (e.g., using `.combine` on Grid tables).

## Setting Up the Development Environment

1.  **Xcode**: Use Xcode 16 or later. The app deploys to iOS 17.2+, but the codebase relies on Swift 6-era concurrency diagnostics and modern SDK APIs such as `AVCaptureEventInteraction`.
2.  **Supabase CLI**: For testing edge functions locally, you will need the Supabase CLI installed.
3.  **Project Generation**: `project.yml` is the source of truth. `Merian.xcodeproj` is committed for convenience, but you should regenerate it after changing targets, packages, entitlements, build settings, or source-group layout:
    ```bash
    cp Signing.local.example.xcconfig Signing.local.xcconfig
    cp Config.local.example.xcconfig Config.local.xcconfig
    make xcodegen
    open Merian.xcodeproj
    ```
    Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your personal Apple Developer Team ID. Do not hardcode a real team ID into `project.yml` or the shared `Signing.xcconfig`.
4.  **Client Config**: App-facing runtime values live in `Config.xcconfig`, with ignored machine-local overrides in `Config.local.xcconfig`. These values ship in the app bundle and are not backend-only secrets. Backend secrets, including Gemini and service-role keys, belong only in Supabase Edge Function secrets. Release archives may warn while using a RevenueCat `test_` key; TestFlight/App Store export should use a production iOS key beginning with `appl_`.
5.  **Backend Operations**: Production Supabase deploys run through GitHub Actions using token-based CLI auth, not a developer's interactive local login. See [`docs/backend-and-data/06-supabase-deployment-runbook.md`](./backend-and-data/06-supabase-deployment-runbook.md) for the CI path, required secrets, and smoke checks. From the repo root, the local emergency fallback remains:
    ```bash
    make db-push
    make functions-deploy
    ```
6.  **TestFlight Release Prep**: Before archiving in Xcode, run `make prepare-ios-release VERSION=x.y.z` from the repo root. If you are ready to use production RevenueCat, pass `REVENUECAT_API_KEY=appl_...` or set the same key in ignored `Config.local.xcconfig` first. The command updates the tracked XcodeGen source, regenerates `Merian.xcodeproj`, and writes the local archive-prep marker. See [`docs/development-guides/14-ios-release-versioning.md`](./development-guides/14-ios-release-versioning.md).

## Testing Protocol

- **Swift/iOS**: All `@MainActor` lifecycle boundaries must not block the main thread.
- **Edge Functions**: You must write and validate code natively using Deno testing frameworks. Before opening a PR targeting `services/supabase/functions`, run:
  ```bash
  cd services/supabase/functions
  deno task test
  ```
  Runtime Edge dependencies are resolved through `services/supabase/functions/deno.json`.
  The Supabase CLI discovers that Deno config during function graph creation, so
  local type checks for runtime files should use the same config:
  ```bash
  cd /Users/emreerdener/Developer/merian
  deno check --config services/supabase/functions/deno.json <changed edge files>
  ```
  New deployed functions should call `Deno.serve(...)` directly and avoid
  runtime imports from deno.land or esm.sh; route packages through `deno.json`
  and use local shared helpers such as `_shared/encoding.ts` where available.

## Submitting a Pull Request 🚀

1.  Fork the repository and create your feature branch: `git checkout -b feature/my-amazing-feature`.
2.  Format your code. Swift code must naturally adhere to Apple's general styling limits. TypeScript should be linted natively before committing.
3.  Commit your changes following standard imperative structures.
4.  Update docs and release notes for user-facing work. Use `CHANGELOG.md` for TestFlight/App Store/support notes and `apps/ios/Merian/Resources/Changelog/changelog.json` for curated in-app Settings notes. See [`docs/development-guides/12-in-app-changelog.md`](./development-guides/12-in-app-changelog.md).
5.  Push to the branch locally.
6.  Open a Pull Request describing the changes, explicitly mentioning if you changed any core network layer boundaries or AVFoundation settings.

We look forward to building this amazing open ecosystem with you!
