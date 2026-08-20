# Merian iOS Structure

The iOS workspace is organized around product ownership first, then
implementation type. A developer should be able to find a user-facing area by
the name a user would use in the app before seeing folders such as `Views`,
`Models`, or `Components`.

## Top-Level Areas

```text
apps/ios/
  Merian/          Main iPhone app
  MerianTests/     Unit tests for the main app
  MerianUITests/   UI tests for the main app
  messages/        Messages extension and shared message-scan code
  photos/          Photos import extension and shared import code
  widgets/         Widget extension sources
```

The main app is organized as:

```text
Merian/
  App/              App entry point, launch screen, root lifecycle wiring
  Assets.xcassets/  App, brand, persona, and reusable visual assets
  Configuration/    Entitlements, Info.plist, privacy manifest, environment configuration
  Core/             Cross-feature services, infrastructure, and UI primitives
  Features/         User-facing product areas
  Models/           SwiftData schemas and app-wide persisted models
  Resources/        Bundled JSON, release notes, and static app resources
```

## Feature Folders

Feature folders are product-area-first. If a feature contains multiple
user-facing areas, those areas get their own folders before implementation
buckets appear.

```text
Features/<FeatureName>/
  Shell/          Root container, routing, tabs, pagers, and feature chrome
  <ProductArea>/  User-recognizable area such as Feed, Map, Settings, or Scan
  Shared/         Helpers shared only inside this feature
```

Inside a product area, use focused implementation folders only when they are
needed:

```text
<ProductArea>/
  Views/
  Components/
  Models/
  ViewModels/
  Services/
  Utilities/
```

Avoid parallel concepts such as `Screens/` and `Views/`. In SwiftUI, sheets,
detail routes, and full-screen pages are all views; folder nesting should
explain ownership.

## Core Versus Shared

Use the narrowest owner that fits:

- Put code in `<Feature>/Shared` when it is reused by multiple product areas
  inside one feature.
- Promote code to `Core` only when it is reused across features or represents
  app infrastructure.
- Keep feature-specific business rules out of `Core` even if the code feels
  reusable.

Examples:

- `Features/Scans/Shared` can own scan-only thumbnails, grids, and deletion
  dialogs.
- `Core/UI` can own generic controls or modifiers reused by Explore, Scans,
  Profile, and Capture.
- `Core/Data/OfflineSync` owns sync infrastructure rather than a
  feature-specific scan screen.

## AI And Foreground Analysis

`Merian/Core/AI/` owns remote inference orchestration and the ephemeral local
analysis that improves foreground scanning copy. `InferenceEngine` remains the
single state owner exposed to SwiftUI through `scanningPhaseText`.
`LocalVisualAnalysis.swift` supplies the injected Vision classifier,
deterministic pixel-trait extractor, one bounded primary-image derivative,
phrase coordination, future Foundation visual-cue seam, validation, and runtime
eligibility policy; `AppDIContainer` owns the live implementations. The current
toolchain derives five image-specific palette, color-intensity, tone, contrast,
and surface cues locally. They render as natural verb-led observations, not
`Kind: detail` labels. Active visual live-to-queue handoff preserves the
ephemeral contextual deck and in-memory carousel media only for an exact
scan-and-attempt owner. Prepared visual work transfers generic copy without
media; audio and Describe are typed nonvisual owners. The same visual cursor
survives save and connectivity changes, while dismissal or Auth removes
contextual phrase/media exposure without blocking durable result recovery.
Generative multimodal cues remain the stable-Xcode-27 milestone.

Gemini remains the sole authority for identification and completed Insight
content. Local classifications and cue text are never persisted, logged,
analyzed as product telemetry, or added to Gemini's payload. See the
[Core AI README](Merian/Core/AI/README.md),
[Capture submission README](Merian/Features/Capture/Submission/README.md), and
[Insight content README](Merian/Features/Insights/Content/README.md) for the
ownership, dispatch, and presentation contracts.

`Core/Data/OfflineSync/OfflineQueueDurability.swift` owns retry timing rather
than an Insight view. Scan analysis uses a five-second minimum, jittered
exponential backoff, a 30-second ordinary local maximum, and ten automatic
attempts; safe server-directed minimums may be longer, while maintenance keeps
its 15-minute maximum. `QueuedRetryPresentation` translates stable codes into
safe customer copy, countdowns, and actions without rendering stored error text.
Offline retryable work exposes no countdown or **Retry now**, and a due deadline
adds no redundant helper. See the
[Core Data README](Merian/Core/Data/README.md),
[Insight content README](Merian/Features/Insights/Content/README.md), and
[offline sync contract](../../docs/backend-and-data/01-offline-sync-pipeline.md).

## Tests

Unit tests should mirror the production owner:

```text
MerianTests/
  Core/<CoreArea>/
  Features/<Feature>/<ProductArea>/
```

If a test primarily exercises a Core manager, place it under `MerianTests/Core`,
even if the behavior appears in a feature screen. If it exercises a product
area's view model, policy, or local helper, place it under that feature product
area.

## Assets

Asset folders describe what the asset is, not where it was first used:

```text
Assets.xcassets/
  App/
  Brand/
  Graphics3D/
  Personas/
```

Avoid prefixes such as `pw_`, `desc_`, or `dictionary-` when artwork is
reusable. Prefer stable descriptive names such as `bird-cardinal`,
`camera-lens`, or `persona-naturalist`.

## Privacy Manifest

The main app owns `Merian/Configuration/PrivacyInfo.xcprivacy`. Keep it in the
`Merian` Resources phase exactly once through `project.yml`; never attach it to
another target merely to satisfy a warning. Before adding a required-reason API,
SDK, executable, analytics property, or off-device data flow, follow the
[iOS App Privacy Manifest Contract](../../docs/development-guides/16-ios-privacy-manifest.md).

After changing the declaration or target membership, run from the repository
root:

```bash
make xcodegen
make validate-ios-project
make validate-ios-privacy-manifest
make test-ios-ci-tooling
```

## Transport Security

The main application uses App Transport Security defaults and has no broad or
domain-scoped exception. `SecureTransportPolicy` accepts backend-provided remote
URLs only when they are credential-free HTTPS; app-owned file URLs and local
paths remain available for captured media. The Supabase origin is validated
under the same rule before client construction.

Run `make validate-ios-transport-security` for the tracked plist and
`make test-ios-transport-security` for adversarial fixtures. Archive and IPA
validation inspect the final built `Info.plist`, and hosted archive evidence
must contain `transport_security: "ats-default"`. See the
[iOS App Transport Security Contract](../../docs/development-guides/17-ios-transport-security.md)
for the complete boundary and release gate.
