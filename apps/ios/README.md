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

## Field Chat Ownership

[Field Chat](Merian/Features/FieldChat/README.md) is a cross-feature product
owner because Insights, Explore, and Species Dictionary all present the same
private conversation experience. Its Models, Services, ViewModels, Views, and
grouped Components separate deterministic presentation, live endpoint/effect
adapters, asynchronous state, and rendering.

Only Field Chat Services resolve the live network client, haptics, telemetry,
clipboard, clock, or request-ID factory. Host features own eligibility,
entitlement, navigation, and their presentation slot; Core Network owns Codable
DTOs, strict wire validation, and transport. Stable `InsightChat...` type names
remain compatibility names and do not place the shared implementation under
Insights.

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
- [Settings](Merian/Features/Profile/Settings/README.md) owns preferences,
  export, resources, and account actions. Its root Models, Services, ViewModels,
  Views, and grouped Components separate presentation from live side effects.
  Plan and Feedback mirror that full shape, Notifications uses
  Models/Services/ViewModels/Views, and Changelog remains a local Models/Views
  catalog.
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

Within Settings, closure-based Services are the only owners that resolve
endpoints, Supabase SDK writes, notification authorization, platform actions, or
RevenueCat actions. The Profile Shell composes the account-fenced geoprivacy and
hardware-reconciliation adapters that require its environment-owned managers;
other Settings state owners use their subarea's narrow default live dependency.
Observable state owners coordinate lifecycle operations, while leaf views retain
navigation and other UI-only timing. A feature test enforces this boundary and a
600-line production-file ceiling.

## Capture Ownership

[Capture Shell](Merian/Features/Capture/Shell/README.md) owns the ordered
Scan/Record/Describe pager, fixed capture chrome, root presentation and route
handoffs, external-import recovery, and the root capture state owner. Its
`Models`, `Services`, `ViewModels`, `Views`, `Modifiers`, and grouped
`Components` separate deterministic presentation policy from live work.

Only Shell Services construct the live network-client, URL-session,
connection-prewarm, remote-media, share/account lookup, keyboard platform, and
haptic adapters. The keyboard service owns raw UIKit notification publishers and
actions; the mounted modifier only binds those publishers to SwiftUI state.
Models remain deterministic. The view model receives small closure-based
dependencies and keeps mutable operation tasks and one-shot handoff state inside
an encapsulated owner with private mutable storage. Views and components retain
UI-only selection, scrolling, focus, expansion, and dismissal timing and issue
no endpoint calls. Feature tests mirror this structure and enforce the
live-service and deterministic Models boundaries, raw-notification confinement,
and a 600-line ceiling for production Shell files.

Capture-wide layout context lives in `Capture/Shared`, including the
composing-center environment value supplied by Shell and consumed by Record. The
cross-feature immutable `CGImage` concurrency wrapper lives in `Core/Media`
because Insights also consumes it.

The modality folders remain independent: `Scan` owns camera and video input,
`Record` owns audio presentation and interaction, `Describe` owns typed and
dictated observations, `Staging` owns the ephemeral mixed-media draft,
chronological nodes, image bundles, and crop presentation, and `Submission` owns
conversion into the shared live/offline timeline, descriptors, projection, and
analysis pipeline. Shell owns staging mutation and disposable-file cleanup; the
toolbar consumes Staging order without deriving another sort.

[Capture Staging](Merian/Features/Capture/Staging/README.md) documents that
boundary and its paired Shell/Submission verification.
[Capture Submission](Merian/Features/Capture/Submission/README.md) separates
deterministic admission/media/goal policy and normalized payload values in
`Models`, narrow live admission/context/deferred-update adapters and telemetry
in `Services`, and visual/nonvisual/Describe orchestration in responsibility-
specific `CaptureWorkspaceViewModel` extensions. Submission has no view layer;
Shell and modality views retain UI-only timing. The actor-backed 150 ms context
race transfers only a sendable snapshot and bounds environment-context waiting,
not total dispatch preparation. A branch with no foreground consumer cancels its
captured lookup; only a timeout-losing lookup remains for late enrichment, and
that task retains the injected service and bounded telemetry inputs rather than
the workspace view model or full display-image collection. The deferred-context
service updates the durable local queue before `/update-scan-context` and
performs at most one remote retry after 500 ms; endpoint, transport, or task
cancellation is terminal. View-model extensions make no endpoint calls, mirrored
tests enforce the ownership boundary, and every production Submission file
remains within the 600-line review guard.

[Capture Scan](Merian/Features/Capture/Scan/README.md) separates
platform-neutral media requests/results, narrow live
camera/context/library/media/feedback adapters, bounded still/video/WAV
preparation, leased temporary media artifacts, cancellation-propagating detached
workers, generation-fenced still/pre-recording/recording tasks, and viewfinder
UI. Shell lifecycle and presentation transitions invalidate pending still and
pre-recording work while gracefully stopping an active video. Scan views perform
no networking or global service resolution; the preview uses its injected camera
owner for session and zoom state. Every production Scan file remains within the
600-line review guard. The reusable crop processor, crop UI, and presentation-
only flash control live in `Core/Media` and `Core/UI` because Profile or the
shared Capture bar also consume them. Capture-specific editable image context
remains in `Capture/Shared`; Profile owns its own avatar-crop presentation
value.

[Capture Record](Merian/Features/Capture/Record/README.md) separates immutable
audio presentation and layout policy, narrow manager/haptic adapters, idle and
scrub state, a thin full-screen view, and focused components. Only Record
Services reference the concrete `AudioCaptureManager` or shared haptic manager;
the Shell resolves those live dependencies and supplies the view with an
immutable snapshot plus closure actions. Audio-engine, WAV, playback, FFT, and
generation-fenced audio-session lifecycle remain in `Core/Hardware`; shared
raster construction and the SwiftUI spectrogram surface live in `Core/Media` and
`Core/UI`; and the audio/video countdown badge lives in `Capture/Shared`.
Capture controls retain permission, record/pause/resume/stop/review actions,
while Submission retains queue-before-inference orchestration. Record views
issue no endpoint calls, and focused tests enforce the ownership boundary and
600-line production-file guard.

[Capture Describe](Merian/Features/Capture/Describe/README.md) separates pure
prompt, subject, tag-ranking, and text-composition Models; narrow live
preference/feedback/keyboard/speech Services; generation-fenced prompt and
lifecycle ViewModels; workspace-scoped Views; and layout-focused Components.
Describe views and components resolve no singleton or platform action, and view
models do not construct concrete hardware adapters. Focus, scrolling,
questions-sheet presentation, and tag auto-advance timing remain UI-owned. The
cross-feature `SpeechManager` lives in `Core/Hardware`, while the Describe
lifecycle observer crosses the composition boundary explicitly and the Services
layer converts that manager into initializer-injected speech, delay, and subject
inference closures. Pending speech startup is canceled and awaited before a
replacement may enter the shared manager, avoiding concurrent configuration and
teardown. Focused tests mirror these boundaries and enforce the 600-line
production-file guard.

## Insight Shell Ownership

[Insight Shell](Merian/Features/Insights/Shell/README.md) owns the root result
presentation, embedded navigation, completed/queued scan handoff, root
presentation hosts, and scan-bound state owner. Its `Models`, `Services`,
`ViewModels`, `Views`, `Components`, and `Modifiers` separate deterministic
presentation policy, live adapters, observable state, and UI-only timing.

`InsightShellDependencies` is the only Shell declaration that resolves live
network clients, authentication, repositories, feature access, app routing,
badge updates, or haptic feedback. Views and view-model extensions consume its
narrow initializer-injected closures and issue no endpoint calls. Presentation,
gallery, scrolling, focus, and dismissal timing remain view-owned. Mirrored
Insights tests enforce deterministic Models, the live-resolution boundary,
removal of aggregate source/test files, and a 600-line ceiling for production
Shell Swift files.

`Insights/Media/Carousel` applies the same product-area boundary below the
Shell: platform-neutral Models own presentation policy, Builders own page
assembly and availability, Services alone resolve audio/boost/telemetry/haptic
effects, and Playback owns AVPlayer observation lifetimes. Pages and Components
retain private mounted UI state. Carousel views perform no networking, stable
call-site initializers keep an optional trailing live dependency default, and
mirrored Media tests enforce folder ownership and the 600-line ceiling. The
cross-feature `AsyncLocalImageView` renderer lives in `Core/UI/Components`, with
its live loader adapter isolated in `Core/UI/Services`. The native pager, page
identity value, zoom host, pagination dots, and hero scroll-edge treatment used
by Insights and Field Trips also live in `Core/UI/Components/MediaCarousel`;
each feature supplies its own page ordering and reuse-key projection. Models
depend only on a platform-neutral selection-candidate contract, while the Core
pager preserves controllers for equal ID/reuse keys and invalidates its native
data-source cache when either identity changes.

The root view-model extensions are split into lifecycle, records, capabilities,
content presentation, media presentation, and presentation identity. Root view
extensions separately own content routing, chat actions, lifecycle attachment,
toolbar assembly, typed presentation hosts/bindings, and Explore composition.
Queued-completion polling is generation-, subject-, and cancellation-fenced, so
a dismissed or replaced destination cannot publish after its delay. Existing
call sites retain their initializer signatures; the optional trailing Shell
dependency defaults to the live adapter.

## Insight Sharing Ownership

[Insight Sharing](Merian/Features/Insights/Sharing/README.md) separates
platform-neutral Share copy/action models; Services-only endpoint, cache, event,
repository, and feedback adapters; focused root-view-model extensions; a
contained share-state request/revision owner; the observable Community request
draft; and thin Views and Components. The Shell-owned `InsightSheetViewModel`
remains the single root state owner and accepts an optional trailing Sharing
dependency for deterministic tests.

Sharing views and components issue no endpoint calls and resolve no live
singleton. Async share-state hydration, publication, editing, and Community
request work retain the existing scan/generation fences; same-scan mutations
invalidate older reconciliation, and a replacement Community request rejects a
late detail response from its predecessor. Existing screen and component
initializers, visible copy, accessibility labels, routes, and endpoint contracts
remain stable. Mirrored Sharing tests enforce those races, deterministic
presentation, ownership folders, aggregate removal, Services-only live
resolution, and the 600-line production-file ceiling.

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
