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

- `Features/Scans/Shared` owns the Scans-only composite grid, queued-row value
  policy, and deletion interaction boundary.
- `Core/UI` owns `ScanThumbnail` and `EmptyStateView` because Explore, Scans,
  Profile, and Species Dictionary consume them.
- `Core/Data/OfflineSync` owns sync infrastructure rather than a
  feature-specific scan screen.

## Scans Ownership

Scans is composed from product-area owners rather than one root implementation:

- [Shell](Merian/Features/Scans/Shell/README.md) owns the root record and
  collection SwiftData queries, typed navigation stack, tab/pager state, and
  root presentation.
- [Library](Merian/Features/Scans/Library/README.md),
  [Collections](Merian/Features/Scans/Collections/README.md), and
  [Map](Merian/Features/Scans/Map/README.md) own their respective product
  behavior and receive prepared records or value snapshots from the Shell.
- [Non-Biological](Merian/Features/Scans/NonBiological/README.md) derives its
  projection from the Shell's timestamp-sorted records and owns its mutation
  orchestration, but it does not mount another persistence query.
- [Shared](Merian/Features/Scans/Shared/README.md) owns the Scans-only grid,
  queued-row value policy, and single-delete interaction shared by multiple
  Scans product areas. Cross-feature thumbnail and empty-state rendering lives
  in `Core/UI`.

`ScanThumbnail` delegates media work to the Core UI loader service, whose
post-suspension cancellation checks prevent cache-filling work from publishing
into a reused tile. Its task identity includes source, policy, target-size,
placeholder, and relevant connectivity inputs. Scans queued-row and Insight
snapshots share `ScanQueueState.isManualRetryEligible`; mutation owners still
re-fetch and revalidate the live row before changing durable state.

For bulk non-biological deletion, view state supplies immutable candidate
snapshots while `BackgroundDatabaseActor` remains the commit-time authority. It
re-fetches each ID and skips a row that has since become biological before any
record, local-path, or cloud-deletion mutation is accepted.

## Profile Ownership

Profile is split by user-facing responsibility:

- [User Profile](Merian/Features/Profile/UserProfile/README.md) owns the visible
  identity card, local stats and achievements, persona and terrarium
  presentation, and the signed-in user's published scans.
- `Profile/Settings` owns preferences and account actions, while its Plan,
  Notifications, Changelog, and Feedback product areas own their corresponding
  screens and state.
- `Profile/Shared` owns account and public-identity state consumed across
  Profile product areas. UserProfile view models depend on narrow live adapters
  rather than resolving shared managers or endpoints in views.

Within UserProfile, `Models`, `Services`, `ViewModels`, `Views`, and grouped
`Components` define the ownership boundary. `ProfileDatabaseActor` prepares
immutable stats and achievement projections off-main. Its post-inference actor
is cached only for the exact `ModelContainer` identity, and `calculateAwards()`
refreshes the value projection before every evaluation so in-place inference
updates cannot reuse stale fields. Avatar preparation and upload are
request/account fenced and consult the view's live typed-presentation slot
before publishing a preview or error.

## AI And Foreground Analysis

`Merian/Core/AI/` owns remote inference orchestration and the ephemeral local
analysis that improves foreground scanning copy. `InferenceEngine` remains the
single state owner exposed to SwiftUI through `scanningPhaseText`.
`LocalVisualAnalysis.swift` supplies the injected Vision classifier,
deterministic pixel-trait extractor, one bounded primary-image derivative,
phrase coordination, future Foundation visual-cue seam, validation, and runtime
eligibility policy; `AppDIContainer` owns the live implementations. The current
toolchain derives five image-specific observations covering dominant colors,
color saturation, lighting, light contrast, and surface detail. They render as
plain visible descriptions such as **Reviewing softly colored areas** and
**Observing light and shadow areas**, not `Kind: detail` labels or internal
statistical buckets such as “moderate” and “balanced.” Active visual
live-to-queue handoff preserves the ephemeral contextual deck and in-memory
carousel media only for an exact scan-and-attempt owner. Prepared visual work
transfers generic copy without media; audio and Describe are typed nonvisual
owners. That exact handoff also retains the canonical scan ID, selected carousel
page, focus state, and time-derived analysis sweep through pending, uploading,
staged, and inferencing queue states while none requires attention; ordinary
queued scans animate only while inferencing. The trailing Insight toolbar slot
stays mounted and fades in its queued delete action only after the durable ID is
bound. The same visual cursor survives save and connectivity changes, while
dismissal or Auth removes contextual phrase/media exposure without blocking
durable result recovery. Generative multimodal cues remain the stable-Xcode-27
milestone.

Gemini remains the sole authority for identification and completed Insight
content. Local classifications and cue text are never persisted, logged,
analyzed as product telemetry, or added to Gemini's payload. See the
[Core AI README](Merian/Core/AI/README.md),
[Capture submission README](Merian/Features/Capture/Submission/README.md), and
[Insight content README](Merian/Features/Insights/Content/README.md) for the
ownership and dispatch contracts. The
[Insight media README](Merian/Features/Insights/Media/README.md) and
[toolbar README](Merian/Features/Insights/Toolbars/README.md) own the carousel
clock, page continuity, and trailing-action presentation rules.

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
