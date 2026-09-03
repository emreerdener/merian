# `_shared` Directory

The `_shared` repository contains the core abstraction domains that power
Merian's globally isolated Deno Edge Functions.

Rather than fragmenting logic recursively through every function directory, the
shared dependencies are grouped by domain. Keep new shared code here only when
multiple functions need the same behavior and the ownership boundary is clear.
Credential/header changes must also satisfy the canonical
[server credential and database release safety
contract](../../../../docs/backend-and-data/13-server-credentials-and-database-release-safety.md).
Scan submission or media-lifecycle changes must satisfy the joined
[scan ingestion reliability and recovery
contract](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

## Infrastructure Map

- **`edgeHandler.ts`**: Authenticated user-facing function wrapper, custom-auth
  `serveEdge(...)` registration, preflight handling, background task dispatch,
  structured operational logging, auth timing, and additive `Server-Timing`
  propagation. Both wrappers assign a server-owned request UUID and add
  `X-Request-ID` to every response. They also overwrite `X-Merian-Handler: 1` on
  every wrapped response so production smoke failures can distinguish a
  handler-owned denial from a gateway/router response without exposing the
  request ID or response body. Expected thrown failures use `PublicHttpError`;
  explicit safe response failures use `publicErrorResponse(...)`. Audited
  returned `4xx` application contracts are still supported, while unexpected
  exceptions become `500 internal_error` and ordinary returned `5xx` bodies keep
  their status but receive a generic status-derived envelope. Authentication and
  purchase-identity handlers use `logIdentitySafeError(...)`, whose fixed field
  set accepts only bounded operation tokens and HTTP status. UUID-shaped values,
  opaque provider IDs, capabilities, URLs, prose, and raw exceptions collapse to
  a generic error kind instead of entering logs. Other handlers may retain
  private exception details only under their separately reviewed logging
  contract.
- **`http.ts`**: CORS headers, JSON responses, parameter validation,
  constant-time comparison helpers, and the canonical bounded request readers.
  `parseJsonBody(...)` is the ordinary object API;
  `readRequestBodyWithinLimit(...)` preserves exact signed webhook bytes; media
  adapters delegate to `readBoundedJsonBody(...)`. They validate JSON media type
  where applicable, declared and actual byte counts while streaming, and invalid
  UTF-8. `readByteStreamWithinLimit(...)` coalesces tiny transport chunks into a
  geometrically growing bounded buffer, so memory tracks accepted bytes instead
  of attacker-influenced chunk count. Every route selects a reviewed
  `JSON_BODY_LIMITS` class (`small`, `standard`, or `bulk`) or an explicit
  media-specific ceiling. Do not add a direct `req.json()`, `req.text()`, or
  unbounded clone to a production handler.
- **`auth.ts`**: Shared bearer parsing, claims validation, generic public
  authentication failures, and the compatibility Auth-server `getUser` strategy
  used by existing authenticated endpoints.
- **`clientAddress.ts`**: Shared proxy-observed client-address extraction and
  purpose-separated daily HMAC derivation. Abuse controls store only the HMAC; a
  missing proxy address joins a conservative shared fail-safe bucket.
- **`claimsAuth.ts`**: Opt-in cached-JWKS `getClaims` authentication for
  latency-sensitive routes. It explicitly validates issuer, audience,
  expiration/not-before, role, and `sub`; accepts anonymous and authenticated
  users; and rejects `service_role`. All functions share the same exact Supabase
  SDK, but keeping this policy out of `edgeHandler.ts` prevents an implicit
  fleet-wide authentication change. Internal replay keeps its separate
  timing-safe service credential path.
- **`publishableKey.ts`**: Canonical public project-key resolver for user-scoped
  Supabase clients. It strictly parses the platform-managed JSON
  `SUPABASE_PUBLISHABLE_KEYS` dictionary, prefers its named `default` key,
  accepts named rotation keys, and retains a correctly shaped legacy
  `SUPABASE_ANON_KEY` only during the overlap window. Production modules may not
  read either environment variable directly.
- **`serviceRoleAuth.ts`**: Fail-closed request authentication and canonical key
  resolution for every internal worker/status boundary that shares this policy.
  It prefers an explicit CI/local `SUPABASE_SERVER_API_KEY`, then the
  production-deploy-synchronized non-reserved `MERIAN_SUPABASE_SERVER_API_KEY`,
  then platform-managed named `sb_secret_...` values in the JSON
  `SUPABASE_SECRET_KEYS` dictionary, then the singular `SUPABASE_SECRET_KEY`
  local/manual fallback, and retains `SUPABASE_SERVICE_ROLE_KEY` only as a
  legacy migration fallback. The synchronized value is the same project key and
  does not create a custom request header. It never infers authority from a
  database query, RLS result, JWT claim, or network capability probe. Key
  configuration is classified separately: current values must have a
  platform-shaped `sb_secret_` prefix plus a URL-safe opaque suffix of at least
  20 characters, while a legacy fallback must be an HS256 JWT with role
  `service_role` and a complete 43-character base64url signature. Publishable,
  anon/user, and truncated placeholder values fail closed. Every source is
  classified independently: malformed values never become candidates or veto an
  exact inbound key from another valid source, while an unmatched request still
  fails as invalid configuration. Legacy JWT keys may use Bearer transport;
  non-JWT secret keys belong only in `apikey`. Request-authenticated routes bind
  privileged database clients and internal calls to the exact matching
  server-managed environment value, never the caller-owned header string or an
  unrelated higher-priority fallback. Environment-originated callers with no
  inbound credential continue to use the documented selection precedence. The
  shared request-header helper applies the same current/legacy key transport to
  operational scripts.
- **`dwcaReleaseState.ts`**: Strict parser and service-only RPC client for the
  canonical default-off DwC-A launch gate. Processing and capability-download
  routes accept only an explicit database Boolean; missing state, query errors,
  and malformed results fail closed.
- **`serviceRoleClient.ts`**: Creates privileged PostgREST, Storage, Functions,
  and Auth Admin clients from an authenticated or environment-resolved server
  key. Its final fetch adapter removes only supabase-js's exact
  API-key-as-Bearer fallback for `sb_secret_...` credentials, preserves all
  unrelated request headers and user access tokens, and retains legacy
  service-role JWT transport for older projects. Production code must use this
  factory rather than constructing an admin `createClient(...)` directly. Every
  SDK request carries a 30-second hard deadline by default, including PostgREST,
  Storage, Functions, and Auth Admin calls. Operational monitors use the options
  factory to retain a 15-second deadline and an explicit streaming response
  ceiling (64 KiB for aggregate health, 2 MiB for detailed scan-media samples).
  JSON Function callers use `invokeServiceRoleJson(...)`: a non-2xx response
  reports only its numeric status, bounded SDK failure class, and the fixed
  `X-Merian-Handler: 1` routing marker before canceling the body. It never logs
  the upstream body, request ID, or credential. Transport and in-routine
  authorization remain independent: migration
  `20260727010340_fix_service_role_authorization_guard.sql` lets
  `internal.require_service_role()` recognize either the legacy JWT claim or
  PostgREST's protected standard `service_role` setting for an opaque key. It
  does not broaden any RPC execution grant. Migration
  `20260727013416_future_proof_server_key_boundaries.sql` applies the equivalent
  private header policy to installed `pg_net` routines and persisted cron
  commands.
- **`outbound.ts`**: Canonical outbound HTTP deadline and response-budget
  adapter. `fetchWithDeadline(...)` combines a caller cancellation signal with a
  hard timeout; `readResponseTextWithinLimit(...)` and
  `readResponseJsonWithinLimit(...)` reject declared or streamed oversized
  provider bodies before parsing. `createResponseBodyLimitFetchTransport(...)`
  enforces the same ceiling while preserving SDK-owned streaming parsers.
  `createDeadlineFetchTransport(...)` applies the ownership rule to Supabase SDK
  clients; authenticated user/claims lookups use a 15-second ceiling. Production
  code must not invoke global or injected fetch transports directly.
- **`gemini.ts`**: The only permitted Google GenAI client boundary. Its
  SDK-owned HTTP transport has a 90-second hard timeout so model calls cannot
  wait for the Edge worker shutdown ceiling.
- **`aws.ts`**: Cloudflare R2/S3-compatible presigned upload, object HEAD/copy,
  and batch deletion helpers. Presigned PUT generation requires a positive safe
  content length and signs exact `Content-Length`, `Content-Type`, and `host`
  through `allHeaders: true`; callers must return those required headers with
  each URL. `deleteR2ObjectIfPresent(...)` is the strict completion-boundary
  helper: it accepts only 2xx or idempotent 404 and rejects every other provider
  response. `deleteR2Objects` uses `mapWithConcurrencyLimit` internally so
  lifecycle workers do not run unbounded delete fanout. Every executed object
  request carries a hard deadline, including batch delete, copy, upload, list,
  and inference-media reads. Prefix helpers classify `staging/`, `quarantine/`,
  and `exports/` as temporary, `public_uploads/free|pro/` as scan media, and
  `avatars/` as durable profile media. Classification alone is not deletion
  authority. Scan purge flows must use
  `deleteScanMediaR2Objects(urls, ownerUserId, config)`, which accepts only flat
  canonical free/Pro keys containing that exact owner UUID and rejects
  foreign/nested/malformed candidates before signing. Avatar replacement must
  use `deleteAvatarR2Object(...)` with the owning user ID.
- **`mediaBudgets.ts`**: Shared media byte ceilings, allowed staging content
  types, inline/staged audio and image validation, clip-count limits, and
  `Content-Length` prechecks. The shared staging cap is six files so one video
  scan can sign five sampled inference frames plus one playback clip; image,
  audio, and video sub-limits still prevent broad over-batching. Request and
  response bodies that may be chunked or omit `Content-Length` must be consumed
  through `readRequestJsonWithinBudget`, `readResponseArrayBufferWithinBudget`,
  or `readStreamArrayBufferWithinBudget` so the byte counter rejects oversized
  streams before V8 can allocate past the Edge heap budget. The request JSON
  adapter delegates to `http.ts`; `mediaBudgets.ts` owns only the larger
  reviewed ceiling and media-specific error copy. The shared storage allowlist
  includes WAV and M4A because playback restore needs both, but
  `/generate-upload-urls` narrows that set by purpose: ordinary inference audio
  is exact `.wav`/`audio/wav`, while `.m4a`/`audio/mp4` requires explicit
  `scan_share_restore`. Signing proves bounded metadata, extension, owner, and
  purpose only; the inference consumer must still inspect the object bytes
  before provider dispatch.
- **`concurrency.ts`**: Ordered promise mapping with a fixed worker width. Use
  `mapWithConcurrencyLimit` for fanout work such as APNs delivery or remote
  object operations where unbounded `Promise.all(...)` could spike sockets,
  heap, provider throttles, or Postgres writes.
- **`fieldChatSpeciesKnowledge.ts`**: Shared Insight/Explore/Species Dictionary
  prompt rules for stable species knowledge. Missing reference prose must not
  block a general species answer, but typical traits must remain distinct from
  recorded observations. The rules preserve identification uncertainty, source
  privacy, and the absence of live search; they do not authorize current/local
  claims or invented citations.
- **`fieldChatResponse.ts`**: Shared Insight/Explore/Species Dictionary Field
  Chat success-envelope builders. Every thread and action payload echoes the
  exact requested scan, post, or species as `subject_id`; thread builders also
  own the v1 limits and clamp the remaining daily sends. The helper also binds
  an assistant to its originating send UUID in private safety metadata,
  canonicalizes request UUID case, derives a deterministic UUIDv8 assistant-row
  identity, and performs bounded completion polling when the quota layer
  identifies an in-flight or completed replay. Keep this boundary shared so an
  empty thread, feedback, note summary, prompt response, concurrent local
  refusal, or ambiguous send retry cannot silently lose subject/request identity
  in one route.
- **`fieldChatReservation.ts`**: Fail-closed adapter to the service-only atomic
  Field Chat admission and stale-quota recovery RPCs. It validates the exact
  subject/conversation/user/request-bound persisted user row returned by
  admission, exposes authoritative cross-table daily counts, maps only stable
  database tokens to public errors, and treats timeout or malformed RPC output
  as retryable unavailability. The database transaction—not an Edge
  count-then-insert read—owns same-key replay/conflict, one unanswered request
  per conversation, two-row capacity, and the shared three-family daily cap.
  Migration `20260821030027_add_species_dictionary_field_chat.sql` extends both
  RPCs with the Species Dictionary subject and quota operation while preserving
  those transaction boundaries.
- **`fieldChatDailyUsage.ts`**: Read-side counter for user messages admitted
  across Insight, Explore, and Species Dictionary chat. PostgreSQL admission is
  authoritative; this helper only shapes current limit responses through the
  service-only `get_field_chat_daily_usage(...)` RPC. Migration
  `20260824210544_preserve_field_chat_daily_usage.sql` stores a content-free
  user/day aggregate, increments it atomically with admission, preserves it
  across conversation cascades, and conservatively combines it during Ghost
  merge. Timeout, database error, or malformed output fails closed with
  retryable `503 field_chat_admission_unavailable`; there is no live-message
  fallback. The same migration registers its merge handler in the effective
  policy allowlist, asserts the complete registry, short-locks all three
  conversation/message families to remove historical message-less threads,
  creates a database-clock UTC cutover guard, and moves conversation creation
  into the reservation transaction. Corrected reservation callers return
  retryable `503 field_chat_admission_cutover_pending` while the cutover is
  `pending` or `ready`; an older create-before-admission bundle can hit the
  direct-insert boundary first and surface an unnormalized failure. Conversation
  `INSERT` is permanently revoked from API roles, so it cannot write before or
  after activation. Exact persisted replays remain available. The service-only
  one-way activation opens admission only after all three selected bundles
  deploy and every live route returns both
  `X-Merian-Field-Chat-Contract: atomic-admission-v1` and its exact
  `X-Merian-Field-Chat-Bundle-SHA256`. The generated digest covers the route's
  transitive runtime graph, Deno configuration, and frozen lock. A `ready`
  database state force-selects all three routes, and the activation row persists
  candidate, migration, and all three live bundle digests. Source fixtures
  exercise every real reserve-delete-fresh-reserve branch and the full merge
  orchestrator, but only a non-skipped disposable database run on the reviewed
  SHA is release evidence.
- **`scanMediaAssets.ts`**: Normalized scan-media lifecycle helpers. Upload
  signing creates staged scan-media asset rows with `scan_id` null until the
  final scan exists, identify finalization marks them promoted/deleted/failed,
  and write paths make best-effort `scan_media_assets` refresh calls after scan
  inserts or video repair updates. The `reconcile-scan-media-assets` worker owns
  stale staged-row repair and abandonment cleanup, while checking active
  ingestion jobs before abandoning staged upload-session media. Composer and
  status paths prefer ready display/playback asset rows before falling back to
  `captured_media` and legacy arrays. Historical compatibility manifests may
  prove `has_audio` through a nested audio reference, but strict Captured Media
  Wire V1 canonicalization drops that field. Current positive values must come
  from verified normalized/durable playback metadata; V1 and legacy URL-array
  fallbacks default false. `scan-media-health` reads the same lifecycle state
  for deploy smoke checks and operational drift alerts, but does not mutate
  media rows. Structured signing registration is idempotent for one
  authenticated owner/client-scan/deterministic key, composes compatible
  subsets, reuses the original upload session after an ambiguous response, and
  enforces the six-source union before signing.
- **`capturedMediaContract.ts`**: Dependency-free executable wire contract for
  `public.scans.captured_media`. It strictly validates every new V1 manifest,
  preserves the installed-client outer-key/`_0` union, and canonicalizes legacy
  reads without decoding retired description timestamps. Compatibility reads
  tolerate legacy `localFile` references; canonical server rewrites discard
  those device-only paths and historical nested video audio, then revalidate
  strict HTTPS-only V1. Strict V1 requires one or more items; the compatibility
  reader accepts historical `[]` as missing, and writers persist `null` when no
  durable item survives canonicalization. Identify finalization, Explore
  restoration, and media reconciliation share this write boundary. Its separate
  generator owns `CapturedMediaWireDTOs.swift`; keep it independent of the
  Gemini response contract because durable JSONB and provider-schema unions have
  different compatibility rules.
- **`scanPersistence.ts`**: Shared scan-row write settler used by all four scan
  producers. It polls the exact `(scan_id, user_id)` topology after success,
  rejection, or a lost response and classifies the result as committed,
  definitely rejected, or unknown. Only positive exact-owner absence evidence
  authorizes pre-insert cleanup; unreadable or contradictory state preserves
  quota, lifecycle rows, and promoted media.
- **`scanIngestionJobs.ts`**: Canonical durable scan-ingestion boundary. Every
  current scan-producing route uses its strict `begin_scan_ingestion` client to
  establish the job and sanitized intent atomically before provider dispatch,
  and uses its finalization client for completion-last media verification. The
  module validates server-canonical UUIDs, SHA-256 values, stage, and completion
  outcome rather than trusting an untyped RPC response. `/check-scan-status`
  exposes the owner-safe job state when the scan row is not complete yet. Claims
  include expected media counts, staged object keys, recovered upload-session
  ids, and a normalized manifest checksum so retries, server replay, and repair
  work can detect accidental media-shape drift. Finalization delegates all
  promoted/deleted dispositions to one per-scan-locked database routine, which
  validates the complete claimed-key manifest, rebuilds ready canonical media,
  and marks the ledger complete last. Canonical video completeness follows
  structured captured media or the legacy standalone-image/playback/audio
  projection; sampled inference frames retained in compatibility image arrays
  are not standalone display rows. Migration
  `20260729012153_fix_video_scan_canonical_finalization.sql` aligns the database
  proof with that projection while retaining exact owner, kind, URL, and
  claimed-key checks. Current successful completion delegates to the user-first
  `complete_scan_ingestion_with_entitlement(...)` orchestrator, which invokes
  canonical media finalization, settles any credit, adds a versioned entitlement
  snapshot, and stores the enriched response. Terminal status delegates only to
  `fail_scan_ingestion_terminal(...)`; schema-cache or direct table fallbacks
  are forbidden because they could bypass hold release.
- **Compatibility success nuance**: `identify`, `identify-describe`, and
  `audio-spec` invoke that finalizer synchronously. Only a failure after the
  exact owner scan row has committed may degrade to a validated compatibility
  response with a `failed_retryable` ledger. A fresh provider-owning
  `identify-multimodal` invocation instead returns retryable 503 when
  finalization fails. Its later same-UUID retry may return a marked
  `reconstructed` replay from the exact owner row while canonical repair remains
  retryable, without another provider call. No producer may return success
  without exact-owner insertion.
- **Provider failure parity**: All four producers return stable
  `400 observation_rejected` for Gemini `SAFETY` or `PROHIBITED_CONTENT` and
  terminalize that policy outcome through the entitlement orchestrator.
  Malformed or structurally invalid provider output remains HTTP `503` and
  `failed_retryable` with a bounded `retry_after`; it retains the linked hold
  for same-UUID recovery rather than creating a contradictory terminal ledger.
- **`scanIngestionRetry.ts`**: Owns the deterministic 30-second ordinary
  `failed_retryable` deadline shared by `identify-multimodal` and the
  compatibility ingestion path used by `identify`, `identify-describe`, and
  `audio-spec`. Explicit server-directed retry values remain separate and may be
  longer; this helper changes no request/response shape or persisted schema.
- **`scanIngestionIntents.ts`**: Sanitized scan-ingestion replay intent helpers.
  `identify-multimodal` records telemetry, observation context, media
  descriptors (including validated still-image focus regions), staged object
  keys, upload-session ids, and payload checksums into `scan_ingestion_intents`
  without raw base64 media bytes or local device paths. Inline-media requests
  are marked non-resumable so `replay-scan-ingestion` and health checks know
  they still depend on the client queue. Server replay is capped at 10 claims
  per sanitized intent before the paired job is marked
  `failed_terminal / server_replay_limit_reached`.
- **`scanRecovery.ts`**: Bounded compatibility repair for an authenticated
  owner's missing `public.scans` row. It accepts no media URLs, validates UUIDs,
  ranges, enums, text, and privacy, derives owner/public coordinates
  server-side, and calls one atomic service-only RPC. That routine shares the
  ingestion claim's transaction-scoped advisory lock and writes the scan plus a
  completed recovery ledger in one transaction. Active/retryable richer
  ingestion is never preempted. Terminal recovery is limited to explicit
  `replay_exhausted`, or exact `media_reconciliation_abandoned` plus the
  matching composite dead-letter/quota/media-lifecycle proof. Current/later
  policy, unproven abandonment, and every other terminal reason remain closed.
  Restore signing obtains the same decision from a bounded service-only proof
  RPC; all exact failed/committed normal and replay reservations remain retained
  as chronological authority while that terminal job is unresolved.
  `check-scan-status` and `share-scan-to-explore` must reload by both scan and
  owner after calling it.
- **`audioProcessing.ts`**: Shared WAV container probe and complete
  decode/trim/resample/encode pipeline used by `audio-spec` and
  `identify-multimodal`. `isWavContainer(...)` is the cheap RIFF/WAVE gate;
  `processWAV(...)` remains the structural parser and normalization authority,
  so a matching extension or header prefix alone cannot establish valid audio.
- **`external.ts`**: Wikipedia and GBIF enrichment helpers used by identify,
  enrichment, species refresh, and dictionary paths. All returned reference
  image URLs pass through `externalImagePolicy.ts` before the enrichment object
  is returned. Provider requests use the shared 2.5-second deadline and parse
  JSON only within a 256 KiB streaming response ceiling.
- **`externalImagePolicy.ts`**: Exact third-party reference-media denylist. The
  current rule suppresses every resized/query variant below
  `inaturalist-open-data.s3.amazonaws.com/photos/605615444/` while leaving other
  iNaturalist and GBIF media untouched. Keep it aligned with the iOS
  `ExternalReferenceImagePolicy`; use a new cleanup/prevention migration for
  every added outlier.
- **`gemini.ts`**: Global `GoogleGenAI` client setup plus structured-output and
  JSON extraction helpers.
- **`biology.ts`**: Shared structured biological generation helpers retained for
  functions that still need text-only ecological generation. Externally
  reachable callers must pass the model selected by the database quota policy;
  service-only maintenance callers pass their reviewed system model explicitly.
- **`aiQuota.ts`**: Service-role client for the atomic `reserve_ai_quota(...)`
  and `finalize_ai_quota_reservation(...)` RPCs. It validates UUID idempotency
  keys, carries nullable original-analysis linkage, protocol, route-derived
  Flash-fallback eligibility, authenticated replay status, and nullable
  complimentary linkage. It uses `clientAddress.ts` with an optional dedicated
  override or built-in server-only Supabase key, maps fail-closed database
  errors to stable HTTP codes, and exposes a fenced provider lease. A route
  commits immediately before a provider attempt; provider failures remain
  charged but become retryable, and only a proven pre-provider no-op may refund.
  `403 ai_consent_required` is emitted by the consent prerequisite before a
  lease, entitlement hold, or provider counter exists. It is a disclosure
  transition—not quota exhaustion—and clients must not retry it automatically.
  `402 pro_required` and `429 ai_quota_daily_exceeded` retain the separate
  entitlement and daily-limit contracts.
- **`complimentaryScans.ts`**: Fail-closed classifier for Flash fallback. It
  accepts only nonnegative safe evidence counts and returns eligible only for
  exactly one user-supplied image, audio clip, or description and zero video.
  Context telemetry does not create another evidence item. Routes derive this
  value after parsing; clients do not authorize their own fallback.
- **`groupTagQuota.ts`**: Optional identification group-tag enrichment behind
  its own database-selected model and quota operation. Quota/provider failures
  are recorded without discarding the successful primary identification.
- **`entitlement.ts`**: Durable user-tier resolver for non-provider feature
  checks and telemetry. It calls the service-only user-aware resolver on every
  check; validates plan/tier, paid status, derived balances, in-flight count,
  and monotonic `entitlement_version`; and returns
  `503 ai_entitlement_unavailable` on a query error, missing row, or malformed
  relationship. It also owns the rollout read and dual-mode protocol-2-to-3
  `426` response. Edge isolate memory is never an entitlement authority.
- **`posthog.ts`**: Fail-closed, account-consent-gated PostHog HTTP capture
  helpers. Every capture resolves the provider-wide greatest `consent_revision`
  across all disclosure versions, denies any head revocation, and permits only a
  head grant carrying the current PostHog disclosure. The query must never
  pre-filter disclosure version before selecting the head. Its 2.5-second
  deadline prevents optional telemetry from consuming request-critical Edge
  wall-clock time. This server helper passing focused tests does not establish
  the separate iOS SDK lifecycle; the aggregate release remains held by the
  [production consent readiness record](../../../../docs/legal/production-consent-readiness-2026-08-03.md).
- **`subscriptionPass.ts`**: Exact product policy for the detached `pro_week`
  pass, including the 7-day duration. The webhook derives purchase time from
  authoritative CustomerInfo `non_subscriptions`, never directly from an event.
- **`explore.ts`**: Explore UUID/hashtag validation, public author identity
  sync, feed-card hashtag/pro-badge/username hydration, and shared
  social-surface helpers.
- **`publicSpeciesProjection.ts`**: Public species projection sanitizer that
  prevents private scan/user fields from leaking into dictionary and Explore
  responses. It also filters exact denied external media from normalized rows,
  legacy comma-separated caches, and first-image projections without changing
  the public DTO shape.
- **`speciesContentProvenance.ts`**: Provenance mapping for scheduled species
  content refresh outputs.
- **`taxonomy.ts`**: Taxonomic normalization helpers and test-backed taxonomy
  transformations.
- **`scanIngestionCompatibility.ts`**: Compatibility ledger for scan-producing
  legacy endpoints. `/identify`, `/identify-describe`, and `/audio-spec` record
  `scan_ingestion_jobs` plus multimodal-shaped sanitized
  `scan_ingestion_intents` in one transaction before provider work. Atomic setup
  failure fails closed and refunds unused provider quota in the route. Staged
  media and text-only intents can be replayed through `replay-scan-ingestion`;
  inline base64 media is redacted and marked non-resumable. Compatibility
  completion delegates to the user-first entitlement completion orchestrator,
  cannot issue a direct complete update, and turns finalization failure into
  durable retryable work. Proven setup or terminal failure calls the terminal
  orchestrator to release a hold; a settlement error propagates so an ambiguous
  outcome remains held rather than being silently terminalized.

The normative complimentary ledger and settlement contract is
[`docs/backend-and-data/18-complimentary-pro-scans.md`](../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

## Identify Subdomain

`_shared/identify/` is the shared inference stack used by `identify`,
`identify-multimodal`, `identify-describe`, and `audio-spec` where behavior is
identical:

- **`clientPayload.ts`**: Cache-hit payload hydration shared by identify
  endpoints.
- **`context.ts`**: Telemetry context normalization, month/time handling, and
  ecological field clamping.
- **`audioSubjectPolicy.ts`**: Shared audio-only subject precedence, prompt
  fragments, private-provider discriminator normalization, and public-field
  canonicalization for `identify-multimodal` and `audio-spec`. Non-human animals
  outrank Human; Human canonicalizes to `Human` / `Homo sapiens`; confidently
  present but unresolved wildlife stays biological; and recordings without a
  confident biological source normalize to `No Wildlife Detected`. The helper
  consumes and removes `audio_subject_type` and never classifies from model
  reasoning. A resolved non-human taxon keeps its normal candidates; if its
  common name is missing, unresolved, or incorrectly Human, the scientific name
  becomes the safe display fallback without changing the non-human decision.
- **`db.ts`**: Scan insert/update helpers, species cache writes, and shared
  database boundaries. Duplicate-safe scan creation is followed by owner-scoped
  read-back so a no-op or cross-owner collision cannot resolve as success.
  Before provider work, all producers also call the service-only
  `ensure_scan_user_profile` prerequisite through this module; it derives a
  valid profile from the exact Auth identity and refuses merge, deletion, and
  cleanup races.
- **`completedResponse.ts`**: Owner-scoped Identify response replay for all four
  scan-producing routes. It validates immutable stored envelopes, reconstructs
  exact durable owner rows through the executable wire contract—including rows
  whose canonical ledger is still finalizing or retryable—and boundedly
  coalesces concurrent AI-quota ownership so at-least-once delivery returns HTTP
  success without a second provider call.
- **`latencyDb.ts`**: Thin service-role RPC client for combined
  primary/candidate dictionary hydration (`hydrate_identification_dictionary`).
  Atomic ingestion setup belongs to `scanIngestionJobs.ts`, not this
  identify-specific subdomain.
- **`media.ts`**: Image/audio media resolution from inline payloads and R2
  staging keys. `parseAudioTransport(...)` validates array shape, nonempty
  members, and mutual exclusion of inline and staged audio before any `.length`
  read, decode, or object-key lookup. Inline bytes are authoritative: a legacy
  destination hint accompanying inline image or audio bytes is validated for
  traversal but excluded from the staged source manifest, ownership checks,
  promotion, deletion, and strict finalization.
- **`moderation.ts`**: Gemini safety evaluation, abuse strikes, and safe media
  promotion. Copy/upload responses and subsequent staging deletion are checked
  explicitly; a non-2xx/non-404 deletion fails promotion and triggers strict
  public-object rollback.
- **`contract.ts`**: Dependency-free executable model and final wire contract.
  It generates provider schemas, infers TypeScript payloads, validates runtime
  values recursively, and supplies Swift DTO generation metadata.
- **`googleSchema.ts`**: Typed adapter from the provider-neutral projection into
  the pinned `@google/genai` `Schema`; SDK field-shape changes fail compilation
  without loading SDK runtime code into contract tooling.
- **`schema.ts`**: Vision prompt plus cached Gemini schemas generated from
  `contract.ts` through `googleSchema.ts`, including the shared provider-private
  audio variant used by both audio-only routes. `/identify` and image-only
  `/identify-multimodal` receive the whole-frame visual primary-subject
  guidance; the blended image+audio instruction does not currently include the
  complete policy. A client saliency region is only a tentative hint. Contract
  parsing validates response structure and the processed-material normalizer
  demotes manufactured/processed objects, but neither independently detects
  incidental background biology. The base `is_biological_subject` description is
  also inherited by Describe, so its current visual-only wording remains a known
  cross-modality semantic gap.
- **`thresholds.ts`**: Tier-specific confidence thresholds mirrored by
  `MerianConfig`.
- **`types.ts`**: Shared request/database types plus model and client payload
  aliases inferred from `contract.ts`.
