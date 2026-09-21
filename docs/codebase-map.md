# Current Codebase Map

Last reviewed: 2026-08-24.

This map is the short-form inventory for the repo as it exists now. Use it when
checking whether a feature, endpoint, schema note, or test reference in another
doc still points at the current file layout.

## Targets And Project Shape

`project.yml` is the project source of truth. `Merian.xcodeproj` is committed
for developer convenience and should be regenerated with `xcodegen generate`
after target, package, entitlement, build setting, or source-list changes.

| Target                    | Type                    | Source                                                                                                            | Deployment   |
| ------------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------ |
| `Merian`                  | iOS application         | `apps/ios/Merian/`, `apps/ios/Shared/Branding/`                                                                   | iOS 17.2     |
| `MerianExploreWidget`     | WidgetKit app extension | `apps/ios/widgets/Explore/`, `apps/ios/Merian/Features/Explore/Widgets/ExploreWidgetCache.swift`, shared branding | iOS 17.2     |
| `MerianMessagesExtension` | Messages app extension  | `apps/ios/messages/MerianMessagesExtension/`, `apps/ios/messages/ScanSharing/Shared/`, shared branding            | iOS 17.2     |
| `MerianWatch`             | watchOS companion app   | `apps/watch/MerianWatch/`, shared branding                                                                        | watchOS 10.0 |
| `merianTests`             | Unit tests              | `apps/ios/MerianTests/`                                                                                           | iOS 17.2     |
| `merianUITests`           | UI tests                | `apps/ios/MerianUITests/`                                                                                         | iOS 17.2     |
| `@merian/web`             | Next.js public web app  | `apps/web/`                                                                                                       | Node/Next.js |

Tracked build config:

- `Config.xcconfig` stores app-facing runtime values such as Supabase URL,
  Supabase publishable key, RevenueCat, PostHog, and Google Sign-In client IDs.
  These are bundled client config values, not backend-only secrets.
- `apps/ios/Merian/Configuration/MerianEnvironment.swift` validates those
  client-safe values. `Configuration/FeatureFlags.swift` owns the app-wide
  client-build flag registry (release gates plus the advisory scan-meter
  control) and DEBUG-only device overrides. Feature-local availability is not
  added to that registry:
  `Explore/FieldTrips/Models/FieldTripSharingAvailability.swift` owns the
  standard-outing sharing decision.
- `Signing.xcconfig` includes optional ignored `Signing.local.xcconfig`.
- `Signing.local.example.xcconfig` is the template for a local Apple Developer
  Team ID.
- `apps/ios/Merian/Configuration/PrivacyInfo.xcprivacy` is the main app's
  privacy declaration. XcodeGen places it exactly once at the root of
  `Merian.app`; `scripts/validate-ios-privacy-manifest.sh` owns the exact
  collected-data and required-reason policy.

Web runtime config:

- `apps/web/.env.example` documents the public web environment.
- `NEXT_PUBLIC_SITE_URL` should be `https://naturebook.earth` in production.
- `NEXT_PUBLIC_SUPPORT_EMAIL` should be `support@naturebook.earth` in
  production.
- Supabase server keys are server-only. Prefer `SUPABASE_SERVER_API_KEY`, then
  the hosted `SUPABASE_SECRET_KEYS` JSON dictionary; `SUPABASE_SERVICE_ROLE_KEY`
  is migration-only. The singular Edge-local `SUPABASE_SECRET_KEY` is
  deliberately unsupported by web. Never expose any server key through a
  `NEXT_PUBLIC_` variable or client component. Their only web owner is
  `apps/web/lib/supabaseAdmin.ts`, guarded by `server-only`; `explore.ts` uses
  that client only through fixed-anonymous, service-only web RPCs.
  `supabasePublic.ts` contains the anonymous Species Dictionary projection
  client. Credential sources are classified independently so a malformed lower
  migration source cannot veto a valid selected source or enter the candidate
  set.
- **Release status:** DwC-A is hidden in Release iOS builds and disabled by the
  canonical private PostgreSQL singleton for the initial launch. The server
  rejects old/direct intake, scheduled continuation is stopped, capabilities are
  revoked, and archive cleanup stays active. Public-web detail independently
  owns canonical anonymous visibility and
  `get_public_web_explore_post_page(...)` returns card plus detail atomically.
  Base promotion remains held for exact-SHA fresh-catalog, complete CI, catalog,
  and credential-smoke evidence; active export load/delivery evidence belongs to
  the later feature-enable gate. See
  `docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`.

## Public Brand and Compatibility

Naturebook is the public product and Merian is the permanent technical identity.
The iOS/extension source of truth is
`apps/ios/Shared/Branding/PublicBrand.swift`; the web source is
`apps/web/lib/site.ts` plus the production environment. Host redirects and the
legacy AASA exception live in `apps/web/proxy.ts` and
`apps/web/lib/canonicalHost.ts`.

New links emit `https://naturebook.earth` or `naturebook://`. The app continues
accepting `https://merian.earth` and `merian://`. Bundle IDs, targets, modules,
App Groups, SwiftData, backend names, `source = 'merian'`, RevenueCat product
IDs, analytics, and `media.merian.app` remain unchanged. See
`docs/system-architecture/08-public-brand-compatibility.md` for the complete
contract and `docs/development-guides/15-naturebook-rebrand-rollout.md` for the
release checklist.

## App Entry And Dependency Injection

| Area                          | File                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SwiftUI app entry             | `apps/ios/Merian/App/MerianApp.swift`, `apps/ios/Merian/App/Presentation/AppRootPresentation.swift`, `apps/ios/Merian/App/Routing/AppURLRouting.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Requests one Store Recovery bootstrap outcome, attaches its container, startup state, and notice, and emits its recovery telemetry after analytics admission; selects onboarding, retryable launch-matched consent restoration, or Capture workspace through `AppRootPresentationPolicy`; configures `ScanRepository`; discards unowned legacy species display preferences; prepares the first-party analytics facade outside tests without configuring PostHog; applies global theme to `UIWindow`; handles canonical `naturebook://` and legacy `merian://` Explore/species/scan/library deep links plus Naturebook/Merian Universal Links; and classifies file URLs for the Photos document-import inbox before Supabase auth handling. It does not construct a `ModelContainer` or own migration/recovery effects.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| App delegate bridge           | `apps/ios/Merian/App/AppDelegate.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Owns background `URLSession` completion handoff and push token callbacks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Debug UI-test seeding         | `apps/ios/Merian/App/UITesting/UITestSeedCoordinator.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Owns deterministic SwiftData, media, route, and Capture-goal fixtures behind `#if DEBUG` together with the signature-compatible Release no-op surface. The app root only invokes its narrow preparation entry points; the portable workflow contract extracts every Debug seed marker from this owner and requires the Release archive denylist to match exactly.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Test-execution detection      | `apps/ios/Merian/Configuration/TestExecutionCoordinator.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Sole process-level owner of UI-test environment, XCTest configuration, and loaded-runtime detection. App startup and reusable Core services consume this Configuration policy to suppress production side effects without depending on an App-root declaration.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Scene lifecycle orchestration | `apps/ios/Merian/App/Lifecycle/AppLifecycleManager.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Applies onboarding and current-consent admission before app-wide foreground maintenance, handles inactive camera suspension, records background timing, and delegates durable queue draining to Offline Sync.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Objective-C exception bridge  | `apps/ios/Merian/App/MerianObjCExceptionBridge.*`, `apps/ios/Merian/Configuration/Merian-Bridging-Header.h`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Converts launch-time SwiftData/Core Data Objective-C exceptions into Swift errors so store recovery can run.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| SwiftData startup recovery    | `apps/ios/Merian/Core/Data/StoreRecovery/Models/StartupStoreBootstrapModels.swift`, `apps/ios/Merian/Core/Data/StoreRecovery/Services/ModelContainerFactory.swift`, `apps/ios/Merian/Core/Data/StoreRecovery/Services/ModelContainerBootstrapper.swift`                                                                                                                                                                                                                                                                                                                                                       | Owns the bootstrap outcome—including its optional `ModelContainer` reference—plus value-only state, notice, and telemetry values; Objective-C-exception-safe `ModelContainer` construction; exhaustive source-isolated migration-plan routing; duplicate-checksum fallback; launch diagnostics; and the corruption quarantine, legacy rescue, plan-free current-schema in-memory safe-mode, and terminal blocked ladder. The full historical plan is validated independently. The focused architecture guard keeps every production owner under 600 lines and excludes Auth/session dependencies.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Dependency container          | `apps/ios/Merian/Core/AppDIContainer.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Owns the production dependency graph, including one typed invalidation bus, one route coordinator, one milestone presenter/coordinator/host registry, and its clock; injects observable hardware, AI, sync, network, analytics, security, settings, profile, goal-context, route, and feedback state through SwiftUI `@Environment`. Preview graphs remain isolated from production route/auth/milestone binding.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Inference internal assembly   | `apps/ios/Merian/Core/AI/Inference/Assembly/InferenceEngineAssembly.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | One-shot `@MainActor` builder for the focused inference owner graph. It preserves the engine initializer's construction order, injected edges, and optional live fallbacks, then returns the completed owners for private retention by `InferenceEngine`. It owns no mutable runtime state and performs no task, network, persistence, logging, filesystem, AppDI, or direct singleton work; `AppDIContainer` remains the production owner of external live dependencies supplied by the app graph.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Inference facade support      | `apps/ios/Merian/Core/AI/Inference/Facade/InferenceEngineCompatibility.swift`, `apps/ios/Merian/Core/AI/Inference/Diagnostics/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Keeps source-compatible nested modality and pure policy adapters separate from the 585-line observable facade. DEBUG-only forwarding methods and their ephemeral scenario coordinator compile out of Release and receive exact focused-owner references through the facade's sole debug factory; they do not widen those private owners or acquire live effects.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Local visual-analysis DI      | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/LocalAnalysis/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | AppDI owns the live Apple Vision classifier, deterministic five-cue palette/tone/contrast/surface trait extractor, `AppleFoundationVisualCueProvider` (default-on release flag; Swift 6.4/iOS 27 adapter and inert older-toolchain fallback), runtime eligibility checker, and light-impact start feedback injected through `InferenceEngine`; direct/default engine instances use inert start feedback. The private local-analysis coordinator owns task lifetime, bounded derivative, provisional classification, request-body gate, phrase cursor, inactivity pause/resume state, and session-scoped power/thermal subscription with explicit producer cancellation behind the live-attempt coordinator's exact-session predicate supplied by `InferenceLiveSubmissionCoordinator`. All local values remain ephemeral, and every production file in this owner stays below 600 lines.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Live inference request DI     | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Request/InferenceLiveRequestService.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | AppDI owns the live visual/nonvisual request service. The service maps the media projector's canonical submission projection, passed through the submission and pipeline coordinators, into one provider payload; performs base64 filtering and optional staged-video upload; and invokes `/identify-multimodal`. The pipeline coordinator supplies exact-attempt validation after every suspension boundary and owns callback timing. The provider-ready fail-safe and body-sent callback retain the attempt coordinator independently for durable queue release; the local-analysis update weakly captures only the focused live-presentation coordinator. The result service adapts parsing/persistence.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Live inference attempt DI     | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/State/InferenceLiveAttemptCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Services/InferenceLiveQueueService*.swift`                                                                                                                                                                                                                                                                                                                                                                                                   | AppDI owns the live durable-queue service. The private coordinator contains the current foreground task, retained displaced handles, active scan, process-local attempt UUID, durable generation, and recoverable scan. Full invalidation detaches the task and clears the local tuple before release and retirement callbacks; recovery detaches and cancels the exact task before publication. Retention keeps cancellation-ignoring displaced work in the Auth drain, while re-entrant callbacks may safely install a replacement. Exact-current retirement fences only its durable-generation slot before its callback while retaining local presentation identity for queue handoff. Awaited deletion rechecks the complete tuple and reports stale success or partial durable identity as unauthorized. The service core resolves no singleton, and only its `+Live` adapter reaches `OfflineQueueManager` for claim, current-owner lookup, deferred-upload release, retirement, exact-generation deletion, and terminal rejection. The engine retains its observable facade without direct queue access.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Inference presentation state  | `apps/ios/Merian/Core/AI/Inference/Presentation/{InferencePresentationCoordinator,InferencePresentationState}.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | The non-observable main-actor coordinator owns exact prepared/active presentation identity, visual queue phrase/media context, and one-shot first-render timing. It accepts only values and synchronous current-attempt checks and returns a value handoff. After visual admission, lifecycle replacement clears the displaced owner, queued context, and timestamp before the submission coordinator installs the replacement, including for a same-scan retry without a new clock. The observable main-actor state owns processing/copy/media/species/queue/loading/telemetry values and named synchronous transitions behind source-compatible engine accessors. Neither owner contains tasks, live dependencies, logging, persistence, or networking; the state also excludes lifecycle identity, filesystem access, and singleton resolution.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Live inference pipeline DI    | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLiveSubmissionCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePipelineCoordinator*.swift`, `apps/ios/Merian/Core/AI/Inference/Pipeline/InferenceLivePresentationCoordinator.swift`                                                                                                                                                                                                                                                                                             | AppDI captures circuit, quota-refund, and logging collaborators in the live adapter. The effect-acquisition-free submission coordinator owns Auth/payload admission, media and telemetry staging, exact activation, local-analysis startup, request/callback construction, and immediate task registration without storing the task. The singleton-free execution core owns visual/nonvisual admission, activation, exact suspension fences, request/result sequencing, completion preparation, benchmark placement, durable finalization, failure dispatch, modality-specific follow-up order, and exact-owner cleanup. Queue-less nonvisual authorization remains synchronous; only queue-backed finalization uses the existing suspension. The effect-acquisition-free live-presentation coordinator is the sole production constructor of both callback bundles, fences exact success identity before persisted-media projection or publication, transfers a queue-less first-render clock from the temporary request ID to the server scan ID, and routes publication-before-event ordering, finish, typed failures, captured hydration context, and visual local-analysis callbacks to focused owners without a task, suspension, mutable state, live dependency, or engine capture.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Live inference completion DI  | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Completion/InferenceLiveCompletionCoordinator*.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | AppDI captures and injects the live accepted-result collaborators. The singleton-free core normalizes persisted and confidence-zero no-record outcomes, sequences discovery/replacement/circuit/telemetry effects, emits committed biological events, and returns a coordinator-minted typed follow-up permit only after exact queue finalization while the full local/durable tuple remains valid. Queue-less authorization requires the nil scan/durable pair. Notifications and milestone scheduling require that permit. The `+Live` adapter is the only bridge for this accepted-result collaborator set; separate failure and identification-review effects retain their existing owners. The pipeline owns benchmark placement and modality-specific effect order; the live-presentation coordinator commits through `InferencePresentationState` and routes hydration to the species-presentation bridge, while the engine retains its stable facade.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Live inference failure DI     | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Recovery/InferenceLiveFailureCoordinator*.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | AppDI captures and injects circuit, haptic, and usage-manager collaborators. The `+Live` adapter binds telemetry and logging and translates those managers into paywall, feedback, and circuit effects. Invoked only by the pipeline, the singleton-free coordinator takes the initial exact ownership snapshot, sequences cancellation and queue handoff, delegates release/retirement/rejection to the attempt coordinator, revalidates local ownership after those synchronous callbacks, and orders terminal effects without creating a task or suspension. The live-presentation coordinator applies only its observable recoverable-ID, queued-presentation, and typed-failure actions; direct engine construction keeps the initializer-injected paywall closure through a lazy fallback adapter.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Live inference result DI      | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Result/InferenceLiveResultService.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | AppDI owns the live result service. It normalizes visual/nonvisual parse/save inputs, forwards the canonical media, model context, and exact persistence fence, and maps the actor's completion proof into persisted, confidence-zero no-record, or rejected outcomes. The pipeline validates the attempt before and after the actor call, prepares completion, and delegates exact-generation queue finalization through the completion and attempt coordinators. `InferenceLivePresentationCoordinator` fences the exact attempt before persisted-media projection and commits admitted observable/media state through the lifecycle and presentation owners. `InferenceScanReplacement` retains synchronous metadata-save safety before the live completion adapter invokes repository-owned deletion.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Species hydration DI          | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHistoricalLoadCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHistoricalHydrationCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesHydrationCoordinator*.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesPresentationCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesEnrichmentCoordinator.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceLookalikeCacheResetService*.swift` | AppDI owns the public-reference value, species-hydration logging dependencies, and legacy-cache reset service. The singleton-free species coordinator carries exact identities and owns the complete live Wikipedia-enrichment-GBIF order plus the shared exact-presentation operations used by historical/review flows, the live task-entry fence before loader publication or provider work, post-suspension cancellation fences, bounded reference merging, exact deferred-loader cleanup, and persistence-work emission. The historical-load coordinator owns lifecycle admission, live-media release, immutable projection, compatibility-reset scheduling, initial publication, generation capture, callback construction, and registered follow-up scheduling without retaining the managed record. The historical-hydration coordinator owns deferred decoding, override refresh, concurrent Wikipedia/enrichment work, enrichment-before-GBIF ordering, and terminal empty-state resolution for a still-current loader whose providers return no image. The review workflow coordinator owns review-action ordering and registered review hydration. The live-dependency-free species-presentation bridge is the sole hydration-callback factory and owns observable publication, live admission, exact identity/review-generation checks, and bounded background-versus-review write routing; the engine retains its stable facade. The private-state enrichment sub-coordinator owns independent loading, current-presentation patching, 403/429 handling, and one taxonomy-gated retry. The cache-reset core is effect-free; only its live adapter owns UserDefaults, process coalescing, detached work, and database-actor construction. |
| Species enrichment DI         | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesEnrichmentService.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesEnrichmentService+Live.swift`                                                                                                                                                                                                                                                                                                                                                                                | AppDI owns the live scoped enrichment value. The live adapter is Core AI's sole `fetchEnrichment` caller; the injected core resolves no live client directly and maps wire metadata and lookalikes into typed domain patches. `InferenceSpeciesEnrichmentCoordinator` retains request admission, independent loading, bounded retry, current-presentation application, and stale-result policy.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Hydration persistence DI      | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHydrationPersistenceService.swift`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHydrationPersistenceService+Live.swift`                                                                                                                                                                                                                                                                                                                                                                          | AppDI owns the live hydration persistence value. The service accepts immutable reference, metadata, and lookalike snapshots emitted by the species coordinator after species-presentation/write-coordinator admission; its live adapter owns database-actor construction and off-main lookalike encoding. Every snapshot carries the expected scientific name, and the actor rechecks it against the effective override-or-original identity before commit. The actor receives domain `TaxonomyData`, so enrichment wire DTOs do not cross into persistence.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Identification review DI      | `apps/ios/Merian/Core/AppDIContainer.swift`, `apps/ios/Merian/Core/Network/Inference/InferenceIdentificationReviewService.swift`, `apps/ios/Merian/Core/AI/Inference/IdentificationReview/`, `apps/ios/Merian/Core/AI/Inference/Hydration/InferenceSpeciesPresentationCoordinator.swift`                                                                                                                                                                                                                                                                                                                      | AppDI owns the immutable account-fenced transport and throwing snapshot values plus the action/effect coordinator's event and milestone dependencies. The singleton-free action/effect core owns generations through the shared write coordinator, ordered local persistence then transport, typed lookup/snapshot failure, and successful Explore refresh then milestone effects. Its `+Live` adapter alone constructs the database actor, maps shared posts, logs failures, and binds AppDI collaborators. `InferenceReviewWorkflowCoordinator` owns override/confirmation/reset and historical displayed-override sequencing, snapshot preflight, local-before-cloud admission, registered review hydration, and exact post-suspension identity checks. The pure presentation mapper returns matching full-value `SpeciesData`, reference-media, and persistence-patch actions. `InferenceEngine` retains stable public entry points. `InferenceSpeciesPresentationCoordinator` coordinates observable commits through `InferencePresentationState`, supplies the workflow's single hydration callback bundle, starts review generations for newly installed live and historical presentations, and owns current-presentation, generation, exact-identity, and persistence-admission routing. Interactive review sequencing, persistence implementation, transport, singleton resolution, Explore invalidation, and milestone resolution remain outside the engine.                                                                                                                                                                                                                                                                                |
| Typed invalidation bus        | `apps/ios/Merian/Core/Routing/Models/AppEvent.swift`, `apps/ios/Merian/Core/Routing/Coordination/AppEventPublisher.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Immutable event inventory plus a synchronous `@MainActor`, process-local, loss-tolerant bus. The subject is private; producer and streaming capabilities are separated, and payloads never replace durable authority.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Root route state machine      | `apps/ios/Merian/Core/Routing/{Models,Policies,Coordination}/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Immutable route values, deterministic coalescing/source/account/outcome policy, and a bounded priority/FIFO coordinator with stable IDs, expiry, account/session fences, explicit outcomes, one in-flight request, and exact presentation-dismissal identity. Durable work remains in its owning store.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Typed visual feedback         | `apps/ios/Merian/Core/UI/Feedback/{Models,Policies,Presentation,Coordination,Services}/`, `ToastPayload.swift`, `apps/ios/Merian/Core/UI/Modifiers/MerianSystemFeedbackModifier.swift`                                                                                                                                                                                                                                                                                                                                                                                                                        | Lightweight severity/action-typed ordinary toasts plus the bounded, deduplicated, session-fenced milestone queue. Models and policies are effect-free; Presentation owns only the FIFO queue and host registry; Coordination sequences scan milestones through injected effects; Services is the sole live network/Auth/Offline Sync/SwiftData/gamification adapter. A foreground-host registry serializes nested rendering, while identity-keyed structured tasks, injected milestone time, and one-time effect claims prevent stale teardown and remount replay. Passive feedback remains pass-through.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Framework publisher bridge    | `apps/ios/Merian/Core/Hardware/Utilities/Publisher+MainActor.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Ordered asynchronous hop from framework Combine publishers with unknown originating executors to a compiler-declared `@MainActor` receive closure. The synchronous app bus does not use this bridge.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Detached work helper          | `apps/ios/Merian/Core/Concurrency/DetachedWork.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Sole owner of the searchable `DetachedWorkCategory` taxonomy and cancellation-propagating `DetachedWork` wrapper for intentional detached image, database, file-system, and bootstrap work.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |

Shared species values live under `apps/ios/Merian/Models/Species/`:
`SpeciesData`, observation values, deterministic display/identity policy, and
rich lookalikes remain Foundation-only and effect-free. Inference-specific
capture telemetry and the handwritten `EdgeResponse` adapter live under
`apps/ios/Merian/Core/AI/Models/`; generated wire DTOs remain in Core Network.
Mirrored value tests live under `apps/ios/MerianTests/Models/Species/`, while
Core AI owns telemetry-construction and Edge-mapping tests. Capture Submission's
`apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionTelemetry.swift`
owns native-default zoom normalization, and its policy suite retains the
separate regression.

The root Models values are intentionally small cross-feature vocabulary.
`QueuedScanContext`, `ScanQueueState`, and `UserReviewState` remain
Foundation-only and effect-free. `Core/Data/OfflineSync/Policies` owns local
queued-media byte inspection,
`Core/Data/OfflineSync/Persistence/OfflineQueueManager+QueuedScanExtraction.swift`
owns main-actor live-row-to-context projection, `Features/Insights` owns
queued-to-active media presentation and focus-descriptor restoration, and
`Core/Data/OfflineSync/Persistence` owns cloud-deletion task/job mutations.
`Models/ActiveSchema` contains the V51 model declarations and deterministic
model/value accessors, never a `ModelContext` fetch workflow. The Models-wide
architecture suite freezes those boundaries and exempts only the ordered
historical migration registry from the 600-line review ceiling.

The app-wide hygiene closure suite scans every Swift source under
`apps/ios/Merian` and freezes the only files above 600 lines:
`App/UITesting/UITestSeedCoordinator.swift`, the measured residual
`Core/Network/SupabaseManager.swift` facade, and the ordered
`Models/SchemaVersions.swift` migration registry. Ordinary production files,
including Explore Feed's post-detail host, remain within the ceiling. This guard
complements rather than replaces domain-specific ownership, dependency, and
tighter line-budget suites. The closure audit also folds Field Notes' request
and feedback values into `FieldNotesEditPolicy.swift` and its caller
configuration into `FieldNotesEditorDependencies.swift`, avoiding three
single-purpose micro-files without changing their declarations or call sites.

## Active SwiftData Schema

The active schema is:

```swift
typealias CurrentSchema = MerianSchemaV51
```

`MerianSchemaV51` is declared in `apps/ios/Merian/Models/SchemaVersions.swift`.
The two checksum-distinct V50 graphs are frozen in
`Models/Schema/SchemaV50Snapshots.swift` and
`Models/Schema/SchemaV50ReleasedActiveSnapshots.swift`; checksum selection
routes each to its own immutable V50→V51 source bridge. V47 through V50 remain
available for fixtures and source-specific startup recovery.

Active persistent models:

- `LocalScanRecord`
- `OfflineQueuedScan`
- `OfflineJobRecord`
- `OfflineQueueEvent`
- `CapturedMediaEntry`
- `ScanCollection`
- `PendingCloudDeletionTask`
- `UserSpeciesPreference`
- `OfflineQueuedScanGoalHint`

The active graph retains the SwiftData tombstone source rename. The
`ScanCollection.isPendingDeletion` property maps to the released `isDeleted`
column with `@Attribute(originalName:)`; the outgoing `is_deleted` wire field
and acknowledgement-only purge contract remain unchanged. V51 additionally
partitions `UserSpeciesPreference` by account with a stable
`owner UUID|scientific name` identity. The canonical schema and recovery
contract is in the
[SwiftData schema contract](./backend-and-data/04-database-schema.md#scancollection-user-albums).

Recent schema milestones:

- V40 introduced `capturedMediaJSON` and `coverImagePath` as scalar mixed-media
  durability mirrors.
- V41 introduced `CapturedMediaEntry` and relationship mirrors for queued and
  completed scans. Current video entries store `StoredVideoMediaReference`
  (`video` plus poster `thumbnail`) in `capturedMediaJSON`; relationship rows
  are compatibility mirrors and should not be treated as the richer source of
  truth.
- V42 added first-class `fieldNotes` columns to `LocalScanRecord` and
  `OfflineQueuedScan`, while preserving the legacy UserDefaults bridge through
  `FieldNotesRepository`. V42 stores now use a source-isolated startup recovery
  plan that jumps directly to V49, avoiding the older V42→V43 bridge that still
  failed on real TestFlight stores.
- V43 introduced AI-derived sex observation metadata on completed local scans.
  V43 stores also use a source-isolated startup recovery plan before the V43→V49
  repair path.
- V44 added optional dog/cat pet-identification display metadata on completed
  local scans.
- V45 added optional invasive-status context to completed local scans. V46 was a
  shipped no-op checksum twin of V45; runtime migration keeps the
  duplicate-prone V44/V45/V46 recent cluster out of the full historical plan,
  jumps older stores V42→V49 or V43→V49, and uses source-isolated recent plans
  for stores already stamped V42, V43, V44, V45, or V46. V44, V45, and V46
  stores jump through separate direct V44→V49, V45→V49, and V46→V49 plans.
- V47 added offline video inference replay fields so sampled frames can be
  queued separately from the user-visible playback video timeline. Its frozen
  schema keeps local-scan, captured-media, and collection models self-contained
  inside V47, and keeps `OfflineQueuedScan` scalar-only.
- V48 added durable queue retry metadata on `OfflineQueuedScan`, plus
  `OfflineJobRecord` and bounded `OfflineQueueEvent` rows for scan ingestion,
  cloud deletion, collection sync, diagnostics, and future offline work. The
  V47→V49 migration is custom, not lightweight: every existing queued scan must
  leave migration with retry fields initialized and a `scan-ingestion:{id}` job
  row so startup can recover persistently on stores with queued media. V47
  job/event rows and replacement queued-scan rows are seeded from migration
  snapshots so stale SwiftData model-identity traps cannot survive into V49.
- V49 is a startup store-repair schema. It keeps the V48 queue scheduler model,
  adds `OfflineQueuedScan.queueSchemaRepairGeneration`, and provides separate
  V48→V49 plans for the known-good V48 checksum and the accidental
  optional-queue V48 TestFlight checksum. Startup diagnostics record redacted
  store metadata and attempted plan names so failing devices can share evidence
  without exposing paths, account data, scan text, or media URLs. The existing
  integer remains an inert released-compatibility field in V51; the current
  queue runtime neither reads nor mutates it. Removing it would alter the model
  shape and requires a future intentional migration. `MigrationPlanTests`
  carries the disk-store fixture matrix for image, video, audio,
  description-only, and mixed queued media, and
  `.github/workflows/ios-startup-safety.yml` runs that suite beside store
  recovery and focused image-loading ownership tests.
- V50 adds `OfflineQueuedScanGoalHint`, a scan-keyed companion containing the
  optional standard-outing and checklist-item preference for a queued scan. Its
  original and processed-release graphs are pinned in `SchemaV50Snapshots.swift`
  and `SchemaV50ReleasedActiveSnapshots.swift`; the lightweight V49→V50 stage
  leaves `OfflineQueuedScan` unchanged.
- V51 makes preferred species names account-scoped in SwiftData. Because V50
  rows and defaults carry no trustworthy owner, the custom V50→V51 stage deletes
  source rows before the new unique identity is materialized, and the startup
  bridge discards any residue rather than assigning it to the next account. V49
  stores use `[V49, frozen V50 bridge, V51]`; V50 stores use the
  checksum-matched source-isolated `[exact V50 graph, V51]` plan. Older recent
  plans reach V49 before applying both forward stages. The recent-source enum is
  consecutive through V50, dispatch is exhaustive, and checksum retry order is
  current store followed by both V50 graphs, then V49 through V42.

Compiled iOS assurance lives in `.github/workflows/ios-build-and-test.yml`. Its
fail-closed detector (`scripts/ci-detect-ios-build-source-changes.sh`) sends
every iOS/watch/project build input, merge-queue commit, and manual request to
pinned Xcode 27.0 (`27A266a`) jobs on the arm64 `xcode-27` runner that execute
the complete unit-test target, then the four deterministic
progressive-analyzing, live-to-queue, queued-retry, and queued-completion UI
smokes, and independently create an unsigned current-SHA Release archive without
allocating a release build. Distribution is owned solely by Xcode Organizer
after the exact SHA passes the full iOS workflow. Operators archive a clean
`main` checkout with the Merian scheme, choose **TestFlight & App Store**, and
leave automatic signing plus **Manage version and build number** enabled. Xcode
and App Store Connect own the unique uploaded build number; GitHub has no Apple
signing or upload credentials. `scripts/check-ios-release-prep.sh`,
`scripts/ios-release-source-fingerprint.sh`, and
`scripts/embed-ios-build-provenance.sh` require a clean exact revision and bind
its fingerprint/state into the app. The tracked `CURRENT_PROJECT_VERSION`
remains a synchronized archive baseline rather than a per-beta counter. CI
verifies this boundary and produces only an unsigned validation archive. The
processed App Store Connect build is then promoted without rebuilding between
TestFlight and App Review stages. The authority decision is documented in
`docs/system-architecture/09-ios-release-publisher.md`; setup, archive,
verification, upload, promotion, and emergency procedures live only in
`docs/development-guides/14-ios-release-versioning.md`. Fingerprinting rejects
tracked `assume-unchanged` and `skip-worktree` index state so sparse or locally
hidden files cannot masquerade as a complete clean release checkout. The embed
phase also rejects traversal, a final plist symlink, or a multiple-hard-link
plist before writing provenance outside the canonical product build directory.
`scripts/check-ios-project-resources.sh` additionally proves the preflight and
embed phases are defined once, invoke only the canonical scripts, belong only to
the main `Merian` target, and occupy the required first and final
product-mutating positions. Its portable detached, duplicate, wrong-command, and
phase-order fixtures live in `scripts/test-check-ios-project-resources.sh`.
`scripts/check-ios-project-source-membership.sh` compares every `project.yml`
source against the generated build phases and rejects source code orphaned
outside all declared targets; its adversarial fixture is
`scripts/test-ios-project-source-membership.sh`.
`scripts/test-ios-build-and-test-workflow.sh` locks the complete unit-target and
exact queued-scan UI selectors, invocation of that membership check, exact-SHA
and lockfile behavior, immutable action pins, focused-result validation,
archive/dSYM checks, and unconditional final decision. Repository rules should
require only `iOS Build and Test / Production readiness`. On failure,
`scripts/extract-ios-test-failure-diagnostics.sh` reads the structured result
summary first, then the failed test tree, and uses the raw build log only as a
fallback. Its fixture test prevents expected negative-path application logs from
replacing the actual failed test and assertion in the job summary.

Backend candidate assurance lives in **Supabase Candidate Validation**
(`.github/workflows/supabase-candidate-validation.yml`). A fail-closed scope job
runs on every pull request and reports the stable **Candidate readiness** check;
manual candidate refs, merge-queue commits, and `.github/workflows/deploy.yml`
force complete validation. The scope covers the full contract-input roots and
unresolved or unclassified comparisons fail closed. The workflow can then verify
a clean exact SHA with pinned tools, full migration replay, discovered pgTAP
catalogs, Edge/database-concurrency tests, lint, and advisors against a
disposable database. It has no Production environment, production secrets, or
mutation step. The production workflow's separate `deploy` job depends on this
gate and is the only job that receives Production access, pushes migrations,
deploys Functions, or runs production smokes.

Historical schema snapshots V1 through V39 live under
`apps/ios/Merian/Models/Schema/`. V40 through V49 live in `SchemaVersions.swift`
alongside the migration plan; the two released V50 graphs are frozen in
`SchemaV50Snapshots.swift` and `SchemaV50ReleasedActiveSnapshots.swift`, while
their bridges, the active V51 owner, and migration plans remain in
`SchemaVersions.swift`.

## Feature Modules

| Feature            | Current files                                                                  | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capture            | `apps/ios/Merian/Features/Capture/`                                            | Product-area-first capture surface. `Shell/` owns the three-page Scan/Record/Describe pager, fixed overlay chrome, the sole root `CameraSheetRouter` host, route consumption, exact dismissal handoff, root view model, pending Photos-import handoff, draft mutation/file cleanup, and the non-blocking active-goal indicator/deep link. Feature-local description/question/video/crop/survey presentations report the same UIKit slot as occupied without becoming global routes. `Core/Models/CaptureGoalContext.swift` defines the source-agnostic goal, provider, typed destination, and app-injected account cache; the Field trips feature is the first provider. `Staging/` owns the ephemeral mixed-media aggregate, canonical chronology and capacity/media values, plus description/crop presentation timing. `Submission/` owns staged-to-request projection, live/replay timelines, hand-written Identify descriptors, shared live/offline admission and analysis orchestration, normalized staged payloads, and the typed foreground/queue-only route. `Refinement/` is reserved for reanalysis helpers; `Shared/` holds cross-mode capture primitives.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Scan               | `apps/ios/Merian/Features/Capture/Scan/`                                       | Visual-modality preview, focus/zoom/photo/video actions, platform-neutral media request/result values, narrow camera/context/Photo Library/media/entitlement/feedback adapters, bounded still preparation, sampled-frame/playback/WAV video preparation, and generation-fenced recording/progress task ownership. Views/components contain no networking or global service resolution, and every production Scan file stays below the 600-line guard. Core Hardware owns session/device configuration through `CameraSessionController`, exposes observable/delegate state through `CameraManager`, and owns the movie/audio recording boundary through `CameraVideoRecordingService`. Shared crop encoding lives in `Core/Media`; the shared crop view lives in `Core/UI` while the presentation-only flash control lives in Capture Shell; Capture source/crop metadata remains in `Capture/Shared`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Record             | `apps/ios/Merian/Features/Capture/Record/`                                     | Audio Listen Mode presentation split across platform-neutral `Models`, the only concrete manager/haptic adapter in `Services`, UI-only idle/scrub state in `ViewModels`, a thin `Views` composition, and focused `Components`. Shell resolves the live manager snapshot and retains microphone permission and record/pause/resume/stop/review controls; Submission retains staging and live-attempt admission, while `Core/AI/Inference/Request` owns `/identify-multimodal` request mapping and dispatch. `Core/Hardware` owns the 15-second Int16 WAV engine, playback, FFT, rolling ambient-noise policy, and token-aware audio-session leases. `Core/Media` owns shared spectrogram raster/layout policy, `Core/UI` owns the shared SwiftUI spectrogram, and `Capture/Shared` owns the audio/video countdown badge. Record views issue no endpoint calls and every production Record file stays below the 600-line guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Describe           | `apps/ios/Merian/Features/Capture/Describe/`                                   | Typed and dictated observation presentation. `Models/` owns prompt/subject values, taxonomy resolution, exact text composition, and stable tag ranking; `Services/` owns live preference, haptic, keyboard, subject-delay, and speech-manager adapters; `ViewModels/` owns prompt/funnel state plus generation-fenced subject inference and dictation sessions without constructing concrete hardware adapters; `Views/` retains the page, workspace lifecycle observer, focus, and sheet timing; and `Components/` owns the UIKit scroll host, navigation, tags, and editor. Views/components resolve no singleton or platform action, Models remain platform-neutral, and every production Describe file remains below the 600-line guard. Cross-feature `SpeechManager` and its lifecycle tests live in `Core/Hardware`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Insights           | `apps/ios/Merian/Features/Insights/`                                           | Product-area-first result feature. `Shell/` owns presentation sessions, completed-scan routes, navigation, and generation-fenced result activation; `Content/` owns biological/non-biological results and queued/foreground analysis UI; `IdentificationReview/` owns candidate and confidence workflows; `Media/` owns Insight page assembly, continuity, focus, availability, inline video, boost policy, and scan-to-export request mapping; `FieldNotes/`, `Sharing/`, and `Toolbars/` own their named subareas; and `Shared/` contains only Insight-specific cross-subarea presentation. Core Media/UI own export processing and reusable carousel playback/gallery primitives. Species Reference and Field Chat are independent cross-feature owners.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Species Reference  | `apps/ios/Merian/Features/SpeciesReference/`                                   | Cross-feature species-level charts, habitat, GBIF heatmaps, taxonomy, lookalikes, and fallback reference imagery used by Insights, Explore, Species Dictionary, and identification review. Platform-neutral Models own aggregation/presentation policy; Services alone resolve SwiftData, endpoints, external sessions, image loading, haptics, and enrichment; generation-fenced ViewModels publish async state; Views and domain Components retain task identity, gestures, scrolling, placeholders, and UI-only timing. Every production file remains below 600 lines.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Field Chat         | `apps/ios/Merian/Features/FieldChat/`                                          | Cross-feature private Pro conversation experience used by Insights, Explore posts, and Species Dictionary pages. Platform-neutral `Models/` own source and presentation values; `Services/` alone resolve live endpoint, haptic, telemetry, clipboard, clock, and request-ID dependencies; `ViewModels/` own subject-generation-fenced conversation, prompt, feedback, availability, and review state; and `Views/` plus grouped `Components/` retain rendering and UI-only timing. Host features own eligibility, entitlement, navigation, and sheet occupancy. Core Network retains Codable DTOs, strict validation, and transport. Stable `InsightChat...` names remain source-compatible. Every production Field Chat file stays below the 600-line guard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Scans              | `apps/ios/Merian/Features/Scans/`                                              | Product-area-first private scan library. `Shell/Models` owns tabs, typed routes, session fencing, and UI-only incident presentation; `Shell/Services` owns queue/record SwiftData reads, account-scoped overview preferences, thumbnail prefetch/backfill/cloud repair, and service-specific repository/loader/actor/event adapters; `Shell/ViewModels` owns queue polling policy, incident loading/coalescing/cancellation/account fencing, store synchronization, selected-record mutations, and the narrow auth/endpoint/event/time/badge dependency value for that state; `Shell/Views` retains only navigation, pager, focus, alert, animation, and lifecycle presentation timing; and `Shell/Components` owns toolbar, tab composition, and presentation modifiers. Shell views/components make no endpoint, Supabase, shared-loader, actor, or app-container lookup. The private queued route retains `QueuedScanContext` while hashing by ID, and the destination treats a persisted same-ID completion as authoritative on every bind. `Library/` owns individual scans, `ScansManager` observable state/actions and event sink, the contained generation-fenced `ScansLibrarySearchCoordinator`, feature-local search/filter models and actors, the advanced filter component, injected export/publication/event/haptic adapters, queued completion-race hydration, and mixed photo/video batch-save feedback. Library views/components resolve no endpoint or singleton. `Collections/Models` owns membership, cover, catalog, and smart presentation values; `Collections/Services` owns save-first validation/mutations, smart suggestion policy, local smart preferences, and narrow event/share-state/sync/feedback adapters; `Collections/ViewModels` derives catalog, detail, selection, and smart-detail state from the Shell-owned record query; `Collections/Views`, `Components/Cards`, and `Components/Catalog` retain navigation, search, timer, lifecycle, and Collections-local presentation; and `Components/Alerts` owns collection-action presentation consumed by Collections, Scans Shell, and Insight. Collections views/components perform no SwiftData fetch or singleton lookup. `Map/Models` owns exact owner-coordinate snapshots, region/annotation geometry, and presentation values; `Map/Services` owns detached SwiftData projection, the revisioned store/index, lossless refresh and sensitive-reset fencing, MapKit/Web-Mercator clustering, viewport work, startup/current-location sequencing, and preview rendering; `Map/ViewModels`, `Map/Views`, and `Map/Components` own presentation state and UI with no endpoint calls or direct persistence reads. Scans Shell remains the typed Insight route owner. `NonBiological/Models` owns correction/copy values plus refresh and erasure snapshots; `NonBiological/Services` owns retention purge, actor-isolated database/file deletion, library invalidation, deletion sync, route, and feedback adapters; `NonBiological/ViewModels` derives the isolated record set from the Shell query and owns mutation lifecycle; and its thin View/Components retain only navigation and presentation timing. Non-biological views/components perform no persistence reads, actor construction, or singleton lookup. `BackgroundDatabaseActor` is the commit-time deletion authority: it re-fetches every candidate and skips a row reclassified as biological before accepting its record, local-path, or cloud-deletion mutation. `Shared/Models` owns detached queued-row values, `Shared/Services` owns injected grid feedback and single-delete orchestration, `Shared/Components/Grid` owns the Scans-only composite grid, and `Shared/Modifiers` owns deletion alert presentation. Shared views/components perform no fetch, endpoint, loader, repository, or app-container lookup. Cross-feature `ScanThumbnail` and `EmptyStateView` presentation lives in `Core/UI`; immutable thumbnail-backfill inputs live with the actor in `Core/Data/Images`. Every production Shell, Library, Collections, Map, NonBiological, and Shared file remains below the 600-line review guard. |
| Explore            | `apps/ios/Merian/Features/Explore/`                                            | Product-area-first public discovery feature. `Shell/` owns the root sheet/router, conversion from typed capture-goal and progress-toast destinations into focused standard Field trip checklist-item routes or Seasonal Challenge detail routes, device-local completed-goal scan lookup and embedded Insight routing, stack-based author-profile routing, the profile-to-scan nesting cap, and scoped video playback coordinator; `Feed/` owns observations feed, post detail, comments, hashtags, feed interaction state, the shared feed/detail media host, feed center Play/Pause versus outer navigation gesture policy, surface-aware video mute transitions, standalone-audio spectrogram playback with a display-synchronized live-clock playhead, and device-local per-post audio boost preferences/DSP; `Map/` owns the map surface; `Identify/` owns Community ID requests/activity; `FieldTrips/` owns its typed cross-surface routes, public Field trip Outings and Events, Goals/Tips detail, completed-scan thumbnails, Seasonal Challenges, guided template detail, focused target expansion/highlighting, its capture-goal provider mapping, progress, publication/challenge-entry detail, badges, and profile modules; `Notifications/` owns Explore activity notifications; `AuthorProfile/` owns public author routes, profile/library presentation, injected loading/pagination/follow/report state, and feature-grouped components, with live networking confined to its `Services/` adapter; `Shared/` holds cross-area Explore presentation and lifecycle helpers, including customer-safe error mapping and the Feed/Field Trips wrapping layout; and `Widgets/` writes the image-only Explore widget cache. Core UI owns the published-scan grid geometry shared by Author Profile, Profile, and Species Dictionary.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Messages sharing   | `apps/ios/messages/ScanSharing/`, `apps/ios/messages/MerianMessagesExtension/` | Shipped iMessage sharing surface. `MerianMessagesExtension/` owns the extension UI, `ScanSharing/Shared/` owns the App Group cache model read by both targets, and `ScanSharing/AppSupport/` owns the containing-app cache writer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Profile            | `apps/ios/Merian/Features/Profile/`                                            | Product-area-first account feature. `Shell/` owns the profile/settings pager, close chrome, and composition of the environment-owned geoprivacy and hardware adapters required by Settings; `UserProfile/` owns the public profile card, published scans, Field trip profile modules, achievements, persona, terrarium, heatmap, and Profile stats actor. Within `UserProfile/`, Models hold feature values/policy, Services resolve live endpoints plus imperative SwiftData, image, event, route, preference, and haptic boundaries, and ViewModels own generation-fenced asynchronous state. Views/Components retain presentation state and rendering; the publication grids keep a read-only local-scan query only for reference-image fallback on already server-visible posts. `Settings/` owns preferences, privacy/processing withdrawal, optional analytics, geoprivacy, export, resources, and danger-zone account actions. Its Models contain presentation values, Services contain narrow account/export/preference/platform action adapters, and ViewModels own serialized, single-flight, or generation-fenced lifecycle state. Leaf Views/Components retain route, binding, focus, animation, reactive environment reads, and rendering state without endpoint, direct SDK-write, repository, or action-singleton lookup. Deterministic account-deletion classification/sequencing lives in `Core/Network/Auth/`; `SupabaseManager` retains live protocol/recovery effects and durable Apple fallback recording, while Settings injects the local purge adapter. `Settings/Plan/` and `Settings/Feedback/` repeat the full Models/Services/ViewModels/Views/Components boundary for RevenueCat and survey submission; `Settings/Notifications/` uses Models/Services/ViewModels/Views for push preferences; and `Settings/Changelog/` owns local Models/Views release notes. Complimentary-scan display state is Plan-owned, Profile-only fading scroll is Stats-owned, and `Shared/` holds cross-area profile state such as `ProfileViewModel`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Species Dictionary | `apps/ios/Merian/Features/SpeciesDictionary/`                                  | Product-area-first species reference feature. `Detail/` owns the public species page, UUID-first readable share action, reference gallery, and authenticated Community sightings preview/paginated grid. `Catalog/Models` owns normalized browse selections/page requests, overview presentation policy, country flags, and the typed category route; `Catalog/Services` alone resolves the live dictionary endpoint, cached image loader, geocoder, and MapKit snapshotter; generation-fenced `Catalog/ViewModels` own catalog, overview, and region-map state; its three thin root Views plus grouped Components retain search, refresh, navigation, and rendering without direct networking. Selection changes fence initial and pagination work before search debounce, including reverted and failed replacement identities. Core Network retains Codable wire DTOs and transport, while Explore Shell owns Identify/Species selection, the shared navigation stack, and the overview model lifetime for one Explore presentation. Catalog owns five-minute same-country reuse and refresh policy. Mirrored Catalog tests enforce those boundaries and a 600-line production-file ceiling. Species is the sole dictionary browser; taxonomy remains catalog/detail metadata and has no separate route. External UUID and UUID-plus-slug links enter through the shared deep-link parser and `CaptureWorkspaceViewModel`, then select Explore Identify/Species before opening this detail in its stack.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Onboarding         | `apps/ios/Merian/Features/Onboarding/`                                         | Product-area-first permission and consent flow. `Shell/Services` alone resolves live settings, consent, telemetry, queue recovery, and animation policy; its state owner sequences Welcome → Camera → Location → Ready and fences duplicate or late step completions. `Steps/` owns copy, layout, UI-only state, shared chrome, and the Ready Models/ViewModel/Components projection without native permission calls. `Permissions/` owns the AVFoundation adapter and one-shot `@MainActor` Core Location delegate, which re-enters the actor before reading authorization state from a nonisolated callback. `MerianApp` injects its selected app-scoped managers and keeps completed users outside the shell while required account evidence is unresolved; only a resolved absence routes them directly to Ready. Mirrored feature tests enforce the ownership boundary, callback-isolation order, and 600-line ceiling, while Core Security owns consent ledger, restoration, authority, lifecycle, and reapproval tests.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

Within Species Dictionary Detail, platform-neutral `Models/` own request, state,
share, presentation, and telemetry policy; `Services/` alone resolve the
dictionary and Community endpoints, telemetry, haptics, entitlement, fallback
Explore state, and Field Chat state; and generation-fenced `ViewModels/` own
page and Community loading. The standalone shell and shared content View retain
navigation, presentation, scroll, and lifecycle timing. Grouped
`Components/{Community,Content,Gallery,Loading,Shared}` render without direct
networking. Mirrored Detail tests enforce stale-completion fencing, endpoint
adaptation, ownership boundaries, and a 600-line production-file ceiling; Core
Network retains wire DTOs and transport.

`SpeciesDictionary/Shared/Models` owns the route and entry-point values,
taxonomy bridge, and reference-image labels/attribution used across Catalog,
Detail, Explore, and Field Trips. Core Network separately owns canonical
UUID/name normalization, exact schema/response-identity validation, transport,
and the bounded memory cache. The backend generated
`species_dictionary.is_public_biological` value is authoritative before catalog
keysets and overview/country aggregation. Mirrored Shared architecture tests
keep that folder platform-neutral and free of networking.

Within Insights Sharing, `Models` owns platform-neutral Share copy and action
projection; `Services` alone resolves publication, Community, detail,
share-state, cache, event, and feedback effects; `ViewModels` owns the focused
root-state extensions, contained reconciliation clocks, and observable Community
request draft; and `Views` plus `Components` retain rendering and UI-only
timing. Sharing views/components contain no networking, the former
Explore-sharing aggregate and nested Community view path are absent, and every
production Sharing Swift file stays below the 600-line review guard.

Within Insights Content, `Models` owns fact data, custom-tag validation,
queued-retry copy, and queued phrase/rotation policy; `Services` alone resolves
preferred-name persistence, ordered and account-bound Supabase tag
synchronization, queue scheduling/mutation, durable queue snapshots, app events,
and haptic feedback; and `ViewModels` owns fact-deck, tag-transaction, queued
retry, name-preference, and Content action state. `Views` retains lifecycle
tasks, bindings, selection, animation, and Debug fixture timing; grouped
`Components` renders cards, Field-trip progress, header, queue recovery,
scanning, and tags without direct networking.
`Core/UI/Components/NamePickerSheet.swift` is the cross-feature display-only
name chooser. Mirrored tests under `MerianTests/Features/Insights/Content` lock
these boundaries, rollback and effect ordering, ordered tag synchronization,
queue request identity, legacy-owner removal, and the 600-line production-file
ceiling.

Within Species Reference, platform-neutral `Models` own observation and heatmap
presentation policy; `Services` alone resolve the local SwiftData projection,
public observation endpoint, GBIF/Wikipedia sessions, bounded image loading,
haptics, and habitat enrichment; and generation-fenced `ViewModels` publish
observation, heatmap, and fallback-image state. `Views` owns the chart
composition and task identity, while domain-grouped `Components` retain
rendering, map gestures, gallery scrolling, retry timing, and other UI-only
state. Empty or replacement identities invalidate older work, pre-cancelled
valid loads do not claim a generation, and the chart owner clears cross-species
values without blanking a same-species refresh. Mirrored tests under
`MerianTests/Features/SpeciesReference` enforce these boundaries, checked
feature sendability, removal of the former `Cards`/`Utilities` owners, and the
600-line production-file ceiling.

Within Insights Media, `Carousel/Models` owns platform-neutral selection, focus,
image-origin, and availability policy. Its `CarouselSelectionCandidate` contract
prevents the policy layer from depending on SwiftUI-backed page values.
`Builders` owns page assembly and transient availability; `Services` adds
Insight telemetry and feedback naming to the Core playback dependency; and
`Playback` owns only inline-video state plus the stable pause coordinator. Root
carousel views, `Pages`, and `Components` retain Insight-only selection, focus,
animation, and mounted inline state without networking or direct singleton
resolution. Media export maps scan state to Core requests in a session-fenced
view-model extension. Mirrored tests under `MerianTests/Features/Insights/Media`
lock those boundaries and the 600-line production-file ceiling. The image
renderer shared by Insights, Explore, Field Trips, and Species Dictionary is
`Core/UI/Components/AsyncLocalImageView.swift`; its live `LocalImageLoader`
resolution belongs to `Core/UI/Services/AsyncLocalImageDependencies.swift`. The
domain-neutral native pager, page identity and gallery values, zoom host,
pagination dots, fullscreen gallery, audio page, and reusable video chrome live
in `Core/UI/Components/MediaCarousel`; feature-owned page values project their
own stable controller-reuse keys into that boundary. Equal ID/reuse keys
preserve a mounted controller; a sequence or key change invalidates the native
data-source cache before the selected page is reinstalled.
`Core/UI/Modifiers/TopToolbarAppearance.swift` owns the transparent top-toolbar
modifier applied directly by native scrolling views, lists, and forms.
`Core/Media/MediaExportService.swift` owns bounded export and share preparation
for both Insight and Scans.

Within Capture, Scan's contained task owner generation-fences still shutters,
video admission/start, recording, and progress work. Shell invalidates pending
visual generations across scene, mode, presentation, teardown, and reset
transitions while preserving graceful stop-and-stage behavior for an active
video. `CameraPreviewView` consumes the environment-injected `CameraManager` as
its single session and zoom owner; it does not resolve the singleton.

Within the Scans row, `ScanQueueState.isManualRetryEligible` is the canonical
grid/Insight value-level retry baseline; mutation owners still re-fetch and
revalidate the durable row. Cross-feature `ScanThumbnail` delegates media work
to `Core/UI/Services/ScanThumbnailLoader.swift`. That service
cancellation-fences shared cache work, while the view's typed task identity
includes every source/policy input that can require a replacement load. Scans
Shared's live grid-feedback and deletion-presentation adapters remain main-actor
owned.

The long-term ownership and extension contract for the Capture/Explore goal seam
is recorded in
[`docs/rfcs/active-capture-goal-context.md`](rfcs/active-capture-goal-context.md).

Within Capture Shell, `Models/` owns deterministic media and presentation policy
plus the normalized navigation-badge snapshot, `Services/` is the only Shell
owner that constructs live clients, sessions, remote-media/prewarm work,
share/account lookup, keyboard platform, app-badge coordination, and feedback
adapters, and `ViewModels/` owns the root state plus routing, imports, staging,
refinement, lifecycle orchestration, and generation-fenced badge refresh.
`CaptureControlDependencies` is the narrow live adapter for control-row
entitlement reads, keyboard dismissal, paywall telemetry, and semantic haptics.
`CaptureNavigationDependencies` is the narrow live adapter for Explore badge
loading, settings mutation, badge coordination, and route feedback. The keyboard
service owns the raw UIKit notification publishers and actions; the mounted
modifier only binds them to SwiftUI presentation state. An encapsulated
operation-state owner keeps task handles, one-shot routes, import coalescing,
timeout fences, and crop ordering in private storage. `Views/`, grouped
`Components/`, and `Modifiers/` retain UI-only pager, focus, expansion,
presentation, control gesture/task cancellation, and dismissal timing without
direct endpoint calls. `Shell/Components/CaptureControls` owns row composition,
the primary press lifecycle, and mode-specific secondary controls;
`Shell/Components/ModeSelector` owns the native Capture selector and
`Shell/Components/Navigation` owns the workspace navigation bar;
`Shell/Models/CaptureControlBarPresentation` owns deterministic chrome
projection. The selector coordinator converges UIKit value-change and primary-
action events through one guarded binding update and snapshots the mode
identifiers, selection, and appearance before reinstalling segment artwork.
Pending presses are invalidated across mode, inactive-scene, suppression,
disablement, and disappearance changes, while visual Pro eligibility is sampled
only when a hold matures. Mirrored tests under
`apps/ios/MerianTests/Features/Capture/Shell/` lock these boundaries, feature
ownership of the control surface, raw-notification confinement, deterministic
Models, and the folder's 600-line production-file ceiling. Fixed control-row
geometry, the pure `CaptureMode` value, and the platform-neutral haptic
vocabulary shared by Shell, Scan, Record, and Describe live in
`Capture/Shared/Models`; the composing-center SwiftUI environment contract lives
in `Capture/Shared/Utilities` because Shell supplies it and Record consumes it.
The immutable `SendableCGImage` wrapper lives in `Core/Media` because Capture
and Insights both use it across concurrency boundaries.

The reanalysis description seam spans those existing owners: Staging owns the
refinement-only supplementary marker and evidence-capacity policy; Shell owns
session reset, tray edits/removal, editor consumption, and dictation-request
transitions; Submission owns the explicit empty/staged/rejected result and
projection into unchanged request/replay values. The stable
`CaptureWorkspaceViewModelRefinementTests` selector includes
`CaptureWorkspaceRefinementDescriptionTests` and `CaptureRefinementReplayTests`.
See the
[Describe contract](features-and-hardware/11-describe-and-voice-dictation.md)
for behavior and the
[test matrix](development-guides/08-testing-strategy.md#reanalysis-description-verification)
for coverage and remaining runtime verification.

Within Capture Staging, `Models/` owns only the ephemeral `StagedCapture`,
capacity policy, modality wrappers, UIKit-backed image bundle, and the one
chronological `StagedCaptureNode` sequence plus the deterministic toolbar
projection. `Services/` owns the narrow Photo Library, keyboard, haptic, and
process-session tooltip adapters; `Components/Toolbar` owns the tray and its
UI-only picker, tooltip, shimmer, and admission-task state; and `Views/` owns
crop/description presentation timing. Those presentation layers make no endpoint
or persistence calls. Shell owns mutation, required-crop and automatic-submit
fences, and disposable-file deletion. Submission owns
`CaptureSubmissionMediaTimeline`, the aligned
`CaptureSubmissionMediaProjection`, and hand-written `Identify*` request/replay
descriptors; Core AI, network, database, and offline queue code consume those
stable values. `InferenceEngine` delegates the typed submission to
`InferenceLiveSubmissionCoordinator`, which stages the presentation and passes
the projection into `Core/AI/Inference/Pipeline`; the pipeline supplies exact-
attempt policy and delegates request preparation/dispatch to
`Core/AI/Inference/Request`. `CaptureStagingToolbarPresentation` filters the
canonical staged order for renderable video covers without a second sort.
Mirrored Staging, Shell, Submission, and Core Data Offline Sync suites own
state, toolbar projection, presentation, wire/replay, and connectivity-policy
assertions respectively.

Within Insight Shell, `Models/` owns deterministic presentation identities,
binding keys, and display projections; `Services/` owns the sole live network,
authentication, repository, routing, feature-access, badge, and feedback
resolution boundary; `ViewModels/` owns scan-bound state plus focused lifecycle,
record, capability, media, content, and presentation projections; and `Views/`,
`Components/`, and `Modifiers/` retain composition, navigation, presentation,
focus, scrolling, animation, and dismissal timing. `InsightContentPresentation`
and `InsightShellPresentation` are the two typed modal slots.
`InsightSheetViewModel+MediaPresentation.swift` and
`+PresentationIdentity.swift` own the former display aggregate's media and
identity seams; `InsightSheetView+Content.swift` owns root content/toast
routing, not Field-trip domain policy. Shell views and view models issue no
endpoint calls. Mirrored Shell, Content, FieldNotes, Media, and Sharing suites
enforce these boundaries, removal of both aggregate files, and the 600-line
ceiling for production files. The optional dependency parameter defaults to
`.live`, and queued completion polling is subject-, generation-, and
cancellation-fenced.

Within Insight Field Notes, `Models/` owns platform-neutral prompt, edit,
visibility-request, and feedback values; `Services/` alone adapts the Core
repository, shared speech manager, Explore visibility action, and haptic
feedback; `ViewModels/` owns editor state plus scan/generation-fenced mutations
on the Shell root; `Views/` owns composition, focus, dismissal, and autosave
task timing; and `Components/Card/` plus `Components/Editor/` own render-only
leaves. `FieldNotesRepository` remains in `Core/Data/FieldNotes` as the shared
SwiftData and legacy-bridge reconciliation boundary. Mirrored Field Notes tests
own edit, visibility, identity, and architecture coverage plus stable-baseline,
overlap, ownership, and automatic-termination dictation fences; repository tests
live under `Core/Data/FieldNotes`, while Share-cache refresh tests live under
`Insights/Sharing`. The former component and root-level test aggregates are
retired, and every production Field Notes Swift file stays below 600 lines.

Within Capture Record, feature files own only immutable presentation, narrow
manager/haptic projection, UI-only artwork and scrubbing state, and mounted
rendering. Core Hardware owns the stable `AudioCaptureManager` facade,
`SpectrogramActor`, and `AudioSessionCoordinator`.
`AudioRecordingEngineController` exclusively owns the engine, input tap,
canonical WAV, bounded PCM stream, DSP task, operation identity, recording
lease, and partial-file cleanup. `AudioReviewPlaybackController` exclusively
owns the review player, progress/completion tasks, playback generation, and
playback lease behind the manager API. `AudioReviewBoostController` owns the
review-only preference, cancellable preparation, and uncached temporary boost
copy; original WAV paths remain the sole staging and inference source. The
coordinator publishes one-shot lease ownership only after activation succeeds;
mode, background, reset, pause, stop, and replacement invalidate pending work
before it can start hardware or publish into newer Capture state. Mirrored Core
Hardware tests lock engine teardown order, WAV retention/deletion, route
recovery, manager- and controller-level duplicate-resume coalescing, transition
invalidation, stop-before-playback-activation cleanup, failed player-start and
completion-wait cleanup, stale playback completion rejection, unconditional
manager-reset cleanup, successful lease replacement, failed-activation
configuration restoration, rollback-failure invalidation, and first-activation
cleanup.

Within Capture Shared, `Services/ImageFocusRegionDetector.swift` owns the
Capture-only bounded Vision objectness request, exact 300 ms deadline and
cancellation bridge, deterministic candidate policy, and privacy-safe outcome,
duration, and coarse-area diagnostics. Scan, Shell imports, and Staging crop
confirmation reuse that service. Shared bounded ImageIO decoding remains in
`Core/Data/Images`; the detector owns no endpoint, app-container lookup, or
mutable singleton.

Within Capture Submission, `Models/` owns deterministic admission, media,
goal-preference, and latency policy plus normalized payload and sendable
environment-context values. `Services/` owns live admission/context composition,
telemetry formatting, the optional LiDAR/Vision `SizeEstimator`, the
actor-backed 150 ms context race, and the sole `/update-scan-context` adapter.
The estimator consumes the shared bounded `Core/Data/Images` decoder and remains
free of networking, app-container lookup, and UI. The deferred-context adapter
commits late context to the durable queue before remote delivery and performs at
most one remote retry after 500 ms; endpoint, transport, and task cancellation
are terminal. Submission cancels captured context work whenever no foreground
attempt will consume it. Only a timeout-losing accepted attempt keeps a
late-enrichment task, which retains the injected service and bounded telemetry
inputs rather than the workspace view model or full display-image collection.
Responsibility-specific `ViewModels/` extensions orchestrate visual, nonvisual,
Describe, admission, and presentation state without issuing endpoint calls. Live
Identify payload construction and dispatch belong to
`Core/AI/Inference/Request`, not these ViewModels. Submission has no view layer;
Shell and modality views retain UI-only timing. Mirrored tests under
`apps/ios/MerianTests/Features/Capture/Submission/` lock policy, context-race,
cancellation, retry, size-estimation, dependency, and architecture behavior,
including the 600-line production-file ceiling.

Scan media workers propagate structured cancellation into detached work and
lease newly created WAV/compressed-playback files until staging accepts them.
This keeps timeout-losing and otherwise unconsumed artifacts inside the Scan
service owner instead of leaving cleanup to views or process lifetime.

## Public Web App

The public web frontend lives in `apps/web/` and is intentionally separate from
the native iOS source tree.

| Area                       | Current files                                                                                                                                                                               | Responsibility                                                                                                                                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App shell                  | `apps/web/app/layout.tsx`, `apps/web/app/theme.ts`, `apps/web/app/globals.css`                                                                                                              | Mantine provider, global metadata defaults, theme, pre-hydration color-scheme bridge, and responsive page chrome.                                                                                                                            |
| Marketing/home placeholder | `apps/web/app/page.tsx`, `apps/web/lib/exploreMedia.ts`                                                                                                                                     | Lightweight landing surface with a public Explore grid that keeps visual heroes and uses species reference thumbnails for audio posts.                                                                                                       |
| Explore share page         | `apps/web/app/explore/post/[postId]/page.tsx`, `apps/web/components/ExploreMediaCarousel.tsx`, `apps/web/components/ExploreBoostedAudio.tsx`                                                | Server-rendered public post page with square ordered media, looping muted video, spectrogram-backed audio, optional local Boost Audio, metadata, and support reporting.                                                                      |
| Species share page         | `apps/web/app/species/[speciesId]/page.tsx`, `apps/web/app/species/[speciesId]/[slug]/page.tsx`, `apps/web/lib/species.ts`                                                                  | Server-rendered UUID-first readable Species Dictionary page with UUID-only/stale-slug redirects, strict versioned Edge mapping, rights-filtered reference imagery/metadata, native CTA, and textual lookalike navigation.                    |
| Web audio boost stream     | `apps/web/app/api/explore/audio/route.ts`, `apps/web/lib/audioProxy.ts`                                                                                                                     | Range-capable same-origin WAV stream restricted to public Naturebook media on the durable `media.merian.app` technical host; used only when a visitor activates browser-local Boost Audio.                                                   |
| Public beta waitlist       | `apps/web/app/api/waitlist/route.ts`, `apps/web/components/WaitlistForm.tsx`, `apps/web/lib/boundedJson.ts`, `apps/web/lib/waitlistSecurity.ts`                                             | 4 KiB streamed JSON boundary, conservative email normalization, explicit Turnstile widget/Siteverify flow, trusted-proxy daily IP HMAC, distributed pre-provider rate claim, stable request IDs, and service-only atomic database insertion. |
| Policy/support pages       | `apps/web/app/privacy/`, `apps/web/app/privacy-choices/`, `apps/web/app/terms/`, `apps/web/app/guidelines/`, `apps/web/app/support/`, `apps/web/app/legal/`                                 | App Store-friendly public policy, data-choice, community, support, and legal hub pages.                                                                                                                                                      |
| Legal/public components    | `apps/web/components/PublicPageShell.tsx`, `apps/web/components/LegalPage.tsx`, `apps/web/components/ThemePreferenceBridge.tsx`, `apps/web/lib/site.ts`, `apps/web/lib/theme-preference.ts` | Shared public page chrome, legal document layout, iOS-to-Mantine theme preference sync, support email/site URL config.                                                                                                                       |
| Supabase access            | `apps/web/lib/supabaseAdmin.ts`, `apps/web/lib/supabasePublic.ts`, `apps/web/lib/explore.ts`, `apps/web/lib/species.ts`                                                                     | Explicit `server-only` server-key client used only through scoped Explore/waitlist RPCs, separated from the anonymous Species Dictionary projection client, plus strict wire mapping.                                                        |
| Web response security      | `apps/web/proxy.ts`, `apps/web/app/layout.tsx`, `apps/web/lib/securityHeaders.ts`                                                                                                           | Per-request nonce CSP, nonce-bound bootstrap script, production HSTS, and explicit browser defense headers.                                                                                                                                  |
| Universal Links            | `apps/web/app/apple-app-site-association/route.ts`, `apps/web/lib/appleAppSiteAssociation.ts`, `apps/web/lib/canonicalHost.ts`, `apps/web/proxy.ts`                                         | Exact Explore/species AASA paths, direct legacy-host AASA exception, and canonical alias redirects constructed by assigning untrusted pathname/search onto fixed `CANONICAL_ORIGIN`.                                                         |
| Formatting helpers         | `apps/web/lib/formatting.ts`                                                                                                                                                                | Shared Naturebook web copy and URL formatting.                                                                                                                                                                                               |
| Local setup and CI         | `apps/web/README.md`, `apps/web/.env.example`, `apps/web/package.json`, `apps/web/lib/dependencySecurity.test.ts`, `.github/workflows/web-quality.yml`                                      | Web setup, waitlist secret/ingress contract, transitive security overrides, frozen dependency audit, tests, typecheck, and production build.                                                                                                 |

## Core Modules

`Core/Concurrency` owns the searchable `DetachedWorkCategory` taxonomy and the
cancellation-propagating `DetachedWork` primitive; `Core/Errors` owns the
localized `MerianError` taxonomy. Workflow actors, UIKit background execution,
transport classification, recovery, and presentation stay with their focused
domain owners.

Captured-media ownership intentionally spans focused layers. `Models/Media` owns
the Foundation-only cross-feature observation value, storage references, the
ordered Codable timeline, snapshots, summaries, and scalar JSON coding.
`Models/ActiveSchema` owns only the V51 `CapturedMediaEntry` declaration.
`Core/Media` owns filesystem and approved-HTTPS resolution plus active-media
mapping, while `Core/Data/CapturedMedia` owns cloud hydration/replacement,
injected file adoption and timeline serialization, and SwiftData mirror
persistence. Capture Submission owns the transport projection. The retired
`Models/ActiveSchema/SerializedMediaItem.swift` aggregate must not return.

| Core area                | Current files                                   | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ------------------------ | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AI                       | `apps/ios/Merian/Core/AI/`                      | `InferenceEngine` stable entry points and source-compatible observable read-throughs; `Inference/Lifecycle` effect-acquisition-free cross-owner ordering for scan replacement, exact background/queued-result and queued-record recovery, result/queue/cancellation/historical transitions, application activity, and Auth quiescence without another task, managed record, or mutable registry; `Inference/Presentation` separates stored observable processing/copy/media/species/queue/loading/telemetry values and named transitions from non-observable prepared/active presentation identity, exact visual queue phrase/media context, and one-shot first-render timing; `Inference/Media` value-only live visual/nonvisual timeline normalization, provider projection, active/persisted carousel mapping, focus-region carry-through, poster fallback, compatible local-path resolution, and HTTPS video policy behind injected filesystem values; `Inference/Pipeline` effect-acquisition-free visual/nonvisual submission staging and task launch plus singleton-free admission, request/result execution, benchmark placement, durable finalization, failure dispatch, modality-specific follow-up order, and exact-owner cleanup behind an injected circuit/refund/logging adapter; `Inference/Completion` accepted-result normalization, shared discovery/replacement/circuit/telemetry effects, committed biological events, exact-finalization authorization, and permit-gated notifications/milestones; `Inference/Request` injected visual/nonvisual request mapping, staged-video upload, and provider dispatch; `Inference/Result` injected live parse/save input normalization, typed persisted/no-record/rejected outcomes, tier confidence presentation bands, and synchronous persisted-replacement/metadata safety before repository deletion; `Inference/Recovery` stateless failure classification and typed presentation plus synchronous exact-owner failure/queue-handoff coordination behind an injected live effect adapter, and lookalike-cache reset policy; `Inference/IdentificationReview` ordered action/persistence/transport/post-success coordination behind an injected live database/effect adapter, bounded throwing review snapshots, complete override/confirmation/reset/historical-refresh workflow sequencing, exact post-suspension presentation fencing, and pure full-value presentation/persistence mapping; `Inference/Hydration` replaceable live/historical/identification-review task ownership, a value-only historical SwiftData projection, dedicated synchronous historical-load orchestration, dedicated registered historical follow-up orchestration, the live-dependency-free species-presentation callback/publication/identity/write-routing bridge, Auth draining, bounded request histories, persisted enrichment TTL, temporary backoff, structured Wikipedia/enrichment/GBIF child work, enrichment mapping behind an injected fetch seam, a sole live endpoint adapter, and immutable hydration persistence snapshots with live database/encoding effects; `Inference/State` contains exact live task/attempt identity behind an injected durable-queue core and sole live adapter, plus bounded write/review sequencing and Auth fencing; `Inference/LocalAnalysis` contains ephemeral model/cadence lifetime plus split Vision, bounded-image, deterministic-trait, phrase, cadence, and default-enabled Foundation-cue generation, validation, and explicit stream cancellation with power/thermal observation; generated Edge DTOs; the stateless shared response-preparation service; the foreground parse/save actor; and on-device viewfinder intelligence.                 |
| Analytics                | `apps/ios/Merian/Core/Analytics/`               | Optional, consent-gated PostHog facade and SDK lifecycle, advisory usage quota, and gamification notification manager. The current production-consent candidate remains release-blocked.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Media                    | `apps/ios/Merian/Core/Media/`                   | Shared bounded local-media processing, including `ScanMediaPayloadPolicy`, `InferenceAudioPreparer`, adaptive audio boost, spectrogram raster/layout policy, normalized seeking, immutable `SendableCGImage` transport, exact-token `MediaPlaybackObservation`, a main-actor audio delegate, token-aware mounted playback-lease ownership, initializer-injected playback effects, and actor-owned media save/share preparation. The playback-session controller coalesces activation, rejects late acquisition after teardown, checks retained leases before reuse, and releases only its exact coordinator token. `MediaExportService` accepts Sendable local/approved-remote requests, processes batches sequentially, and is shared by Insight and Scans.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Data/Database            | `apps/ios/Merian/Core/Data/Database/`           | `BackgroundDatabaseActor`, its focused collection-sync, queue-selection, upload-lifecycle, background-account-work, inference-lifecycle, inference-retry, retry-mirror, live-scan, offline-finalization, scan-record-support, species-metadata, and non-biological-retention persistence extensions, `FileIOActor`, `ScanRepository`, and the layered `HistoricalSync/{Models,Decoding,Services,Persistence}` boundary and its domain-owned pagination/checkpoint policy. The Historical Models layer owns request values and unchanged DTOs, Decoding owns row quarantine, Services owns the sole live Auth/PostgREST adapter, Persistence owns `HistoricalDatabaseActor`, and `ScanRepository` retains ordering, pagination, account fencing, and events. Inference lifecycle owns durable eligibility, claims/retreats, generation validation, telemetry, and orphan release; inference retry owns both retry commits; the finalization owners share record mapping and media serialization while keeping SwiftData, file adoption, and cross-domain orchestration separated. These owners use throwing scan/job reads and leave process, task, network, Auth, file, and UI effects in Offline Sync services. Queue selection owns full pending-set paging, funding-prioritized upload payloads, and state-bound atomic empty-media quarantine; Media Upload's `UploadSync` is its sole production consumer. The species-metadata extension owns local Wikipedia/reference, enrichment, lookalike recovery, and identification-review mutations with private helpers and no networking, Auth, file, or UI dependency. The non-biological-retention extension owns the erasure values, bounded expired-record selection, and atomic record/cloud-tombstone commit with the same dependency exclusions. `ScanRepository` also owns the ordered accepted-account-deletion cleanup: it resets sensitive derived map state, explicitly deletes every active-schema model, saves, requires verified account-derived Preferences cleanup, and invokes the injected process-state reset only after those durable steps succeed. The sequence is fail-closed but is not one cross-store transaction.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Data/Images              | `apps/ios/Merian/Core/Data/Images/`             | Layered image ownership documented by the local README: the stateless `ImageDownsampler` owns shared bounded ImageIO thumbnail decoding; `LocalImageLoader` owns cache/request orchestration and the isolated media session; `Concurrency` owns decode admission; `Policies` owns HTTPS/content admission and retry classification; `Recovery` owns immutable scan snapshots, canonical source identity, its lock-protected process-local mapping registry, source revisions and bounded change streams, exact filename, read-only rescue-store, and constrained timestamp evidence; and `Services` owns injected single-flight cloud repair plus post-startup, cancellation-aware two-pass SwiftData registration in bounded fresh contexts. The area also owns file-backed still-image preparation, the durable `ExternalImageImportStore` Photos inbox and EXIF extractor, archive rescue, media-aware add-only photo/video PhotoKit writes, RAM caching, and immutable reference-thumbnail backfill inputs plus actor-owned policy backed by shared Core Species Reference transport. Capture-only focus detection and physical-size estimation remain in Capture Shared and Submission respectively.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Data/Field Notes         | `apps/ios/Merian/Core/Data/FieldNotes/`         | Shared `@MainActor` SwiftData-first reconciliation for private notes across active and queued scans plus the legacy defaults bridge. Throwing reads and writes fail closed; the bridge mirrors only successful durable state.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Data/Species Preferences | `apps/ios/Merian/Core/Data/SpeciesPreferences/` | Account-scoped SwiftData CRUD and fail-closed device-global legacy removal for preferred species display names; normalized timestamp-conflict policy with a local-wins equality rule; a 200-character value limit and 1,000-species local/remote/pending-delete union bound; exact PostgREST row/upsert values; the sole narrow live Supabase adapter with immutable scientific-name keyset paging; a focused local-recovery owner for interrupted SwiftData/UserDefaults mutations; and main-actor single-flight, force-preserving trailing requests, last-outcome-aware account freshness/diagnostics, lease, post-suspension local refetch, and tombstone coordination. The V51 SwiftData model remains in `Models/ActiveSchema`, and the legacy/account-partitioned metadata store remains in Core Preferences.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Offline sync             | `apps/ios/Merian/Core/Data/OfflineSync/`        | Durable queue state machine, generation-fenced upload/inference URLSession ownership, exact server-issued staging-key handoff, consumed-key re-upload recovery, a persisted `failed_retryable` dispatch latch and fresh-context retry accounting, compare-before-clear retry/probe registries, background replay and reconciliation, the lock-protected UIKit background-execution wrapper, bounded pre-/post-durability connectivity classification, a focused response-to-persistence finalization service, audio queue helpers, and tokenized sync phase state. Scan-analysis retries use a five-second minimum, jittered exponential growth, a 30-second ordinary local maximum, and ten automatic attempts; server-directed minimums remain authoritative, while maintenance keeps its 15-minute maximum.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Store recovery           | `apps/ios/Merian/Core/Data/StoreRecovery/`      | The coordinator façade owns the shipped SwiftData configuration; `Models` owns source/migration values, diagnostics, manifests, and recovery-local JSON coding; `Policies` owns migration selection, error classification, and privacy-safe fingerprints; and `Services` owns Core Data metadata inspection, local diagnostic persistence, exact SQLite artifact discovery, and rollback-protected quarantine/legacy rescue. Diagnostics fingerprint captured metadata strings and keys. Manifests retain error codes and allowlisted stable domains, fingerprint custom domains and raw prose, and are required before archive success.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Hardware                 | `apps/ios/Merian/Core/Hardware/`                | Stable camera, audio-capture, haptic, and environment-context facades over focused platform owners; cross-feature speech; one-shot token-aware audio-session coordination; the reviewed framework-Combine-to-main-actor bridge; spectrogram DSP and ambient-noise classification; thermal/battery orchestration. `EnvironmentContext/Models` and `Policies` own context values and deterministic location rules; its location controller alone owns Core Location delegate, authorization, tracking, continuations, invalid-fix rejection, accurate/coarse cache separation, revocation fencing, and exact-generation timeout state; its geocoding service alone owns coalesced bounded `CLGeocoder` work; and its weather adapter alone owns WeatherKit. Audio capture receives maximum-duration feedback through AppDI instead of resolving the haptic singleton.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Notifications            | `apps/ios/Merian/Core/Notifications/`           | App-wide system-notification infrastructure and the cross-feature post-identification permission sheet. Stable push and badge facades preserve caller APIs; Models and Policies own immutable values and deterministic routing/presentation/badge decisions; Services alone own UserDefaults, Supabase account-scope projection, UNUserNotificationCenter, UIApplication, and Core's push-registration/unread-count endpoint effects; Coordination owns account-aware latest-state remote-registration draining; Badges owns generation-fenced single-flight unread state; and Views owns only the injected permission presentation. The account scope is local coalescing metadata and never enters the wire payload. Explore's visible activity feed, catalog, and mark-read adapters remain feature-owned. `Services/BackgroundScanNotificationService.swift` shares alert preferences and unseen-scan badges after direct or recovered background result commits; scheduling deduplication remains in the push manager.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Network                  | `apps/ios/Merian/Core/Network/`                 | `Auth/` owns value-only transition/error/session/lease models, Guest-presentation and deterministic transition policies, exact-session lease and exclusive transition coordinators, the sign-out single-flight, and the observable effect-free `AuthRuntimeState` for transition, generation, transition-analytics, exact-session lease/drain, and local sign-out state. It also owns provider-neutral Auth-session bootstrap, recovery, lifecycle, conditional deferred-event replay, and public-author identity-refresh coordination, provider-presentation admission, focused Apple/Google authorization Services, the shared task-free Supabase Auth session adapter for OAuth, recovery, local-sign-out, credential/session/profile-metadata mapping, and live Auth calls, account-deletion error/session classification, ghost-profile queue/error policy, pure deletion phase order, separate dependency-injected fresh/recovery deletion coordinators, purchase-safe sign-out phase order and route selection, stable and compatibility completion keyed by destination, Auth generation and transition ownership, pending-proof routing, restoration, fail-closed journal verification, retry, recovery-only reset admission, and ghost-merge phase sequencing. Provider-neutral owners contain no provider SDK or singleton access; only the named authorization Services acquire Apple/Google/UIKit framework dependencies. The lifecycle and bootstrap `+Live` adapters acquire their focused Supabase Auth calls; the shared Auth session `+Live` adapter acquires the request-scoped OAuth, recovery, and local-sign-out calls. `SupabaseManager` retains the focused lifecycle provider, history service, and local-sign-out coordinator, delegates transition-state storage to `AuthRuntimeState`, adapts bootstrap identities through its stable SDK-typed entry point, and injects live bootstrap, session-recovery, OAuth completion, consent, endpoint, purchase-identity Auth-state/handoff, sign-out, handoff, logging, purge, durable recovery, account-deletion, public-author event, and lifecycle effects into focused owners. The local-sign-out coordinator owns retained task lifetime and exact cleanup sequencing; it and recovery use the shared task-free Auth session adapter, whose live file is the sole direct local SDK invalidation owner. The lifecycle provider owns SDK stream mapping and exact current-state replay; the history service retains listener-admitted synchronization, while its `+Live` adapter is the reviewed Auth owner of `AppDIContainer.shared` for offline-queue context and scan-repository composition. OAuth completion fences cancellation after every suspended phase and admits a cancelled caller to cleanup only after it has already mutated the SDK session. Core Security's Purchase Identity live compatibility adapter owns legacy sign-out purchase requests, and its session live-effects adapter owns RevenueCat, entitlement, resolver, profile-query, Supabase-client, and diagnostic acquisition for ordinary readiness. The area also owns Sign in with Apple authorization-code/Vault registration and subject-bound credential-state revalidation, strict account-deletion receipts, TLS-pinned session transport and per-attempt authenticated dispatcher, shared Insight/Explore/Dictionary Field Chat endpoints and strict DTO validation, private Field trip completion-scan DTO mapping, typed/account-fenced inference identification-review PostgREST/RPC service, Explore DTOs, species dictionary/observation-stats DTOs, and Keychain manager. Protocol-3 purchase-principal requests are owned by Core Security's other Purchase Identity live adapter. |
| Preferences              | `apps/ios/Merian/Core/Preferences/`             | `AppSettings` typed observable state; the exact `UserDefaults` key registry; the small `UserDefaults`-backed Explore-share and field-note bridges; preferred-name legacy cleanup plus account-qualified, monotonic tombstone and diagnostic metadata; the verified accepted-account-deletion inventory for account-derived caches; and an injected runtime-reset composer for observable settings, gamification, the generation-fenced app badge, and RAM images. Extracted owners import neither Supabase nor SwiftData. Device settings, consent, deletion-recovery state, and the Apple manual-revocation notice survive that account cleanup. Durable species values and reconciliation are owned by `Core/Data/SpeciesPreferences`; deletion-recovery state and the exact secure-key registry are owned by Core Security.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Security                 | `apps/ios/Merian/Core/Security/`                | Circuit breaker; device identity; the exact app-owned Keychain key registry; focused Account Deletion, Purchase Identity (including task-free session live-effect composition), Ghost Profile Merge, RevenueCat, entitlement, and scan-admission boundaries; `Consent/Models` for exact policy/evidence and source-compatible durable values; `Consent/Policies` for provider authority, ownership, retry, synchronization merge, and observable-state projection; `Consent/Repositories` for verified local ledger/journal transitions; `Consent/Services` for deterministic mutation and remote mapping plus sole live clock/app-metadata, PostgREST/RPC, Realtime, and cloud-session dependency adapters; `Consent/Coordinators` for runtime composition, account/session/lease and Ghost/inference workflows, synchronization, restoration, and Realtime task ownership; the 597-line `ConsentManager` observable compatibility facade for mutable state, lifecycle entry points, SDK application, merge publication, and Auth-transition draining; atomic verified ledger-file and Keychain withdrawal-journal bytes; and social guard. The canonical purchase-identity target is [`purchase-principal-auth-separation.md`](./rfcs/purchase-principal-auth-separation.md); the canonical consent hold is [`production-consent-readiness-2026-08-03.md`](./legal/production-consent-readiness-2026-08-03.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Species reference        | `apps/ios/Merian/Core/SpeciesReference/`        | Shared non-UI Wikipedia mobile-sections and GBIF taxon-key transport/parsing used by Inference and scan-thumbnail recovery. Callers retain scheduling, presentation identity, URL admission, image loading, and persistence policy.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| UI                       | `apps/ios/Merian/Core/UI/`                      | Cross-feature render-only controls, cards/feedback/model-tier presentation, audio spectrogram, glow loading skeleton, bounds-safe array access, cross-feature scan thumbnails and empty states, goal progress, and a domain-neutral media carousel package containing pager, gallery, audio playback, and reusable video chrome. Explicit UI service adapters own live image loading and the sole main-actor UIKit share-sheet presentation bridge; feature owners retain loading state, activity-item construction, navigation, source policy, entitlement lookup, telemetry, and presentation lifetime.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Routing                  | `apps/ios/Merian/Core/Routing/`                 | Immutable `AppEvent` and `AppRoute` models, deterministic route policy, narrow producer/consumer capabilities, the synchronous loss-tolerant event bus, and the bounded delivery-critical root-route coordinator. Models and Policies are effect-free; Coordination owns the only mutable delivery state.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Utilities                | `apps/ios/Merian/Core/Utilities/`               | Exact two-file, Foundation-only home for cached ISO 8601 formatters and trim-to-non-empty string normalization. App lifecycle lives in `App/Lifecycle`; intentional detached execution in `Core/Concurrency`; Field Notes reconciliation in `Core/Data/FieldNotes`; background execution and scan connectivity policy in `Core/Data/OfflineSync`; the shared error taxonomy in `Core/Errors`; the framework publisher bridge in `Core/Hardware`; safe collection access in `Core/UI`; species common-name presentation in `Features/SpeciesReference`; and typed event/route coordination in `Core/Routing`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

Within the Network row, the provider-neutral Apple credential-registration
service owns strict receipt validation, its `+Live` adapter alone owns the
Supabase Function DTOs and invocation, and `SupabaseManager` retains only the
exact-session assembly around that injected operation. The adapter performs
exactly one authenticated invocation per service call and owns neither retry
policy nor asynchronous task state.

The historical-session service's `+Live` adapter is the explicitly inventoried
`Auth/Services` owner permitted to resolve `AppDIContainer.shared` for
offline-queue context and scan-repository composition; it provides prepared work
to the retained service. The task-free `SupabaseAuthSessionService` in that row
projects refreshed and loaded Supabase sessions and maps OAuth values. Its one
`+Live` adapter owns the corresponding request-scoped OAuth, recovery, and local
sign-out SDK calls plus privacy-safe recovery and sign-out diagnostics; the
recovery coordinator owns terminal local-clear sequencing. The separate local
sign-out coordinator owns ordinary and account-cleanup retained task lifetime
and exact sequencing. `SupabaseManager` composes adoption, publication, and
cleanup around those injected ordinary-readiness purchase and entitlement
boundaries without reacquiring those dependencies directly.

The same Network row assigns the SDK's fallback authentication URL to
`AuthenticationCallbackCoordinator` and its dependency package. They own
transition and pending-handoff admission, anonymous/different-account refusal,
replacement reconciliation, exact-session adoption, purchase/entitlement
ordering, final verification, and mutation-aware cleanup without owning a task
or SDK value. Cancellation after preflight stops before installation; sign-out
beginning during installation prevents adoption or publication; and later
purchase/entitlement continuations retain exact-session fences.
`SupabaseManager` preserves the public URL entry point and injects the focused
OAuth service. That service's `+Live` adapter alone performs Supabase URL
conversion; the facade still owns exact-session adoption and injects captured
session capabilities, Keychain marker, purchase, entitlement, cleanup, and
diagnostic effects. Focused live diagnostics retain the existing privacy-safe
copy.

Purchase-continuity source work is split explicitly within those rows.
`PurchaseIdentitySourceHandoffCoordinator` owns aggregate fail-closed journal
projection, exact-session preparation, exact-source abandonment, and failed-
sign-out restoration through injected boundaries. Cancellation during
compatibility preparation's final SDK-session read cannot report success, and
the already-durable proof remains recoverable. Both abandonment routes recheck
the transition or unowned account-work fence after the initial suspended SDK
read and before remote cancellation; stable proof retirement repeats that fence
after its final suspended read. `PurchaseIdentityHandoffAuthJournal` owns Auth
error translation over Core Security's store, while
`PurchaseHandoffPreparationCoordinator` in Core Security owns proof construction
and stable `preparing`/`prepared` checkpoint order. `SupabaseManager` remains
the live Auth SDK/state assembler and centralized pending-fence publisher.
`PurchaseIdentitySessionLiveService+Live` is the focused owner that acquires
RevenueCat, entitlement, resolver, profile-query, Supabase-client, and
diagnostic dependencies for ordinary purchase readiness. Its task-free service
owner weakly gates deferred legacy linking and entitlement refresh so neither
effect can begin after the Auth facade is released.

Within the AI row,
`Inference/Hydration/InferenceHistoricalRecordProjection.swift` is the concrete
persisted-record-to-value owner for historical Insight loads.
`InferenceEngine.load(from:)` delegates to `InferenceHistoricalLoadCoordinator`,
which admits presentation replacement, releases previous live-media buffers,
constructs and synchronously publishes the projection, captures generations and
callbacks, and registers follow-up work without retaining the managed record.
`InferenceHistoricalHydrationCoordinator` then owns deferred decoding,
displayed-override refresh, concurrent Wikipedia and enrichment branches, and
enrichment-before-GBIF ordering. Historical publication and terminal reference
cleanup revalidate exact presentation identity; the shared species coordinator
applies the same fence before a live task can publish its initial loader or
issue provider work and again during deferred cleanup. An older same-scan task
therefore cannot create or clear a newer loader, and a still-current historical
loader ends as empty when providers return no image.

`Inference/State/InferenceLiveAttemptCoordinator.swift` is the concrete owner
for the current foreground task, retained displaced task handles, and exact
process-local/durable attempt identity.
`Inference/Services/InferenceLiveQueueService.swift` is its injected queue
boundary, and only the `+Live` adapter resolves `OfflineQueueManager` for the
live-attempt lifecycle. The engine keeps source-compatible accessors and
observable sequencing but no direct durable-queue access. Focused overlap tests
prove a suspended finalizer cannot clear, retire, or authorize follow-ups over a
same-scan replacement or a presentation that relinquished its durable owner.
Invalidation detaches task and identity before callbacks, recovery cancels the
exact displaced task before publication, and Auth awaits cancellation-ignoring
displaced work.

`Inference/Presentation/InferencePresentationCoordinator.swift` is the concrete
non-observable owner for prepared and active presentation identity, exact visual
queue phrase/media context, and the pending first-render timestamp. It returns a
value handoff after synchronous validation; `InferencePresentationState` applies
the observable queue, copy, media, species, and processing commits behind stable
engine accessors. The coordinator contains no task, endpoint, persistence,
logging, singleton, or UI-model dependency. Auth admission and post-drain
cleanup clear its owners and queued visual context while preserving an
outstanding first-render metric; post-drain cleanup also removes context
installed re-entrantly during quiescence. An admitted visual replacement has a
stricter boundary: the lifecycle owner clears the displaced presentation
identity, queued phrase/media context, and timestamp before the submission owner
installs the replacement. A same-scan retry that supplies no new clock therefore
cannot consume or log its predecessor's tap interval. Once an exact queue-less
response is admitted, its pending clock moves from the temporary client identity
to the server-assigned scan ID before presentation; a stale callback cannot move
or consume that metric.

`Inference/Presentation/InferencePresentationState.swift` is the concrete stored
observable-value owner. Its named synchronous transitions cover scan
preparation, visual/nonvisual telemetry, success, queue handoff, dismissal,
cancellation, and historical projection without taking lifecycle identity or
performing an effect. The engine retains source-compatible computed accessors,
so existing SwiftUI consumers observe the same values. Reset and nonvisual
transitions clear prior subject distance rather than carrying visual telemetry
into another scan. Historical replacement clears the metadata/enrichment and
lookalike loading flags before the displaced hydration generation loses write
authority.

`Inference/Media/InferenceLiveMediaProjector.swift` is the concrete value-only
owner for live visual/nonvisual timeline normalization and provider/presentation
projection. It preserves explicit owner order, derives the legacy default order
only when needed, selects display-policy image bytes, carries focus regions,
maps both live bytes and persisted paths into `ActiveScanMedia`, suppresses only
an explicitly matching video poster as a duplicate image page, retains a
distinct adjacent still, and uses the poster as fallback when video is
unavailable. Its injected live values contain only Documents/temporary lookup,
file existence, and secure-remote URL policy. The projector owns no task,
network request, persistence, logging, or observable state. The submission
coordinator publishes its pre-request values and the pipeline consumes its
immutable submission projection; on accepted completion,
`InferenceLivePresentationCoordinator` invokes persisted mapping only after
exact-attempt admission and publishes through the lifecycle and
presentation-state owners.

`Inference/Pipeline/InferenceLiveSubmissionCoordinator.swift` owns the
visual/nonvisual startup sequence behind the engine's stable methods. It
preserves Auth and empty-payload disposition, admission-before-replacement,
media/telemetry staging, attempt and presentation activation, local visual
analysis, first-render timing, immutable request/callback construction, and task
registration. The execution task is installed immediately in
`InferenceLiveAttemptCoordinator`, which remains the only task-handle owner. The
startup coordinator contains no mutable registry and resolves no network,
persistence, logger, filesystem, or singleton dependency.

`Inference/Pipeline/InferenceLivePipelineCoordinator.swift` owns the exact
visual/nonvisual execution session after the submission coordinator publishes
the media projector's staged presentation values. It sequences admission,
activation, circuit gating, request/result services, completion preparation,
benchmark placement, durable finalization, synchronous failure dispatch,
modality-specific follow-ups, and exact-owner cleanup. Queue-less nonvisual
authorization remains synchronous after commit; only the queue-backed branch
awaits finalization. The core resolves no live singleton or logger. Its `+Live`
adapter binds circuit, quota-refund, and logging effects captured by AppDI,
while narrow callbacks carry observable publication, hydration scheduling,
local-analysis timing, typed failure actions, and finish routing. The adjacent
`InferenceLivePresentationCoordinator` is the sole production callback factory.
It synchronously fences the exact attempt before persisted-media projection or
accepted publication, then routes publication-before-event ordering, finish,
failure, captured hydration context, and visual local-analysis events to focused
owners without a task, suspension, mutable state, live dependency, or engine
capture.

`Inference/Completion/InferenceLiveCompletionCoordinator.swift` is the shared
accepted-result and follow-up authorization owner. Its singleton-free core
normalizes both result modalities and requires exact durable finalization plus a
current local presentation with no outstanding durable generation before issuing
its file-scoped typed permit. Queue-less authorization accepts only the nil
scan/durable pair. Its `+Live` adapter contains concrete discovery, replacement,
circuit, telemetry, event, notification, and milestone effects. AppDI captures
those collaborators once; the pipeline keeps benchmark placement and reviewed
modality-specific effect order, while the live-presentation coordinator commits
through `InferencePresentationState` and routes hydration to the species-
presentation bridge. The engine keeps its stable facade.

`Inference/Recovery/InferenceLiveFailureCoordinator.swift` is the synchronous
failure and durable queue-handoff owner. It takes the initial exact ownership
snapshot, performs the retired-owner durable-state recheck, delegates queue
release, retirement, and rejection through the attempt coordinator, and rechecks
local ownership after those synchronous queue callbacks before later
presentation effects. It sequences injected terminal effects without creating a
task or suspension and is invoked only by the pipeline coordinator. Its `+Live`
adapter binds telemetry and logging and adapts the circuit, haptic, and usage
managers supplied by AppDI. The live-presentation coordinator applies only the
failure coordinator's three narrow observable presentation actions.

`Inference/IdentificationReview/InferenceIdentificationReviewCoordinator.swift`
is the review action and effect owner. It uses the engine's shared write
coordinator for replacement and Auth fences, sequences local persistence before
the account-fenced review RPC, and publishes an Explore refresh before milestone
processing only after transport succeeds. Its `+Live` adapter contains database-
actor construction, shared-post lookup, logging, and the AppDI-captured event
and milestone bridges. The adjacent snapshot service distinguishes a missing row
from a store failure, while `IdentificationReviewPresentation` maps override,
confirmation, reset, and dictionary results into paired observable and durable
values without side effects.
`Inference/IdentificationReview/InferenceReviewWorkflowCoordinator.swift` owns
the complete interactive and displayed historical-override sequences: throwing
snapshot preflight, local-before-cloud admission, registered review hydration,
dictionary/enrichment fallback, review mutation, and reference-image follow-up.
It revalidates scan, species, presentation, review generation, cancellation, and
Auth state after external suspension so stale results cannot publish or enqueue
persistence. The engine retains the public review signatures.
`Inference/Hydration/InferenceSpeciesPresentationCoordinator.swift` coordinates
observable commits through `InferencePresentationState`, supplies the workflow's
single hydration callback bundle as its current-species,
presentation-generation, exact-identity, and write-admission source, and starts
review generations for new live and historical presentations.

The Core root contract is documented in `apps/ios/Merian/Core/README.md`. It
limits root Swift owners to the dependency container and logging categories. The
cross-domain architecture suite freezes that inventory, requires a README for
every Core domain, checks bounded stateless Policies and their exact documented
local-input exceptions, keeps shared UI components transport/persistence-free,
rejects `try?` SwiftData fetches, protects sensitive diagnostics, and tracks the
remaining production file above 600 lines: the 3,461-line
`SupabaseManager.swift`. Its purchase-identity binding state, keyed resolution
task, foreground repair, legacy-profile query, and ordinary live-effect assembly
have focused owners under `Core/Security/PurchaseIdentity/`; the facade supplies
only Auth state, account-work, and handoff closures to the session live adapter.
Explore wire/request models now have focused owners under
`Core/Network/Models/Explore/`; shared semantic-location redaction lives in
`Core/Models/ExploreLocationPrivacy.swift`. The Codable post-location mode lives
in `Core/Network/Models/Explore/ExploreLocationSharingAPIModels.swift`, while
Explore-specific labels and symbols live in
`Features/Explore/Shared/Models/ExploreLocationSharingPresentation.swift`. Field
Trips wire/request models likewise have eight focused owners under
`Core/Network/Models/FieldTrips/`; feature presentation, Insights route
projection, milestone policy, and preference persistence remain outside that
network-model boundary.

Static tuning values follow those same domain boundaries. AI confidence,
scanning cadence, and cache recovery live under `Core/AI/Inference`; image
encoding and dimension policy under `Core/Data/Images`; historical pagination
and non-biological retention under `Core/Data/Database`; queue batching and
storage under `Core/Data/OfflineSync`; and shared scan-media byte limits under
`Core/Media`. The retired cross-domain `Core/Utilities/MerianConfig.swift`
aggregate must not return.

`Core/UI/Services/ShareSheetPresenter` is the shared activity-controller bridge.
It owns topmost-controller discovery, iPad popover anchoring, main-actor
presentation, and main-actor dismissal delivery; feature adapters retain
activity-item construction and their own playback, overlay, export, analytics,
and task lifetimes.

Within Core Hardware's camera boundary, `CameraSessionController` owns the
lock-backed lazy capture stack, video/depth/photo outputs, shared serial camera
queue, session/device configuration, active-device locking, and hardware photo
execution. The root `CameraManager.swift` owns observable state plus
frame/depth/photo delegate processing and app-level orchestration.
`CameraVideoRecordingService` receives the controller's queue and a lazy session
provider and exclusively owns the lazily created movie output,
audio/stabilization preparation, recording operations, cleanup/logging, and
file-output delegate correlation. Constructing these owners resolves no capture
object; provider/factory access stays behind explicit lifecycle work. Required
session input/video/photo topology is preflighted before mutation, a transient
input failure leaves configuration retryable, optional depth cannot displace the
photo output, and the start callback requires a running session plus the current
session-lifecycle generation so a completed stop suppresses a queued stale
start. `CameraManager` separately generation-fences MainActor start and stop
presentation, so an older completion cannot overwrite a newer requested
lifecycle; its pure presentation state coalesces duplicate same-intent requests.
`Camera/Models` owns value-only recording identities, `Camera/Policies` owns
deterministic session presentation, zoom, frame-rate, microphone, and
recording-generation decisions, and `Camera/Coordination` owns the
lock-contained photo and video request lifecycles plus the MainActor target-FPS
debounce task. `CameraArchitectureTests` prevents the focused owners from
acquiring network, persistence, or UI effects, separates session/device and
movie-output AVFoundation from manager delegates, and enforces focused line
ceilings.

Within Core Hardware's audio boundary, `AudioCaptureManager` remains the
observable recording/review facade and presentation-lifecycle owner.
`AudioCapture/Services/AudioRecordingEngineController` owns the lazy engine,
input tap, canonical Int16 WAV, bounded PCM stream, DSP task, exact operation
identity, partial-file cleanup, and recording-specific session lease.
`AudioCapture/Services/AudioReviewPlaybackController` owns the concrete review
player, progress/completion tasks, generation/player correlation, and
playback-specific lease. Their live dependencies are the only audio-capture
edges that create AVFoundation recording/playback objects or resolve the shared
session coordinator; deterministic Core Hardware tests inject those effects and
fence late activation, route-recovery failure, resume retry, and stale
completion. `AudioCaptureArchitectureTests` enforces the split, dependency
exclusions, and focused ceilings: 600 lines for the 516-line manager, 550 for
the recording controller, and 250 for the playback controller.

Core Media's `AudioPlaybackSessionController` applies the same exact-token
contract to mounted shared and Explore audio. It coalesces activation, verifies
that a retained lease is still current before reuse, generation-fences teardown
during that validation, drains a retired activation before replacement, releases
late acquisition after teardown or explicit pending-work cancellation, and
cannot deactivate a recording or player that replaced it. Reusable Core UI and
Explore audio await this owner again immediately before every audible
start—including play-button, seek-resume, loop, and fallback-player paths—so
recording, speech, or another player replacing a retained lease cannot leave the
page using a stale session. Merely mounting a page acquires no lease. Lifecycle
and player-identity fences prevent a suspended play from starting after
teardown. Generic `MediaPlaybackDependencies` no longer imports AVFoundation or
exposes its former synchronous `AVAudioPlayer` session-mutation seam. Its
existing async `activatePlaybackAudio` closure remains the narrow unmuted-
`AVPlayer` admission seam and delegates to the coordinator.

Within Core Hardware's haptic boundary, `HapticManager` remains the stable
observable facade and owns settings/expedition admission, semantic trigger
timing, diagnostics, and the latest-attempt projection. `Haptics/Models` and
`Haptics/Policies` own platform-neutral values and pure decisions.
`Haptics/Services/HapticFeedbackController` owns seven reusable UIKit generator
wrappers and the lazy Core Haptics engine; impact and selection preserve UIKit
delivery while optionally adding the Core Haptics transient, and exact engine
identity prevents a stale stopped/reset callback from clearing its replacement.
`Haptics/Services/HapticAudioSessionAdapter` is the only haptic source that
imports AVFoundation or inspects the shared audio session. Architecture tests
freeze these dependencies and enforce ceilings of 300 lines for the facade, 125
for models, 100 for policy, 400 for the controller, and 100 for the adapter.

Within `Data/Images`, recovery evidence priority is a registry invariant rather
than an assumption about caller order. Strong scan-ID/media-order evidence may
evict a lower-confidence timestamp claim for either its canonical URL or local
file, while a multi-image timestamp group is admitted or evicted atomically.

Non-biological retention crosses two Core Data owners deliberately. The focused
`BackgroundDatabaseActor` extension selects and atomically commits eligible
erasure work, reporting accepted erasures separately from rows actually deleted.
`ScanRepository` uses the first outcome for file/tombstone cleanup and the
second for `scanLibraryChanged`; commit-time biological reclassification
produces neither outcome. User-requested bulk-deletion presentation and feedback
remain owned by `Features/Scans/NonBiological`.

The Data/Database species-metadata architecture guard inventories the complete
iOS production and test Swift trees. Each of its seven persistence methods and
11 mirrored behavior tests must resolve to exactly one focused owner; private
helper, import, dependency, and 600-line boundaries are enforced separately.

The queue-selection persistence extension is likewise effect-free. It owns
pending upload paging, funding priority, and atomic empty-media quarantine while
Media Upload's `UploadSync` retains transient transfer and network policy.
Unreadable funding state fails selection closed, and scan/job fetch or save
failure rolls back quarantine rather than committing a partial transition.
`QueueSelectionPersistenceTests` mirrors that behavior, and
`QueueSelectionArchitectureTests` freezes sole declaration/test ownership, the
exact consumer allowlist, shared offline-job lookup, narrow dependencies, and
600-line ceilings.

The upload-lifecycle persistence extension owns pending upload claims, durable
manifest staging, and task-snapshot-fenced orphan release. Media Upload and
Inference Replay keep network, URLSession, and orchestration policy. A focused
`BackgroundDatabaseActor` extension shares actor-isolated retry-mirror repair
with the inference-retry owner under an exact consumer allowlist.
`UploadLifecyclePersistenceTests` and `UploadLifecycleArchitectureTests` mirror
those behavior and ownership boundaries and cap the residual aggregate against
regrowth.

The background-account persistence extension owns exact Auth/generation/phase
activation, current-owner validation, transition candidate projection, and the
durable pending-state/staging-key retirement that must commit before task
cancellation. Background Transfer and Media Upload retain all Auth leases,
URLSession effects, and orchestration. Throwing scan/job reads keep storage
failure distinct from an absent legacy record and retain private failure
context. Activation creates a genuinely absent legacy ingestion job in the same
durable save as its owner marker. `BackgroundAccountWorkPersistenceTests`
mirrors the three existing actor races and proves activation creates the missing
ingestion job for a legacy scan; `BackgroundAccountWorkArchitectureTests`
freezes sole declaration/test ownership, exact production consumers, per-scan
fence balance, narrow dependencies, and focused/residual size ceilings.

The inference-lifecycle persistence extension owns durable eligibility reads,
claims and retreats, background/live generation checks, telemetry hydration, and
timestamp-fenced orphan release with ordered candidate locks and fresh post-wait
eligibility reads. Its inference-retry sibling owns general and server-result
recovery retry commits. Every scan/job read is throwing; genuinely absent legacy
jobs remain supported, while read failures fail closed and orphan reconciliation
loads every candidate job before mutation. Offline Sync services retain process
generations, scheduling, URLSession and network effects, cancellation, and
finalization. `InferenceLifecyclePersistenceTests`,
`InferenceRetryPersistenceTests`, and `InferencePersistenceArchitectureTests`
mirror behavior and freeze sole ownership, exact consumers, private helpers,
balanced persistence fences, dependency exclusions, focused-file ceilings, and
the residual aggregate cap.

Scan finalization completes the database-actor split. The declaration file is
empty of methods; focused live and offline extensions share actor-isolated
record support, a stateless record factory, and an injected ordered-media
serializer. `BackgroundInferenceFinalizationService` owns background
generation/response/persistence ordering, while the stateless
`InferenceResponsePreparationService` keeps foreground and background decode,
success validation, request-appropriate response-ID comparison, mapping, and
immutable funding-settlement projection identical without an actor hop under the
per-scan lock. Queue-backed and client-ID-bearing requests require an exact
echo; the existing queue-less nonvisual request retains its server-assigned ID.
It performs no entitlement, usage, queue, or task effect. The generated wire
DTOs remain generator-owned; `EntitlementStateSnapshot`, the prepared value, the
`SpeciesData` graph, and both foreground/background result carriers use
compiler-checked `Sendable` conformances. Live and background completion apply
the carried settlement only after exact queue deletion through
`OfflineSync/Services/Funding/OfflineQueueManager+InferenceSettlement.swift`.
That owner delegates lease retention and trailing-pass coalescing to the
injected `InferenceFundingReconciliationOwner`, which Auth admission cancels and
awaits. Architecture tests freeze the sole owners, dependency direction, lock
containment, checked value transfer, and focused production-file ceilings.

Unsupported inference audio crosses narrow fail-closed owners. Media Upload
rejects non-local or non-WAV audio before signing, and surviving terminal
callbacks quarantine it before durable staging. Inference Replay applies the
same quarantine to persisted staged rows, while `BackgroundDatabaseActor`
rechecks the contract before its serialized inference claim. Queue Maintenance
owns the shared needs-attention transition. No owner converts or rewrites
persisted inference audio.

Within `Core/Security/Consent/Coordinators`,
`RequiredConsentRestorationCoordinator` owns the restoration state machine,
retry budget, UUID-keyed outstanding-task retention, cancellation snapshot and
drain, and account/session/generation/caller-cancellation fences. A canceled
timer cannot regain admission after manual retry reuses its attempt number.
`ConsentManagerRuntime` composes the package and supplies narrow facade
callbacks. `ConsentCloudSessionCoordinator` owns account-work lease/session
adoption, scheduled synchronization, inference admission, and Ghost rebinding
through a separately owned live Supabase adapter. Its inference path snapshots
bindable unowned evidence before adoption and rejects cancellation or stale
lease/generation authority after synchronization before missing proof can enter
reapproval. `ConsentMutationService` owns evidence creation and local write
sequencing; its live adapter alone supplies the clock, UUID, and app metadata.
`ConsentStateProjectionPolicy` owns derived state. `ConsentManager` mirrors
restoration state for observation and combines the restoration and
synchronization cancellation snapshots with the Realtime teardown registry at
the Auth-transition boundary; it does not own mutation construction, cloud
session workflows, derived algorithms, restoration retry transitions, task
identity, or channel removal. Canceled restoration handles and started Realtime
removals remain in their coordinators until exact completion, so an ordinary
invalidation that does not await its returned boundary cannot hide unfinished
work from a later Auth-transition drain.

`Core/Network/Endpoints/MerianNetworkClient+FieldTrips.swift` owns Field Trips
request actions and typed response projections for the feature and its existing
cross-feature callers.
`Endpoints/MerianNetworkClient+CommunityIdentification.swift` owns the eight
Community request/activity/detail/edit/search and submit/withdraw/restore
operations. `Endpoints/MerianNetworkClient+ExploreBrowsing.swift` owns eight
stateless Feed/Map/post/detail/author/hashtag/species reads and their typed
projections, including existing Profile, Insights, Dictionary, and tab-badge
callers. `Endpoints/MerianNetworkClient+ExploreInteractions.swift` owns 12
comment/reply/mention, like/follow, comment mutation, report, and block methods
used by Feed, Author Profile, Notifications, Identify, and Core's social guard.
`Endpoints/MerianNetworkClient+Notifications.swift` owns the four notification
catalog/count/read and push-registration methods;
`Endpoints/MerianNetworkClient+PublicProfile.swift` owns username/display-name/
avatar updates and username availability. Notification feature state, Core
Notifications' system push/registration/badge lifecycle, and shared
`ProfileViewModel` identity/upload orchestration stay with their focused owners.
`Endpoints/MerianNetworkClient+ExplorePostManagement.swift` owns six
composer-media/share-state/incident reads and unshare/notes/content edits, with
their existing response validation and payload rules. Feed, Insight Sharing, and
Scans Shell keep adapters, state, reconciliation, and account fences.
`Endpoints/MerianNetworkClient+FieldChat.swift` owns all 17 Insight,
Explore-post, and Species Dictionary chat methods, while
`Decoding/FieldChatResponseDecoder.swift` owns their stateless strict
candidate-success validation. Shared Field Chat Services and ViewModels retain
source/effect adaptation and generation-fenced presentation state.
`Endpoints/MerianNetworkClient+SpeciesDictionary.swift` owns seven method
variants: authenticated resolution plus the six detail, catalog, overview, and
stats reads; `Decoding/SpeciesDictionaryResponseValidator.swift` owns typed
schema/identity validation, and `Caching/SpeciesDictionaryResponseCache.swift`
contains the separate locked detail/stats memos. Dictionary and Species
Reference Services retain their adapters and state owners.
`Endpoints/MerianNetworkClient+ScanLifecycle.swift` owns detailed/bulk status,
the status-string compatibility wrapper, and scan deletion.
`ScanLifecycleAPIModels.swift` owns their unchanged status DTOs;
`Decoding/ScanLifecycleResponseDecoder.swift` owns plain explicit-key decoding,
strict identity/cardinality checks, and confirmed deletion.
`Endpoints/MerianNetworkClient+Collections.swift` owns the authenticated
`/sync-collections` call and its private explicit-key request DTO. Core Data
retains collection snapshot projection, durable scheduling, account-work
transaction state, acknowledgement-only local purge, and retry after a
classified `401`; the endpoint defers nested session recovery because Auth must
quiesce that same task and lease before advancing.
`Endpoints/MerianNetworkClient+ScanPublication.swift` owns direct Explore-share
and Ask-the-Community request mapping and success validation.
`Recovery/MerianNetworkClient+OwnedScanRecovery.swift` owns record-based
publication and Field Chat preflight, status polling, immutable local snapshots,
payload construction, and missing-row orchestration;
`Recovery/OwnedScanRecoveryPolicy.swift` owns deterministic admission. The
polling owner propagates task cancellation before and during status probes and
retry delays, so a cancelled publication or preflight cannot resume recovery.
`Media/ScanPublicationMediaRestorer.swift` and
`ScanPublicationMediaRestorePolicy.swift` own local-file planning, MIME and
budget policy, and restored-media upload. Queue/deletion scheduling stays in
Core Data. `Endpoints/MerianNetworkClient+Inference.swift` owns Identify
prewarm, compatibility request construction, and multimodal request/dispatch;
`Core/Network/Inference/` owns immutable request values plus stateless JSON,
inline-media, staged-owner, and recoverable-conflict policy. `Transport/` owns
the pure route/error/replay policy, request-scoped executor, sole pinned
session/TLS owner, and per-attempt authenticated dispatcher. The dispatcher owns
Auth leases/headers, transition validation, constrained-network headers, and its
file-local upload delegate around the injected session transport. The client
façade injects both stateful owners behind narrow value and prepared-body
bridges; the endpoint uses the shared cancellation-propagating detached-work
boundary for off-main body preparation.
`Endpoints/MerianNetworkClient+ScanEnrichment.swift` owns deferred-context and
enrichment requests; `Endpoints/MerianNetworkClient+Exports.swift` owns export
intake; `Endpoints/MerianNetworkClient+ProductFeedback.swift` owns survey and
Community feedback submission. Capture/Settings/Identify retain their existing
adapters, scheduling, and interaction state; Core AI uses the focused live
enrichment adapter. `InferenceSpeciesHydrationCoordinator` owns scoped
scheduling and current-presentation decisions, `InferenceHydrationCoordinator`
owns task lifetime and backoff, and `InferenceSpeciesPresentationCoordinator`
supplies observable publication and admitted-write callbacks behind the stable
engine facade. `EnrichScanResponse` remains hand-written below the generated
Identify block in `Core/AI/InferenceEdgeDTOs.swift`, and the survey request
model remains in Settings Feedback Models.
`Endpoints/MerianNetworkClient+MediaStorage.swift` owns signing and scan-image
inspect/repair endpoints; `MediaStorageAPIModels.swift` owns their
wire-unchanged, value-only `Sendable` DTOs.
`Media/MerianNetworkClient+MediaUploads.swift` owns Data/file PUTs and
foreground video upload; `Media/PresignedMediaUpload.swift` owns exact
signed-header and HTTP-200 policy; `Media/StagedVideoUploadPlan.swift` owns
immutable file/manifest planning. Queue manifest validation and background jobs,
live inference attempt fencing, Core Data Images cloud repair, and Profile
avatar promotion stay caller-owned.
`Endpoints/MerianNetworkClient+AccountDeletion.swift` owns six legacy/v2 intake
and public recovery operations plus three private request-only DTOs.
`AccountDeletionAPIModels.swift` owns the operation-specific preparation
receipt, strict accepted/recovery receipt, status DTOs, and v2
preparation/commit payloads. `AccountDeletionRecoveryValidation.swift` and
`Decoding/AccountDeletionResponseDecoder.swift` own only stateless
proof/timestamp and operation-specific receipt validation. Two fixed-route value
bridges retain private authenticated or capability-only transport.
`Core/Network/Auth/` owns the value-only transition/session/lease foundation;
provider-neutral Auth-session bootstrap snapshots, injected dependencies, and
complete-token exact-context keyed task coordinator with pre-session
cancellation plus post-purchase-readiness completion fencing; a focused SDK
bootstrap service/live adapter for session projection, reads, missing-session
classification, and anonymous sign-in plus a separate diagnostics owner;
lifecycle event/diagnostic values, injected dependency boundaries,
session-projection coordinator, and conditional deferred-event replay task;
provider-neutral OAuth credential, session, completion, and metadata values;
OAuth token-subject policy, session-replacement/Apple-registration workflow, and
shared completion coordinator with provider/transition validation, explicit
replacement disposition, and cancellation fences around every suspended
completion phase; provider-presentation admission dependencies/coordinator with
one retained Apple completion task; and focused Apple/Google live Services for
presentation, provider-value mapping, Apple controller/nonce ownership, window
policy, and diagnostics; account-deletion classification; ghost-merge queue/
error policy; pure deletion phase order; and separate dependency-injected
fresh/recovery deletion, purchase-sign-out route, sign-out phase, keyed
purchase-handoff completion, and Ghost durable-preparation/keyed-completion
coordinators. Its public-author dependency/coordinator pair owns
transition-owned refresh and the keyed restored-session
Ghost-completion/refresh/event sequence. Its Apple credential-revocation pair
owns exact identity/generation lookup and an identity-bound terminal-clear
admission. Recovery repeats the exact expected and current session after
account-work quiescence and returns a typed completion, context-change, or
purchase-handoff deferral outcome. Rejected work remains pending for the next
stable Auth context without a hot lookup loop, and the manager's centralized
aggregate handoff publication resumes it when the fence becomes false. A context
generation changed during suspended clear replays after the deferred result
rather than losing an earlier lifecycle wakeup. `SupabaseManager` retains the
focused lifecycle provider, history service, and local-sign-out coordinator plus
bootstrap publication, session-recovery, and public-author event effect assembly
while preserving the SDK-typed bootstrap entry point. The bootstrap service/live
adapter owns bootstrap SDK projection, reads, missing-session classification,
and anonymous sign-in; the lifecycle provider owns the Auth SDK stream,
SDK-state mapping, deferred-event registration, and exact current-state replay.
Listener replacement cancels the superseded task and replay obligation, and a
post-coordinator cancellation fence blocks its trailing credential-revocation
resume effect; the history service owns every listener-admitted synchronization
task. Its embedded `AuthRuntimeState` owns transition/generation,
transition-analytics, exact-session lease/drain, and local sign-out state
without acquiring those live effects; `Core/Security/GhostProfileMerge` owns the
typed remote service and sole Supabase Function adapter;
`Core/Security/AccountDeletion` and `AppDIContainer` retain injected secure
storage, cleanup, and retirement effects. `Core/Network/Transport/` owns
stateless Edge URL construction, unavailable-route and stable-error
classification, retry allowlists/account binding, and value-only Auth-recovery
decisions. Its request-scoped `AuthenticatedRequestExecutor` owns the logical
attempt state machine and applies those policies plus injected Auth,
entitlement, and consent effects. `PinnedNetworkTransport` owns the single
configured session, lock-backed first-use initialization, exact Supabase
host/subdomain policy, required platform trust plus pin validation, fail-closed
unreadable/unmatched-chain handling, TLS delegate, raw and caller-deadline
dispatch, and DEBUG override; `AuthenticatedTransportDispatcher` owns each
attempt's Auth/session fence and upload delegate. `MerianNetworkClient.swift`
retains configuration diagnostics and injects both owners behind typed-response,
body-ignoring, encoded-body, and raw-response JSON POST bridges. Its only
non-Edge PostgREST bridge admits the exact authenticated scan-admission RPC and
applies the caller's two-second, no-cache/no-retry policy through that same
pinned transport. Fixed-result Dictionary/stats bridges exclusively access the
client's private cache instance, validating each loaded response before
insertion; their typed GET helper remains private. The internal configuration
guard preserves Dictionary validation/cache ordering without exposing URLs. The
typed POST bridge forwards optional idempotency keys and selectively replaces
decoding errors without catching transport failures. Wire DTOs remain in
`Models/FieldTrips/`, `Models/Explore/`, `InsightChatAPIModels.swift`,
`SpeciesDictionaryAPIModels.swift`, `SpeciesObservationStatsAPIModels.swift`,
`ScanLifecycleAPIModels.swift`, and `MediaStorageAPIModels.swift`, plus
`AccountDeletionAPIModels.swift`. The encoded-body bridge preserves typed
request encoding and returns bytes for Field Chat's strict decoder. The
raw-response bridge keeps scan recovery bound to its expected Auth owner through
the private transport. The prepared-JSON bridge forwards enrichment's serialized
body and stable key after its configuration/serialization/UUID validation
sequence. The account-bound encoded bridge keeps signing's lowercase body owner
bound to the same private transport UUID without bypassing current-session
resolution. Two raw PUT bridges expose only request/file inputs and response
values, adding no Auth/retry policy.
`CoreNetworkIntegrationArchitectureTests.swift` freezes the exact 18
endpoint-owner inventory, prevents duplicate aggregate endpoint methods, applies
the 600-line ceiling across the extracted Auth, Endpoint, Inference, Media,
Recovery, and Transport owners plus the client façade, and requires exactly six
Transport files: three stateless policies, the request-scoped executor, the
pinned session, and the authenticated dispatcher. It also freezes the sixty-one
Auth foundation paths and caps Auth, Purchase Identity, `SupabaseManager.swift`,
and their combined production surface at 7,734, 2,016, 3,461, and 13,211 lines,
respectively. The guard includes the effect-free observable owner for
transition, generation, transition-analytics, exact-session lease/drain, and
local sign-out state plus the focused listener/current-state adapter,
historical-sync task owner, lifecycle diagnostics, and live listener's
generation/context/transition-observation order; the bootstrap dependency/
coordinator pair plus focused SDK service/live adapter and diagnostics owner;
the recovery dependency/coordinator and local-sign-out coordinator with its
colocated dependency boundaries; one shared task-free Supabase Auth service/live
adapter and diagnostics owner for OAuth, recovery, and local sign-out; bootstrap
and local-sign-out single-flights, missing-session, cancellation, exact-refresh,
anonymous-readiness, local-clear, and final-session rules; the lifecycle event
model, dependency boundaries, coordinator, and replay owner; the OAuth model,
identity-token policy, workflow, completion dependency package/coordinator,
provider-admission dependency package/coordinator, live-provider Services, and
the typed Apple credential-registration service and sole Supabase live adapter,
including exactly one Function invocation per service call and no retry policy,
asynchronous task, facade, or alternate transport ownership in that adapter; the
live SDK-install mutation marker before post-install cancellation plus
exact-target transition adoption before recovery, explicit teardown of retained
purchase-handoff and purchase-identity resolution work, and the reviewed
residual generic Auth SDK calls in the facade; the shared deletion dependency
package; and fresh/recovery coordinators, the purchase-sign-out and
purchase-handoff dependency and route owners, relocated declaration and
helper-function ownership, former account-deletion, purchase-safe sign-out,
purchase-handoff, and ghost-merge helper names, the public-author refresh and
Apple credential-revocation dependency/coordinator pairs, the fallback
authentication callback dependency package, coordinator, live-diagnostics split,
and sole OAuth live-adapter callback installation, the ten explicit structured
task owners, actor isolation, provider-neutral SDK/singleton exclusion, focused
provider-service framework ownership, and provider-only Apple lookup capture
across suspension. The sole live public-author event/logging adapter remains an
explicit owner outside the provider-neutral Auth package. The same guard locks
the Core Security ghost-merge models/service/store and purchase-handoff
models/stores, including device-only verified persistence and sole live Ghost
endpoint ownership. It records the exact, disjoint ambiguous-replay
classifications and confines live dependency acquisition to the reviewed
transport, Auth, inference-preflight, and owned-recovery owners. The backend
`get-filtered-discovery-feed` route remains in the Edge fleet but is
intentionally absent from the iOS replay classification because no iOS endpoint
owns or calls it. The mirrored `MerianTests/Core/Network/Endpoints/` folder owns
request/transport regression and architectural boundary tests, using shared
per-case fixtures, type-preserving JSON comparison, and immutable single-read
request snapshots for replay checks. `NetworkEndpointTestSupportTests.swift`
protects those shared assertions for data- and stream-backed request bodies;
`ScanPublicationEndpointTransportTests.swift` and
`ScanPublicationRecoveryArchitectureTests.swift` jointly require caller
cancellation to terminate record-based persistence polling before a late status
response is interpreted or a later status/recovery request can start;
`MerianTests/Core/Network/NetworkTransportTestSupport.swift` separately owns the
legacy process-global URL interceptor and the lock-backed scoped transport used
by those endpoint fixtures. The cross-slice architecture guard prevents either
fixture family from drifting back into the aggregate client suite;
`MerianTests/Core/Network/Decoding/` owns chat validation, Dictionary DTO and
schema/identity tests, and scan lifecycle wire/strict-response tests;
`MerianTests/Core/Network/Caching/` owns deterministic Dictionary
expiry/alias-capacity/reset tests. `MerianTests/Core/Network/Inference/` owns
payload, media-budget, account-binding, staged-owner, and conflict policy; the
endpoint folder owns inference transport and architecture coverage.
`MerianTests/Core/Network/Media/` owns pure signed-upload policy, local video
planning, and Data/file/foreground upload regressions plus publication-restore
error, count, byte, and signing-purpose policy.
`MerianTests/Core/Network/Recovery/` owns deterministic missing-row admission
and the Field Chat local/cloud identity fence.
`MerianTests/Core/Network/Transport/` mirrors the three stateless policies,
request-scoped executor, pinned session, and authenticated dispatcher. It owns
URL/route/error classification, bounded unavailable-route scheduling,
ambiguous-replay allowlists, retry-account binding, value-only Auth-recovery
selection, exact request/account replay, refresh application, per-attempt
failed/successful body-release notification, logical-callback idempotency across
replay, pre-dispatch and post-unauthorized-refresh cancellation, session
configuration, exact Supabase hostname admission, concurrent single-session
initialization, certificate-chain matching plus missing/empty/untrusted-chain
rejection, injected-session and bounded no-cache dispatch, exact scan-admission
route confinement, and authenticated request construction. The cross-slice
source guard keeps session construction in `PinnedNetworkTransport`, per-attempt
Auth leasing in `AuthenticatedTransportDispatcher`, and verifies the executor's
ordinary and transition-owned application branches. `MediaUploadTests.swift`
keeps its held-request cancellation transport, per-session signals, and bounded
completion/cleanup helpers private to that file; it does not add a production
task or session owner. `MediaStorageAPIModelsTests.swift` owns
signing/inspection wire decoding. Account-deletion endpoint/recovery/transport
and boundary suites live under `Endpoints/`; DTO/receipt tests live under
`Decoding/`, and pure recovery syntax/expiry tests remain directly under
`Core/Network/`. Their isolated fixtures do not bypass valid-transition
admission. Value-state and lease tests live in
`Auth/AuthTransitionFoundationTests`; observable transition/generation,
transition-analytics, exact-session lease/drain, and local sign-out ownership
live in `Auth/AuthRuntimeStateTests`; admission, adoption, provider callback,
OAuth rollback/metadata, exact direct-link upgrade, and purchase-handoff
decisions live in `Auth/AuthTransitionPolicyTests`. Token parsing, normalized
metadata, replacement/registration retry, fail-closed provider/transition and
registration configuration, shared OAuth completion, provider
admission/callback/task ownership, and provider mapping/cancellation behavior
live in `Auth/OAuthIdentityTokenPolicyTests`, `Auth/OAuthSignInModelsTests`,
`Auth/OAuthSignInWorkflowTests`, `Auth/OAuthSignInCoordinatorTests`, and
`Auth/OAuthSignInCancellationTests`, `Auth/OAuthProviderSignInCoordinatorTests`,
`Auth/GoogleOAuthAuthorizationLiveProviderTests`, and
`Auth/AppleOAuthAuthorizationLiveProviderTests`.
`Auth/AppleOAuthCredentialRegistrationServiceTests` owns exact value forwarding,
strict registered-receipt validation, and transport-error propagation.
Account-deletion classification, intake, and cleanup/retirement sequencing live
in `Auth/AccountDeletionTransitionPolicyTests`,
`Auth/AccountDeletionIntakeWorkflowTests`, and
`Auth/AccountDeletionCleanupWorkflowTests`; live-boundary deletion ordering and
recovery routing live in `Auth/AccountDeletionCoordinatorTests` and
`Auth/AccountDeletionRecoveryCoordinatorTests`. Purchase-safe ordering and
preflight/inter-phase cancellation live in
`Auth/PurchaseIdentitySignOutWorkflowTests`; stable/legacy selection,
pending-proof routing, fail-closed journal rereads, recovery-only reset
admission, cancelled transition admission, and account-work-quiesced retry live
in `Auth/PurchaseIdentitySignOutCoordinatorTests`; source preparation, including
cancellation during compatibility preparation's final SDK-session read,
exact-source abandonment/restoration, and aggregate fail closure live in
`Auth/PurchaseIdentitySourceHandoffCoordinatorTests`; exact Auth journal error
translation lives in `Auth/PurchaseIdentityHandoffAuthJournalTests`; proof
construction and durability checkpoints live in Core Security's
`PurchaseIdentityHandoffPreparationCoordinatorTests`; exact journal persistence
and compatibility live in
`Core/Security/PurchaseIdentity/PurchaseIdentityHandoffStoreTests`. Stable and
compatibility completion behavior lives in
`Auth/PurchaseIdentityHandoffCoordinatorTests`; typed compatibility-route and
terminal-error behavior lives in
`Core/Security/PurchaseIdentity/LegacyPurchaseHandoffRemoteServiceTests`.
Session binding/linking, durable-handoff fence projection, same-context
single-flight, and differently keyed resolution supersession live in
`Core/Security/PurchaseIdentity/PurchaseIdentitySessionCoordinatorTests`,
including stale final-admission cache rejection; foreground repair and its final
exact-session fence live in
`Core/Security/PurchaseIdentity/PurchaseIdentityReadinessCoordinatorTests`;
typed legacy-profile forwarding lives in
`Core/Security/PurchaseIdentity/LegacyPurchaseIdentityProfileServiceTests`;
legacy attribute precedence, provider/entitlement/diagnostic forwarding,
exact-account readiness, and fail-closed owner release live in
`Core/Security/PurchaseIdentity/PurchaseIdentitySessionLiveServiceTests`.
Ghost-merge replacement, durable preparation, provider-transition and stale-
source rejection, keyed completion/supersession, queue-wide retry, and
completion order live in `Auth/GhostProfileMergePolicyTests`,
`Auth/GhostProfileMergeWorkflowTests`, and
`Auth/GhostProfileMergeCoordinatorTests`; typed operation forwarding and
provider/terminal error adaptation live in
`Core/Security/GhostProfileMerge/GhostProfileMergeRemoteServiceTests`; exact
queue persistence, validation, and legacy migration live in
`Core/Security/GhostProfileMerge/GhostProfileMergeStoreTests`.
`AuthSessionLifecycleCoordinatorTests` owns provider-neutral listener
orchestration, durable fail closure, deletion-barrier local entitlement
projection closure, state order, purchase/entitlement sequencing, and
post-suspension fences, including replay-owner-driven deferred sign-out cleanup
and stale signed-out postflight rejection. `AuthLifecycleReplayCoordinatorTests`
owns task replacement, transition carry-forward, stable-event obligation
clearing, release-during-suspension, and no-deferred-event behavior.
`CoreNetworkIntegrationArchitectureTests` rejects strong manager capture in the
live lifecycle dependency assembly and pins its weak purchase-principal and
linked-user cleanup bindings. `AuthSessionBootstrapCoordinatorTests` owns
current session reuse, sign-out/quiescence order, true-missing anonymous
creation and failure, exact-token task sharing, replaced-owner rejection,
preflight and sign-out-wait cancellation, task replacement, transition drift,
post-readiness cancellation, and final session admission after purchase
readiness. `AuthSessionBootstrapLiveServiceTests` owns SDK identity/expiry and
anonymous-fresh projection, exact SDK/compatibility missing-session
classification, unrelated-error rejection, and SDK failure forwarding.
`AuthSessionRecoveryCoordinatorTests` owns ordinary and transition-owned
exact-session refresh, cancellation/session drift around suspension, anonymous
purchase/entitlement/final-readback admission, pending-handoff preservation, and
terminal local cleanup, including cancellation delivered after SDK sign-out has
started and entry for a cancelled OAuth transition only after its SDK mutation,
cleanup of the exact adopted replacement target, plus rejection of a different
replacement session installed while cleanup waits for account-work quiescence.
The consolidated `SupabaseAuthSessionServiceTests` suite owns OAuth, recovery,
and local-sign-out SDK adaptation. `AuthLocalSignOutCoordinatorTests` owns
single-flight sequencing, transition/cancellation fences, canceled-task cleanup,
and post-SDK external cleanup. The separate colocated
`AuthLocalSignOutFacadeTests` suite owns the facade request gate.
`AuthenticationCallbackCoordinatorTests` owns fifteen deterministic fallback URL
cases covering success order, pending-handoff, transition and sign-out overlap,
anonymous/different-account refusal, exact-account refresh, installation failure
before and after SDK mutation, mutation-aware cleanup, pre-install and
suspended-phase cancellation, exact installed-target transition adoption,
purchase readiness, and final session drift.
`PublicAuthorIdentityRefreshCoordinatorTests` owns eighteen deterministic cases
covering stale-target scheduling, keyed replacement and compare-before-clear
cleanup, Ghost/lease/refresh/event ordering, direct and scheduled cancellation
admission and postflight, cancellation-diagnostic suppression, lease and
current-user drift, remote failure, exact transition ownership, ownerless
refresh, and completed-marker reset. `AppleCredentialRevocationCoordinatorTests`
owns seventeen cases covering lookup and terminal-clear transition overlap,
identity/generation drift, stable-context revalidation, recovery deferral
without immediate retry, explicit stable resume, context-change replay without a
lost wakeup, cancellation, coalescing, owner release, and fail-closed clearing.
`SupabaseManagerTests` retains Supabase SDK/Auth effect assembly; focused
provider suites own provider-specific adapter classification.
`AccountDeletionCapabilityStoreTests`, `AccountDeletionLocalCleanupStoreTests`,
and `ManualAppleRevocationNoticeStoreTests` own device proof, recovery-phase,
and notice behavior. `AccountSettingsViewModelTests`,
`ScanRepositoryPurgeTests`, and `AccountScopedPreferencesTests` own the Settings
dependency handoff and account-local purge boundaries; `AppDIContainerTests`
remains scoped to container identity and preview isolation;
`AppRootPresentationTests` owns launch/root-presentation policy. The joined
lifecycle-coordinator/manager audit also locks post-suspension listener and
coordinator-owned anonymous-bootstrap publication plus keyed task replacement,
pre-destructive deletion/sign-out cancellation, pre- and post-install OAuth
replacement cancellation with disposition-aware reconciliation, direct
provider-link cancellation immediately before the SDK mutation, cancellation
after each suspended OAuth completion phase, completion-owned cleanup after a
mutated session, exact generation and transition ownership before purchase-proof
removal, and coordinator-owned target-plus-UUID compare-before-clear cleanup for
restored-session public-author refresh, conditional deferred-lifecycle replay
plus signed-out postflight fencing, provider admission/presentation and Apple
completion-task ownership, and generation-fenced Apple credential revalidation,
coordinator release during a suspended lookup, and provider-only live capture.
The Apple framework notification/state lookup and privacy-safe diagnostics
remain in focused live adapters outside `Auth/`; sign-in provider presentation
and mapping remain in focused Services inside `Auth/`. The cross-language
`accountDeletionCoverage.test.ts`, `purchasePrincipalMigrationContract.test.ts`,
and `ghostProfileMergeClientContract.test.ts` contracts read their extracted
owners directly. The Apple registration contract reads the Apple authorization
provider, provider sign-in coordinator, facade assembly, OAuth workflow, and
completion coordinator and freezes one-use credential routing,
provider/transition plus Apple-required/Google-forbidden configuration before
session installation; the Ghost contract additionally reads `SupabaseManager`,
the OAuth coordinator, models, identity-token policy, replacement workflow, and
cancellation suite, the Ghost coordinator/dependencies, typed service/live
adapter, store, policy, workflow, and focused tests, plus the Consent facade,
runtime, cloud-session coordinator and live adapter, synchronization, merge,
state-projection, Realtime, restoration, repository, and retry owners and their
focused authority, cloud-session, synchronization, Realtime, and restoration
tests; owner or suite rehomes must update those paths atomically. Together they
pin account-work lease and session adoption plus the synchronization
coordinator's complete scheduled and active task registry and Auth-transition
drain, including superseded and previously invalidated work, plus restoration
retry retention and Realtime removal retention through exact completion, the
combined drain, and canceled-retry admission after manual attempt-number reuse
plus stale-account fencing. The identity-free
`services/supabase/functions/_tests/fixtures/account-deletion-preparation-v2-success.json`
fixture is shared by the Deno handler and native DTO/decoder tests. It locks the
exact four-field preparation shape and proves that shape cannot decode as the
strict accepted/recovery receipt. The
[Network matrix](../apps/ios/Merian/Core/Network/README.md#preparation-receipt-contract)
tracks the source contract and separate real-session evidence boundary.
`StagedVideoUploadTests` now owns the protected empty-file-before-signing CI
regression. Feature Services and ViewModels retain presentation adapters and
interaction state. See the
[Core Network guide](../apps/ios/Merian/Core/Network/README.md),
[Core Network integration audit](../apps/ios/Merian/Core/Network/README.md#core-network-integration-audit),
[Explore browsing verification matrix](../apps/ios/Merian/Core/Network/README.md#endpoint-verification),
[Explore interaction verification matrix](../apps/ios/Merian/Core/Network/README.md#explore-interaction-verification),
[notification/public-profile verification matrix](../apps/ios/Merian/Core/Network/README.md#notification-and-public-profile-verification),
[Explore post-management verification matrix](../apps/ios/Merian/Core/Network/README.md#explore-post-management-verification),
[Field Chat verification matrix](../apps/ios/Merian/Core/Network/README.md#field-chat-verification),
[Dictionary verification matrix](../apps/ios/Merian/Core/Network/README.md#species-dictionary-verification),
[scan lifecycle verification matrix](../apps/ios/Merian/Core/Network/README.md#scan-lifecycle-verification),
[scan-publication/recovery verification matrix](../apps/ios/Merian/Core/Network/README.md#scan-publication-and-owned-recovery-verification),
[enrichment/export/feedback verification matrix](../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification),
[media storage/upload verification matrix](../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-verification),
[account-deletion/recovery verification matrix](../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-verification),
[inference-network verification matrix](../apps/ios/Merian/Core/Network/README.md#inference-verification),
[Identify verification matrix](../apps/ios/Merian/Features/Explore/Identify/README.md#verification),
and
[Field Trips verification matrix](features-and-hardware/25-field-trips.md#verification).

Foreground maintenance belongs to `App/Lifecycle/AppLifecycleManager.swift`,
which delegates queue draining to
`Core/Data/OfflineSync/OfflineJobScheduler.swift` after onboarding and
required-consent admission. The scheduler owns persisted retry-wake restoration
and the ordered six-effect drain; its narrow `DrainOperations` value permits
isolated dispatch-policy tests without starting live queue work. Reanalysis has
a separate synchronous safety boundary in
`Core/AI/Inference/Result/InferenceScanReplacement.swift`: prove the replacement
is durable and save transferred metadata before the engine asks
`ScanRepository.eradicateScan` to delete the original. The repository owns the
deletion/outbox transaction and optional post-commit cleanup handle. See the
[Core Data guide](../apps/ios/Merian/Core/Data/README.md) and
[app lifecycle contract](development-guides/02-app-lifecycle.md).

`Core/Media/MediaExportService.swift` is the shared Insight/Scans export
boundary. Its private actor processes Sendable requests sequentially, keeps
remote previews file-backed, and uses an ephemeral, cookie-free session that
accepts only exact-host HTTPS `media.merian.app`, refuses cross-host redirects,
and revalidates final response URLs. Single-share images are bounded to 2,048
px; Scans batch-share images use 1,024 px under the existing 20-selection cap.

Within Core Network, `PinnedNetworkTransport` owns the sole configured pinned
session and caller-bounded raw dispatch. `MerianNetworkClient` owns the narrow
scan-admission bridge that validates the exact PostgREST route plus nonempty
bearer and anon-key credentials before using that transport; it exposes no
general raw-request capability.

Within Core Data, the OfflineSync foundation pass replaces the former aggregate
type file with focused `Models`, `Policies`, `Coordinators`, `Persistence`, and
`Services` owners. The second slice replaces the sync aggregate with focused
`CloudDeletion`, `Collections`, and `MediaUpload` service files for eligibility,
preparation, signing, generation lifecycle, dispatch, and recovery. Queue
maintenance is split between a state owner for counts, tombstones, and
main-context flushes and a deletion owner for persistence-fenced task
cancellation, retained-media selection, database commits, file cleanup, and
purge. Shared offline-job and Field Trip goal-hint lookups live under
`Persistence` rather than gaining wider manager visibility. The same boundary
owns one fresh throwing scan/job authority projection and the throwing
queued-scan lookup/mapper, keeping storage failure distinct from absence. The
former queue aggregate is now split into `CaptureAdmission`, `Funding`,
`FieldTripProgress`, and `InferenceReplay` services. Capture admission keeps
stateless file staging separate from manager-owned admission and live handoff;
funding, goal-hint replay, and uploaded-scan reconciliation have distinct
owners. `OfflineQueueDurability.swift` retains only live manager mutations and
retry orchestration. The first URLSession slice moves terminal-work tracking,
Auth lease retention and transition quiescence, and nonisolated delegate routing
under `Services/BackgroundTransfer`; the following terminal-routing slice adds
private owner validation/adoption and accepted/rejected callback routing to the
same boundary. Upload completion is now a fifth focused `MediaUpload` owner: it
contains callback accumulation, unsupported-audio quarantine, durable staging
finalization, and inference dispatch handoff. Generation validation/invalidation
stays with `UploadLifecycle`; queued SwiftData records map to Sendable inference
snapshots under `Persistence`, alongside reusable preferred-goal reads.
`Policies/QueuedInferenceMediaPolicy.swift` owns the storage-aware,
manifest-only local-WAV fence; generic persisted media models remain free of
queue policy. `Policies/BackgroundInferencePolicy.swift` owns actor-independent
route/response and server-status decisions, while the eight
`Services/BackgroundInference` files separately own exact process-generation
lifecycle, generation-fenced request dispatch, accepted task-result and
transport-failure completion, response-to-persistence finalization, delayed
status probing and exact-generation background-task retirement, server-result
recovery plus retryable-status persistence, durable-authority orphan
reconciliation, and general transport-retry/server-poll lifetime. The former
URLSession aggregate is retired. The dispatch/retirement handoff stays
fail-closed: an unsuccessful durable inference retirement preserves the
suspended task and active process generation, while a later committed retirement
finishes that exact generation immediately. When Auth owns the retirement sweep,
generation completion precedes transport cancellation. The
[Offline Sync ownership guide](../apps/ios/Merian/Core/Data/OfflineSync/README.md)
is the canonical source inventory. Its architecture suites freeze every
relocated declaration plus exact focused-file/import sets, private mutable
state, durable/destructive ordering, responsibility boundaries, mirrored test
ownership, retired aggregates, and 600-line ceilings. This organization changes
no SwiftData, wire, queue-state, task-description, or endpoint contract. The
Core Data-wide integration guard additionally rejects `try?` SwiftData fetches
anywhere under `Core/Data`, bounds the 13-file database-actor surface and
durable-authority consumers, and requires durable job claims before collection
or cloud-deletion network work begins. Collection sync now separates its
immutable desired-state model, injected account-lease service, persistence-only
actor extension, and Core Network endpoint. The service fences before dispatch
and after response; a fresh actor purges only rows still marked for deletion, so
an in-flight local reactivation survives the stale acknowledgement.

## SwiftData Actors

| Actor                                  | File                                                                                                                                                                                                                                                                                                                                                                                                                                     | Lifecycle                                                                                                                                                                                                                                                                                                                                                                                              |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BackgroundDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/BackgroundDatabaseActor.swift` plus focused `+CollectionSync.swift`, `+QueueSelection.swift`, `+UploadLifecycle.swift`, `+BackgroundAccountWork.swift`, `+InferenceLifecycle.swift`, `+InferenceRetry.swift`, `+RetryMirror.swift`, `+LiveScanPersistence.swift`, `+OfflineFinalization.swift`, `+ScanRecordSupport.swift`, `+SpeciesMetadata.swift`, and `+NonBiologicalRetention.swift` extensions | Ad-hoc for live/offline final record commits, species enrichment/reference/review persistence, non-biological deletion/retention commits, and fresh collection snapshot/acknowledgement contexts; long-lived through `OfflineQueueManager.resolvedQueueDbActor(container:)` for fail-closed, generation- and timestamp-fenced upload/inference transitions, retry reconciliation, and orphan recovery. |
| `HistoricalDatabaseActor`              | `apps/ios/Merian/Core/Data/Database/HistoricalSync/Persistence/HistoricalDatabaseActor.swift`                                                                                                                                                                                                                                                                                                                                            | Ad-hoc per historical sync, streaming one cloud page at a time behind the repository orchestrator and focused cloud adapter.                                                                                                                                                                                                                                                                           |
| `ProfileDatabaseActor`                 | `apps/ios/Merian/Features/Profile/UserProfile/Services/ProfileDatabaseActor.swift`                                                                                                                                                                                                                                                                                                                                                       | Ad-hoc behind `ProfileTabDependencies` for Profile render calculations; container-identity-cached via `OfflineQueueManager.resolvedProfileDbActor(container:)` with a fresh projection for every post-inference award evaluation.                                                                                                                                                                      |
| `SpeciesObservationStatsDatabaseActor` | `apps/ios/Merian/Features/SpeciesReference/Services/SpeciesObservationStatsDatabaseActor.swift`                                                                                                                                                                                                                                                                                                                                          | Ad-hoc behind `SpeciesObservationStatsDependencies` for each species chart load; filtered/projection SwiftData fetches local observation overlays, then delegates bucketing to `Features/SpeciesReference/Models/SpeciesObservationStatsReducer.swift`.                                                                                                                                                |
| `SearchDatabaseActor`                  | `apps/ios/Merian/Features/Scans/Library/Services/ScanLibrarySearchActors.swift`                                                                                                                                                                                                                                                                                                                                                          | Ad-hoc for incremental search payload extraction from stable scan IDs; full rebuilds use value snapshots and do not perform a second SwiftData fetch.                                                                                                                                                                                                                                                  |
| `FileIOActor`                          | `apps/ios/Merian/Core/Data/Database/FileIOActor.swift`                                                                                                                                                                                                                                                                                                                                                                                   | Singleton actor for image/audio file writes, deletes, and path validation.                                                                                                                                                                                                                                                                                                                             |

`HistoricalDatabaseActor` exposes throwing page and collection reconciliation
boundaries. A failed local read or save aborts the pass rather than
manufacturing an empty authoritative snapshot; cancellation rolls back pending
work before absent-remote collection pruning and commit. Targeted
completed-result hydration maps those local failures to durable transient
recovery, and insertion counts exclude invalid-timestamp rows.

The Scans library's advanced filtering worker is intentionally not a SwiftData
actor. `Features/Scans/Library/Models/ScanLibraryFilterIndex.swift` accepts only
`Sendable` projections extracted by `ScansLibrarySearchCoordinator`; it caches
option dimensions and performs normalized matching off-main without owning a
`ModelContext`. Full text-payload and posting-index construction also remains in
the coordinator's cancellation-aware detached worker. `ScansManager` remains the
UI-facing selection, filter-input, action-feedback, and event-subscription
owner; the coordinator owns targeted reindexing. Live export, Explore
publication, share-state, app-event, and haptic adapters are isolated to
`Features/Scans/Library/Services/ScansLibraryDependencies.swift`; Library views
perform no endpoint or singleton lookup. Every production Library file remains
below 600 lines.

The Scans root follows the same boundary. `ScansShellDataStore` owns fresh
SwiftData projections, `ScansThumbnailPipeline` owns loader/repair/backfill
integration, and `ScansShellViewModel` owns queue and Explore-media incident
state through its narrow auth/endpoint/event/time/badge dependency value.
Service-specific live adapters stay with their data-store and thumbnail owners.
`ScansSheetView` retains only navigation and presentation timing and performs no
direct endpoint, Supabase, app-container, loader, or actor lookup. Every
production Shell file remains below 600 lines.

## Supabase Edge Function Inventory

Inference and media staging:

- `generate-upload-urls`
- `identify`
- `identify-multimodal`
- `update-scan-context`
- `identify-describe`
- `audio-spec`
- `check-scan-status`
- `enrich-scan`
- `insight-chat`

Shared identify helpers under `services/supabase/functions/_shared/identify/`
own cross-route contracts for the executable model/final wire descriptor,
generated provider schema, thresholds, cache hydration, database writes, media
resolution, moderation, latency-oriented database RPCs, and subject
classification. `_shared/identify/contract.ts` generates the Vision/Describe
schemas plus the provider-private audio variant, runtime-validates provider and
complete server-enriched responses, and infers their TypeScript types.
`_shared/identify/googleSchema.ts` is the typed seam from that dependency-free
projection into the pinned Google SDK schema.
`_shared/identify/audioSubjectPolicy.ts` owns the shared audio-only
non-human-over-Human precedence and consumes its provider-private discriminator
before either audio route assembles the unchanged public Identify payload.
`services/supabase/scripts/validate_edge_dtos.ts` imports that same executable
descriptor and deterministically generates the marked Identify DTO block in iOS
`InferenceEdgeDTOs.swift`, including nested types, arrays, numeric
representations, coding keys, and explicit decoders. The gate compares the
checked-in block exactly and checks exclusive generated DTO ownership across the
complete `apps/ios` source graph. Its focused tests, third-party-free Deno
config, and frozen lock exercise stale generation, aliased decoder extensions,
missing source roots, and runtime numeric bounds.
`_shared/capturedMediaContract.ts` independently owns the durable
`public.scans.captured_media` outer-key/`_0` union. Its focused
`validate_captured_media_dtos.ts` generator owns
`Core/Data/Database/CapturedMediaWireDTOs.swift`; Identify provider-schema
projection does not consume this JSONB compatibility union. Strict V1 validates
every nonempty new write, while compatible reads accept historical aliases,
description timestamps, device-local references, nested video audio, and empty
manifests before canonical rewrites discard retired/device-only fields. Current
scan-ingestion intent schema v3 likewise persists description contexts as
text-only `freeText`; schema-v2 replay remains readable and is normalized before
any new durable write. `scanIngestionJobs.ts` owns the atomic ingestion-setup
call and strict RPC response validation; `latencyDb.ts` owns dictionary
hydration. `completedResponse.ts` owns owner-scoped stored/reconstructed success
replay and bounded concurrent-request coalescing across all four scan-producing
routes. `subjectClassification.ts` is the processed-material boundary: visual
and describe routes call it before biological gates so manufactured or processed
objects cannot enter `species_dictionary` through one route while another blocks
them.

`services/supabase/functions/_shared/scanRecovery.ts` is the shared
compatibility owner-row repair boundary used by `check-scan-status` and
`share-scan-to-explore`. It validates only bounded non-media fields, derives
identity and public privacy projection server-side, checks the owner-scoped
ingestion job, and performs a duplicate-safe write. Both callers reload by scan
and authenticated owner before proceeding. iOS builds the matching payload in
`Core/Network/Endpoints/MerianNetworkClient+ScanPublication.swift`; Field Chat
preflights it from `InsightSheetView+Toolbar.swift`, while
`Features/Explore/Shared/Models/ExploreErrorFormatter.swift` translates
technical share failures into customer-facing retry guidance.

`services/supabase/functions/_shared/aiQuota.ts`, `_shared/groupTagQuota.ts`,
`_shared/entitlement.ts`, `_shared/complimentaryScans.ts`, migrations
`20260723160229_enforce_server_ai_quotas.sql` and
`20260802235833_three_complimentary_pro_scans.sql`,
`20260803181936_add_reservation_safe_entitlement_protocol.sql`, plus
`scripts/cutover_complimentary_entitlements.sql`, own the cross-route
paid-provider and complimentary-result boundary. Identification, audio,
cache-miss enrichment, model chat, and Explore/Community share-or-edit audio
moderation reserve a database operation with a stable UUID before dispatch. The
shared moderation helper refuses live provider work when a transitive caller
omits that quota boundary. The migration owns durable entitlement versioning,
policy/model selection, UTC-day and user/IP counters, ten-minute fenced
reservation leases, charged failed-retry state, automatic stale refund, and
API-role privilege revocations. Coverage lives in
`_tests/aiQuotaCoverage.test.ts`, `_tests/aiQuotaMigrationContract.test.ts`, and
`tests/ai_quota_security.sql`. The complimentary extension adds one fixed
three-scan private lifetime ledger, original-analysis linkage, server-derived
Flash fallback, protocol 3, user-first completion/terminal settlement fences,
paid preservation, Ghost merge cap, and admin aggregates. iOS adds a serialized
account/scan funding reservation, durable release marker, conservative legacy
blockers, one bulk owner-scoped funding-state read, entitlement-refresh-fenced
terminal settlement, and persisted deferred paid/complimentary/Flash
reclassification. Coverage lives in
`_tests/complimentaryProScansMigrationContract.test.ts`,
`_tests/complimentaryScansConcurrencyDb.test.ts`, and
`tests/complimentary_pro_scans_security.sql`; the normative contract is
`docs/backend-and-data/18-complimentary-pro-scans.md`.

`services/supabase/functions/sync-collections/` and migrations
`20260803180211_harden_collection_ownership_and_memberships.sql` plus
`20260803215309_fix_collection_owner_upsert_ordinality.sql` and
`20260803215310_grant_collection_sync_invoker_privileges.sql`, then
`20260804002819_fix_collection_membership_conflict_ambiguity.sql`, own custom
collection reconciliation. One invoker RPC atomically accepts new/same-owner
collection IDs without reparenting foreign collisions; a second joins both
membership parents to that owner. The forward repairs use valid PostgreSQL
ordinality syntax, grant only the invoker operations required for sync, and use
the composite primary-key constraint to avoid PL/pgSQL output-variable
ambiguity; collection ownership remains column-update protected. Accepted IDs
alone feed composite-key hydration and the O(N) delta. A trigger, split
authenticated RLS, explicit service-only RPC ACLs, and mutable-column-only
`service_role` UPDATE protect direct database paths. Source coverage is
route-local plus `_tests/collectionOwnershipMigrationContract.test.ts`;
fresh-catalog coverage is `tests/collection_ownership_security.sql`.

Supabase project credential boundaries:

- `services/supabase/functions/_shared/publishableKey.ts` resolves hosted named
  publishable keys and the temporary complete legacy anon fallback for
  user-scoped clients.
- `services/supabase/functions/_shared/serviceRoleAuth.ts` owns strict
  server-key source classification, exact internal request matching, and
  format-aware standard headers. Hosted deploys add the non-reserved
  `MERIAN_SUPABASE_SERVER_API_KEY` synchronization fallback without changing
  inbound transport. Inbound matching isolates independently valid sources while
  unmatched malformed configuration still fails closed.
- `services/supabase/functions/_shared/serviceRoleClient.ts` is the only
  privileged SDK factory and removes only an exact inherited opaque-key Bearer
  fallback while preserving real user JWTs.
- `services/supabase/scripts/resolve_project_api_keys.ts` performs bounded,
  reveal-explicit Management API resolution for positive and real public-key
  negative smoke controls.
- `services/supabase/scripts/verify_edge_secret_digest.ts` compares the
  synchronized secret's stored SHA-256 digest with the exact selected key
  without logging either value. The deploy workflow requires this after
  synchronization and before Function deployment, then uses bounded
  propagation-aware positive smoke retries. The canonical matrix and exit gate
  are in
  `docs/backend-and-data/13-server-credentials-and-database-release-safety.md`.

Privileged database routine execution:

- `services/supabase/migrations/20260723144640_harden_privileged_routine_execution.sql`
  owns the deny-by-default public-definer ACL catalog, fixed empty search paths,
  owner-safe defaults, and caller-check requirement.
- `services/supabase/migrations/20260727010340_fix_service_role_authorization_guard.sql`
  keeps the service-only in-function check compatible with legacy JWT keys and
  PostgREST role impersonation for opaque server keys without changing grants.
- `services/supabase/migrations/20260727013416_future_proof_server_key_boundaries.sql`
  adds the private key-format-aware `pg_net` header policy, migrates installed
  HTTP routines and persisted cron commands, and repairs mixed user/service
  dispatch in the owner media-incident routine.
- `services/supabase/migrations/20260727183356_restore_identity_first_media_incident_guard.sql`
  restores identity-first mixed routine dispatch after a later migration
  accidentally reintroduced the JWT-only branch.
- `services/supabase/migrations/20260727190637_secure_explore_comment_reactions_and_defaults.sql`
  enables the last missing public-table RLS boundary, restricts reaction-table
  grants to the Edge admin client, and revokes unsafe global/schema future table
  and sequence defaults.
- `services/supabase/migrations/20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql`
  catalogs owned user foreign keys, reuses only valid/ready leading indexes,
  creates bounded small indexes, and requires supervised construction for large
  or partitioned relations.
- `services/supabase/functions/_tests/privilegedRoutineMigrationContract.test.ts`,
  `services/supabase/functions/_tests/serverApiKeyBoundaryMigrationContract.test.ts`,
  `services/supabase/functions/_tests/publicSchemaSecurityMigrationContract.test.ts`,
  `services/supabase/tests/privileged_routine_security.sql`, and
  `services/supabase/tests/public_schema_security.sql`, plus
  `services/supabase/scripts/audit_privileged_routine_acl.ts` provide static,
  disposable-catalog, and production read-only enforcement respectively.

Server species-count projection:

- `services/supabase/migrations/20260724222838_optimize_species_count_trigger.sql`
  owns the explicit lock/backfill/cutover transaction, private
  `(user_id, species_id)` scan-count ledger, one-time drift repair,
  deterministic per-user serialization, and the insert/delete/update/truncate
  transition-table triggers.
- `services/supabase/functions/_tests/speciesCountTriggerMigrationContract.test.ts`
  locks the `BEGIN → LOCK TABLE → final trigger → COMMIT` ordering plus the
  statement-level, no-full-recount schema contract.
- `services/supabase/tests/species_count_trigger_security.sql` exercises bulk
  inserts, unrelated updates, OLD/NEW owner and species transfers, deletion,
  dictionary `SET NULL`, catalog shape, fixed search paths, and API-role denial.

Public species data:

- `species-dictionary` — read-only public detail/catalog/overview projection
- `resolve-species-dictionary` — authenticated name-only page resolution;
  `index.ts` owns admission and verification orchestration, `db.ts` owns bounded
  lookups and service-only persistence, and `_shared/verifiedSpecies.ts` owns
  exact GBIF verification. Its migration adds the resolution rate counters,
  taxon-key index, and canonical identity reuse; see the
  [resolver contract](../services/supabase/functions/resolve-species-dictionary/README.md).
- `species-observation-stats` — public global iNaturalist charts behind
  canonical dictionary binding, optional user plus daily-HMAC IP limits,
  negative caching, bounded provider fetches, fenced database cold-fill leases,
  stale-if-error retention, and schema/identity-checked iOS memoization

Explore and social:

- `get-explore-feed`
- `get-explore-map-points` — privacy-safe Explore Map clustering with faceted
  species-category and image/video/audio filtering
- `get-explore-post`
- `get-explore-post-detail`
- `get-explore-author-profile`
- `get-explore-author-posts`
- `get-explore-hashtag-posts`
- `get-explore-species-posts` — authenticated, exact-species Community sightings
  cards with image-quality cursor ordering
- `get-explore-comments`
- `get-explore-comment-replies`
- `get-explore-mention-suggestions`
- `explore-post-chat` — private per-viewer Pro Field Chat grounded only in the
  public privacy-filtered post projection
- `field-trips`
- `report-explore-comment`
- `report-explore-post` — authenticated Explore post-content moderation queue
  used by feed, post-detail, and Community-detail **Report post** actions;
  separate from scan identification review
- `flag-issue` — backward-compatible JWT-authorized identification-dispute
  ingress; owner submissions atomically write `flagged_reviews` and mark the
  scan for review, while the exact old Community post-report signature is routed
  to `explore_post_reports` without changing scan review state
  (`services/supabase/migrations/20260831120000_submit_owned_flag_issue_atomically.sql`
  and
  `services/supabase/migrations/20260901032158_repair_owned_flag_issue_insert_detection.sql`
  plus the matching Deno contract and
  `services/supabase/tests/flag_issue_submission_security.sql` lock the database
  boundary)
- `get-explore-reactions`
- `get-explore-post-reactors` (detail-only people and their emoji)
- `set-explore-post-reaction`
- `set-explore-comment-reaction`
- `toggle-explore-comment-reaction` (older-client compatibility)

Explore community identification:

- `request-community-identification`
- `get-community-identification-feed`
- `get-community-identification-activity`
- `get-community-identification-detail`
- `update-community-identification-request`
- `search-community-taxa`
- `submit-community-identification`
- `withdraw-community-identification`
- `restore-community-identification`
- `submit-community-feedback`

The root iOS contract is Observations / Field trips / Identify. Identify owns
Species/Community, with Species leading and selected by default. Its `Models/`
define presentation and route values, `Services/` adapts live
network/identity/event dependencies, `ViewModels/` owns dashboard, pagination,
detail, search, and feedback state, and `Views/` plus grouped `Components/`
render without direct networking. The feature boundary is documented in
`apps/ios/Merian/Features/Explore/Identify/README.md`. Species reuses
`Features/SpeciesDictionary/Catalog/`; that product area owns the typed category
route and normalized browse-selection policy, Services-only endpoint/image/map
adapters, selection- and generation-fenced catalog/overview/map state, and
render-only root views and grouped components. Explore Shell still owns the
shared navigation stack, Identify/Species selection, and the overview model's
Explore-presentation lifetime. Catalog applies five-minute same-country reuse on
navigation and keeps stale content visible during refresh. The Activity route's
service adapter lives in
`services/supabase/functions/get-community-identification-activity/`, while
`20260731050009_add_community_identification_activity.sql` owns its internal
projection, triggers, shared request classifier, service-only RPC, and current
generation backfill.
`20260731063804_index_community_identification_activity_actor_user_fk.sql` owns
the actor-to-user reverse FK index used by deletion and identity maintenance.
`20260801145720_use_usernames_for_community_identification_activity.sql` owns
public-username attribution in the Activity read RPC. Species is the sole
Species Dictionary browser; taxonomy remains reference metadata and has no
separate route or feature directory.

The Explore root is organized under `apps/ios/Merian/Features/Explore/Shell/`:
`Models/` owns root-mode and initial-route policy plus the typed notification
destination, open token, and preparation outcome; `Services/` alone resolves the
live app-event stream and root Scans-library request plus narrow haptic actions;
`ViewModels/` owns latest-wins notification post preparation, token-checked
success/failure commits, and the one-time staged-to-pending dismiss handoff;
`Views/` owns the shared `NavigationPath`, root selection, destination
registration, lifecycle modifiers, sheet occupancy, and playback coordinator;
and `Components/` owns the segmented picker and bell. Shell views contain no
endpoint or singleton lookup, and every production Shell file remains below 600
lines. Field-trip route values consumed across Explore, Profile, Feed, Author
Profile, and Insights live with their product owner under
`Explore/FieldTrips/Models/FieldTripRoutes.swift`.

Observations Map is organized under `apps/ios/Merian/Features/Explore/Map/`:
`Models/` owns focus/request values, presentation, camera, filtering, and region
policy, plus its bounded in-memory cache; `Services/` is the only Map layer with
a live `MerianNetworkClient` closure; `ViewModels/` owns spatial
load/filter/selection state; and `Views/` plus grouped `Components/` own
camera/gesture timing and rendering. Its focused presentation and state tests
mirror that owner under `apps/ios/MerianTests/Features/Explore/Map/`; wire
decoding and payload tests remain under `MerianTests/Core/Network/`.

Observations Feed is organized under `apps/ios/Merian/Features/Explore/Feed/`:
`Models/` owns routes, composer values, and presentation policy; `Services/`
owns live feed/comment/interaction, post-detail, composer-image,
identity/entitlement, and notification-realtime adapters; `ViewModels/` owns
catalog, post-store, comments, hashtag pagination, and post-detail state; and
`Views/` plus grouped
`Components/{Cards,Catalog,Comments,Composer,Detail,DetailCards,Media,Shared}`
render without direct networking. Focus, scroll proxies, typed sheet occupancy,
and delayed presentation work remain view-local. Feed production files stay at
or below the pass's 600-line review guard.

Explore activity is organized under
`apps/ios/Merian/Features/Explore/Notifications/`: `Models/` owns decoded
notification values, stable row presentation, and notification reply routes;
`Services/` alone resolves live catalog/read, comment/reply, viewer-context,
telemetry, and error dependencies; `ViewModels/` owns generation-fenced catalog
and reply-thread loading/pagination state; and `Views/` plus grouped
`Components/` render without direct networking or singleton lookup. The Shell
notification coordinator owns the latest-open token, token-checked preparation
outcome commit, and separated staged and pending dismiss destinations, while
Feed keeps `ExploreNotificationReplyThreadTarget` inside `ExplorePostRoute`.
Failed catalog refresh preserves the last successful cursor, and a server reply
found after bounded notification fallback insertion replaces that fallback in
place.

The cross-area public-media renderer, player bridge, hero image, indicators,
playback extensions/state/policies/coordinator, and narrow loader adapters live
under `apps/ios/Merian/Features/Explore/Shared/Media/`. The domain-neutral Pro
badge lives under `Core/UI/Components/`; reusable spectrogram loading lives
under `Core/Media/`; and secure comment-avatar fallback shared by Feed and
Notifications lives under `Explore/Shared/Models/`. Shell coordinates navigation
but Feed owns its tab, hashtag, detail, and typed route declarations.
Playback-policy/state tests mirror Shared/Media; Feed, Notifications, and Shared
presentation/state tests mirror their production owners; the cross-surface
audio-boost suite remains under `MerianTests/Features/Explore/`.

Explore publishing, activity, and delivery:

- `get-explore-notifications`
- `get-explore-unread-notification-count`
- `mark-explore-notifications-read`
- `share-scan-to-explore`
- `unshare-explore-post`
- `update-explore-field-notes`
- `update-public-username`
- `update-public-display-name`
- `update-public-avatar`
- `check-public-username`
- `get-scan-explore-share-state`
- `set-explore-post-like`
- `set-user-follow`
- `create-explore-comment`
- `delete-explore-comment`
- `register-push-device`
- `send-push-notification`
- `block-user`

`services/supabase/functions/_shared/fieldChatResponse.ts` owns the additive
success-envelope identity shared by `insight-chat`, `explore-post-chat`, and
`species-dictionary-chat`. Every empty/populated thread and action success
echoes its requested scan, post, or species UUID as `subject_id`; iOS validates
that echo plus populated message/conversation identity before applying candidate
success. The same helper binds each assistant to its canonical send UUID in
private metadata, derives its deterministic UUIDv8 row identity, and boundedly
coalesces in-flight quota/transport replays; both response messages project that
UUID so iOS can require one complete pair and manual retry can preserve the
original request. New sends reserve both rows inside the 30-row cap, and
conflicting text reuse fails explicitly. Route-local prompt builders keep
Insight model output and deterministic Explore labels within the shared
three-prompt, 120-character safety contract.

`services/supabase/functions/_shared/fieldChatReservation.ts` owns the
fail-closed adapter to `20260729163616_reserve_field_chat_sends_atomically.sql`.
That migration serializes per-user cross-table daily accounting before
per-conversation capacity admission, inserts the exact subject-bound user row
atomically, blocks a second unanswered UUID in that conversation, and revokes
direct browser-role chat-table access. Its narrow stale-quota routine can reopen
only a ten-minute-stale exact request whose user row exists and assistant is
absent; the subsequent provider attempt is newly metered.
`20260730180000_bind_field_chat_rows_to_subjects.sql` then makes retained
Insight conversations structurally match their exact scan owners and makes
conversation/scan-or-post/user and copied-feedback identity structural through
validated deferred composite foreign keys. It cleans only impossible historical
private bindings, independently binds conversation-optional feature feedback to
its exact scan owner, and closes the remaining direct Insight-feedback Data API
surface. `20260821030027_add_species_dictionary_field_chat.sql` adds the
Edge-only Dictionary conversation, message, and feedback tables; subject type
`species_dictionary`; operation `species_dictionary_chat_reply`; three-family
daily admission and stale recovery; and anonymous-account merge support. Each
Dictionary send reloads only the bounded public reference projection and treats
its text as untrusted data. Community sightings, observation charts, scans,
notes, people, locations, media, URLs, and attribution identities never enter
that prompt. `20260824210544_preserve_field_chat_daily_usage.sql` adds the
content-free user/day admission aggregate, service-only read RPC, atomic
counter-backed reservation/conversation creation, and conservative Ghost-merge
coalescing. It registers the effective handler, asserts registry coverage, and
short-locks all three conversation/message families to remove historical
message-less threads. It blocks novel sends through the next database-observed
UTC boundary and until explicit activation, permanently reserves conversation
insertion for the atomic RPC, and keeps exact persisted replays available. Any
unverifiable usage or cutover read fails closed. Source fixtures exercise all
three production reservation/delete paths and the full current-day merge race;
they require non-skipped disposable-database execution before release.

iOS now allowlists `species-dictionary-chat` for exact-key ambiguous replay, and
runtime handler-core tests exercise action/ownership/recovery. The database
boundary prevents quota denial from creating an empty conversation. After all
three selected bundles deploy, a one-way service-only activation records the
candidate, migration, and all three content-addressed route digests after the
live marker/digest probes match. Database `ready` force-selects the full fleet
after the migration becomes the deployment baseline. Swift and Deno execute
`docs/contracts/species-dictionary-prompt-label-policy.json`, including U+2013
EN DASH, U+0085 normalization, and U+FEFF rejection. The handler suite executes
the actual wrapper with deterministic accepted/refused authenticators; hosted
real-token authentication remains an evidence gap. The checked-in
`species_dictionary_chat_production_hold` blocks Supabase production until
controls execute without database skips, same-SHA hosted gates, the real
released-binary V49→V50 install-over, and canonical external evidence pass. Its
source verifier requires the named ID; after a reviewed inactive change, the
exact-SHA-checked mutation job verifies current protected main, merged-PR
provenance, required checks, and automatic environment policy. No reviewer click
or per-commit clearance is required; the active hold remains until its evidence
is complete. Optional audit tools download and recompute retained artifact
digests and verify their exact-SHA runs and payloads.

Data lifecycle, identity, and exports:

- `sync-collections`
- `merge-ghost-profile` — uses a source-issued, provider-bound proof to
  atomically merge guest data before purging the anonymous Auth shell. Its
  pending schema-aware hardening must execute source-controlled ownership
  policies, verify derived scan state, and schedule permanent provider repair.
- `reconcile-ghost-profile-merges` — scheduled service-role worker that leases
  committed merge receipts and retries obsolete anonymous Auth deletion.
- `resolve-purchase-principal` — authenticated, additive stable-purchase
  identity boundary. Ordinary resolution hashes a device-only installation
  capability and uses a monotonic binding intent to resolve one immutable
  server-owned RevenueCat customer. Protocol 3 adds source-authenticated
  sign-out reservation, exact fresh-anonymous claim, and source-only
  cancellation on the same route. Prepared rows block generic binding writes,
  and terminal intent fences reject resolver completions begun before
  preparation. The route never accepts an Auth UUID, principal ID, or provider
  ID from the body and never performs a provider transfer.
- `transfer-signout-purchases` — legacy-mode StoreKit-only compatibility
  handoff. It binds one fresh anonymous UUID, requires RevenueCat receipt sync
  plus server verification, and leaves account promotions on the linked source.
  Retain it throughout the supported old-client and rollback window.
- `safe-delete` — authenticated intake plus immediate processing for the durable
  `pending → storage_pending → auth_pending → completed` account-deletion state
  machine; retained scans become account-detached ownerless scientific
  tombstones that preserve exact coordinates and other scientific facts, all
  canonical R2 prefixes receive a cursor-persisted sweep and delayed empty
  verification pass, a stored Apple credential is revoked and destroyed, and
  only then may Auth be deleted. Legacy Apple identities return a durable manual
  fallback disposition that supporting clients persist; fallback delivery to
  older binaries remains release-gated. The SQL storage claim requires the
  matching cleaned-up `storage_pending` private job and vetoes live profiles or
  owned scans. See the
  [canonical scientific-retention contract](./backend-and-data/17-scientific-observation-retention.md).
- `register-apple-revocation-token` — authenticated one-use Apple code exchange,
  identity-subject binding, Vault refresh-token persistence, token-free
  response-loss idempotency, and compensating revocation after persistence
  failure. See the
  [canonical Apple deletion contract](./backend-and-data/20-sign-in-with-apple-account-deletion.md).
- `reconcile-account-deletions` — scheduled service-role worker that leases and
  resumes incomplete relational, storage, Apple provider, and Auth deletion work
  without accepting caller-selected user IDs. Aggregate
  queue/lease/configuration health is exposed only through
  `get_account_deletion_health()` and consumed by
  `services/supabase/scripts/monitor_account_deletion_health.ts` plus the
  independent `.github/workflows/account-deletion-health-monitor.yml` schedule.
- `repair-scan-image` — owner-authenticated R2 inspection and missing-image
  repair; promotes one surviving staging image and atomically replaces its exact
  URL across active scan, captured-media, normalized-media, and matching
  owner-post Explore metadata.
- `delete-scan` — owner-authenticated fast path that durably fences a scan UUID
  before deleting canonical and derived R2 media, then removes the owner row
  only after storage confirms deletion.
- `auto-purge-nonbio` — service-only daily retention intake that
  generation-locks and revalidates expired non-biological rows, writes permanent
  scan-deletion fences, and delegates all R2 and row erasure to the independent
  reaper.
- `reconcile-scan-deletions` — service-only deadline-draining reaper for
  interrupted scan erasure; leases private jobs, compare-before-releases
  failures, and emits aggregate oldest-pending/backlog/expired-lease health.
- `submit-feedback-survey`
- `request-export-dwca` — deployed tombstone-compatible permanent-account
  boundary; while the launch gate is off its atomic service-only request RPC
  returns `disabled`, and global exports remain internal-only.
- `export-dwca` — currently disabled service-authenticated resumable worker;
  `_shared/dwcaReleaseState.ts` reads the canonical database gate and `db.ts`
  owns canonical phase claims, immutable job-membership/revision validation,
  full-member privacy fences before final side effects, claim-bound 100-row/256
  KiB keyset access, durable cursors/manifests, and row/byte budgets;
  `archive.ts` owns fixed-capacity incremental CSV encoding while `crc32.ts`
  calculates bounded chunk checksums and composes full-entry CRCs algebraically;
  `zip.ts` owns manifest-sized archive streaming without a per-archive-byte
  checksum loop; `storage.ts` owns claim-fenced CSV chunks and R2 multipart
  upload plus short read-only signing; `downloadGrant.ts` owns 256-bit
  application capability generation; `pseudonym.ts` owns versioned export HMACs;
  `worker.ts` performs one preparation, assembly, or delivery phase per claim
  and revalidates after every delivery suspension; and `drain.ts` owns
  sequential deadline/step bounds, oldest-due waves, failure suppression, and
  aggregate queue-health classification. Independent production continuation and
  archive-deletion alerting lives in `scripts/monitor_dwca_export_queue.ts` and
  `.github/workflows/dwca-export-health-monitor.yml`, so absent cron/Vault
  configuration cannot silence both workers and monitoring.
- `download-dwca` — public opaque-capability GET boundary; while the launch gate
  is off it returns `410` before signing storage. When enabled it applies a
  distributed address limit and full-source privacy fence on every click before
  issuing a no-store R2 read redirect valid for at most 30 seconds.
- `reconcile-dwca-archive-cleanup` — scheduled service worker that
  deadline-drains UUID-leased archive-deletion outbox rows, durably backs off
  storage failures, purges retained completed snapshots, and emits aggregate
  oldest-due/backlog/expired-lease health.
- `revenuecat-webhook` — verifies the configured bearer credential and
  RevenueCat raw-body HMAC, parses bounded event identities, fetches
  authoritative CustomerInfo, and commits idempotent per-user state through
  service-only database RPCs. Route-local `handler.ts`, `protocol.ts`,
  `signature.ts`, `subscriber.ts`, and `db.ts` keep those boundaries
  independently testable.
- `reconcile-revenuecat-subscribers` — scheduled service-role repair worker that
  deadline-drains small durable queue leases and applies newer authoritative
  CustomerInfo snapshots when webhook delivery is missed; `db.ts` also owns the
  service-only backlog-health read used by
  `services/supabase/scripts/monitor_revenuecat_reconciliation.ts` and its
  scheduled GitHub monitor.
- `get-filtered-discovery-feed` — retained authenticated backend feed surface;
  current iOS Explore feed loading uses `get-explore-feed`, so no iOS endpoint
  owns this route and it is absent from the native replay classification.

Scheduled/background workers:

- `refresh-species-content`
- `refresh-species-model-content` — priority-ordered model-content worker for
  habitat, lookalikes, and group tags. `_shared/verifiedSpecies.ts` owns bounded
  exact-GBIF identity and taxonomy validation shared with authenticated
  dictionary resolution; `db.ts` separates retryable provider/partial failures
  from terminal empty results and persists validated candidates through
  service-only claim/write RPCs.
- `refresh-taxonomy-nodes`
- `community-taxonomy-status`
- `sync-community-taxonomy-index`
- `process-community-consensus-jobs`
- `refresh-merian-reference-images`
- `expire-subscription-passes`
- `auto-purge-nonbio`
- `reconcile-scan-media-assets`
- `reconcile-ghost-profile-merges`
- `backfill-explore-audio-spectrograms`
- `replay-scan-ingestion`
- `scan-media-health`
- `reconcile-scan-deletions`
- `reconcile-dwca-archive-cleanup`

Every function above has a `[functions.<name>]` entry in
`services/supabase/config.toml`. `merge-ghost-profile` and `request-export-dwca`
intentionally use `verify_jwt = true`. App-facing routes with a documented
custom identity policy may set `false` and authenticate inside shared handler
code; service-role workers such as `reconcile-ghost-profile-merges` set `false`
for `pg_net` reachability and enforce an exact constant-time match through
standard format-aware transport: current opaque keys use `apikey` only, while a
legacy service-role JWT uses matching `apikey` and Bearer values. Each function
also has a generated local `deno.json` backed by `functions/dependencies.lock`.
The dependency/deploy control plane lives in
`services/supabase/scripts/function_dependency_tools.ts`,
`sync_function_deno_configs.ts`, `validate_function_dependencies.ts`,
`plan_function_deploy.ts`, and `deploy_function_batches.sh`; CI uses that graph
to type-check deploy-time configs and select transitive runtime consumers. The
discovery-based `test_supabase_tooling.sh` runner type-checks every standard
TypeScript script, runs every `*_test.ts`, exercises the isolated DTO validator,
and syntax-checks/tests shell tooling without a hand-maintained test list. The
shared `validate_migration_contracts.sh` runner discovers every
`*Migration*.test.ts` and `migration*.test.ts` source contract for both the
local Make target and production deploy before database replay. The inventory
above is descriptive rather than a second source of truth:
`function_dependency_tools_test.ts` requires exact name-for-name parity between
`config.toml` and discoverable function graphs without hard-coding a fleet size.

## Supabase Media Projections

Legacy owner-row recovery uses both a private rollout timestamp and the
immutable exact `failed_scan_ingestions` ID snapshot captured by
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql`. Snapshot
membership is mandatory: a producer insert blocked behind migration DDL cannot
gain historical recovery authority from its earlier transaction-start timestamp.

On iOS, `Core/Network/Endpoints/MerianNetworkClient+ScanPublication.swift` owns
direct publication mapping;
`Core/Network/Recovery/MerianNetworkClient+OwnedScanRecovery.swift` and its
payload/policy siblings own record-based and Field Chat compatibility recovery;
and `Core/Network/Media/ScanPublicationMediaRestorer.swift` plus its policy own
local-media repair. `MerianNetworkClient.swift` remains in this boundary only as
the façade for its private authenticated bridge and narrow owner-ID value.

| Surface                                       | Current files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scan ingestion jobs and intents               | `services/supabase/migrations/20260705120000_add_scan_ingestion_jobs.sql`, `services/supabase/migrations/20260705130000_extend_scan_ingestion_jobs_media_manifest.sql`, `services/supabase/migrations/20260705140000_add_scan_ingestion_intents.sql`, `services/supabase/migrations/20260705150000_schedule_scan_ingestion_replay.sql`, `services/supabase/migrations/20260707143157_cap_scan_ingestion_replay_attempts.sql`, `services/supabase/migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql`, `services/supabase/migrations/20260728220000_persist_idempotent_scan_responses.sql`, `services/supabase/migrations/20260729012153_fix_video_scan_canonical_finalization.sql`, `services/supabase/functions/_shared/scanIngestionJobs.ts`, `services/supabase/functions/_shared/scanIngestionIntents.ts`, `services/supabase/functions/_shared/scanIngestionCompatibility.ts`, `services/supabase/functions/_shared/scanIngestionRetry.ts`, `services/supabase/functions/_shared/identify/completedResponse.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/replay-scan-ingestion/`, `services/supabase/functions/_tests/scanMediaIngestionContract.test.ts`, `services/supabase/functions/_tests/dwcaDownloadAndScanFinalizationMigrationContract.test.ts` | Durable server-side state ledger, sanitized replay intent, and scheduled replay dispatcher for accepted scan ingestion attempts. One shared helper supplies the deterministic 30-second ordinary `failed_retryable` deadline to all four scan producers without overriding explicit server-directed values. Claim creation and compatibility recovery share a per-scan database generation lock. The multimodal path updates job state through inference, media promotion, scan insert, and failure; completion is written last by one transaction that proves every claimed staging-key disposition and ready canonical media row and stores the validated success envelope. Canonical projection follows structured captured media or the legacy standalone-image/playback/audio timeline, never treating video inference frames as standalone display rows. Claims include upload-session ids and a normalized media-manifest checksum so retries can be tied back to the exact media shape. Compatibility scan-producing endpoints write the same ledger before returning success, with staged image/audio and text-only intents shaped for multimodal replay. A repeated request first replays a stored completion or reconstructs an exact durable owner row as marked `200`, never calling the provider twice; reconstructed replay may retain a retryable canonical ledger. The paired intent row stores telemetry/descriptors/staged keys without raw media bytes, marking inline-media requests as non-resumable. The replay worker claims due resumable staged media/audio/video or text-only jobs and re-invokes the multimodal path with the same `client_scan_id`, capped at 10 server replay claims before structured `replay_exhausted`; status polling keeps `found` / `not_found` compatibility while exposing optional job details for retry and ops visibility. The contract matrix locks these guarantees across image, audio, text-only, video, status, repair, recovery, and Explore-share seams.                     |
| Captured Media Wire V1                        | `services/supabase/functions/_shared/capturedMediaContract.ts`, `services/supabase/scripts/validate_captured_media_dtos.ts`, `services/supabase/scripts/validate_captured_media_dtos_test.ts`, `apps/ios/Merian/Core/Data/Database/CapturedMediaWireDTOs.swift`, `apps/ios/Merian/Core/Data/Database/HistoricalSync/Models/HistoricalSyncModels.swift`, `apps/ios/Merian/Core/Data/Database/HistoricalSync/Decoding/HistoricalScanPageDecoder.swift`, `services/supabase/functions/identify-multimodal/capturedMedia.ts`, `services/supabase/functions/share-scan-to-explore/db.ts`, `services/supabase/functions/reconcile-scan-media-assets/worker.ts`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Executable contract and generated PostgREST boundary for the owner-visible mixed-media timeline. New nonempty writes are strict, bounded, credential-free HTTPS V1 with text-only descriptions; compatible reads tolerate historical aliases, timestamps, nested video audio, `localFile`, and `[]`, while canonical rewrites discard retired/device-only data and store `null` when nothing durable remains. Historical iOS sync decodes rows independently, quarantines malformed rows without poisoning a page, advances pagination by raw remote row count, and classifies a targeted malformed cloud-complete row as an immediate no-redispatch contract mismatch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Scan admission preview                        | `services/supabase/migrations/20260809155517_add_scan_admission_preview.sql`, `apps/ios/Merian/Core/Security/ScanAdmissionManager.swift`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionDependencies.swift`, `apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+SubmissionAdmission.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Caller-scoped read-only paid → complimentary → Flash UX preflight. iOS uses an exact-route bridge over the shared certificate-pinned session with a two-second request/wall-clock deadline and no wait/cache/retry. Only classified connectivity failure plus current local eligibility selects queue-only; malformed/authentication/TLS/server failures stay blocked. No preview reserves quota, and durable replay still requires authoritative `reserve_ai_quota(...)`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Identification latency and deferred context   | `services/supabase/migrations/20260715153946_reduce_identification_latency_round_trips.sql`, `services/supabase/functions/_shared/identify/latencyDb.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/update-scan-context/`, `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Inference.swift`, `apps/ios/Merian/Core/Network/Inference/`, `apps/ios/Merian/Core/Network/Transport/AuthenticatedRequestExecutor.swift`, `apps/ios/Merian/Core/Network/Transport/PinnedNetworkTransport.swift`, `apps/ios/Merian/Core/Network/Transport/AuthenticatedTransportDispatcher.swift`, `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`, `apps/ios/Merian/Core/AI/Inference/Request/InferenceLiveRequestService.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionEnvironmentContextGrace.swift`, `apps/ios/Merian/Features/Capture/Submission/Services/CaptureSubmissionDeferredContextService.swift`, `apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+VisualSubmission.swift`                                                                                                                                                                                                                                                                                 | Keeps the durable queue/auth gates while shortening the non-model critical path. One service-role RPC claims ingestion and records its sanitized intent before Gemini; eligible biological results use at most one RPC to hydrate cached primary/candidate dictionary data afterward. On iOS, `InferenceLiveRequestService` owns final live request adaptation, optional staged-video upload, and the single endpoint invocation; the focused Core Network endpoint and stateless payload/policy files own wire construction, media budgets, account-bound request values, the queue-backed/direct transport choice, and cancellation-aware off-main body preparation. Transport policy owns replay decisions; the request-scoped executor applies bounded retry and injected Auth effects, the pinned transport owns the sole session/TLS boundary, the authenticated dispatcher owns per-attempt Auth/session validation and upload progress, and the main client injects both stateful owners. All current modalities share the durable server success fence. The eligible live-camera still path additionally gives weather/geocoding 150 ms, avoids simultaneous inline/background uploads, commits late context locally before the one-retry `/update-scan-context` adapter patches it through the staged-context table/trigger, and never invokes a second identification request; gallery, audio-bearing, and video submissions retain their existing client submission behavior while participating in the same server durability boundary. Diagnostic headers and structured metrics cover tap-to-render without exposing scan/user/species/location identifiers. Model selection and all generation settings remain unchanged.                                                                                                                                                                                                                                                                                                    |
| Owner-row durability and compatibility repair | `services/supabase/functions/_shared/identify/db.ts`, `services/supabase/functions/_shared/scanPersistence.ts`, `services/supabase/functions/_shared/scanRecovery.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/check-scan-status/`, `services/supabase/functions/share-scan-to-explore/`, `services/supabase/migrations/20260728035237_harden_dwca_downloads_and_scan_finalization.sql`, `services/supabase/migrations/20260729173000_recover_media_abandoned_owned_scans.sql`, `services/supabase/migrations/20260729200000_harden_media_abandoned_scan_recovery_proof.sql`, `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ScanPublication.swift`, `apps/ios/Merian/Core/Network/Recovery/MerianNetworkClient+OwnedScanRecovery.swift`, `apps/ios/Merian/Core/Network/Media/ScanPublicationMediaRestorer.swift`, `apps/ios/Merian/Features/Explore/Shared/Models/ExploreErrorFormatter.swift`, `apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+Toolbar.swift`                                                                                                                                                                                                                                                                                                                                           | Makes every scan-producer HTTP success contingent on moderation, required media promotion, primary species resolution, duplicate-safe scan creation, and owner-scoped read-back. A fresh provider-owning multimodal success additionally requires complete-last canonical-media finalization. Its later same-UUID request may return a marked reconstructed replay from the exact owner row while canonical repair remains retryable, without another provider call. Compatibility producers attempt finalization synchronously; only a post-row failure may leave a retryable ledger while returning the validated owner-row response immediately. A returned write rejection permits quota/media cleanup only after an exact-owner read proves absence; lost or unreadable responses preserve committed quota and promoted objects until same-UUID recovery. Older/interrupted missing rows can be repaired only from bounded non-media local state after an atomic database decision defers to active/retryable ingestion and permits exact structured `replay_exhausted`, or exact `media_reconciliation_abandoned` with composite service proof: a post-result dead letter no earlier than the latest charged normal/replay inference reservation, producer-generation-appropriate evidence, no active reservation or invalid timestamp lineage, and no moderation-rejected or moderation-pipeline-failed capture row. A private rollout cutoff bounds legacy unstructured proof; modern proof binds exact quota identity, validated provider output, and completed safety evaluation. Current/later policy, unproven abandonment, unknown, and arbitrary terminal reasons fail closed. Explore can combine repair with owner-staged media and applies the same proven-absence rule to restoration updates; Ask the Community repairs through status first; Field Chat repairs non-media state before presentation. Technical errors are translated into retryable customer-facing messages without granting direct scan writes to iOS. |
| Scan media assets                             | `services/supabase/migrations/20260705100000_add_scan_media_assets.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711143348_repair_scan_media_assets_audio_constraints.sql`, `services/supabase/migrations/20260711171512_backfill_missing_ready_audio_assets.sql`, `services/supabase/functions/_shared/scanMediaAssets.ts`, `services/supabase/functions/identify-multimodal/`, `services/supabase/functions/reconcile-scan-media-assets/`, `services/supabase/functions/scan-media-health/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Normalized image/video/audio lifecycle. Standalone audio is promoted into `audio_storage_urls`, `captured_media`, and ready owner-scoped audio assets; extracted video audio remains inference-only. The explicit constraint repair upgrades early production tables that `CREATE TABLE IF NOT EXISTS` could not reshape, and the follow-up refresh migration makes audio part of the canonical RPC and backfills durable recordings that lack normalized rows. Repair and health paths retain their existing staged-media responsibilities.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Owned scan image recovery                     | `services/supabase/migrations/20260726041109_fence_storage_erasure_claims.sql`, `services/supabase/migrations/20260726041338_repair_owned_scan_image_references.sql`, `services/supabase/functions/repair-scan-image/`, `apps/ios/Merian/Core/Data/Images/Recovery/`, `apps/ios/Merian/Core/Data/Images/Services/CloudScanImageRepairActor.swift`, `apps/ios/Merian/Core/Data/Images/LocalImageLoader.swift`, `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+MediaStorage.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Prevents stale storage outbox rows from authorizing live-account prefix erasure, reconnects strongly evidenced Documents files to missing durable URLs, renders recovered files locally, and restores verified-missing cloud references through owner-scoped staging promotion plus one atomic metadata transaction. Production deployment and recovered-object coverage remain independently verifiable states.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Explore post media                            | `services/supabase/migrations/20260703130000_add_explore_post_media.sql`, `services/supabase/migrations/20260710120000_add_explore_audio_moderation.sql`, `services/supabase/migrations/20260711055524_add_explore_audio_moderation_attestations.sql`, `services/supabase/functions/_shared/explorePostMedia.ts`, `services/supabase/functions/_shared/exploreComposerMedia.ts`, `services/supabase/functions/_shared/audioModeration.ts`, `services/supabase/functions/_shared/audioSpectrogram.ts`, `services/supabase/functions/share-scan-to-explore/`, `services/supabase/functions/request-community-identification/`, `services/supabase/functions/update-explore-field-notes/`, `services/supabase/functions/backfill-explore-audio-spectrograms/`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Post-owned image/video/audio snapshots. Audible media must have a matching content-addressed attestation or pass the dedicated Gemini speech/non-speech classifier under the authoritative quota boundary before share, Community-request, or edit replacement; changed bytes, model, or policy contract force re-moderation. Approved WAV audio gets a deterministic persisted spectrogram poster shared by web and normalized media; a bounded service-role repair worker fills historical blanks while unsupported legacy codecs keep playback and the icon fallback. Legacy local audio can be repaired through owner-scoped staging into `audio_storage_urls`, canonical `captured_media`, and normalized assets before the same gate runs. Failed attempts create no pending/public media state; maps, widgets, profile grids, and compact previews remain thumbnail-first.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Explore media health                          | `services/supabase/migrations/20260726144647_add_explore_media_quarantine_lifecycle.sql`, `services/supabase/migrations/20260726144754_implement_explore_media_quarantine_state_machine.sql`, `services/supabase/migrations/20260726174555_align_explore_author_publication_contract.sql`, `services/supabase/functions/reconcile-explore-media-health/`, `services/supabase/functions/get-explore-media-incidents/`, `services/supabase/functions/ingest-r2-media-events/`, `docs/backend-and-data/12-explore-media-health-and-quarantine.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Direct signed R2-origin checks confirm unexpected primary-object loss only after two spaced `404` responses. Public projections omit confirmed-missing items and reversibly quarantine all-missing posts while preserving author intent and engagement. Profile count/preview/grid visibility is canonical; owner recovery totals and service-wide aggregate scope remain separate. Owner incidents, repair-triggered restoration, audit runs, optional event acceleration, and read-only verifier credentials are one compatibility contract.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Explore owner share-state parity              | `services/supabase/migrations/20260729120000_align_explore_share_state_media_health.sql`, `services/supabase/functions/get-scan-explore-share-state/`, `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ExplorePostManagement.swift`, `apps/ios/Merian/Features/Insights/Sharing/ViewModels/InsightSheetViewModel+ExploreShareState.swift`, `apps/ios/MerianTests/Core/Network/Endpoints/ExploreShareStateEndpointTests.swift`, `apps/ios/MerianTests/Core/Network/MerianNetworkClientTests.swift`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Keeps owner-only publication identity available for media repair while deriving `is_explore_feed_visible` from the same moderation, aggregate quarantine, usable-item, tombstone, species, shadow-ban, and Community-publication boundaries as canonical Explore projections. The endpoint requires matching scan identity and coherent UUID/time/privacy topology before returning server state; a legitimately hidden post does not imply a Community request or visible destination. Insight Sharing owns scan-keyed cache reconciliation and presentation-generation-fenced UI state. Endpoint tests own wire/topology coverage; the aggregate suite retains the Insight cache-state integration.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

The July 28 incident extensions to these surfaces are
`20260728230000_recover_inline_scan_ingestion_completions.sql`,
`20260728231000_make_staged_scan_media_registration_idempotent.sql`,
`20260728232000_ensure_scan_user_profile.sql`,
`20260728233000_recover_identity_merge_interrupted_scans.sql`, and
`20260729012153_fix_video_scan_canonical_finalization.sql`. Together with
`generate-upload-urls/assetRegistration.ts`,
`share-scan-to-explore/restoredMediaValidation.ts`, and the four scan producers,
they exclude phantom inline sources, serialize signing retry, enforce the
Auth-backed profile prerequisite, fence in-flight identity merge, retain
standalone audio, project video media without standalone inference frames, and
owner-scope Explore restoration.

The normative joined behavior, success boundary, recovery order, deployment
unit, and verification matrix are maintained in
[`16-scan-ingestion-reliability-and-recovery.md`](backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

The scan-admission preview is the sole non-Edge PostgREST exception admitted by
that Core Network bridge. Wrong routes and missing or blank credentials fail
before dispatch; the two-second pinned request remains caller-scoped,
non-caching, and non-retrying.

## Internal admin surface

- `apps/admin/`: isolated Next.js + Mantine SSR admin for
  `admin.naturebook.earth`, with Google OAuth, TOTP AAL2, role-aware navigation,
  strict response headers, CSRF/origin-checked Server Actions, and no
  service-role key. Its dependency-security tests and
  `.github/workflows/admin-quality.yml` enforce a frozen install, reviewed
  Next.js/PostCSS/Sharp floors, blocking dependency audit, tests, type-check,
  and production build for every pull request and affected `main` changes.
  Repository rules must require the resulting status, and the separate Vercel
  project must use it as a required Deployment Check before domain promotion.
- `services/supabase/migrations/20260719161112_add_internal_admin_foundation.sql`:
  internal membership/session/audit/review/feedback/pricing schema, narrow admin
  RPCs, reversible post moderation, and canonical AI usage ledger.
- `apps/admin/app/(admin)/complimentary-entitlements/` and migration
  `20260802235833_three_complimentary_pro_scans.sql`: analyst-only aggregate
  balances, hold age, settlement reasons, Flash fallback, exhaustion, and paid
  conversion with no per-user ledger browser surface.
- `services/supabase/functions/report-user/`: authenticated non-self visible
  profile reporting endpoint.
- `services/supabase/functions/_shared/aiUsage.ts`: normalized Gemini modality
  accounting and bounded best-effort writers for independent operations.
- `services/supabase/tests/admin_foundation_security.sql` and
  `admin_review_ai.sql`: live pgTAP authorization/session and grouped
  review/moderation/ledger contracts.
- `docs/backend-and-data/10-internal-admin.md` and
  `11-internal-admin-operations.md`: architecture/data contract and the
  setup/deployment/recovery operator runbook.

## Test Inventory

Swift unit tests live under `apps/ios/MerianTests/` and cover:

- Active schema models and migration invariants.
- Capture workspace staging, camera analysis, Photos document-import durability
  and EXIF handling, active capture-goal presentation/gesture policy,
  audio/describe helpers, and queued handoff flows.
- Field trip capture-context decoding and provider mapping into generic goals,
  cross-field trip order and wraparound, completion advancement,
  account-isolated caching, stale-data retention, exact artwork mapping, typed
  destinations, and focused Explore routing, plus private completed-scan ID
  decoding for item-specific catalog/detail thumbnails.
- Core AI, network, security, hardware, analytics, utilities, and data actors.
- `Core/Architecture/CoreIntegrationArchitectureTests.swift` freezes the Core
  root/domain and README inventories, the explicit one-file residual size
  inventory, stateless Policies plus their exact documented file/clock/jitter
  inputs, transport/persistence-free shared UI components, throwing SwiftData
  reads, and self-tested privacy guards for error, server-message, and local-
  path logging.
- `Core/Utilities/CoreUtilitiesIntegrationArchitectureTests.swift`
  (`CoreUtilitiesArchitectureTests`) freezes the exact Foundation-only
  date/string helper inventory and every declaration, member, and test moved to
  App Lifecycle, Concurrency, Data Field Notes, Offline Sync, Errors, Hardware,
  Media, Core UI, and Species Reference. Concurrency ownership includes both
  `DetachedWorkCategory` and `DetachedWork` in the same focused source.
- `Core/AI/Inference/InferenceScanReplacementTests.swift` owns durable
  reanalysis metadata and original-retention coverage;
  `InferenceIntegrationAuditTests.swift` owns visual/audio/Describe overlaps
  between live results, Auth, cancellation, and exact queue generations.
  Injected parser outcomes do not substitute for database-actor persistence
  tests.
- `Core/AI/Inference/InferenceLiveQueueServiceTests.swift` owns exact durable
  adapter forwarding without a live singleton;
  `InferenceLiveAttemptCoordinatorTests.swift` owns local/durable identity,
  full-invalidation and exact-current retirement callback ordering, re-entrant
  replacement preservation, retained displaced-task quiescence, recovered-
  background admission, partial-identity rejection, and suspended same-scan
  finalization races.
- `Core/AI/Inference/InferencePresentationCoordinatorTests.swift` owns prepared,
  active, nonvisual, stale-owner, reset, visual queue-context, Auth admission,
  post-drain re-entrant cleanup, pending-metric preservation, and one-shot
  first-render lifecycle plus exact-source clock-rebinding coverage.
  `InferenceArchitectureTests.swift` freezes its non-observable, effect-free
  boundary and prevents its private state from returning to `InferenceEngine`.
- `Core/AI/Inference/InferenceSessionLifecycleCoordinatorTests.swift` owns the
  cross-owner new-scan, visual/nonvisual replacement, queue-handoff,
  cancellation, historical-load, and cancellation-ignoring Auth-drain matrix.
  Its architecture sibling freezes reviewed operation order, effect exclusions,
  method-local engine/submission delegation without facade-owned recovery
  guards, semantic task operations, and the 600-line ceiling.
- `Core/AI/Inference/InferenceSessionLifecycleRecoveryTests.swift` owns exact
  background ownership transfer, pre-publication displaced-task cancellation,
  stale same-scan rejection, queued-result identity fencing/publication, and
  queued-record callback ordering. The shared lifecycle test support contains
  only inert collaborators and value fixtures.
- `Core/AI/Inference/InferenceLiveMediaProjectorTests.swift` owns display-image
  selection, default/explicit timeline behavior, aligned provider and owner
  projections, focus-region carry-through, explicit poster suppression/fallback,
  adjacent-still retention, secure video admission, compatible local-path
  lookup, persisted-image remapping, and legacy nonvisual filtering/modality
  behavior. `InferenceArchitectureTests` prevents the extracted mapping and
  filesystem access from returning to the engine.
- `Core/AI/Inference/InferenceLivePipelineCoordinatorTests.swift` owns
  deterministic admission, empty visual encoding, queue-less modality order,
  durable nonvisual finalization, circuit routing, and suspended replacement
  coverage; `InferenceLivePipelineDurableVisualTests.swift` owns the complete
  queue-backed visual success order through exact deletion, notification,
  benchmarks, hydration, milestones, and cleanup.
  `InferenceLiveSubmissionCoordinatorTests.swift` owns synchronous visual,
  audio, and Describe startup presentation, Auth rejection, visual empty-payload
  release-before-retirement, nonvisual retirement-only compatibility, and task
  registration. The architecture suite freezes both modality orders, engine
  delegation, effect exclusions, and the 600-line startup-owner ceiling.
  `InferenceLivePresentationCoordinatorTests.swift` owns exact accepted/stale
  publication, suppression of stale persisted-media projection, queue-less
  first-render transfer to the server scan ID, rejection of stale transfer,
  publication-before-event ordering, exact finish routing, and all three typed
  failure actions, plus exact request-body session forwarding, phrase-deck
  preservation on visual cancellation, and captured hydration policy and
  `ModelContainer` forwarding. The suite carries the standard one-minute async
  limit; its dedicated support file owns only deterministic fakes and the
  harness. Their architecture sibling freezes the core/live split, the sole
  production callback factory, exact-attempt-before-clock-transfer and attempt-
  before-projection order, AppDI composition, engine delegation, captured
  hydration and visual local-analysis routing, synchronous queue-less
  authorization, retired ownership, and the Pipeline production-file ceiling.
- `Core/AI/Inference/InferenceLiveCompletionCoordinatorTests.swift` owns
  completed-outcome normalization, shared-effect order, event/notification
  gating, sealed queue-less and exact queue authorization, and replacement or
  durable-retirement finalization races; its architecture sibling freezes the
  core/live split, AppDI composition, permit construction, retired engine
  effects, and visual/nonvisual effect order.
- `Core/AI/Inference/InferenceLiveFailureCoordinatorTests.swift` owns exact
  synchronous release/retirement and effect ordering, stale suppression,
  retired-owner/transport/connectivity handoff, quota, terminal rejection, and
  synchronous queue-callback replacement races; its architecture sibling freezes
  the core/live split, AppDI composition, post-retirement ownership guard,
  narrow engine actions, retired engine effects, and no-suspension boundary.
- `Core/AI/Inference/InferenceReviewSnapshotServiceTests.swift` owns the bounded
  durable review projection, its distinct missing-row result, and the proof that
  SwiftData read failures leave confirmation and reset state unchanged.
- `Core/AI/Inference/InferenceIdentificationReviewCoordinatorTests.swift` owns
  local-before-cloud and refresh-before-milestone order, failed-sync effect
  suppression, replacement and Auth-fence rejection, typed snapshot/lookup
  failures, and the silent ID fallback;
  `InferenceReviewWorkflowCoordinatorTests.swift` owns local-before-lookup/cloud
  sequencing, serialized dictionary/review writes, overlapping override
  replacement, missing-row enrichment/ID fallback, and stale displayed-override
  dictionary and fallback rejection;
  `InferenceIdentificationReviewPresentationTests.swift` owns full-value
  override, confirmation, reset, dictionary normalization, reference admission,
  and matching persistence-patch behavior. `InferenceArchitectureTests.swift`
  freezes the review action/effect/workflow split, effect placement, AppDI
  composition, the single hydration-owned workflow state source, engine
  boundaries, and production-file ceiling.
- `App/Lifecycle/AppLifecycleManagerTests.swift` owns onboarding/consent
  admission and the live scheduler routing guard.
  `Core/Data/OfflineSync/OfflineJobSchedulerTests.swift` owns ordered dispatch,
  suspension, and persisted future-wake behavior through inert effects on a
  fixture-owned scheduler. These are not real provider-replay tests. The
  [focused inference matrix](development-guides/08-testing-strategy.md#live-inference-requestresult-verification)
  joins those suites with the queue, persistence, Capture, and shared-state
  fixtures; runtime acceptance requires current-source build products.
- `Core/Data/OfflineSync/CaptureAdmissionTests.swift`,
  `LiveCaptureLifecycleTests.swift`, and `InferenceReplayTests.swift` own
  capture-file/media ordering, explicit shared-manager isolation, foreground
  generation fencing, and replay-coalescing behavior. Their architecture suite
  freezes the matching production ownership, the file-store consumer allowlist,
  each test suite's exact type/display identity, and its serialized
  `.offlineQueueManager` process-state lease.
- `Core/Data/OfflineSync/QueuedScanExtractionTests.swift` owns deterministic
  queue-to-inference media and telemetry mapping without installing shared
  manager state. `MediaUploadCompletionTests.swift` owns generation, sibling,
  exact-manifest, durable-staging, callback-token, and unsupported-audio
  quarantine regressions under a serialized `.offlineQueueManager` lease.
  `QueuedInferenceMediaPolicyTests.swift` owns local-WAV storage/format
  classification, while `QueueMaintenanceTests.swift` proves invalid-media
  quarantine preserves completed-result and funding authority.
  `OfflineSyncFoundationArchitectureTests.swift` and
  `OfflineQueueSyncArchitectureTests.swift` freeze their production and test
  ownership, imports, consumer allowlists, private helper containment, retired
  aggregate files, and focused 600-line ceilings.
- `Core/Data/Database/InferenceLifecyclePersistenceTests.swift` and
  `InferenceRetryPersistenceTests.swift` own durable claims, retreats,
  generation validation, inferencing orphan release, retry authority, post-wait
  terminal-state preservation, cloud-complete preservation, missing legacy jobs,
  and cancellation fence release. `InferencePersistenceArchitectureTests.swift`
  freezes the two focused production owners, exact consumers, throwing reads,
  orphan-batch preload, private helpers, balanced fences, source/test ceilings,
  and the residual actor cap.
- `Core/Data/OfflineSync/BackgroundTransferOwnershipTests.swift` owns terminal
  tracker completion, synchronous delegate registration, durable-before-cancel
  Auth quiescence, relaunched task lease adoption, and bounded retirement retry.
  `BackgroundTransferArchitectureTests.swift` freezes the four focused
  production owners, exact declaration/import and mutable-state consumers,
  focused private validation, rejected-retirement and inference-completion
  consumers, mirrored test ownership, failed-retirement generation preservation,
  successful-retirement process completion, and 600-line ceilings.
- `Core/Data/OfflineSync/BackgroundInferenceLifecycleTests.swift`,
  `BackgroundInferenceDispatchTests.swift`,
  `BackgroundInferenceCompletionTests.swift`,
  `BackgroundInferenceWatchdogTests.swift`,
  `BackgroundInferenceRecoveryTests.swift`,
  `BackgroundInferenceRetryTests.swift`, and
  `BackgroundInferencePolicyTests.swift` own exact generation claims and stale
  completion fencing, hard preparation timeout, non-cooperative loser
  cancellation, caller-cancellation identity, dispatch ordering, accepted
  result/failure fencing, stale result-file cleanup with replacement active and
  completion-owner preservation, compare-before-clear probe replacement, parsed
  open-task identity, post-enumeration probe/generation revalidation,
  recovery/cancellation/retirement/retry ordering, durable server-result
  evidence, terminal contract mismatch handling, replacement poll-token
  rejection, durable retry-marker recovery, cancellation-independent restoration
  of a committed general-retry wake, and route/response/status policy.
  `BackgroundInferenceArchitectureTests.swift` freezes their nine production
  owners, including reconciliation, policy actor independence, declaration,
  import and consumer boundaries, direct-map containment,
  cleanup-registration-before-claim and compare-before-clear completion and
  watchdog ordering, durable retry save before immediate central wake
  restoration in both retry paths, no intervening suspension before that
  restoration, post-save poll/generation revalidation before process-local
  replacement, shared response preparation without a
  finalization-to-processing-actor hop, mirrored test ownership, and the
  600-line production-file ceiling.
- `Core/Data/Database/CoreDataIntegrationArchitectureTests.swift` freezes the
  exact 13-file `BackgroundDatabaseActor` inventory, narrow imports and 600-line
  ceilings, declaration-only root, Core Data-wide ban on silently discarded
  SwiftData fetch failures, one-context durable scan/job authority projection,
  exact authority consumer bounds, and throwing absence/failure contracts across
  finalization, goal hints, queue maintenance, and cloud deletion. It also
  freezes the exact four-file Historical Sync layer/import inventory, the
  repository and production-file ceilings, direct-networking exclusions, and the
  four-file mirrored Historical Sync test inventory. The post-refactor extension
  also freezes post-startup, bounded, throwing two-pass rescue registration and
  exact-container acceptance in `ScanRepository`.
- `Core/Data/Images/ScanMediaRecoveryRegistrationTests.swift` verifies
  cancellation, the hard 200-record cap, stable paging order,
  strong-evidence-before-timestamp phases, and no SwiftData work when no rescue
  index exists.
- `Core/Data/OfflineSync/QueueActorCacheTests.swift` and the existing
  `ProfileActorCacheTests.swift` verify that long-lived persistence actors are
  reused only for the exact `ModelContainer` that created them.
- Typed event delivery and route priority/FIFO, coalescing, expiry, overflow,
  account/session fencing, occupied-presentation deferral, exact dismissal,
  missing-target rejection, framework main-actor hops, and detached-player
  callback suppression.
- `MerianTests/Support/SharedProcessStateTestTrait.swift` provides
  resource-keyed cross-suite exclusion for temporary network-client/request-
  interceptor overrides, offline-queue fixtures, the shared gamification
  manager, and app-icon badge state. `SharedProcessStateGate` atomically leases
  all requested resources, cancels queued waiters, and checks release tokens.
  Capture's `OfflineQueueTestCase` uses the same gate across XCTest
  setup/teardown. `OfflineQueueTestState` restores the prior model context;
  individual cases still own async completion and all other state restoration.
  Generic Insight contexts do not configure the shared queue, and lifecycle
  admission tests inject inert maintenance actions. Route and paywall tests
  inject private request sinks instead of owning app-host presentation
  singletons. Suite-local `.serialized` remains complementary and does not
  replace this gate. `SharedProcessStateGateTests` covers the lease contract.
- Scan-media recovery filename safety, rescue-store alignment, constrained
  timestamp grouping, authenticated cloud inspection/repair DTOs, and one-device
  local fallback behavior.
- Camera-roll automatic opt-out, photo/video PhotoKit resource selection,
  source-video retention, image GPS scrubbing, local/approved-cloud media export
  payloads, exact-host rejection, and media-aware result copy.
- Profile achievements, heatmap/stats, Explore, Species Dictionary, species
  observation stats, Messages sharing, Insights, Scans, and onboarding view
  models.

UI tests live under `apps/ios/MerianUITests/` and include launch coverage plus
seeded flows through `App/UITesting/UITestSeedCoordinator.swift`. The
progressive-analyzing regression opens the normal foreground Insight, advances
generic → Vision category → validated image trait only after explicit badge
taps, and verifies the native badge accessibility frame after each opacity-only
label change. The live-to-queue regression proves an open analyzing sheet binds
its exact image-backed durable row without presenting a synthetic error. It also
locks the same selected carousel page and animation-session token across the
handoff, keeps the pending analysis overlay and badge mounted, and exercises the
queued delete confirmation after its toolbar action fades in.

The queued-audio handoff regression opens a staged tile, asserts embedded Back
navigation, the shared scanning status badge and `Did you know?` card, then
verifies the same audio page remains available before and after the completed
result replaces the queued presentation. The seed writes a valid Documents PCM
WAV, and the smoke requires its decoded playback control on both sides of the
handoff rather than accepting a filename-only page. There is no timer-driven
replacement: after every queued-state assertion passes, the smoke taps the
shared status badge to request the exact app-private Debug fixture handoff. The
fixture saves through the open Insight sheet's exact environment `ModelContext`
and directly calls the existing production queue-promotion method with that same
context; the library event remains only for parent-list refresh. Release retains
no-op coordinators. The exact-SHA hosted iOS gate executes all four
deterministic analyzing, live-to-queue, queued-retry, and queued-completion
regressions after the complete unit target; the remaining UI tests are compiled
but retain their feature-specific runtime gates.

Deno tests live under `services/supabase/functions/_tests/` plus function-local
`*.test.ts` files. Run from `services/supabase/functions` with:

```bash
deno task test
```

Stable purchase-identity coverage spans the resolver's protocol/DB/handler
tests, `_tests/purchasePrincipalMigrationContract.test.ts`, the disposable
`_tests/purchasePrincipalCompatibilityConcurrencyDb.test.ts` and
`_tests/purchasePrincipalSignoutRotationConcurrencyDb.test.ts` schedules, and
`tests/purchase_principal_security.sql`. The protocol-3 concurrency fixture
proves prepared-resolver exclusion, claim/cancel serialization, expiry recovery,
and terminal binding-intent fences; it must execute against a disposable
database for release and a connection-refused self-skip is not a pass. iOS
source/unit and physical-device evidence owns the complementary write-ahead
journal, exact fresh-anonymous claim, unrelated-session rejection,
RevenueCat/entitlement gate, and relaunch behavior.

Fleet-wide ingress coverage lives in `_shared/http_test.ts`,
`_tests/edgeHandler.test.ts`, `_tests/jsonEndpointSecurityCoverage.test.ts`, and
`_tests/jsonEndpointSecurityMigrationContract.test.ts`. The executable
`services/supabase/tests/waitlist_security.sql` fixture verifies the waitlist
RPC's ACL, constraints, duplicate behavior, and transactional rate ceilings. Web
parser, email, proxy, HMAC, and Turnstile behavior is covered by
`apps/web/lib/*.test.ts`.

Field trip Deno/database coverage includes the tier-specific evidence gate,
pending preferred-goal retention, weak-match confirmation, completed-progress
downgrade reconciliation, receipt replay, matching specificity, and private RPC
ACLs, plus the starter-level catalog and deny-by-default Backyard enrollment
trigger/backfill, in `_tests/fieldTripsMigrationContract.test.ts` and
`_tests/fieldTripProgressDb.test.ts`.

Consent causal coverage spans `_tests/legalConsentMigrationContract.test.ts`,
`_tests/legalConsentConcurrencyDb.test.ts`, `tests/legal_consent_security.sql`,
and the iOS Consent remote-service, synchronization, cloud-session, facade, and
`SupabaseManager` suites. Static contracts lock RPC shape, privileges, indexes,
client wire mapping, and account-row-before-stream lock order. The
disposable-database fixture releases overlapping grant and revocation calls for
both Gemini and PostHog and requires a revoked final head with monotonic
revisions in either order. The pgTAP upgrade fixture additionally submits
prior-disclosure revocations with their stale observed parents after
current-version grants, then verifies both RPCs rebase the accepted parent and
every consumer keeps the revoked all-version head authoritative.

Recovered image refresh is shared through
`Core/UI/Modifiers/ImageRecoveryReloadModifier.swift`. It observes canonical
source revisions for `ScanThumbnail`, `AsyncLocalImageView`, Profile public scan
images, Explore hero images, and composer images. These consumers include the
revision in their task identity and discard cancelled results. The loader uses
the same source revision for cache/coalescing identity; cloud repair separately
requires verified evidence. The
[image pipeline](system-architecture/03-image-pipeline.md) is canonical for the
evidence and refresh contract.

Missing-image repair coverage spans
`repair-scan-image/{validation,db,worker}_test.ts`,
`_tests/{accountDeletionMigrationContract,migrationMediaContract}.test.ts`,
`tests/{account_deletion_security,scan_image_repair_security}.sql`, and the iOS
`LocalImageLoaderTests` (including
`LocalImageLoaderTests+RecoveryEvidence.swift`),
`LocalScanMediaRecoveryRevisionTests`, `CloudScanImageRepairActorTests`,
`ScanThumbnailLoaderTests`, `ImageLoadingArchitectureTests`,
`ScanImageCloudEndpointTests`, and `MediaStorageAPIModelsTests`. Shared
signing/PUT coverage is included in the
[media storage matrix](../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-verification).

App privacy assurance spans source, generated project, archive, and export.
`scripts/check-ios-project-resources.sh` validates the source manifest and
requires exactly one Merian Resources membership. The current-SHA archive
requires `Merian.app/PrivacyInfo.xcprivacy` and records
`privacy_manifest_valid: true`; `scripts/validate-ios-exported-ipa.sh` repeats
the root-path and exact-content checks for an Organizer export. The declaration
inventory and change contract live in
`docs/development-guides/16-ios-privacy-manifest.md`. Xcode's aggregate report,
App Store answers, and counsel approval remain operator evidence rather than
repository-generated facts.

App transport assurance spans configured origins, URL-construction boundaries,
source plist, archive, and export. `SecureTransportPolicy.swift` admits only
credential-free HTTPS for remote strings while preserving app-owned local files.
`scripts/validate-ios-transport-security.sh` rejects broad and domain-scoped ATS
exceptions plus insecure Supabase origins; the archive and IPA validators repeat
the check against the built `Info.plist`, and exact-SHA archive evidence records
`transport_security: "ats-default"`. The normative contract lives in
`docs/development-guides/17-ios-transport-security.md`.

## Documentation Maintenance Checklist

When changing the codebase, update docs in the same change if any of these move:

- `CurrentSchema`, schema model fields, or migration stages.
- App target deployment versions, entitlements, packages, or XcodeGen targets.
- Privacy manifests, required-reason API use, collected-data categories,
  purposes, identity linking, tracking, SDK composition, or executable bundle
  ownership.
- ATS exceptions, configured remote origins, signed URL handling, or any
  backend-supplied URL boundary.
- Edge Function request/response bodies, auth policy, config entries, or storage
  lifecycle behavior.
- Destructive queue claim authority, live-owner vetoes, account-isolation
  canaries, recovery coverage, or incident exit criteria.
- Capture modes, offline queue state transitions, media staging, or field-notes
  ownership.
- Camera-roll preference semantics, Photos permission level, media resource
  type, source-file ownership, approved export hosts, or temporary-file cleanup.
- Feature module names, file paths, or view-model/actor ownership.
- Public Explore surfaces, notification behavior, widget cache shape, or privacy
  contracts.
- Public web routes, metadata, env variables, canonical `naturebook.earth`
  generation, or legacy `merian.earth` Universal Link compatibility.
- Native extension targets, App Group boundaries, or shipped/de-shipped
  extension source ownership.
- Asset catalog groups, reusable artwork names, app icons, brand marks, persona
  art, or widget fallback imagery.
- Cross-feature domain contracts, typed navigation boundaries, cache-version
  rules, or accepted architecture decisions under `docs/rfcs/`.
- Release-note behavior in `CHANGELOG.md` or the bundled in-app changelog JSON.

## Explore emoji-reaction ownership

- `apps/ios/Merian/Features/Explore/Shared/Reactions/` owns catalog
  presentation, the common picker, scrollable chips, and fixed post controls.
- `Explore/Feed/Services/ExploreReactionDependencies.swift` injects set/page
  operations; `Feed/ViewModels/ExploreReactionMutationQueue.swift` serializes
  target work. `ExplorePostStore` owns post summaries. `+PostReactions`,
  `+CommentReactions`, and `+ReplyLoading` own reconciliation and stale-read
  protection. Map, Author Profile, hashtag feeds, detail, and notification reply
  copies use this Feed state owner.
- `Core/Network/Endpoints/MerianNetworkClient+ExploreReactions.swift` and
  `Core/Network/Models/Explore/ExploreReactionAPIModels.swift` own the native
  wire adapter and reaction response/page values.
- `services/supabase/functions/_shared/exploreReactions.ts` owns Unicode and
  capability validation; `exploreReactionDb.ts` owns guarded RPC adapters and
  bounded preview enrichment. The three reaction routes are thin authenticated
  handlers; the legacy toggle route remains available.
- `resources/emoji/` and `scripts/generate-explore-emoji-catalog.py` own pinned
  Unicode/CLDR source, attribution, and generated iOS/Edge catalogs.
- Migrations `20260918142009_add_explore_post_reaction_type.sql` and
  `20260918142010_add_explore_emoji_reactions.sql` own the enum addition,
  service-only storage/RPCs, canonical database catalog, notification
  capability, aggregation, and ghost-profile merge coverage.

See the
[product contract](./rfcs/explore-page.md#emoji-reactions-update-2026-09-18),
[API contract](./backend-and-data/05-api-contracts.md#explore-emoji-reactions-2026-09-18),
and
[verification matrix](./development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).

Detail reactor identities use `get-explore-post-reactors` and its guarded
`get_explore_post_reactors` RPC. Native ownership is
`ExplorePostReactorsViewModel` plus the typed detail sheet; see the
[people API](./backend-and-data/05-api-contracts.md#post-reaction-people).

### Conversational species discovery

`Features/SpeciesDictionary/Search/` owns the results-first Search route, glass
entry, keyboard-closed illustrated welcome, rotating prompts, real-species
starter grid, filters, two result tabs, and generation-fenced session state. Its
starter grid composes the existing Catalog view model and remote-image owner.
Explore Shell retains that model for one presentation. The entry and Field Chat
toolbar button share the presentation-only rainbow glow/shimmer in
`Core/UI/Modifiers/RainbowCapsuleAccent.swift`; feature controls retain their
own actions and labels. Core Network owns the dedicated endpoint,
`SpeciesDiscoverySearchAPIModels` and `SpeciesSearchResponseValidator`.
`services/supabase/functions/species-discovery-search/` owns bounded question
interpretation and real-record retrieval through the new indexed, service-only
search RPC. See the
[canonical dictionary contract](features-and-hardware/16-species-dictionary.md#conversational-discovery-search)
and
[verification matrix](development-guides/08-testing-strategy.md#species-discovery-search-verification)
for state, privacy, native selectors, Edge/database tests, and manual
acceptance.
