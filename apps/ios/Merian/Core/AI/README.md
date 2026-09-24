# Core AI

This directory owns reusable on-device analysis and the client half of Merian's
remote identification pipeline. Capture-specific composition remains under
`Features/Capture`; server prompts, schema, and Gemini calls remain under
`services/supabase/functions/_shared/identify/` and `identify-multimodal/`.

The canonical behavioral contract is
[AI Engineering](../../../../../docs/system-architecture/04-ai-engineering.md).
This README maps that contract to native source and test ownership.

## Responsibilities

- `Models/CaptureTelemetry.swift` owns the inference capture-context value and
  its deterministic live/environment adapters. Its Debug simulator-only
  `DebugIdentificationReplayProfile` carries the versioned fixed-audio context
  through one foreground request. It has no global state or durable schema
  field; ordinary queue recovery is outside controlled comparison.
  `InferenceLiveRequestService` passes an ephemeral attempt validator to the
  network measurement boundary for nonvisual requests. Only validated fixed
  replay bodies can use it to attest a profile; it carries no wire fields. The
  [measurement guide](../../../../../docs/development-guides/21-identification-app-measurement.md#fixed-context-for-foreground-audio-comparisons)
  owns the exact synthetic context and evidence limits. Its comparison-slot
  variant retains a generated assignment in that same ephemeral profile.
  `InferenceLiveRequestService` carries the authenticated comparison capture
  through the response; result processing attaches the typed persistence outcome
  only after its normal fence. Publication arms an exact scan render proof in
  `InferencePresentationCoordinator`, and successful queue finalization records
  a separate completion proof. The existing UIKit draw callback consumes render
  proof once; replacement/Auth/queue transitions clear it. These proofs are
  observation evidence, not durable species metadata. The new prompt-comparison
  profile uses a separate generated table and typed binding through those same
  owners. Its finalization proof receives the actual `SpeciesData` and binds
  subject state plus conditional confidence; only a named animal includes a
  normalized scientific-name digest. The
  [prompt observation contract](../../../../../docs/development-guides/21-identification-app-measurement.md#prompt-comparison-observation)
  defines the strict log shape and provisional-reference limits.
  `Models/SpeciesData+EdgeResponse.swift` is the sole handwritten
  `EdgeResponse`-to-`SpeciesData` adapter. The platform-neutral species value
  graph and display/identity policies remain under `Merian/Models/Species`,
  while generated Edge DTOs remain under Core Network. Neither Core AI model
  file resolves networking, persistence, task, or singleton effects.
- `InferenceEngine` retains the stable live-analysis entry points and
  source-compatible observable and foreground-task accessors. It delegates
  live-submission startup to `InferenceLiveSubmissionCoordinator`, callback
  construction and outcome routing to `InferenceLivePresentationCoordinator`,
  delegates recovered-result admission and commit order to
  `InferenceSessionLifecycleCoordinator`, and keeps the recovery and review
  entry points source-compatible. Stored presentation values and their
  synchronous transitions live in `InferencePresentationState`; execution order,
  attempt identity and durable-queue actions, ephemeral presentation identity
  and visual queue context, cross-owner session replacement, request/result
  adaptation, accepted-result effects, failure coordination, hydration, bounded
  writes, and reference work remain in focused owners.
- `Inference/Assembly/InferenceEngineAssembly.swift` is the one-shot
  `@MainActor` composition boundary for those focused owners. It preserves the
  existing construction order and initializer-injected live fallbacks, then
  hands the completed graph to `InferenceEngine`, which continues to retain its
  runtime collaborators privately. The assembly stores no mutable runtime state,
  starts no task, and resolves only the initializer's existing optional live
  fallbacks. `AppDIContainer` remains the production owner of the external live
  dependencies supplied by the app graph.
- `Inference/Facade/InferenceEngineCompatibility.swift` owns the nested
  source-compatible modality values and pure static policy adapters.
  `Inference/Diagnostics/InferenceEngine+Debug.swift` preserves the existing
  debug API as thin forwarding methods, while
  `InferenceEngineDebugSupport.swift` coordinates deterministic scenarios from
  exact private owner references supplied by a DEBUG-only facade factory. Both
  diagnostic files are excluded from Release compilation and acquire no live
  network, persistence, logging, filesystem, AppDI, or singleton effects.
- `Inference/Lifecycle/InferenceSessionLifecycleCoordinator.swift` is the
  effect-acquisition-free `@MainActor` sequence owner for session replacement.
  It orders new-scan preparation, visual and nonvisual analysis replacement,
  successful result publication, exact background and queued recovery commits,
  queued-record handoff, pipeline finish, queue handoff, dismissal, explicit
  cancellation, historical-load admission, application activity changes, and
  both Auth-transition phases across the attempt, hydration, write, local
  analysis, presentation-identity, and presentation-value owners. It creates no
  task and resolves no networking, persistence, logging, filesystem, or
  singleton dependency; mutable state and durable queue effects stay with those
  focused owners.
- `Inference/Presentation/InferencePresentationCoordinator.swift` is the
  non-observable `@MainActor` owner for prepared and active presentation
  identity, exact visual queue-handoff phrase/media context, and the pending
  first-render timestamp. It accepts only value inputs and synchronous current-
  attempt checks, creates no task, resolves no live dependency, and never owns
  `SpeciesData`, `ActiveScanMedia`, logging, persistence, or networking. The
  engine keeps stable public methods, while
  `InferenceSessionLifecycleCoordinator` asks `InferencePresentationState` to
  apply value changes in the existing synchronous order around this coordinator.
  An admitted visual replacement resets the displaced presentation owner, queued
  visual context, and render timestamp before installing its new owner, so a
  same-scan retry without a new clock cannot consume stale timing state. Auth
  admission and the post-drain quiescence cleanup both discard presentation
  owners and queued visual context; both preserve a pending first-render metric
  for an already-mounted result probe. After exact-attempt admission, a response
  without a queue may transfer that clock from its process-local request ID to
  the authoritative server scan ID without changing the original start
  timestamp.
- `Inference/Presentation/InferencePresentationState.swift` is the sole stored
  observable value owner behind the engine facade. It contains processing and
  metadata/enrichment and lookalike loading flags, scanning copy, projected
  media, `SpeciesData`, the queued-presentation ID, and display telemetry. Named
  synchronous mutations preserve publication order for preparation, success,
  queue handoff, cancellation, and historical projection. Historical replacement
  also clears both loading flags synchronously because the displaced hydration
  task is no longer authorized to clear them. It owns no lifecycle identity,
  task, network, persistence, logging, filesystem, or singleton dependency.
  New-scan, nonvisual, and cancellation transitions explicitly clear subject
  distance so a later scan cannot inherit a previous visual measurement.
- `Inference/Media/InferenceLiveMediaProjector.swift` is the value-oriented
  boundary between Capture submission media and live Insight presentation. It
  selects display-policy images, derives the legacy fallback timeline only when
  no explicit timeline exists, produces the aligned provider projection, maps
  ordered live or persisted media into `ActiveScanMedia`, carries focus regions,
  suppresses only an explicitly matching video poster as a duplicate carousel
  item, retains a distinct still immediately before a video, and preserves a
  poster when a video URL is rejected. Its small injected dependency value owns
  only Documents/temporary path lookup and HTTPS validation; the projector
  performs no networking, persistence, task creation, logging, or observable
  mutation. `InferenceLiveSubmissionCoordinator` synchronously publishes the
  pre-request presentation and passes the immutable submission projection to the
  pipeline; on accepted completion, `InferenceLivePresentationCoordinator`
  invokes persisted mapping only after exact-attempt admission and publishes
  through the lifecycle and presentation-state owners.
- `Inference/Hydration/InferenceHydrationCoordinator.swift` privately owns the
  replaceable live, historical, and identification-review task slots; retains
  cancelled handles until completion for Auth quiescence; and contains the
  bounded request histories, 24-hour enriched-species cache, and temporary
  rate-limit deadline. Wikipedia, enrichment, and GBIF work remain structured
  children of the owning slot instead of creating a second task owner.
- `Inference/Hydration/InferenceSpeciesHydrationCoordinator.swift` owns the
  complete live Wikipedia/enrichment/GBIF sequence plus the exact-presentation
  Wikipedia, GBIF, enrichment, and missing-reference operations reused by the
  historical and identification-review flows. The historical and review workflow
  coordinators sequence those calls around projection and review-action work.
  The species coordinator admits exact scan/species/presentation identities,
  validates the complete identity at registered live-task entry before
  publishing the loader or starting provider work, sanitizes and caps reference
  URLs, rejects cancellation again after every external suspension, and allows
  deferred reference-loading cleanup only for the exact presentation that
  started it. It reaches the observable presentation only through an injected
  hydration callback bundle for current values, exact identity, loading, and
  persistence admission. Its private-state
  `InferenceSpeciesEnrichmentCoordinator` sub-owner runs metadata and lookalikes
  independently, owns the one bounded lookalike retry, and applies rate-limit
  policy through `InferenceHydrationCoordinator`. The core owners resolve no
  live client, logger, UserDefaults value, detached task, or database actor;
  `InferenceSpeciesHydrationCoordinator+Live.swift` owns logging only.
- `Inference/Hydration/InferenceSpeciesPresentationCoordinator.swift` is the
  live-dependency-free `@MainActor` bridge between species hydration,
  identification review, observable presentation state, and bounded writes. It
  is the sole production constructor of the hydration callback bundle, applies
  admitted species/reference/loading values, starts review generations,
  validates exact scan/species/presentation/review identity, routes immutable
  persistence work to the background or serialized review owner, advances the
  exact review generation before marking alternatives exhausted, and admits
  eligible live hydration. It creates no task and owns no mutable state, network
  transport, persistence implementation, singleton, or live dependency.
  `InferenceEngine` retains its stable public facade and delegates these
  operations to the bridge.
- `Inference/Hydration/InferenceHistoricalHydrationCoordinator.swift` owns the
  registered historical sequence after synchronous presentation replacement:
  initial reference state, awaited deferred decode, displayed-override
  hydration, concurrent Wikipedia and scoped enrichment, then GBIF after the
  enriched taxon key is available. It contains no task handle, live singleton,
  network client, managed record, or persistence executor. Task retention and
  retry/cache policy remain in `InferenceHydrationCoordinator`; exact reference
  operations remain in the species coordinator; presentation-state commits and
  bounded write admission return through callbacks supplied by the species-
  presentation bridge. Cancellation is rechecked after the decode, override, and
  enrichment suspension boundaries; exact presentation identity is revalidated
  before publication. If reference providers finish without an admissible image,
  the owner resolves its own still-current `.loading` state to `.empty`.
- `Inference/Hydration/InferenceHistoricalLoadCoordinator.swift` owns the
  synchronous persisted-record startup sequence behind `InferenceEngine.load`:
  historical admission, active-scan identity, live-media release, immutable
  projection, legacy-cache reset scheduling, initial publication,
  presentation/review generation capture, callback construction, and registered
  hydration scheduling. It creates no task, resolves no live dependency, and
  retains no managed `LocalScanRecord` after `load(from:)` returns. The engine
  retains only the stable facade.
- `Inference/Hydration/InferenceLookalikeCacheResetService.swift` isolates the
  legacy local-cache compatibility decision from historical presentation. Its
  live adapter alone reads/writes the reset version, coalesces process-wide
  work, and asks `BackgroundDatabaseActor` to clear stale blobs. The historical-
  load coordinator reads `needsReset` while projecting a record and supplies the
  optional model container when scheduling is required.
- `Inference/Hydration/InferenceHistoricalRecordProjection.swift` snapshots one
  persisted `LocalScanRecord` on `@MainActor` into immutable presentation,
  media, hydration-plan, and deferred-decode values before any suspension. It
  owns the complete persisted-record-to-`SpeciesData` mapping, override/original
  identity projection, Human/unresolved suppression, reference admission, rich
  and legacy lookalike precedence, and candidate decoding. The historical-load
  coordinator owns synchronous presentation orchestration and commits through
  `InferencePresentationState`; the historical-hydration coordinator consumes
  the hydration plan, the species coordinator supplies the shared reference
  operations, and writes return through the species-presentation bridge's narrow
  persistence-admission callback behind the engine facade.
- `Inference/Hydration/InferenceSpeciesEnrichmentService.swift` owns typed
  metadata/lookalike response normalization. It trims nonblank habitat, maps
  wire taxonomy into `TaxonomyData`, keeps raw alternate names for persistence
  while returning sanitized presentation names, and maps every lookalike field
  into `SimilarSpeciesEntry`. Its `+Live` adapter is the sole Core AI bridge to
  `MerianNetworkClient.fetchEnrichment`; the endpoint extension remains the
  wire-contract owner. The immutable `Sendable` service has no observable,
  task-lifetime, retry, or persistence effects.
- `Inference/Hydration/InferenceHydrationPersistenceService.swift` owns the
  admitted reference, metadata, and lookalike persistence snapshots. Its `+Live`
  adapter constructs `BackgroundDatabaseActor` and JSON-encodes mapped
  lookalikes in a utility-priority detached task before the actor write. The
  species coordinator carries identity and post-suspension cancellation; the
  species-presentation bridge validates the exact current presentation and
  routes admitted work; and the write coordinator retains operation lifetime,
  queue bounds, presentation/review generations, and Auth quiescence.
  `InferenceSpeciesPresentationCoordinator` constructs the one hydration bundle
  from callbacks backed by current presentation state, exact identity, and
  admitted writes behind the stable engine facade. `AppDIContainer` composes the
  reference, enrichment, persistence, logging, and cache-reset values; tests
  inject only their narrow closures.
- `Inference/State/InferenceWriteCoordinator.swift` privately owns the bounded
  background-write queue, presentation generations, Auth-transition fence, and
  ordered identification writes. Species-changing review work, same-species AI
  confirmation, and legacy flagging use independent bounded action generations
  on one final-writer tail, so confirmation does not invalidate an unrelated
  historical hydration. `InferenceSessionLifecycleCoordinator` sequences its
  reset and Auth-fence operations; the coordinator's mutable write registries do
  not escape their focused owner.
- `Inference/State/InferenceLiveAttemptCoordinator.swift` privately owns the
  current foreground task handle, retained displaced handles, active scan and
  process-local attempt identity, optional durable foreground generation, and
  recoverable-presentation scan. It validates the complete local/durable tuple.
  Full invalidation atomically detaches the current task and clears the local
  tuple before release and retirement callbacks, so a re-entrant callback may
  safely install a replacement. The displaced task is cancelled but retained
  until it terminates, allowing Auth quiescence to cancel and await both current
  and previously displaced work. Recovered-result admission uses the same local
  detach-and-cancel operation without durable callbacks before publishing the
  recovered state. Exact-current retirement fences only its durable-generation
  slot before the callback so the local presentation can still hand off to the
  queue. Awaited deletion rechecks the complete tuple and reports failure when
  that tuple was replaced or its durable generation was relinquished, so a stale
  completion cannot clear, retire, or authorize follow-ups over another owner.
  `Inference/Services/InferenceLiveQueueService.swift` is its narrow injected
  durable boundary; only `InferenceLiveQueueService+Live.swift` resolves
  `OfflineQueueManager` for claim, current-owner lookup, deferred-upload
  release, retirement, exact-generation deletion, and terminal rejection.
  `InferenceEngine` remains the observable presentation facade backed by
  `InferencePresentationState`; `InferenceSessionLifecycleCoordinator` orders
  replacement and cancellation operations across both owners.
- `Inference/Pipeline/InferenceLiveSubmissionCoordinator.swift` is the
  effect-acquisition-free `@MainActor` startup sequence owner for visual and
  nonvisual submissions. It preserves Auth-fence and empty-payload disposition,
  pipeline admission, lifecycle replacement, media projection and presentation
  staging, attempt/presentation activation, telemetry, visual local-analysis,
  first-render timing, immutable request construction, callback selection, and
  task-registration order. It creates the one live execution task but installs
  it immediately in `InferenceLiveAttemptCoordinator`, which remains the sole
  task-handle and attempt-identity owner. The coordinator stores no mutable
  state and resolves no network, persistence, logging, filesystem, or singleton
  dependency. `InferenceEngine` retains the source-compatible entry points as
  thin delegates. Local-analysis launch and current-session policy remain
  private; the existing engine diagnostics cross only DEBUG-gated forwarding
  methods.
- `Inference/Pipeline/InferenceLivePipelineCoordinator.swift` is the shared
  visual/nonvisual execution owner after the submission coordinator has staged
  presentation inputs. It performs exact admission and activation, circuit
  gating, request dispatch, result processing, completion preparation, benchmark
  placement, durable finalization, modality-specific follow-up order,
  synchronous failure dispatch, and exact-owner cleanup. Queue-less nonvisual
  authorization remains synchronous after commit; only queue-backed finalization
  introduces the existing suspension. The core resolves no live singleton or
  logger and emits narrow callbacks for presentation publication, hydration
  scheduling, local-analysis timing, failure actions, and final cleanup. Its
  `+Live` adapter owns circuit, quota-refund, and logging effects;
  `AppDIContainer` captures and injects those managers for production.
- `Inference/Pipeline/InferenceLivePresentationCoordinator.swift` is the
  effect-acquisition-free `@MainActor` adapter between those callbacks and the
  focused presentation owners. It is the sole production constructor of both
  live-pipeline callback bundles. It performs the synchronous exact-attempt
  success admission before persisted-media projection, lifecycle publication,
  and the biological completion event. For a queue-less response, that same
  admission transfers the pending first-render clock from the session's
  process-local request ID to the server-returned scan ID before publication. It
  routes finish, all typed failure actions, and post-result hydration; and
  preserves the visual local-analysis cancellation and request-body session
  mapping. Captured model containers and reference policies reach only the
  species-presentation bridge. The owner creates no task, suspension, network or
  persistence operation, mutable state, singleton, or engine retention cycle.
- `Inference/Completion/InferenceLiveCompletionCoordinator.swift` is the shared
  accepted-result boundary for visual and nonvisual inference. It normalizes
  discovery state, sequences replacement metadata, circuit success, and scan
  telemetry, emits the committed biological-scan event, and grants a typed
  follow-up permit only after exact queue finalization and a post-suspension
  local-owner check. The permit has a file-scoped initializer, and queue-less
  authorization accepts only the nil scan/durable-identity pair, so another
  caller cannot forge or bypass durable finalization. Notifications and
  milestone scheduling require that permit; queue-less nonvisual completion uses
  a synchronous authorization path so its reviewed timing does not gain a
  suspension. The core coordinator has no live singleton or task construction.
  Its `+Live` adapter owns concrete manager, repository, settings, analytics,
  event, notification, and milestone bridging; `AppDIContainer` captures those
  collaborators once and injects the dependency value. The pipeline coordinator
  places benchmarks and preserves modality-specific effect order; the live-
  presentation coordinator commits accepted state and routes hydration, while
  the engine and media projector retain their stable facade and value-
  construction roles.
- `Inference/LocalAnalysis/InferenceLocalAnalysisCoordinator.swift` privately
  owns the classification, deterministic-trait, Foundation-cue, and phrase-
  rotation task slots; bounded derivative and provisional classification;
  request-body gate; phrase cursor; inactivity pause/resume state; and the
  Foundation stage's power/thermal subscription and explicit stream-cancellation
  lifetime. The engine supplies the exact visual-session predicate and receives
  presentation phrase values. Local task handles and mutable lifecycle state do
  not escape the coordinator or participate in durable Auth quiescence.
- `Inference/Request/InferenceLiveRequestService.swift` is the initializer-
  injected boundary for visual/nonvisual live request preparation and provider
  dispatch. It owns base64 filtering, image MIME detection, observation-context
  JSON, visual/audio/timeline descriptor forwarding, staged-video upload, and
  the one `/identify-multimodal` invocation. The live pipeline coordinator
  supplies an exact attempt validator after encoding, video upload, and provider
  return; it keeps provider-ready and request-body callback timing and delegates
  durable queue actions to the live-attempt coordinator before routing parsing
  and persistence through the result service below. The engine retains only the
  staged presentation and local-analysis callback. The delayed and body-sent
  callbacks retain the coordinator independently so durable upload release does
  not depend on engine lifetime; only the local analysis update remains weakly
  engine-owned.
- `Inference/Result/InferenceLiveResultService.swift` adapts visual/nonvisual
  responses to the existing `InferenceProcessingActor.parseAndSave` boundary. It
  forwards the original response/context JSON, canonical media projection, model
  context, and exact persistence fence; normalizes optional media paths; and
  returns typed persisted, completed-without-record, or rejected outcomes. The
  pipeline coordinator supplies validation before and after the actor call. A
  confidence-zero response still reaches presentation and queue completion only
  when the actor proves terminal completion. The completion coordinator
  sequences accepted-result effects and delegates exact-generation queue
  finalization to the live-attempt coordinator. The service has no retained
  request/task state or presentation, queue, discovery, or notification effects.
- `Core/Network/Inference/InferenceIdentificationReviewService.swift` owns the
  typed `species_dictionary` projections and
  `update_owned_scan_identification_review` RPC mutation used by review flows.
  Its mutation value exposes only coherent override, confirmation, and reset
  factories; one typed `UserReviewState` therefore drives both local persistence
  and the exact raw enum string encoded for the RPC. Every live operation
  acquires and finishes an account-work lease and rejects a result after an
  account transition. It contains no presentation, local persistence, or
  post-success effects. `AppDIContainer` composes this service alongside the
  live request and result services.
- `Inference/IdentificationReview/InferenceReviewSnapshotService.swift` owns the
  bounded, throwing SwiftData read required before confirmation or reset. It
  returns only the durable species UUID and original AI reasoning. A missing row
  remains an optional compatibility result, while a store failure propagates to
  `InferenceIdentificationReviewCoordinator`; the review workflow then returns
  before invoking the species-presentation callback bundle or changing action
  generations, local state, or cloud state. `AppDIContainer` owns and injects
  the live value so this failure path is deterministic in tests.
- `Inference/IdentificationReview/InferenceIdentificationReviewCoordinator.swift`
  is the singleton-free main-actor owner for review and legacy-flag action
  generations, ordered admission and mutation writes, typed snapshot and
  dictionary failures, review transport, and the post-sync Explore refresh and
  scan-milestone sequence. Its `+Live` adapter alone constructs
  `BackgroundDatabaseActor`, resolves the shared-post mapping, logs failures,
  and bridges the AppDI-captured event and milestone collaborators. The
  coordinator derives its local state from the same immutable mutation passed to
  transport, so those representations cannot diverge. The core coordinator
  resolves no live singleton, Supabase query, detached task, or unchecked
  Sendable wrapper. Auth fencing and replacement rejection remain in the shared
  `InferenceWriteCoordinator` it receives.
- `Inference/IdentificationReview/InferenceReviewWorkflowCoordinator.swift` owns
  the complete override, confirmation, reset, and historical displayed-override
  workflows. It preserves local admission before lookup/cloud work, performs
  throwing snapshot preflight before any confirmation/reset mutation, registers
  replacement hydration in the shared review task slot, and validates the exact
  scan/species/presentation/review generation after every external suspension.
  Cancellation-ignoring dictionary and species-ID fallback results therefore
  cannot update observable state, enqueue stale persistence, or escape to their
  caller. The coordinator receives the write/effect and species-hydration
  owners; it resolves no live singleton or endpoint itself.
- `Inference/IdentificationReview/IdentificationReviewPresentation.swift` owns
  the pure full-value mappings for override placeholders, AI confirmation,
  reset, and Species Dictionary hydration. It returns typed engine presentation
  actions plus the matching persistence patch, so presentation and durable
  mapping cannot drift. `InferenceEngine` keeps the public method signatures,
  while `InferenceSpeciesPresentationCoordinator` coordinates observable
  `SpeciesData` and reference-media commits through `InferencePresentationState`
  and supplies the review workflow's single hydration callback bundle. The
  bridge starts review generations for newly installed live or historical
  presentations and routes admitted hydration writes through the review/write
  owner. Interactive override, confirmation, and reset sequencing, persistence
  implementation, transport, Explore invalidation, and milestone lookup remain
  outside the engine.
- `Inference/Result/InferenceScanReplacement.swift` owns the synchronous
  reanalysis metadata safety boundary. Only a typed persisted outcome with
  distinct, non-empty scan IDs and a replacement visible in a fresh store
  context can authorize replacement. It saves tags, collection membership, and
  field notes before returning the original record to the engine for
  repository-owned deletion. No-record outcomes, missing/deleted records, lookup
  failures, and failed metadata saves preserve the original. Save failure
  restores only the helper's staged fields, not unrelated user edits. A cleanup
  failure can leave two scans; it cannot justify deleting the only usable
  original. Review state intentionally belongs to the new analysis.
- `Inference/Recovery/InferenceLiveFailurePolicy.swift` owns stateless
  interruption and failure classification, modality-specific retirement reasons,
  and telemetry/circuit/feedback decisions. It reuses Core Network's
  `EdgeFunctionErrorPolicy` stable-code parsing and the shared connectivity
  policy without invoking transport. `InferenceFailurePresentation.swift` owns
  unchanged recovery copy and the `.inferenceError` value factory.
  `InferenceLiveFailureCoordinator.swift` is the singleton-free synchronous
  owner that snapshots exact attempt validity, sequences cancellation and queue
  handoff, retires through the live-attempt coordinator, applies terminal queue
  disposition, and orders telemetry, circuit, logging, paywall, feedback, and
  failure-value creation. Because queue callbacks are synchronous and may
  re-enter, it revalidates local ownership after release, retirement, and
  rejection before later presentation effects. It emits only narrow
  recoverable-scan, queued-handoff, and failure-publication actions for
  `InferencePresentationState` behind the engine facade. The pipeline
  coordinator is the sole caller for both live catch paths. Its `+Live` adapter
  binds telemetry and logging and adapts the circuit, haptic, and usage managers
  captured by `AppDIContainer`. Direct engine construction retains the
  source-compatible paywall closure through a lazy fallback adapter. The core
  coordinator and both policies create no task and introduce no suspension
  between the ownership snapshot, retirement, and terminal commit.
- `Core/SpeciesReference/Services/SpeciesReferenceHydrationService.swift` owns
  the shared public Wikipedia/GBIF session, request construction, wire DTOs, and
  off-main parsing used by Inference and thumbnail recovery. The engine
  orchestrates its presentation coordinator and observable state owner; admitted
  inference-side reference writes pass through
  `InferenceHydrationPersistenceService`.
- `InferenceProcessingActor` owns off-main image encoding and the foreground
  parse-to-persistence workflow. It delegates response decoding, success
  validation, domain mapping, expected-scan comparison, and immutable funding-
  settlement projection to the stateless
  `Inference/Services/InferenceResponsePreparationService.swift`, delegates
  media writes to `FileIOActor`, and delegates scan persistence to
  `BackgroundDatabaseActor`. Background URLSession completion uses that same
  response-preparation service directly, so it does not await the processing
  actor while holding a per-scan persistence fence. The service performs no
  entitlement, usage, queue, or task effect. Prepared responses, the normalized
  settlement, and their `SpeciesData` value graph use compiler-checked
  `Sendable` conformances rather than an unchecked actor-boundary assertion. The
  live result service does not replace those owners.
- `Inference/LocalAnalysis/` separates the injected Vision classifier and broad-
  category policy, bounded-image builder, deterministic pixel-trait extractor,
  phrase coordinator, Foundation visual-cue seam, validation, and runtime
  eligibility policy. No production file in that owner exceeds 600 lines.
  `AppDIContainer` owns the live providers and light-impact start feedback and
  injects them through `InferenceEngine` composition into the local-analysis and
  submission coordinators. Direct/default engine instances keep start feedback
  inert.
- `Inference/LocalAnalysis/ScanningPhrasePolicy.swift` owns the established
  cloud-analysis phrase deck, accepted Vision confidence and margin, and phrase
  cadence. `Inference/Result/InferenceConfidencePolicy.swift` owns the Flash/Pro
  presentation bands and safe unknown-tier fallback.
  `Inference/Recovery/InferenceLookalikeCachePolicy.swift` owns the versioned
  local-cache reset marker. These effect-free values stay beside their behavior
  and do not return to a cross-domain Utilities aggregate.
- On-device Vision classification runs concurrently with the network request to
  provide scanning phrases. It does not replace or add a Gemini call, and the
  local image and phrase text never enter the request, persistence, analytics,
  or logs.
- The marked Identify wire block in `InferenceEdgeDTOs.swift` is generated from
  the server's executable contract. It owns explicit `CodingKeys` and
  `init(from:)` implementations; do not hand-edit or extend those DTOs.

## First-Result Critical Path

The Analyze-tap timestamp is passed into `InferenceEngine.analyze` or
`analyzeNonVisual`, so image, video, audio, and describe paths share the
tap-to-first-render boundary without changing non-image submission behavior.
`InferencePresentationCoordinator` retains that process-local timestamp until
`InferenceLiveSubmissionCoordinator` consumes it for the exact scan's one-shot
draw probe and routes the duration through the pipeline's injected benchmark
adapter. Result publication and both Auth cleanup phases preserve the pending
metric, while replacement, dismissal, queue handoff, historical load, and
explicit cancellation clear it as before. After the HTTP response arrives,
`InferenceLiveResultService` prepares one visual/nonvisual actor request and
revalidates the exact attempt around that suspension. The actor's response
decoding and local persistence are measured separately.
`InferenceLiveCompletionCoordinator` normalizes the typed completed outcome and
shared success effects. `InferenceLivePresentationCoordinator` then revalidates
the exact local/durable attempt before it invokes `InferenceLiveMediaProjector`
to remap persisted image paths in the original timeline.
`InferencePresentationState` publishes the resulting `ActiveScanMedia` before it
commits `speciesData` and ends processing. Only a committed, still-current
presentation with no outstanding durable generation receives a follow-up permit;
queue-backed paths must also complete their exact durable-row deletion while the
full local/durable tuple remains current. Queue-less authorization accepts only
the nil scan/durable pair.

Scan milestones and Field trips start in follow-up work through
`ScanMilestoneCoordinator`. Current multimodal `200` already guarantees the
authenticated server scan row; the coordinator still polls `/check-scan-status`
for compatibility and before reading the server progress receipt. After the
progress attempt it gathers new achievement unlocks without presenting them
early, evaluates the `New to Naturebook` eligibility flag, and batches standard
outing progress, Seasonal Challenge progress, achievements, then the dictionary
milestone. The background completion path uses the same coordinator; scan-ID
deduplication prevents a live/background race from presenting the batch twice.
The server receipt is also the evidence authority: a weak unconfirmed
identification returns no Field trip credit, and evidence-downgrade
reconciliation returns no new milestone. The coordinator must not infer credit
from the local confidence badge or fabricate a toast for either case. Primary
cache-miss Wikipedia/GBIF resolution may occur before the server response as
part of durable success; follow-up reference hydration remains outside
response-to-first-render.

Every external reference URL emitted by `InferenceSpeciesHydrationCoordinator`
is normalized through `ExternalReferenceImagePolicy` before the species-
presentation callback publishes it to `SpeciesData` or a persistence snapshot
reaches scan state. The current exact rule treats iNaturalist media `605615444`
as absent while preserving later permitted URLs in source order. Wikipedia and
GBIF hydration must use this same boundary; do not write a provider URL straight
into `referenceImageUrl`.

`Insights/Shell/Components/InsightFirstRenderProbe.swift` closes the
user-perceived measurement for `InsightSheetView` with a one-shot UIKit draw
probe after the first result frame participates in a display pass. Do not
replace that boundary with only a SwiftUI state assignment or `onAppear`; those
measure scheduling, not pixels presented.

## Progressive analyzing copy

Visual scans start with generic, directly observable copy. The submission
coordinator starts local analysis from the primary inference image; the local
analysis owner builds one image bounded to 512 px and reuses it for every local
provider. When the primary visual item has an accepted
`NormalizedImageFocusRegion`, that already-padded top-left region is cropped
from the local image; otherwise the full square inference image is used. Other
captures and Gemini's payload are unchanged.

`AppleVisionSubjectClassifier` runs `VNClassifyImageRequest`. A top result must
meet the 0.65 confidence threshold, lead the runner-up by at least 0.15, and map
to a supported broad category. A qualifying category replaces the generic pill
immediately. After Vision completes, `AppleImageVisualTraitExtractor` samples
the same bounded image at 32×32 pixels and derives five image-specific
observations: dominant colors, saturation distribution, lighting distribution,
light contrast, and surface detail. It does not use Vision labels to generate
text or infer identity.

The single injected phrase clock advances no more often than every 2.3 seconds.
Every phrase in the current deck is displayed once before that deck can wrap to
its first phrase. When all five deterministic cues qualify, that deck spans 11.5
seconds before any image-trait wording repeats. Newly accepted phrases join the
current round before a wrap. Source priority is generic → Vision category →
deterministic image trait → Foundation Models cue. An eligible Foundation cue
replaces the deterministic deck with up to six observations followed by five
general visual phrases before repeating. This general tail adds variety without
lowering source priority or admitting late category/trait callbacks. Newly
streamed observations take the next tick, then resume the general tail at its
previous position. A full eleven-phrase cycle lasts 25.3 seconds. Pixel-derived
traits use the same validator as Foundation cues and are limited to complete,
unique, 2–5-word details whose rendered pill text fits within 36 characters. All
local phrases describe only visible form, color, tone, contrast, texture,
arrangement, markings, and proportions; they do not imply an identity,
confidence, record lookup, geographic range, or Gemini completion.

Image-trait pills use natural verb-led sentences rather than labeled fields: for
example, **Analyzing gray and green colors**, **Reviewing softly colored
areas**, or **Observing light and shadow areas**, not **Color: gray and green
tones**. Middle measurements are translated into visible distributions instead
of exposing statistical bucket language such as **moderate color levels** or
**balanced light and dark**. The constrained trait kind selects the action verb
but is never rendered as a `Kind: detail` prefix.

Every local mutation is fenced by a typed visual-presentation session containing
the exact scan ID and presentation-attempt UUID, plus the durable foreground
generation. `InferenceLiveAttemptCoordinator` owns that identity, and
`InferenceLiveSubmissionCoordinator` gives the local-analysis coordinator a
narrow current-session predicate. Result arrival, dismissal, scan replacement,
queue handoff, Auth transition, and failure synchronously cancel and release all
coordinator-owned producers. Dismissal invalidates the ephemeral phrase and
live-media association while Gemini networking, upload, persistence, and result
recovery continue independently. Auth admission clears that state atomically so
a replacement account cannot see the preceding scan's phrase or in-memory image.
App deactivation stops every local model and cadence task but retains the
current phrase and exact visual-session callback only when cadence was active;
reactivation resumes only that cadence and never starts Vision or trait work
again, including for audio or Describe. Consecutive inactive and background
notifications are idempotent and retain that single pending cadence resume while
the exact presentation remains current. Networking and result publication never
await the coordinator, Vision, or a visual-cue stream.

The Debug-only manual analyzing fixture also retains its exact current context
across inactive/background transitions. Reactivation leaves it timer-free; only
an explicit advance while active changes its phrase. This prevents launch
lifecycle events from discarding the fixture before its first UI-test tap.

Vision and deterministic trait extraction have separate task owners. The trait
provider must cooperate with cancellation, but even a test provider that hangs
or ignores cancellation cannot keep Vision completion, result publication, or an
Auth drain suspended; a late return is rejected by cancellation and
scan-generation checks before it can publish text.

Queue transfer is typed rather than inferred from a free scan ID.
`InferencePresentationCoordinator` validates and consumes the exact prepared or
active owner, then returns a value handoff for
`InferenceSessionLifecycleCoordinator` to commit through
`InferencePresentationState`. A prepared visual scan can hand off only its full
generic deck and never live media. An active visual handoff additionally
requires the exact scan ID and attempt generation; it snapshots the current
phrase, every unseen option, and then the seen options so nothing repeats before
the available deck is exhausted. Its cursor and live carousel association
survive queue-save and offline/online changes. **Waiting for connection** is a
temporary overlay that consumes no contextual phrase. A stale ownership check
clears contextual handoff state and falls back safely. Audio and Describe
sessions are typed as nonvisual, retain their existing copy, and can never
inherit a visual phrase or image.

### Foundation Models milestone

AppDI injects `AppleImageVisualTraitExtractor` and
`AppleFoundationVisualCueProvider`. Five deterministic dominant-color,
saturation, lighting, light-contrast, and surface-detail cues remain active. The
generative provider is guarded by `FeatureFlag.foundationVisualCues`, whose
production default is true; Release ignores local overrides. Eligible iOS 27
devices use it automatically. Debug Settings → Feature Flags → **On-device
visual observations** can disable it or clear an existing override for testing.

The Swift 6.4 branch uses only `SystemLanguageModel.default`, a fresh image-only
session, a bounded structured schema and 512 response tokens. Older compilers
and OS versions return no stream. It emits each completed cue object once,
preserving its array index while later objects are incomplete. The returned
`FoundationVisualCueStream` owns an explicit cancellation callback; the
coordinator cancels it on every scope exit, including early return after
eligibility loss. Stream termination also cancels the detached utility worker.
`FoundationVisualCueProviding` remains the integration seam. Its coordinator
starts work only after both Identify's request-body completion callback and
local Vision completion, and accepts at most six indexed cues with a constrained
trait kind and 2–5-word detail.

The coordinator observes power and thermal notifications for the active
Foundation session. Losing eligibility cancels even a silent model stream;
subscriptions end with the stage, and recovered eligibility does not restart it
within the same attempt. Its injectable notification center keeps these
lifecycle regressions independent of process-global notifications.

The engine buffers partial snapshots until the indexed object is complete. It
silently rejects duplicates, fixed identity/taxonomy/certainty/match vocabulary,
Vision candidate tokens, `-like` wording, unsupported characters, and rendered
pill labels over 36 characters. The prompt prohibits naming the subject, but the
token filter cannot recognize every name missing from Vision's candidates; this
remains part of adversarial device acceptance before production enablement. The
richer stage does not start while Apple Intelligence is unavailable or not
ready, Low Power Mode is on, thermal state is serious/critical, or the app is
inactive. The provider reports unavailable rather than use Private Cloud
Compute.

The project and CI now target stable Xcode 27.0 build `27A266a`, with exact
compiler-build checks on every hosted macOS lane. The runtime audit includes
Foundation parsing, lifecycle, and feature-flag tests. The production flag is
enabled. Hosted evidence and physical-device acceptance in the canonical
[validation checklist](../../../../../docs/system-architecture/04-ai-engineering.md#stable-toolchain-activation-checklist)
remain outstanding; enabling the flag does not establish real-model behavior.

## Inference Invariants

Model choice is server-owned and must remain:

- Free: `gemini-2.5-flash`
- Pro: `gemini-2.5-pro`

Latency work must not change thinking budgets, prompts, response schema, image
resolution, output-token limits, or the single Gemini `generateContent` call per
scan. If measured Gemini time dominates, report it as the remaining latency
floor rather than silently changing these economics or behavior.

An explicit capture timeline is also a request invariant.
`InferenceLiveMediaProjector` projects the ordered image, standalone-audio,
video, and description items once; `InferenceLiveSubmissionCoordinator`
publishes its presentation value and passes the submission value through
`InferenceLivePipelineCoordinator` to `InferenceLiveRequestService`. The service
uses it unchanged for audio file order, `audioMediaItems`, observation-context
JSON, video paths, and `ownerMediaTimeline` in both live visual and live
nonvisual requests. Do not independently aggregate audio paths or descriptors:
their raw input positions are the durable identity used by Edge validation and
promotion.

Audio evidence has a format and ownership invariant as well. Provider-bound
audio must be a local, structurally valid WAV within
`ScanMediaPayloadPolicy.maxInferenceAudioBytes`; `InferenceEngine` must never
reinterpret an HTTPS reference as a Documents path or pass M4A directly to
ordinary inference. Historical refinement resolves a local or secure remote
`StoredMediaReference` through `InferenceAudioPreparer`, streams remote bytes
under the same bound, and creates a new Documents-owned mono 44.1 kHz Int16 PCM
WAV sidecar. Offline replay uses the queue's freshly signed WAV staging keys.
M4A remains a playback/restore format and is eligible for upload only under
`scan_share_restore`. iOS validates new queue sources before persistence and
Edge independently validates RIFF/WAVE bytes plus the complete WAV structure
before the provider call.

External-reference suppressions are also an invariant: they target an immutable
media identity, never a species name, result index, or provider host. A denied
first URL must promote the next permitted URL rather than removing the species
or producing a synthetic censored carousel item.

## Generated Edge DTO Boundary

The canonical response descriptor lives at
`services/supabase/functions/_shared/identify/contract.ts`. It generates the
provider schema, executes server runtime validation, and generates the marked
Identify DTO block in `InferenceEdgeDTOs.swift`. The generated client boundary
includes nested DTOs, array and primitive types, wire `CodingKeys`, and explicit
decoders. Domain types remain separate and are populated after decoding.

The durable historical-media union has a separate executable descriptor at
`services/supabase/functions/_shared/capturedMediaContract.ts` and a generated
block in `Core/Data/Database/CapturedMediaWireDTOs.swift`. Keeping it separate
prevents the JSONB compatibility union from being coupled to Gemini provider
schema projection.

For an intentional contract change, regenerate and validate from the repository
root:

```sh
make generate-edge-dto-contract
make generate-captured-media-dto-contract
make validate-edge-dto-contract
```

Review the Swift diff. The validation lane compares the generated block exactly
and scans all of `apps/ios` for redeclarations or direct/aliased extensions of
generated DTOs. Root response fields remain optional to decode older cached
payloads and support staggered rollout; the Edge runtime validates the full
final response strictly before sending it.

Audio confidence V2 retains the same decoded numeric field. Named animals use
confidence in the returned taxon; Human uses confidence in Human identity and
keeps its existing badge. Unresolved wildlife retains presence confidence
without presenting it as species certainty. `SpeciesDataEdgeResponseTests`
covers both tiers, badge boundaries, all four states, and preservation of the
original score.

Audio subject presentation continues to use those existing fields. `Human` /
`Homo sapiens` is a resolved biological result and keeps the established Human
candidate, reference, sharing, and Field Chat suppressions. A biological result
without resolved taxonomy exposes no species-match confidence or candidates.
When the active evidence is audio-only, new and historical unresolved records
display as **Unidentified Wildlife**, while a non-biological result displays as
**No wildlife detected**. These labels are presentation-only compatibility
guards; they do not mutate stored scans or derive identity from model reasoning.
Historical hydration recognizes canonical and malformed Human taxonomy aliases
and does not restore stale candidates, lookalikes, GBIF keys, or external
reference imagery for Human or unresolved subjects.

## Entitlement response state

`EdgeResponseWrapper.entitlement` is optional so historical stored envelopes
remain decodable. A usable current response may carry the server's `plan_used`,
whether a complimentary credit was consumed, and the complete entitlement-after
snapshot. `InferenceResponsePreparationService` copies those generated wire
values into `InferenceResponseSettlement`. When the request supplied a client
scan ID, the response must echo it exactly; the legacy queue-less nonvisual path
continues to accept the server-assigned ID because it sends no client ID. The
generated DTOs remain generator-owned; the settlement carries the compiler-
checked `EntitlementStateSnapshot` domain value across actor boundaries. The
completion boundary rechecks that the settlement and prepared result carry the
same scan ID before invoking any account mutation.

Foreground completion applies the settlement only after local record persistence
and, for queue-backed work, exact durable queue deletion; background completion
does the same after its final main-context queue deletion. `OfflineQueueManager`
owns the account-lease-protected entitlement, advisory-meter, and
funding-reservation effects. `InferenceFundingReconciliationOwner` retains every
accepted lease, coalesces trailing passes, and prevents a cancellation-ignoring
pass from resuming queue work. Auth admission cancels and awaits that owner
before replacing the source session. The client does not derive a trial or
decrement a complimentary counter locally. Stored replay metadata remains
version-checked and cannot establish current-launch complimentary access before
`get_my_entitlement()` supplies the baseline.

Complimentary holds belong to the original `scanId`. Retry generations,
enrichment, Field Chat, and provider subcalls reuse that analysis and cannot
spend another credit. The joined server/client contract is
[Three Complimentary Pro Scans](../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Live Attempt Ownership

`scanId` identifies durable work; it does not identify the current attempt.
Every queue-backed live submission also creates a UUID inference generation and
writes it to the scan-ingestion `OfflineJobRecord.metadataJSON` in the same
transaction as the queued scan. `InferenceEngine` carries that UUID into the
admitted pipeline session, while `InferenceLiveAttemptCoordinator` owns the
active scan, process-local attempt UUID, durable generation, recoverable scan
identity, current task handle, and any cancelled displaced handles still needed
for Auth quiescence. Full invalidation detaches the current task and clears
local identity before durable callbacks, then retains the cancelled displaced
task until termination; a synchronous callback can install a replacement without
that replacement being cancelled by cleanup. `InferenceLivePipelineCoordinator`
validates at task entry, supplies the exact predicate that
`InferenceLiveRequestService` checks after request-preparation suspension points
and provider return, and supplies `InferenceLiveResultService` with the same
validator before and after parsing and persistence. The pipeline sequences
result preparation; the live presentation coordinator applies the exact-owner
observable/media commit. `InferenceLiveFailureCoordinator` owns failure and
queue-handoff sequencing and returns only synchronous observable actions to that
bridge. `InferenceLiveCompletionCoordinator` owns shared accepted-result effects
and requests exact cleanup from the attempt coordinator through the injected
`InferenceLiveQueueService`; its typed permit fences every notification,
milestone, hydration, and funding-settlement follow-up after cleanup suspends.
Auth admission advances a dedicated follow-up authorization epoch before it
cancels every current or retained displaced live task and awaits all of them. A
queue deletion that ignores cancellation may finish, but it cannot mint a permit
or mutate account state after that epoch closes. The narrower epoch leaves the
durable queue owner intact for Auth quiescence; using full attempt invalidation
there would incorrectly resume background work. Service-level validation does
not replace the database actor's commit-time persistence fence.

All user-facing inference modes are queue-backed before provider dispatch.
Online text-only Describe submissions use a zero-byte `.staged` row, so they
receive the same durable persistence fence and exact cleanup as media-bearing
captures rather than relying only on a process-local presentation token.

A queue-backed generation is single-use. The live queue adapter asks
`OfflineQueueManager` to atomically consume it before
`InferenceLiveSubmissionCoordinator` stages or launches the provider pipeline,
so a duplicate submission is an idempotent no-op across the process.
Cancellation or a pre-provider capture exit registers its UUID in the manager's
generation task registry synchronously, before the asynchronous durable handoff
acquires the per-scan coordinator, so a repeated call cannot restart that UUID
in the handoff window. A registered retirement is excluded from the definition
of a current attempt immediately, fencing delayed persistence, UI publication,
and cleanup while the durable release is still pending. Transient durable-owner
fetch or save failures retain the retiring marker and retry with bounded
backoff; they neither reopen the UUID nor abandon a claim that would suppress
recovery indefinitely. Any intentional new attempt must first claim a newly
generated durable UUID.

Local invalidation snapshots the scan and durable generation, clears the
coordinator's process-local tuple, and only then releases deferred upload and
registers retirement. Successful or failed queued deletion rechecks the same
scan, local attempt UUID, and durable generation after its suspension; a late
finalizer from attempt A therefore cannot clear or retire replacement B, even
when both attempts use the same `scanId`.

Terminal failure handling follows the same ownership protocol. The failure
coordinator captures whether the full scan, presentation-attempt, and durable
foreground generation still match before registering synchronous retirement.
Only that proven owner may emit failure telemetry, record a circuit-breaker
failure, trigger an error haptic, or request an error placeholder, and it does
so without another suspension between the ownership snapshot and terminal
commit. Release, retirement, and rejection callbacks are synchronous boundaries,
so the coordinator rechecks local scan and attempt identity after each relevant
boundary before any later handoff, feedback, or failure-publication action.
`InferenceLivePresentationCoordinator` synchronously applies those narrow
presentation actions through the attempt, lifecycle, and presentation-state
owners. A cooperatively cancelled task or callback-installed replacement
therefore exits silently instead of overwriting the current attempt.

The failure coordinator preserves three separate interruption decisions:
Swift-task cancellation, a thrown `CancellationError` after logical ownership
loss, and URLSession's `.cancelled` error. Retired-owner and connectivity
handoffs still precede the full-owner stale guard, so only the exact local sheet
can acknowledge background ownership. Remaining error classification runs after
that guard and queue release. Known conflicts, consent, provider admission,
observation rejection, and visual decoding retain their non-circuit behavior.
Nonvisual decoding intentionally keeps the existing generic service failure and
circuit accounting; Describe and audio also keep their distinct generic
telemetry.

### Queue-backed connectivity contract

Connectivity failure must be a queue handoff for an exact queue-backed
foreground generation, not a terminal Insight error. The required path publishes
the matching `queuedPresentationScanId`, stops live analyzing without
synthesizing `SpeciesData` or firing an error haptic, and lets the open Insight
bind a value snapshot of that durable row. Direct requests without a queue owner
may still show **Network timeout**. Exhausted server and unclassified failures
use **Analysis delayed / Scan saved** for queued work so an HTTP/provider
failure is never mislabeled as proof that the device is offline.

Local presentation ownership and durable provider ownership are separate
authorities. A path-monitor callback may retire the durable foreground
generation before URLSession reports its failure. The exact still-current sheet
must remain eligible to publish the queued handoff, while a newer scan,
background completion, or replaced presentation must still fence every delayed
mutation. Durable retirement alone is not permission to leave the current sheet
with no result and no queued context.

**Current source status (2026-08-10): remediated; release acceptance pending.**
The catch paths now use full durable ownership for provider results and generic
failures, but retain the exact local presentation UUID solely for the queued
connectivity acknowledgement. They release queue-backed recovery state
idempotently and never record device connectivity loss against the provider
circuit. Queue-backed `identifyMultiModal` uses a 30-second URLRequest timeout
for Pro-funded scans (local trial) and 15 seconds otherwise and returns its
first transient `URLError` without the shared inline transport replay;
queue-less callers retain the reviewed 90-second window and replay. The pipeline
snapshots paid/complimentary Pro funding from the exact generation-matched
durable job immediately after synchronous foreground admission; missing or
legacy metadata uses 15 seconds. The snapshot is local transport policy and does
not change the provider payload or server tier. Handler-owned Auth refresh,
route propagation, and idempotent 5xx handling stay in the shared transport.
`InferenceEndpointTransportTests` owns the protected URLSession-level
deadline/replay and pre-dispatch cancellation regressions, `DetachedWorkTests`
locks parent cancellation reaching the detached preparation handle, and
`InferenceRequestPolicyTests` owns account/request policy. The engine regression
retires durable ownership before releasing visual and nonvisual transport
errors, including data-path and session-disconnect variants, and separately
delivers `.timedOut` while the exact durable owner and path-satisfied state
remain active. The shared scan connectivity policy recursively recognizes
wrapped URL failures while keeping certificate, authentication, and ATS policy
errors out of both decisions even when a broader outer error would otherwise be
eligible. It proves exact queued routing, one request, bounded handoff, eventual
durable retirement, and row survival. A companion case proves a successful
transport response that loses durable ownership before the post-request check
also hands the exact local presentation to the queue; a transport-owned
cancellation does the same. **Analysis delayed** remains an error placeholder
through the explicit `.inferenceError` presentation role; customer-facing title
changes cannot alter that routing. Do not describe this as shipped until the
remaining exact-SHA and physical-device closure gates in the
[live scan connectivity handoff incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md)
pass.

Required-consent failure is handled before the generic transport branch in both
visual and nonvisual live inference. It publishes the temporary **Approval
needed / Scan saved** recovery state while the root returns the account to
Ready, and it never records a `CircuitBreakerManager` failure. Repeated policy
rejections therefore cannot impose the 15-minute network cooldown after the user
completes fresh approval. The durable queue remains the owner of the original
scan and media throughout this transition. After explicit approval opens the
lifecycle gate, it resumes at most the newest consent-blocked row whose
unreleased, dispatchable funding reservation proves the current account and
exact scan ID. Rows without that ownership proof remain paused in Scans.

Provider admission is also separated from transport health for both live
pipelines. Exact `402 pro_required` presents **Upgrade needed / Scan saved**;
`429 ai_quota_daily_exceeded` requests the root paywall without publishing a
synthetic Insight result; and stable user/IP rate limits present **Retrying
shortly / Scan saved**. These coordinator-owned decisions do not advance the
device network circuit. The durable queue retains the observation behind the
paywall and continues to honor the server retry schedule; entitlement exhaustion
becomes explicit attention after the server proof refresh, while temporary rate
limits use the server's bounded retry delay. Production AppDI binds the failure
dependencies to `UsageManager`; direct and test engine construction preserve the
initializer-injected main-actor paywall closure through the fallback live
adapter.

Exact `400 observation_rejected` is terminal policy feedback, not a transport
failure. Both live pipelines present **Try another capture / Scan not
processed**, keep the state out of the device network circuit, and immediately
mirror the background queue's non-actionable failed disposition when durable
state is available. A failed durable transition leaves the normal background
owner eligible to apply the same terminal response safely; the rejected media is
never automatically redispatched as though connectivity had failed.

Live persistence and background retry/finalization share
`ScanInferencePersistenceCoordinator`. The live save validates both the
in-memory foreground generation, durable job generation, and provider result
scan ID while holding that coordinator. A valid confidence-zero response remains
a terminal no-record result, but queue-backed work accepts it only when the
provider echoed the exact scan ID; a mismatched response remains queued for
recovery rather than causing another attempt's work to be finalized. Successful
live cleanup passes an exact `ForegroundInferenceGenerationExpectation` to
`deleteQueuedScan`; the expectation is compared again after URLSession task
enumeration. A stale generation must return without cancelling tasks, clearing
task registries, or deleting the queued row. An unfenced deletion is reserved
for an explicit user/system request whose intended outcome is to cancel every
generation. If background recovery wins, `InferenceSessionLifecycleCoordinator`
validates the exact presentation/foreground tuple, atomically detaches and
retains the live task, cancels it, and only then publishes recovered state.
Offline Sync does not re-read or cancel the facade task after that call, so a
synchronous observer-installed replacement remains safe. The detached task's
delayed error, result commit, and queue mutation are fenced by its invalidated
identity. A SwiftData error while loading the durable owner also fails closed;
it is not treated as proof that the job was deleted.

If a foreground request loses its HTTP response after the server completed the
scan, `InferenceLiveAttemptCoordinator` retains the exact failed presentation
scan ID independently of `activeScanId`; the engine exposes that value for
observable recovery. A normal background response or `/check-scan-status`
recovery may hydrate only that retained ID, only when the provider/result or
local record echoes the same scan ID, and only when no newer foreground scan
owns the presentation. The stable engine methods only forward immutable recovery
values; the queued-record facade additionally supplies a synchronous loader so
the lifecycle owner never acquires the managed record.
`InferenceSessionLifecycleCoordinator` owns the checks and the reviewed clear-
before-publication or clear-before-record-load order. Known exact
ingestion/quota replay conflicts use the temporary customer state **Restoring
scan / Safely saved** instead of the misleading **Network timeout** placeholder;
installed clients are protected primarily by the server's idempotent `200`
response replay.

Foreground still analysis sends inline image bytes with `r2ObjectKeys: []`. A
destination filename is not an uploaded staging source; advertising a synthetic
key causes strict server finalization to wait for an asset that cannot exist.
Older affected responses are repaired only by the server's exact owner-scoped
inline-manifest recovery contract. If a durable failure happens before any owner
row exists, the offline queue discards potentially consumed staging keys and
uploads its retained local media again.

Loading a persisted library record is also a presentation replacement. The
stable `InferenceEngine.load(from:)` facade delegates to
`InferenceHistoricalLoadCoordinator`. That owner invalidates the exact live
UUID, releases its deferred-upload hold, cancels live provider/hydration work,
and schedules durable handoff before assigning the historical `activeScanId`. It
then releases prior live-media buffers before building and synchronously
publishing `InferenceHistoricalRecordProjection`, avoiding overlapping large
live and persisted presentations in memory. The queued capture remains intact
for background recovery. Projection occurs while the SwiftData record is live on
`@MainActor`; the registered hydration task captures only that immutable value.
Rich lookalikes are decoded once for refresh planning, while legacy lookalike
names and candidate bytes are converted in one awaited detached decode.

## Verification

Use the canonical
[live inference verification matrix](../../../../../docs/development-guides/08-testing-strategy.md#live-inference-requestresult-verification)
for the extracted request, result, and recovery boundaries. The
[cleanup plan](../../../../../docs/rfcs/codebase-cleanup.md#phase-2-behavior-preserving-file-splits)
records slice completion, integration-audit outcomes, and outstanding runtime
evidence.

Focused tests live under `apps/ios/MerianTests/Core/AI/`.
`Core/AI/Models/CaptureTelemetryTests.swift` preserves live and historical
capture-context mapping, while the colocated
`SpeciesDataEdgeResponseTests.swift` preserves the handwritten wire-to-domain
adapter. The shared Models suites exercise only the platform-neutral domain
graph, and `SpeciesModelsArchitectureTests.swift` enforces that ownership and
effect-free boundary. Native-default camera zoom normalization remains a Capture
Submission policy and is covered by `CaptureSubmissionPolicyTests`, not the Core
AI telemetry suite.
`Core/AI/Inference/InferenceEngineAssemblyArchitectureTests.swift` freezes the
sole production owner-graph constructor, exact construction order and injected
edges, exhaustive engine-to-assembly dependency forwarding and consumption,
stable engine initializer surface, private engine retention, one-shot effect-
free assembly boundary, and 600-line ceiling.
`InferenceEngineFacadeArchitectureTests.swift` freezes the 600-line engine
ceiling, private focused-owner retention, pure compatibility adapters,
compile-time diagnostic isolation, stable debug signatures, and delegation of
first-render metrics and alternatives-exhausted state to their focused owners.
`Core/AI/Inference/InferenceConfidencePolicyTests.swift`,
`InferenceLookalikeCachePolicyTests.swift`, and
`ScanningPhrasePolicyTests.swift` freeze the extracted inference thresholds,
installed cache-reset version, tier fallback, and phrase cadence.
`Core/AI/Inference/InferenceHydrationCoordinatorTests.swift` covers replacement
task retention, exact-task awaiting for review replacements, Auth admission and
drain behavior, stale completion isolation, bounded request histories, persisted
TTL pruning, and backoff expiry/reset.
`Core/AI/Inference/InferenceHistoricalRecordProjectionTests.swift` covers the
complete persisted presentation mapping, active-override identity, Human and
unresolved suppression, rich/legacy lookalike planning, cache-reset and metadata
scope independence, candidate decoding after source-record deletion, and
malformed-data compatibility.
`Core/AI/Inference/InferenceHistoricalHydrationCoordinatorTests.swift` covers
decode-before-override ordering, concurrent remote-stage admission, enrichment-
before-GBIF ordering, enriched-key use, species-cache scope independence,
replacement while decode ignores cancellation, and cancellation while override
hydration ignores cancellation. It also locks terminal `.empty` reference state
when the eligible providers return no usable image.
`Core/AI/Inference/InferenceHistoricalLoadCoordinatorTests.swift` covers initial
publication before deferred hydration, Auth-fenced admission without state
mutation, replacement of a cancellation-ignoring historical decode, and required
legacy lookalike reset scheduling with the record's model container.
`Core/AI/Inference/InferenceSpeciesEnrichmentServiceTests.swift` covers exact
request/scope forwarding, metadata trimming and taxonomy mapping, raw-versus-
sanitized alternate names, missing-field preservation, complete lookalike
mapping, empty payloads, and error propagation without live networking.
`Core/AI/Inference/InferenceSpeciesHydrationCoordinatorTests.swift` covers the
complete live Wikipedia/enrichment/GBIF order, exact enriched taxon-key use,
independent metadata/lookalike completion, reference-loading transitions, stale
Wikipedia suppression without consuming the retry, persistence-work emission,
post-cancellation suppression for Wikipedia, GBIF, metadata, and lookalikes,
pre-start stale-presentation rejection, same-scan presentation replacement
during deferred loading cleanup, and 429 backoff.
`Core/AI/Inference/InferenceSpeciesPresentationCoordinatorTests.swift` covers
observable species/reference/loading publication, shared review callbacks,
case-insensitive exact identity, presentation and review-generation fencing,
exact and mismatched alternatives-exhausted admission, background versus
serialized review-write routing, stale/Auth-fenced write rejection, and live
biological admission. Its architecture sibling freezes the single production
callback factory, engine delegation, fence and routing tokens, effect/state/task
exclusions, private dependency storage, and 600-line ceiling.
`InferenceLookalikeCacheResetServiceTests.swift` freezes nil-container and
reset-required admission without touching UserDefaults or a live database actor.
`Core/AI/Inference/InferenceHydrationPersistenceServiceTests.swift` covers exact
snapshot/container forwarding, live reference and domain-taxonomy metadata
writes, and the live adapter's lookalike encode, persist, and decode round trip
in the existing SwiftData blob. `SpeciesMetadataPersistenceTests` locks the
effective override-or-original identity fence for both reference and enrichment
writes. Architecture coverage separately freezes the detached encoding boundary.
`Core/AI/Inference/InferenceWriteCoordinatorTests.swift` covers queue bounds,
Auth quiescence, reset cancellation, action-history eviction, ordered stale
write rejection, confirmation/review generation independence, and the shared
identification final-writer tail.
`Core/AI/Inference/InferenceLiveQueueServiceTests.swift` records the injected
durable boundary and verifies exact claim/current-owner results, optional
generation release, retirement policy, generation lookup, adopted-media
deletion, terminal rejection, and false-result propagation without resolving the
live queue. `InferenceLiveAttemptCoordinatorTests.swift` covers exact local and
durable identity, queue-less ownership, full-invalidation and exact-current
retirement callback ordering, re-entrant replacement preservation,
failed-finalization retirement, recovered-background admission, partial durable-
identity rejection, and both sides of a suspended same-scan replacement race. It
also proves invalidation detaches task and identity before durable callbacks, so
a callback-installed replacement survives. A stale successful finalizer cannot
clear or authorize replacement ownership, and a stale failed finalizer cannot
retire it. `InferenceLivePipelineCoordinatorTests.swift` covers incomplete,
unavailable, and duplicate admission, empty visual encoding refund/retirement
order, queue-less visual and nonvisual follow-up order, durable nonvisual
finalization before follow-ups, circuit-gated failure dispatch, and a suspended
stale result that cannot publish or clear a replacement.
`InferenceLiveSubmissionCoordinatorTests.swift` locks visual media, telemetry,
identity, task staging, and exact one-shot first-render benchmarking; audio and
Describe copy; Auth rejection; visual empty-payload release-before-retirement;
and the retained nonvisual retirement-only compatibility path. The pipeline
architecture suite freezes both startup orders, engine delegation, effect
exclusions, immediate installation in the sole attempt task owner, and the
600-line production ceiling. `InferenceLivePresentationCoordinatorTests.swift`
locks exact accepted and stale publication, suppression of stale persisted-media
projection, queue-less first-render clock transfer to the server scan ID,
rejection of that transfer for a stale attempt, publication-before-event
ordering, exact finish routing, and all three typed failure mappings. It also
proves exact request-body session forwarding, phrase-deck preservation during
visual cancellation, and captured hydration-policy and `ModelContainer`
forwarding. The suite has the standard one-minute async limit; dedicated test
support keeps its behavior cases focused. The shared pipeline architecture suite
freezes the sole production callback factory, the attempt- before-projection
order, engine delegation, captured hydration and local- analysis forwarding,
live-effect confinement, the synchronous queue-less branch, and the 600-line
ceiling for every Pipeline production file.
`InferenceLivePipelineDurableVisualTests.swift` separately locks the complete
durable visual success order, including exact queue deletion before
notification, benchmark completion, hydration, and milestone follow-ups.
`Core/AI/Inference/InferenceLiveCompletionCoordinatorTests.swift` covers
persisted and confidence-zero normalization, exact shared-effect order,
rejected-persistence inertness, biological event gating, sealed queue-less
authorization, successful and failed durable finalization, notification
preference gating, funding settlement after deletion, mismatched-settlement
rejection, owner replacement, Auth admission, and durable-generation retirement
during a suspended finalizer. Its sibling architecture suite freezes the
singleton-free core/live-adapter split, AppDI composition, retired engine
effects, visual/nonvisual call-site order, and production-file ceiling.
`Core/AI/Inference/InferenceLiveRequestServiceTests.swift` covers visual and
nonvisual provider mapping, inline-image key omission, MIME detection,
descriptor alignment, observation-context encoding, video upload order,
request-body callback forwarding, empty encodes, and exact-attempt rejection
after image encoding, video upload, or provider return.
`Core/AI/Inference/InferenceLiveResultServiceTests.swift` covers normalized
visual/nonvisual persistence inputs, model-context identity, canonical media
order, exact fence forwarding, typed outcomes, nil/empty compatibility,
confidence-zero completion, stale/cancelled returns, the server-assigned queue-
less nonvisual identity, and the live actor adapter.
`Core/AI/Inference/InferenceResponsePreparationServiceTests.swift` covers exact
case-insensitive response identity, immutable settlement projection, mismatch
suppression, server-assigned identity compatibility, and malformed-account
omission without mutating global state.
`Core/AI/Inference/InferenceReviewSnapshotServiceTests.swift` proves the live
bounded projection, preserves the missing-row compatibility result, and shows
that an unreadable SwiftData store fails confirmation and reset closed before
observable review state changes.
`InferenceIdentificationReviewCoordinatorTests.swift` locks local-before-cloud
ordering, successful refresh-before-milestone effects, sync-failure suppression,
replacement and Auth-fence rejection, typed snapshot failure, dictionary lookup
failure logging, and the silent species-ID compatibility fallback through
injected closures. `InferenceReviewWorkflowCoordinatorTests.swift` locks atomic
local admission before dictionary/cloud work, serialized dictionary and review
writes, replacement during a cancellation-ignoring lookup, enrichment followed
by missing-row ID fallback, and stale dictionary and species-ID fallback
rejection for historical results.
`InferenceIdentificationReviewPresentationTests.swift` locks the exact override,
confirmation, reset, dictionary normalization, URL admission, and
persistence-patch mappings, including a persistence result when no live
presentation remains. `InferenceArchitectureTests.swift` freezes the review
action/effect/workflow split, AppDI composition, effect placement, retired
engine helpers, source-order invariants, the species-presentation bridge's
hydration callback bundle as the workflow's only current-species and
presentation-generation source, and the 600-line ceiling for every extracted
review owner. `Core/AI/Inference/InferenceLiveResultIntegrationTests.swift`
proves both engine pipelines use the injected result boundary, publish
confidence-zero completion, forward the original media timeline and ordered
context JSON, preserve persisted media order, withhold rejected results, and
reject an uncancelled stale return for a replacement local attempt. These
queue-less fixtures omit a response scan ID; durable queue transitions,
notifications, milestones, and reference effects are not exercised by this
suite. The service suite separately tests forwarding the exact fence and
revalidating an injected same-scan replacement identity. Suspension tests use
continuation gates, not timing sleeps.
`Core/AI/Inference/InferenceLiveFailurePolicyTests.swift` locks interruption
precedence, exact HTTP status/code classification, connectivity security vetoes,
retirement reasons, and modality-specific telemetry/circuit/feedback decisions.
`InferenceFailurePresentationTests.swift` locks exact copy, saved/direct
fallback, the quota presentation omission, and typed placeholder/telemetry
mapping. `InferenceLiveFailureCoordinatorTests.swift` locks synchronous release,
retirement, recoverable-ID, telemetry, circuit, log, rejection, feedback,
paywall, and presentation order; it also covers stale suppression, exact
retired-owner, transport-cancellation, and connectivity handoffs, and
release/retirement/rejection callback replacement races through an injected
queue boundary. Its architecture sibling freezes the singleton-free core/live
split, AppDI composition, the three presentation actions, post-retirement owner
guard, retired engine effects, and the no-task/no-suspension boundary.
`InferenceLiveRecoveryIntegrationTests.swift` exercises both queue-less engine
paths for known conflict presentation, cancellation and stale-failure
suppression, and injected quota paywall requests; decoding cases also
distinguish audio from Describe. The result and recovery integration suites
share `InferenceLiveEngineTestSupport` and the single-operation
`InferenceOperationGate`. Both suites claim
`.sharedProcessState(.networkClientOverrides)`, also used by
`InferenceEngineTests`, before temporarily setting the lookalikes-reset
UserDefaults value and resetting the shared circuit breaker. The helper restores
the previous UserDefaults value and clears the circuit at teardown; it never
replaces queue-manager state. Suite-local `.serialized` alone cannot coordinate
those peer suites. `Core/Security/CircuitBreakerManagerTests.swift` instead uses
a fresh manager per XCTest case instead of borrowing the shared engine circuit.
The queue-less integration tests do not prove durable handoff or actual
haptic/telemetry delivery. Coordinator tests prove deterministic orchestration
against injected effects, while existing queue-backed engine/network suites
cover the live durable ownership boundaries; actual feedback delivery remains
runtime/device verification. `Core/AI/LocalVisualAnalysisTests.swift` exercises
the local-analysis coordinator through the stable engine adapters, including
replacement, dismissal, request completion, application inactivity/reactivation,
queue handoff, and Auth fences plus non-cooperative provider returns.
`Core/AI/Inference/InferencePresentationCoordinatorTests.swift` directly locks
prepared, active, nonvisual, stale-owner, reset, queue-phrase/media, Auth-
admission cleanup, post-drain rejection of re-entrant presentation context, and
one-shot first-render transitions plus exact-source clock rebinding without
constructing the observable engine.
`Core/AI/Inference/InferencePresentationStateTests.swift` locks every value
reset, successful-result and queue-handoff publication, cancellation, historical
replacement including displaced-loader cleanup, visual-to-nonvisual distance
isolation, and Observation invalidation through the engine's source-compatible
scalar and value-type media accessors.
`Core/AI/Inference/InferenceSessionLifecycleCoordinatorTests.swift` executes the
cross-owner sequence directly. It covers complete new-scan reset, visual and
nonvisual replacement, displaced visual owner/queue/render-clock cleanup,
coherent active-visual queue handoff, explicit cancellation, historical
replacement, and Auth quiescence that waits for every cancellation-ignoring
owner, including a live task displaced before Auth admission. Its architecture
sibling freezes the reviewed ordering, method-local engine/submission
delegation, absence of facade-owned recovery guards or mutations, semantic
attempt-task operations, effect exclusions, and the 600-line ceiling.
`Core/AI/Inference/InferenceSessionLifecycleRecoveryTests.swift` separately
locks exact background ownership transfer, displaced-task detachment and
cancellation before publication, stale same-scan replacement rejection, every
queued-result presentation-identity fence, matching-result publication, and
queued-record callback ordering without constructing the engine or a managed
SwiftData record. `Core/AI/Inference/InferenceLiveMediaProjectorTests.swift`
locks display-image selection, default-versus-explicit timeline ownership,
ordered submission mapping, visual focus regions, video poster suppression and
fallback, secure remote-video admission, adjacent-still retention, compatible
Documents/temporary path resolution, persisted-image remapping, empty legacy
input filtering, and the legacy nonvisual audio-modality decision without
filesystem or network access.
`Core/SpeciesReference/SpeciesReferenceHydrationServiceTests.swift` covers
Wikipedia/GBIF requests, response parsing, missing-description compatibility,
and failure behavior. Its architecture suite prevents either consumer from
reclaiming the shared transport, while `InferenceArchitectureTests.swift` locks
the extracted task-state boundaries, the session-lifecycle sequence owner,
attempt queue core/live split, the durable request-callback capture, injected
request and result boundaries, the species/enrichment coordinator cores,
hydration logging and cache-reset live adapters, enrichment mapper/live endpoint
adapter, and hydration persistence/live database adapter, the value-only
historical record projection, the synchronous historical-load owner, the
registered historical-hydration owner, pre-projection live-media release order,
and no-managed-record task capture, the non-observable presentation-lifecycle
owner, the observable presentation-value owner, the live media projector and
retired engine mapping helpers, stateless recovery policies, the
identification-review action/effect and workflow coordinators, live adapter, and
pure presentation mapper, file-private format/mapping helpers, the retired
local-analysis aggregate, and extracted-owner ceilings. The dedicated
live-failure architecture suite owns synchronous failure-commit and
effect-placement guards. Network timing and request-upload handoff coverage
lives under `MerianTests/Core/Network/`; the full server generation invariants
are enforced by the Deno tests beside `identify-multimodal`.
`Core/AI/InferenceEngineTests.swift` retains the integration proofs for Auth
quiescence, closed-fence review rejection, stale confirmation rejection after an
override, and presentation-reset hydration cancellation.
`Core/Data/Database/SpeciesMetadataPersistenceTests.swift` separately locks
atomic override admission, destructive reset/identity replacement, and
non-destructive same-species historical refresh.

`Core/AI/Inference/InferenceScanReplacementTests.swift` uses isolated current-
schema stores to cover persisted-result admission, missing/same/blank IDs,
pending-only replacement inserts, durable metadata transfer, review-state reset,
and metadata-save failure without discarding unrelated user edits.
`InferenceIntegrationAuditTests.swift` covers visual, audio, and Describe flows
through the injected live boundaries: no-record/missing-ID reanalysis retains
the original; Auth quiescence waits for cancellation-ignoring results and
rejects late success/failure; and suspended positive-confidence queue results
cannot delete recovery rows, publish completion, or overwrite a replacement
generation. The parser results in these overlap tests are injected;
database-actor tests remain the authority for actual result persistence.

Queue-backed inference suites claim both required resources in one
`.sharedProcessState(.networkClientOverrides, .offlineQueueManager)` trait.
`Support/SharedProcessStateGate.swift` supplies atomic, cancellation-aware test
leases shared with the Capture XCTest base, `OfflineQueueTestCase`. The queue
scope restores the prior model context after each case; individual tests must
still await their own async work and restore every other field they change.
Generic Insight contexts no longer configure the queue or launch repository
startup work. `SharedProcessStateGateTests` locks overlap, independent
resources, cancelled waiters, throwing scopes, and stale-release isolation.
`Core/Data/OfflineSync/OfflineJobSchedulerTests.swift` covers ordered foreground
drain dispatch, including inference replay, with injected inert effects and a
fixture-owned wake timer. The lifecycle suite verifies admission and the live
scheduler route; neither suite starts uncontrolled provider or maintenance work.

A queue-handoff regression is not valid when it throws from consent preflight or
another pre-request seam. It must dispatch through mocked URLSession transport,
retire the exact durable foreground generation before releasing the transport
error, and prove the same-ID sheet becomes `.queued` without a second request,
placeholder, haptic, circuit failure, or manual test cleanup of queue ownership.
The full matrix and release evidence requirements live in the
[incident](../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md).
