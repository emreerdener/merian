# Naturebook Repository AI Code Conventions & Guidelines

When generating or modifying code for Naturebook in the Merian repository,
follow these constraints to ensure optimal performance, hardware safety, and
architectural consistency.

## 0. The Documentation Directory

The `docs/` folder contains the master reference for the application:

- Refer to `docs/system-architecture/01-system-architecture.md` for overall
  architecture and pipeline logic.
- Refer to `docs/system-architecture/02-zero-oom-and-concurrency.md` for strict
  P0 iOS and Deno concurrency/memory safety rules.
- Refer to `docs/features-and-hardware/01-camera-and-hardware.md` for hardware
  integrations like LiDAR and precise telemetry snapshots.
- Refer to `docs/backend-and-data/04-database-schema.md` for PostgreSQL &
  SwiftData schemas.
- Refer to `docs/backend-and-data/05-api-contracts.md` for all network
  request/response shapes.
- Refer to
  `docs/backend-and-data/13-server-credentials-and-database-release-safety.md`
  before changing Supabase keys, headers, internal workers, privileged clients,
  RLS/grants/default ACLs, migrations, user foreign-key indexes, destructive
  queues, or backend release evidence.
- Refer to `docs/backend-and-data/01-offline-sync-pipeline.md` for offline
  queue, sync state machine, and deletion architecture.
- Refer to `docs/development-guides/02-app-lifecycle.md` for
  `AppLifecycleManager` phase contracts and trigger ordering.
- Refer to `docs/development-guides/12-in-app-changelog.md` before adding
  release notes or user-facing changelog entries.
- Refer to `docs/system-architecture/08-public-brand-compatibility.md` before
  changing product names, display names, URLs, email addresses, deep links, App
  Store metadata, legal copy, or stable Merian identifiers.
- Refer to `docs/system-architecture/09-ios-release-publisher.md` before
  changing iOS version/build ownership, CI archive boundaries, Organizer
  signing, source identity, upload evidence, or promotion state.
- Refer to `docs/development-guides/14-ios-release-versioning.md` for the sole
  supported iOS archive, upload, recovery, TestFlight, and App Review procedure.
- Refer to `docs/development-guides/15-naturebook-rebrand-rollout.md` for
  domain, AASA, email, Supabase, App Store, and release verification.
- Refer to `docs/development-guides/16-ios-privacy-manifest.md` before adding or
  changing an Apple required-reason API, privacy manifest, SDK, executable,
  analytics property, data-collection purpose, identity-linking behavior, or
  tracking behavior.
- Refer to `docs/development-guides/17-ios-transport-security.md` before
  changing ATS configuration, configured origins, signed URLs, or any boundary
  that converts a backend-supplied string into a remote URL.
- Refer to `docs/system-architecture/03-image-pipeline.md` for capture → disk →
  cache → display image flow.
- Refer to `docs/features-and-hardware/17-public-web-share-pages.md` before
  changing `apps/web/`, canonical `naturebook.earth` routes, legacy
  `merian.earth` compatibility, Open Graph metadata, or Explore share URL
  behavior.

## 1. Project Generation (XcodeGen)

- **Public brand boundary**: Use `PublicBrand` from
  `apps/ios/Shared/Branding/PublicBrand.swift` for public iOS and extension
  values. Use Naturebook for user-facing copy and keep Merian for existing
  project, target, module, bundle, app-group, persistence, backend, analytics,
  and product identifiers. New links emit only `naturebook.earth` or the
  `naturebook` scheme; parsers retain documented Merian compatibility aliases.
- **NEVER** directly modify `Merian.xcodeproj`.
- **ALWAYS** update `project.yml` when adding new packages, frameworks, scopes,
  or entitlements.
- Run `xcodegen generate` before attempting to build.
- The main app's `PrivacyInfo.xcprivacy` must remain an app-owned resource in
  the `Merian` target exactly once. A third-party manifest cannot cover
  first-party required-reason API use. Update the source manifest, exact
  validator, fixtures, canonical privacy inventory, and generated project
  together; run `make validate-ios-privacy-manifest` and
  `make test-ios-ci-tooling`.
- The main app must retain ATS defaults. App-configured and remotely supplied
  network URLs must pass the shared credential-free HTTPS boundary; local-file
  handling must remain explicit. Run `make validate-ios-transport-security` and
  the adversarial archive/IPA fixtures whenever that boundary changes.
- Do not hardcode a real Apple Developer Team ID in `project.yml` or shared
  tracked config. Signing must flow through `Signing.xcconfig` -> optional
  `Signing.local.xcconfig`, with the local file ignored by git.
- **Build Versioning**: `project.yml` tracks the reviewed `MARKETING_VERSION`
  release train and the archive build baseline; `Info.plist` files must strictly
  inherit `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. After the
  exact SHA passes **iOS Build and Test**, archive a clean checkout with Xcode
  Organizer, use **TestFlight & App Store**, and keep **Manage version and build
  number** enabled. Xcode is the sole signed archive/upload authority and App
  Store Connect reports the authoritative uploaded build. Keep the approved
  release train until intentionally starting a new one; do not increment the
  baseline per beta or add a competing CI, Fastlane, script, or agent upload
  recipe. Point to the canonical runbook instead.
- API Keys must be injected via `Config.xcconfig` or `MerianEnvironment.swift`.
  NEVER hardcode `GEMINI_PAID_API_KEY` or `SUPABASE_ANON_KEY` inside `.swift`
  files.

## 2. Directory Structure

The workspace enforces this layout inside `apps/ios/Merian/`:

- `Features/`: Complete user domains (`Capture`, `Explore`, `Insights`,
  `Onboarding`, `Profile`, `Scans`, `SpeciesDictionary`).
- `Core/`: Foundational logic organized into subdirectories:
  - `AI/`: `InferenceEngine`, generated Edge DTOs, `InferenceProcessingActor`,
    the private `Inference/Hydration` lifecycle and `Inference/State` write
    coordinators, the injected `Inference/Request` live provider boundary, and
    the `Inference/LocalAnalysis` ephemeral model/cadence owner plus its split
    classifier, image, trait, cue, and phrase policies
  - `Data/Database/`: `BackgroundDatabaseActor`, `FileIOActor`,
    `HistoricalDatabaseActor`, `ScanRepository`
  - `Data/Images/`: `MediaPreparationActor`, `LocalImageLoader`, `ImageCache`,
    `ArchiveManager`, `PhotoLibraryManager`
  - `Data/OfflineSync/`: `OfflineQueueManager`, `SyncStateManager`
  - `Hardware/`: `CameraManager`, `HardwareOrchestrator`,
    `EnvironmentContextManager`, `AudioCaptureManager`, `SpectrogramActor`
  - `Network/`: `MerianNetworkClient`, `SupabaseManager`
  - `Security/`: `CircuitBreakerManager`, `DeviceIdentityManager`,
    `EntitlementManager`, `RevenueCatManager`, `SocialGuardManager`
  - `SpeciesReference/`: shared non-UI Wikipedia mobile-sections and GBIF
    taxon-key transport/parsing used by Inference and scan-thumbnail recovery
  - `Utilities/`: `MerianConfig`, `AppLifecycleManager`,
    `BackgroundTaskWrapper`, `FieldNotesRepository`, `ImageDownsampler`
  - `Analytics/`, `Intents/`
- `Models/`: Standardized pure Data structures and `SwiftData` logic.
- `Configuration/`: target-owned Info.plist, entitlement, and privacy-manifest
  files. Repo-level project files such as `project.yml`, `Config.xcconfig`, and
  signing config remain at the repository root.

The public web app lives outside the iOS source tree in `apps/web/`. It uses
Next.js, React, and Mantine for server-rendered public pages. Keep service-role
secrets server-side only and run the web checks from
`docs/development-guides/08-testing-strategy.md` when changing web routes. The
private admin app is a separate browser-facing trust boundary in `apps/admin/`.
It receives only the three documented `NEXT_PUBLIC_` values and must never
import or recreate a service-role/secret-key client. Do not introduce computed
or whole-object `process.env` access. Run its frozen install, blocking
dependency audit, tests, type-check, and production build; preserve the required
`Naturebook Admin Quality / test` GitHub check and Vercel Deployment Check.

- `MerianLog` lives at `Core/MerianLog.swift`.
- `SearchDatabaseActor` lives in
  `Features/Scans/Library/Services/ScanLibrarySearchActors.swift` because it is
  an implementation detail of the Scans Library search index.
- The Sendable advanced-filter projection and detached predicate engine live in
  `Features/Scans/Library/Models/ScanLibraryFilterIndex.swift`. Keep
  `LocalScanRecord` reads in `ScansLibrarySearchCoordinator`'s yielding
  extraction boundary; never move SwiftData models into the detached filter
  engine. Full `SearchIndexSnapshot` construction must remain cancellation-aware
  and detached with the text-payload build. Live export, publication, app-event,
  durable-share-state, and haptic resolution belongs only in
  `Scans/Library/Services`.

## 3. Application State & Dependency Injection

- **DO NOT** use scattered `@EnvironmentObject` implementations or rely heavily
  on SwiftUI environment scoping for heavy singletons.
- **ALWAYS** use `AppDIContainer.shared` for injecting business logic. This
  protects the SwiftUI View lifecycle from massive memory redraw loops. Once a
  view model receives an `AppDIContainer`, read settings/services through that
  container rather than reaching back to global singletons; previews and tests
  rely on isolated container instances.
- Pass required core managers (e.g., `let cameraManager: CameraManager`) into
  `Views` as `@Observable` bindings or `@ObservedObject` properties.
- **iOS 17 `@Observable` Macro Dependency Loss**: Uncontrolled `@escaping` view
  layout wrappers (e.g. `GeometryReader`) can swallow Swift `@Observable`
  dependency tracking silently. If a nested `@Bindable` manager changes inside a
  structure but doesn't trigger UI updates, extract the dependency-reliant
  structure into a formal `private struct SomeSubcomponent: View`. This isolates
  the dependency boundary so that Swift invokes a clean dynamic observation
  connection specifically for that component.
- **Computed `@Observable` Data Trees**: When relying on computed collections
  derived from `@Observable` managers (e.g., pulling a dynamic `tags` array
  depending on `activeQuestionIndex`), calculate the property natively
  **inside** the physical Component's scope that needs it, rather than computing
  it in the parent and injecting frozen arrays via `let` constants. This
  guarantees standard real-time UI synchronization between parent indices and
  structural filters.

## 4. Hardware and Performance Limits

- iOS Background limitations severely constrain API requests. Any heavy file I/O
  operations must be decoupled via `Task.detached(priority: .background)`.
- Image conversions (e.g. `downsampleImage`) or large JSON parsing must occur
  off the Main thread to prevent 60FPS UI stutters.
- Avoid forcing `.isHighResolutionCaptureEnabled` without throttling image loads
  via `ImageIO` `CGImageSourceCreateThumbnailAtIndex` bounded logic. A full
  12MP–48MP uncompressed capture will cause iOS Out of Memory (OOM) crashes if
  repeatedly appended array buffers are allocated without bounds.
- Do not use `UIImage(contentsOfFile:)` or `UIImage(data:)` on user-selected
  originals, avatar picks, scan media, or share/export flows. Route file-backed
  still-image staging and avatar previews through `MediaPreparationActor`; use
  `ImageDownsampler.downsampledUIImage(...)` only for already-bounded
  crop/display bytes. The full raster must never enter RAM.
- **Photos share import is a document-import contract, not an extension.** Keep
  the `public.image` `Viewer`/`Alternate` declaration in the app Info.plist,
  copy incoming file URLs through `ExternalImageImportStore` while
  security-scoped access is active, and stage them through the shared
  `PreparedStagedImageLoader` with `requiresCrop: true`. Do not add a Photos
  Share Extension, App Group receipt, backend import endpoint, database job, or
  broad Photo Library permission for this path. Pending files remain durable
  across onboarding and temporary quota/capacity blocks and are removed only
  after staging or terminal decode failure.
- **Photos export must stay file-backed and add-only.** Never load a retained or
  remote video into `Data` to save it. Use `URLSession.download`, pass the file
  URL to the `.video` PhotoKit resource, await `performChanges`, and only then
  delete export-owned temporary files. Keep the automatic setting default-off,
  let explicit Downloads bypass that setting, and accept remote media only from
  the exact approved `media.merian.app` host. Follow
  [Camera Roll and Captured-Media Export](../features-and-hardware/27-camera-roll-media-export.md).
- **UI Lifecycle Triggers for Hardware**: Never bind `AVCaptureSession` or heavy
  hardware drivers to Swift UI sheet closures like `.onAppear` or `.onDismiss`.
  In iOS 16+, rapid presentation state changes or `.scenePhase` background
  sweeps can cause these closures to fire out of order, permanently deadlocking
  the backend AV queue. Always use deterministic `.onChange(of: stateVariable)`
  observers guarded by `scenePhase == .active`.
- **AVFoundation queue ownership**: Never read `AVCaptureSession.inputs` or
  configure an `AVCaptureDevice` synchronously on `@MainActor`. Resolve inputs
  and run `lockForConfiguration()` inside the camera queue, then publish
  observable state back through `Task { @MainActor in ... }`.
- **Image encoding — WebP first, JPEG fallback only through ImageIO**: Image
  payloads produced by the app (inference, display, offline queue, manual crop)
  attempt lossy WebP via `CGImageDestinationCreateWithData` with
  `UTType.webP.identifier`, using `MerianConfig.imageCompressionQuality`. If
  ImageIO cannot create a WebP destination in the current runtime, the shared
  encoder may fall back to `UTType.jpeg` with the same quality setting and the
  client must label the MIME type from the payload magic bytes. Never introduce
  `UIImage.jpegData(compressionQuality:)` or ad hoc JPEG branches outside the
  shared ImageIO encoder.

## 5. UI and Glassmorphism (Aesthetics)

- **Stunning UIs are mandatory**: The user should be wowed at first glance.
- Implement `.ultraThinMaterial` backgrounds to merge UI elements over camera
  viewfinders.
- Avoid large opaque black or white overlay panes. Make components dynamic,
  animated with native SwiftUI transitions such as `.spring()`, and highly
  responsive.
- DO NOT use XIBs or custom rigid Storyboards. Write SwiftUI exclusively.

## 6. Supabase & Deno Edge

- The `identify` Edge node abstracts all `generativelanguage` (Google) calls.
- Never write direct Gemini inference code inside iOS Swift controllers — this
  leaks API keys and bypasses edge limits.
- Keep the Deno Edge `index.ts` files synchronized with the Swift
  `IdentifyResponse` API Contract mapped in
  `docs/backend-and-data/05-api-contracts.md`.
- Ensure all unstructured display text (e.g. `common_name`) is locked via
  `systemInstruction` rules to format as Title Case, preventing lowercase UI
  outputs before values are cached to the database.
- **Every new Edge Function MUST have a `[functions.<name>]` entry in
  `services/supabase/config.toml`.** Keep `verify_jwt = true` for routes reached
  only with Supabase user JWTs; anonymous sessions also have valid user JWTs,
  and the gateway supports legacy and asymmetric signing keys.
  `merge-ghost-profile` therefore keeps the gateway check for both phases, then
  revalidates the live user and binds its RPCs with `auth.uid()`. Use
  `verify_jwt = false` only for a documented replacement boundary: an
  intentionally public read, webhook signature, custom in-handler user
  verification, or service-role worker. `species-dictionary` and
  `species-observation-stats` are intentionally public species-only reads. The
  latter still requires a canonical dictionary UUID/name pair, applies atomic
  user/IP/global population limits, and fences cache population in Postgres;
  never replace those controls with isolate-local state or a free-form provider
  name lookup. Preserve a still-retained positive stats payload when a refresh
  fails, and never memoize a stats response on iOS unless its schema is version
  2 or newer and its canonical UUID/name identity matches the request. Internal
  workers such as species/reference refresh, taxonomy import/status/refresh,
  consensus processing, non-biological purge, scan-media reconciliation/health,
  and ghost-merge reconciliation require one exact current or legacy server key
  through the shared service-role auth helper; opaque keys use `apikey` only.
  After adding or retiring a route, run `sync_function_deno_configs.ts --check`,
  `validate_function_dependencies.ts`, and `function_dependency_tools_test.ts`.
  The configured names must exactly match the discoverable graph names; never
  add or update a hard-coded fleet count.
- **Edge runtime imports must be deploy-stable.** New function entrypoints
  should use `Deno.serve(...)` directly, runtime dependencies must be routed
  through the reviewed `services/supabase/functions/deno.json` manifest, and
  deployed code should not add direct URL/npm/JSR imports. Regenerate the
  function-local configs, validate the shared frozen lock, and run
  `deno check --frozen` with the touched function's own `deno.json`. The fleet
  uses one exact Supabase SDK; `_shared/claimsAuth.ts` remains opt-in and must
  stay out of `_shared/edgeHandler.ts` so cached-JWKS claims verification is
  limited to the routes that explicitly adopt that authentication policy.
- **Do not improvise credential contracts.** Hosted plural key variables are
  JSON dictionaries; singular local variables are separate sources. Do not
  reinterpret a plural variable as a raw string based on key length, manually
  overwrite a platform-managed value, prefer the legacy key to avoid a
  migration, invent a custom credential header, or place an opaque project key
  in Bearer transport. Use `_shared/publishableKey.ts`,
  `_shared/serviceRoleAuth.ts`, and `_shared/serviceRoleClient.ts`.
- **Do not create secret-derived diagnostics.** Error output must not reveal a
  credential prefix, suffix, length, partial value, candidate name, or failed
  internal response body. A stable reason code, endpoint, request correlation
  ID, and HTTP status are sufficient.
- **Do not bypass enforcement to reach green.** Never suppress a discovered
  tooling test, weaken a real public-key negative smoke, add an analyzer
  exception for raw credential/fetch logic, or describe a change as
  production-ready before disposable replay and hosted verification both pass.

## 7. Database Safeties

- Anonymous IDs (`DeviceIdentityManager.shared.deviceId`) exist solely to
  persist the advisory `UsageManager` meter locally on iOS across reinstalls.
  They are not quota or entitlement authority. Do not use IDFV (`.deviceId`) for
  backend user records, analytics identifiers, server quota keys, or constructed
  S3/R2 storage keys.
- **Strict IDOR Alignment**: When querying Edge Functions (like `/identify`) or
  formulating Cloudflare R2 staging buckets (`staging/\(userId)/`), **always**
  use `SupabaseManager.shared.currentUser?.id.uuidString`. Edge functions
  natively apply IDOR security checks against the active auth JWT. Supplying the
  local vendor ID instead will trigger `403 Forbidden` pipeline blocks.
- Follow RLS (Row Level Security) schemas by avoiding direct CRUD modifications
  to PostgreSQL from iOS. POST through Edge REST endpoints protected by the
  route's documented verification strategy. Most existing authenticated routes
  use `supabaseAdmin.auth.getUser()`; latency-sensitive `/identify-multimodal`
  and `/update-scan-context` use cached-JWKS `auth.getClaims(token)` plus
  explicit issuer, audience, time, role, and `sub` validation. Never substitute
  unverified JWT decoding or request-body user IDs.
- **Identify success owns the scan row.** Do not move moderation, required media
  promotion, primary species resolution, scan creation, or owner-scoped
  read-back behind `EdgeRuntime.waitUntil`. Completion must be written last,
  after every claimed staging-key disposition and ready canonical media row are
  proved. A current multimodal `200` must make its `scan_id` immediately usable.
  Only optional analytics, group tags, and candidate enrichment belong in
  post-response work.
- **Missing-row recovery stays server-owned.** iOS may send only the bounded
  non-media `recovery_scan` to documented status/share routes and media only
  through owner-scoped staging keys. The server must derive owner identity,
  serialize against ingestion claim creation, defer to active/retryable
  ingestion, permit exact structured `replay_exhausted`, and require matching
  composite dead-letter/quota/media-lifecycle provenance for exact
  `media_reconciliation_abandoned`, including rejection of active attempts, dead
  letters older than later charged policy authority, invalid timestamps,
  unstructured rows absent from the immutable migration-time ID snapshot or
  outside its cutoff, and incomplete modern safety evidence. Never use
  transaction timestamp alone as the legacy boundary: a DDL-blocked insert can
  resume later with an earlier `now()`. Restore signing must obtain the same
  decision from the bounded service-only proof RPC; both signatures remain in
  the privileged grant ledger and production no-write readiness gate. All exact
  failed/committed normal and replay reservations remain retained as
  chronological authority until the terminal job is resolved. It must insert
  without overwrite and reload by both scan and owner. Never trust the terminal
  label alone, add a direct client scan upsert, or weaken RLS/grants to make
  recovery work.
- **New migrations use the CLI transaction.** Supabase CLI `2.109.1` batches
  each migration with its history insert. Do not add top-level transaction
  controls or any executable concurrent index DDL to a new migration. Historical
  applied files are immutable compatibility artifacts, not templates. Use the
  supervised production index preflight for a large or partitioned relation.
- **A queue marker is not destructive authority.** Do not blanket-delete an
  orphaned `pending_storage_deletions` row, sweep its prefixes, make it due,
  reset its cursor/lease, or delete Auth to clear monitoring. Preserve evidence,
  investigate request and private-job provenance with restricted access, and use
  a reviewed durable request or forward metadata migration only after the cause
  is classified.
- **Redundant queue state must reconcile monotonically.** Scan-ingestion
  retry/completion markers and attempts live on both `OfflineQueuedScan` and
  `OfflineJobRecord`. Fresh reads consult both, serialized writers repair drift
  before mutation, attempt projection is the nonnegative maximum, and cloud
  completion outranks retry. Never reset staging state from one cached copy or
  add the counters together.
- **SwiftData Predicate Boolean Mapping Bug**: When creating `@Query(filter:)`
  definitions with `#Predicate`, NEVER rely on implicit boolean checks (e.g.
  `$0.isBiological`). Due to iOS 17 compilation faults, SwiftData will ignore
  the filter and return all rows. **ALWAYS** map operators against booleans
  explicitly (e.g. `$0.isBiological == true` or `$0.isBiological == false`).
- **SwiftData Predicate `UUID()` Evaluation Fault**: Due to Swift 5.9 macro
  constraints, passing a raw `UUID` parameter against a persistent `String`
  column inside a `#Predicate` causes compiler timeouts that hang builds without
  error logs. **MUST** extract `.uuidString` outside the closure before
  comparing (e.g., `let stringVal = id.uuidString`, then
  `#Predicate { $0.id == stringVal }`).
- **SwiftData Optional Array Mutation Bug**: When mutating an optional SwiftData
  relationship array (e.g. `record.collections?.append(newCollection)` or
  `record.collections?.removeAll(where: ...)`), SwiftData often fails to trigger
  its internal `didSet` observers. This leaves the `ModelContext` unaware of the
  mutation, preventing inverse relationships from updating correctly. **ALWAYS**
  explicitly reassign the array instead:
  `var updated = record.collections ?? []; updated.append(newCollection); record.collections = updated`
  or
  `var updated = record.collections ?? []; updated.removeAll(where: ...); record.collections = updated`.
- **SwiftData Relationship Mirror Read Faults**: When a scalar mirror and
  relationship mirror carry equivalent data, hot SwiftUI read paths must prefer
  the scalar mirror. For mixed media, `serializedCapturedMediaItems` decodes
  `capturedMediaJSON` before lazily faulting `capturedMediaEntries`; reversing
  this can crash on `_InvalidFutureBackingData` while layout faults
  `CapturedMediaEntry.kindRaw`.
- **Snapshot SwiftData models before async work.** Never capture a live `@Model`
  in a `Task`, `Task.detached`, modal callback, share/export path, or delete
  confirmation that can outlive the view. Copy IDs and scalar fields first, then
  re-fetch by ID when mutation is required.
- **Scan Finalization Lock**: Any new path that creates or replaces a completed
  `LocalScanRecord` for an inference result must acquire
  `ScanFinalizationCoordinator` for the stable scan ID before
  checking/inserting/replacing. This includes visual live saves, non-visual live
  saves, and background URLSession completion. Bypassing the lock can make two
  SwiftData contexts race on `LocalScanRecord.id`; Core Data may then invoke
  unique-constraint merge logic and abort while merging no-inverse
  `capturedMediaEntries`.

## 8. Test Infrastructure Rules

- **Always use `CurrentSchema` in tests.** Never pin test containers to a
  historical `MerianSchemaV{N}`. A pinned schema silently drops all fields added
  in later versions (e.g., `MerianSchemaV26` adds `similarSpecies`), so tests
  pass against the wrong model shape and produce false confidence:
  ```swift
  // CORRECT
  let schema = Schema(CurrentSchema.models)
  // WRONG — silently drops similarSpecies, zoomFactor, etc.
  let schema = Schema(MerianSchemaV9.models)
  ```
- **Classify internal signals before sending them.** Loss-tolerant reload and
  lifecycle hints use the `AppEventPublisher` owned by the test's
  `AppDIContainer`; delivery-critical navigation uses its `AppRouteCoordinator`.
  Neither service exposes a separate `.shared` singleton. Application-defined
  `Notification.Name` values and posts are forbidden. Tests that trigger
  foreground timeout behavior send `.appDidResumeAfterTimeout` through the
  container bus. Sheet cleanup remains timeout-driven from the foreground path,
  while `.inactive` only pauses hardware so system overlays do not close the
  Insight sheet. Routed sheets and Capture-local editors/covers resume delivery
  only from exact `onDismiss` callbacks; do not introduce a teardown
  `Task.sleep`. A feature host with several local modal destinations uses one
  typed optional presentation value, with sheet and cover bindings filtered from
  that value. Raw Combine `.sink` is fail-closed to the reviewed owner files; do
  not add one without explicit weak/strong capture, cancellable lifetime,
  cancellation, ordering, and actor-isolation review. Follow the
  [canonical routing contract](../system-architecture/10-event-and-presentation-routing.md).
- **Do not call private methods via `@testable import`.** Swift allows calling
  internal-level methods from test targets, but `private` members are
  inaccessible. Always test behavior through public/internal interfaces (e.g.,
  `DeviceIdentityManager.shared.deviceId` instead of the private
  `getOrGeneratePersistentIDFV()`).
- **Do not assert `validHistoricImagePaths` synchronously in unit tests.**
  `InferenceEngine.load(from:)` populates this property inside a `Task { ... }`
  that calls `FileIOActor.shared.validPaths(from:)`, which filters out
  non-existent disk paths. Paths that don't exist in the simulator sandbox
  return empty — assert `speciesData` properties instead.
- **No `await` needed for `ImageDownsampler` in tests.** `ImageDownsampler` is a
  `public enum` with static methods. Call
  `ImageDownsampler.downsample(data:maxSize:)` directly — no actor isolation, no
  `await`.

## 9. Documentation Maintenance

- **ALWAYS create and update documentation accordingly.** Whenever you implement
  a new feature, modify a system's architecture, or alter an API contract,
  update the corresponding markdown file in the `docs/` folder to reflect
  reality. Do not wait to be asked. Maintain an accurate, synchronized
  documentation set that matches the codebase.
- Architecture and stability changes must update the specific domain guide, not
  just this checklist. Event/presentation work must synchronize
  `docs/system-architecture/10-event-and-presentation-routing.md`. For
  zero-OOM/concurrency work, synchronize
  `docs/system-architecture/02-zero-oom-and-concurrency.md`,
  `docs/system-architecture/03-image-pipeline.md`, and the relevant
  feature/backend guide in the same change set.
- Required-reason API, SDK, executable, collected-data, purpose, linking, or
  tracking changes must update
  `docs/development-guides/16-ios-privacy-manifest.md` and its exact validator.
  If product data practices changed, also synchronize the public Privacy Policy,
  App Store answers, and counsel-review record; a manifest change is not runtime
  consent or legal approval.
- **User-facing changes must consider release notes.** For features, fixes, UX
  changes, or deployment notes that users or testers should see, update root
  `CHANGELOG.md` and, when appropriate,
  `apps/ios/Merian/Resources/Changelog/changelog.json`. Follow
  `docs/development-guides/12-in-app-changelog.md`.
- **In-app changelog entries are curated.** Do not dump commit history into the
  app. Add concise user-facing entries only for releases or in-progress feature
  notes the team chooses to expose.

## 10. Agent Workflows

Codex is the only supported repository development agent. Root `AGENTS.md`
contains universal safety, authorization, synchronization, verification, and
delegation rules. Task procedures use progressive disclosure: canonical skills
live under `skills/` and their repository discovery links live only under
`.agents/skills/`.

The six project skills are:

| Skill                          | Responsibility                                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `$merian-ios`                  | SwiftUI/watchOS, XcodeGen, dependency injection, offline capture, hardware limits, and safe Debug/UI-test fixtures |
| `$merian-swiftdata-migrations` | Outgoing-schema freeze order, historical types, migration stages, and startup recovery                             |
| `$merian-supabase`             | Merian database, RLS, Edge, security, client, and candidate-validation overlay                                     |
| `$merian-api-contracts`        | Deno, generated Swift, and web payload coordination through generate → review diff → validate                      |
| `$merian-web-admin`            | Public web/internal admin trust boundaries and package-local verification                                          |
| `$merian-release`              | Explicitly authorized TestFlight, Supabase production, RevenueCat, and rollout procedures                          |

`$merian-release` cannot be invoked implicitly. Implementation, preparation,
candidate validation, or green CI never authorizes a deployment or publication.
Legacy files under `.agents/workflows/` and `apps/ios/.agents/workflows/` are
compatibility pointers only; the skills own the procedures.

Three read-only project agents live under `.codex/agents/`:

- `merian_explorer` traces unknown ownership and execution paths.
- `merian_reviewer` independently reviews correctness, security, concurrency,
  migrations, release safety, and test gaps.
- `merian_contract_auditor` checks implementation, DTO, documentation, CI, and
  release-control drift.

Use them only under the delegation conditions in `AGENTS.md`; the primary agent
owns every edit. Run `make validate-agent-assets` after any change to these
instructions, skills, agents, compatibility pointers, or Agent Quality workflow.
Deterministic validation is the required check. Live Codex evaluations are
non-blocking during their documented calibration window and are scored from
enumerated expectations rather than a second model judge.

## 11. SwiftData Schema Migration Safety

**CRITICAL — load `$merian-swiftdata-migrations` and read
`skills/merian-swiftdata-migrations/references/schema-update.md` before touching
any schema.** The skill is the canonical procedure; this section documents why
the model-shape invariants exist.

The durable invariant is concise: retired schemas reference fully qualified,
frozen snapshot types; only the current schema references global active types;
and relationship-bearing snapshots preserve matching Swift type identity. On iOS
26 and later, every custom stage must also resolve distinct from/to model
references.

The skill owns the ordered freeze procedure, relationship rules, custom-stage
requirements, disk-backed tests, startup recovery checks, and documentation
criteria. Keep version-specific recovery topology in source, focused tests, and
the canonical database guide rather than copying it into this agent overview.
