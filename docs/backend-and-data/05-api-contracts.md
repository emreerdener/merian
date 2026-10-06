# API Contracts and Network Mappings

> **Beta policy update — September 18, 2026:** The owner authorized the existing
> beta backend rollout under the
> [Field Chat beta release decision](../release-evidence/field-chat-beta-release-decision-2026-09-18.md).
> `species_dictionary_chat_production_hold` is inactive by explicit exception,
> not because every full-release criterion passed. Statements below requiring
> all external/device/hosted-token evidence before backend rollout describe the
> full-release policy; that evidence remains open. Exact-SHA backend validation,
> live repository controls, runtime security/consent, and audited cutover
> activation remain required. This exception does not authorize iOS
> distribution.

Naturebook operates through a decoupled backend. The iOS application exclusively
hits Supabase Edge Functions, abstracting its networking away from 3rd-party
providers like Google Gemini.

The normative end-to-end success, retry, recovery, security, and rollout
contract for Capture → Identify → Insight → Field Chat / Explore is
[Scan Ingestion Reliability and Recovery](./16-scan-ingestion-reliability-and-recovery.md).
The sections below remain authoritative for individual request and response
shapes.

## Fleet-Wide JSON Ingress and Error Contract

Every production Deno endpoint reads JSON through bounded primitives in
`services/supabase/functions/_shared/http.ts`. Most routes use
`parseJsonBody(...)`; signed webhooks use the same module's exact raw-byte
reader, and reviewed media adapters delegate to its bounded JSON reader. The
ordinary object reader:

- accepts `application/json` and `application/*+json` only;
- rejects malformed, negative, non-decimal, or conflicting `Content-Length`
  values;
- compares the declared size with the actual streamed size;
- cancels the stream before retaining a chunk that would cross the limit;
- coalesces accepted chunks into a geometrically growing bounded buffer so
  allocation stays proportional to byte count rather than transport chunk count;
- rejects invalid UTF-8 and malformed JSON; and
- requires a JSON object unless the endpoint explicitly documents another shape.

Routes use the smallest endpoint class that can contain a valid request:

| Class      | Maximum body | Intended payload                     |
| ---------- | -----------: | ------------------------------------ |
| `small`    |       16 KiB | scalar IDs, actions, and preferences |
| `standard` |       64 KiB | ordinary structured API requests     |
| `bulk`     |        1 MiB | explicitly bounded batches           |

Media endpoints may use a reviewed larger ceiling through
`_shared/mediaBudgets.ts`; they still use the same streaming reader. Bodies are
uncompressed JSON. These byte limits are an allocation boundary, not a schema
validator: each endpoint must continue to validate field types, string lengths,
array counts, UUIDs, and ownership.

Parser failures use stable public codes:

| HTTP | Code                                                               |
| ---: | ------------------------------------------------------------------ |
|  400 | `invalid_content_length`, `invalid_json`, or `invalid_json_object` |
|  413 | `payload_too_large`                                                |
|  415 | `unsupported_media_type`                                           |

Authenticated routes use the shared handler's two stable `401` codes:
`auth_session_missing` when no live Auth session backs the credential and
`invalid_session_token` for other invalid or expired user credentials. The
first-party iOS client attempts one SDK session refresh for either code and
rebuilds the original request with the rotated access token before considering
account-specific recovery. It must not replace an anonymous identity merely
because an expired access JWT was rejected while its refresh token remains
valid. The rejected handler request has not crossed the endpoint's domain
mutation boundary, so the one refresh replay is safe.

On iOS, `AuthenticatedRequestExecutor` owns bounded replay selection and
`AuthSessionRecoveryCoordinator` owns the task-free Auth transition sequence.
The coordinator captures the exact expected session before quiescing account
work and repeats the expected/current-session check afterward, alongside
cancellation, transition ownership, SDK identity, purchase readiness,
entitlement, and final SDK readback around the refresh and anonymous-replacement
suspension points. Terminal clear returns a typed completed, rejected, or
purchase-handoff-blocked outcome. It rejects cancellation, context drift, and
pending handoff evidence before mutation; after SDK sign-out begins, it invokes
the remaining local and purchase-identity cleanup even if the SDK call fails or
cancellation arrives. A blocked Apple credential clear retains its signal
without a hot retry loop and resumes when the aggregate purchase-handoff fence
becomes false. Live Supabase, RevenueCat, Keychain, analytics, and logging
adapters remain assembled by `SupabaseManager`; the task-free
`SupabaseAuthSessionService` centralizes request-scoped OAuth, recovery, and
local-sign-out SDK adaptation, while its `+Live` companion alone performs those
Auth calls. The recovery coordinator owns terminal local-clear sequencing. The
separate `AuthLocalSignOutCoordinator` owns ordinary and account-cleanup task
lifetime and sequencing. This ownership split changes no HTTP status, public
code, payload, or retry count.

Provider-backed routes additionally return HTTP `403` with code
`ai_consent_required` when the authenticated account lacks the current 18+
self-attestation, lacks the current Terms receipt, lacks the current Google
Gemini grant, or resolves a revoked all-version provider head at the greatest
accepted consent revision. The head is selected before disclosure compatibility,
so a withdrawal created under an older disclosure cannot be hidden by a prior
current-version grant. During the bounded replacement build window the server
accepts only an explicitly allowlisted complete beta bundle; after owner-only
strict cutover, only adult policy `2026-08-03`, Terms `2026-08-03`, and Gemini
disclosure `2026-08-04.1` pass. This failure occurs at the common database quota
boundary before provider dispatch; clients must return the user to the
disclosure screen rather than retrying the same request in a loop.

The `reserve_ai_quota` name does not classify its failures. Its consent helper
runs before entitlement selection and provider-counter reservation, so this
`403` does not mean the account has no scans left and must not consume an
included Pro scan or daily Flash allowance. Provider-admission failures remain
distinct:

| HTTP | Code                                  | Meaning and required client behavior                                                                                                                                                                                                                                                                                                    |
| ---: | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  403 | `ai_consent_required`                 | Disclosure-policy transition. Preserve queued media, stop automatic inference retry, and require fresh authoritative consent.                                                                                                                                                                                                           |
|  403 | `ai_openai_consent_required`          | Legacy OpenAI permission denial. During beta, preserve the scan and funding in needs-attention and offer an explicit eligible online retry without permission UI. Current beta admission does not emit this denial. Retain compatibility decoding; do not reopen Gemini onboarding, select another provider, or automatically resubmit. |
|  409 | `ai_identification_preflight_changed` | The app-assigned recipient changed after the client's check. Preserve the observation and rerun preflight; do not blindly retry, grant permission, or select another provider.                                                                                                                                                          |
|  400 | `ai_identification_preflight_invalid` | The recipient expectation header is invalid. Stop inference and correct the request; do not retry through an older admission path.                                                                                                                                                                                                      |
|  402 | `pro_required`                        | The requested capability has no valid paid/included/fallback entitlement. Present the existing upgrade path.                                                                                                                                                                                                                            |
|  429 | `ai_quota_daily_exceeded`             | The applicable daily provider allowance is exhausted. Preserve the queued retry and honor `Retry-After`; live Capture replaces Insight with the existing paywall instead of synthesizing a result placeholder. Do not route to consent.                                                                                                 |
|  429 | `ai_user_rate_limit_exceeded`         | Temporary per-user request-rate protection. Use bounded retry.                                                                                                                                                                                                                                                                          |
|  429 | `ai_ip_rate_limit_exceeded`           | Temporary per-network request-rate protection. Use bounded retry.                                                                                                                                                                                                                                                                       |

### Scan admission preview RPC

Before Capture starts camera/audio hardware or submits staged evidence, an
online authenticated client calls
`get_my_scan_admission_preview(p_flash_fallback_eligible boolean)`. The RPC has
no user-ID input and derives the account from `auth.uid()`. It returns exactly
one row. The current iOS caller uses `IdentificationEvidenceAllowance`: one
non-video photo or standalone audio item plus at most one note, or one
description alone, is eligible. Additional physical media, multiple
descriptions, video-derived evidence, and refinement pass false. This preserves
the Free fallback when Pro funding is exhausted without changing funding
precedence or quota limits.

| Field             | Type              | Meaning                                                                                  |
| ----------------- | ----------------- | ---------------------------------------------------------------------------------------- |
| `decision`        | text              | `allowed`, `daily_quota_exhausted`, or `pro_required`                                    |
| `effective_plan`  | text              | Prospective `pro_paid`, `pro_trial`, `pro_complimentary`, or `free` plan                 |
| `daily_limit`     | integer, nullable | Applicable UTC-day limit, or null for an unlimited plan/no applicable policy             |
| `daily_remaining` | integer, nullable | Non-negative remaining allowance after existing usage; zero accompanies daily exhaustion |

This endpoint is an advisory, read-only UX preflight: it does not reserve a
complimentary credit, increment a counter, or authorize provider dispatch. The
client opens the existing paywall and preserves staged input for either denial.
`reserve_ai_quota(...)` remains authoritative, and a later exact
`ai_quota_daily_exceeded` caused by a concurrent device or request must use the
same paywall fallback.

For image imports, `requestPhotoPickerEntryAdmission` previews the minimum
one-photo addition before opening the native picker, independently of its
maximum selection count. Pending shared text counts as the optional note. After
selection, a synchronously registered draft operation checks the actual selected
count before file loading/preparation. An external Photos/Files receipt previews
its one-photo addition before metadata extraction or decoding. A known denial
preserves the draft/receipt. A response from a discarded draft generation cannot
present a paywall or error on its successor. Final submission rechecks because
the preview is non-reserving; concurrent account/quota changes can still deny
that boundary. See the
[capture lifecycle](../features-and-hardware/29-staged-capture-review.md) and
[funding contract](./18-complimentary-pro-scans.md). No new wire field is
introduced for the note.

Before acquiring an account-work lease, iOS waits for eligible first-launch Auth
session setup through the existing single-flight bootstrap coordinator. Ordinary
bootstrap does not await purchase linking; paid readiness remains a separate
fail-closed boundary. This joins background warmup or retries a failed anonymous
setup. Prior OAuth recovery, purchase handoff, deletion, and other Auth
transitions remain blocked; cancelled or identity-changed attempts cannot
dispatch. The caller waits at most five seconds and returns promptly on
cancellation without cancelling shared bootstrap work. This bound is separate
from the RPC deadline below.

The iOS preflight uses an exact-route bridge over the shared certificate-pinned
Supabase session. It admits only the configured
`POST /rest/v1/rpc/get_my_scan_admission_preview` request with a nonempty bearer
credential and nonempty `apikey` header. The request has a two-second request
and wall-clock deadline, `waitsForConnectivity = false`, no URL cache, and no
PostgREST retry. A valid row is the only online admission proof. A classified
URL transport failure such as no route, DNS/host failure, connection loss, or
timeout may consult the current local entitlement meter only to choose a
**queue-only** route: Capture may preserve the observation in the durable queue,
but it must not create a foreground inference generation or dispatch Identify.
The authoritative reservation is therefore deferred to queue replay.

This narrow fallback does not turn arbitrary preflight failures into offline
work. Cancellation, authentication/TLS failure, server response failure,
malformed or missing rows, and unsupported decisions remain fail-closed with
retry feedback. A valid `daily_quota_exhausted` or `pro_required` response still
opens the paywall. Known-offline Capture follows the same local-meter,
queue-only rule without attempting the RPC.

Release order is database first, iOS second. The iOS client intentionally blocks
online processing with retry feedback when this RPC is unavailable for any
reason other than a classified URL transport failure, so shipping the caller
before migration `20260809155517` would stop online scans rather than bypass
admission.

Before constructing a first Identify request for a newly onboarded account, an
iOS client must push pending adult, Terms, and Gemini evidence and verify a
fresh read of those same account rows plus the provider-wide Gemini head. Local
onboarding completion and persisted `syncedUserId` values are not API
authorization. The failure and release proof are documented in the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md).

Receipt insertion is complete only after an ID- and owner-scoped read-back
matches every immutable field sent by the client and includes a server
timestamp. The same exact match is required before a row can confirm an
ambiguous insert; a mismatched row preserves the original transport failure.
Across receipt, current-event, and provider-head reads, only an empty successful
result is authoritative absence. A present row with an unsupported enum or
invalid timestamp is `MerianError.invalidResponse` and keeps required-consent
restoration fail-closed.

## Causal Consent Append RPC Contract

The iOS client appends mutable provider permission only through these
authenticated PostgREST RPCs:

- `append_user_ai_consent_event(...)`, fixed to the caller's `google_gemini`
  stream;
- `append_user_openai_consent_event(...)`, fixed to the caller's independent
  `openai` stream (collection implemented but disabled in shipped source);
- `append_user_analytics_consent_event(...)`, fixed to the caller's `posthog`
  stream.

All three accept the same parameters: `p_id`, `p_disclosure_version`,
`p_event_kind`, `p_occurred_at`, `p_disclosure_text`, `p_action_text`,
`p_platform`, `p_app_version`, `p_app_build`, and the nullable
`p_causal_parent_id` observed when the local action was created. The caller
cannot supply a user ID, provider, server timestamp, or revision. Direct table
inserts and sequence access are denied.

Each call returns exactly one row with this shape:

```json
{
  "accepted": true,
  "event_revision": 42,
  "accepted_parent_id": "previous-event-uuid-or-null",
  "authoritative_revision": 42,
  "authoritative_event_id": "submitted-or-current-event-uuid",
  "recorded_at": "server-timestamp-or-null"
}
```

The RPC first locks the caller's `public.users` row against ghost-profile merge,
then takes a transaction-scoped advisory lock. Both AI recipients share the
account-level AI lock because their event IDs share one table; PostHog retains
its separate lock. Head lookup and causal comparison are always
recipient-specific. Under that lock:

- a grant is inserted only when `p_causal_parent_id` equals the current head;
- a stale grant returns `accepted = false`, no event revision or timestamp, and
  the authoritative head without inserting a row;
- a revocation is always accepted and stores the locked current head as
  `accepted_parent_id`, even when the caller observed an older parent; and
- an accepted event receives the server's monotonic `event_revision`.

The client must persist the returned accepted parent and revision. It retains a
rejected grant only as superseded local evidence. `occurred_at` and
`recorded_at` are audit evidence and never order provider authorization.

Reusing an event ID is idempotent only when its owner, provider and every
immutable payload field match. Concurrent same-account cross-provider reuse
returns the same controlled conflict as a sequential collision. A revocation
retry may repeat its originally observed parent because the stored parent can
have been rebased; any other mismatch raises `consent_event_id_conflict`
(`23505`). Missing authentication or an unavailable caller account fails with
`42501`. After an ambiguous transport failure, a fetched row is confirmation
only when its immutable payload matches the attempted event, with the same
revocation-parent exception.

On iOS, `Core/Security/Consent/Services/ConsentRemoteModels.swift` owns this
exact request/result shape and the selected-row projections.
`ConsentRemoteService.swift` owns result validation, fixed-recipient dispatch,
and immutable-payload retry confirmation; `ConsentRemoteMapping.swift` owns pure
row mapping, exact payload comparison and timestamp conversion;
`ConsentRemoteService+Live.swift` is the sole direct PostgREST/RPC adapter.
`ConsentSynchronizationCoordinator` supplies the runtime-wired observed-account,
SDK-session, cancellation, and generation fence across every suspended service
phase; it sequences pending evidence before the authoritative read and persists
a merged result before notifying the observable facade.
`ConsentCloudSessionCoordinator` separately owns ordinary and Auth-transition
session/account-work authorization around session adoption, scheduled
synchronization, inference admission, and Ghost rebinding. Its live adapter is
the only owner that resolves Supabase Auth and account-work leases for those
workflows. After suspended inference synchronization, the coordinator checks
cancellation, the original lease, and synchronization generation before
interpreting authoritative absence; a stale authorization context exits without
writing a reapproval marker. `ConsentSynchronizationMergePolicy` performs the
evidence upsert and authority derivation. `ConsentLedgerRepository` publishes
that result to local state only after a verified durable write.
`RequiredConsentRestorationCoordinator` owns the account- and generation-fenced
restoration state and UUID-keyed retry lifetime, retains canceled handles
through completion, independently rejects canceled retry callers after manual
attempt-number reuse, and contributes the handles to Auth-transition draining;
it has no wire or Supabase dependency. `ConsentManagerRuntime` composes these
owners and wires narrow callbacks; `ConsentManager` remains the sole observable
compatibility and SDK facade. `ConsentRealtimeCoordinator` owns the analytics
channel/listener/retry lifecycle and retains started removals through exact
completion for the Auth-transition drain. Its
`ConsentRealtimeCoordinator+Live.swift` is the only direct analytics-consent
Supabase Realtime adapter. The runtime supplies the manager-backed
current-account callback, and the facade retains lifecycle triggers. The
owner-filtered INSERT stream requests an authoritative refetch; it is not an
alternate append path. Explicit stop, listener completion, and coordinator
deinitialization converge on one coalesced channel-removal operation, with
deinitialization initiating cleanup independently of listener cancellation. Auth
replacement cannot install another SDK session until the prior channel's
retained removal completes.

The schema, rollout, concurrency, and release-evidence requirements are defined
in the [database schema](./04-database-schema.md),
[Supabase deployment runbook](./06-supabase-deployment-runbook.md), and
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

Edge errors return:

```json
{
  "error": "A stable caller-safe message",
  "code": "stable_machine_code",
  "request_id": "server-generated-uuid"
}
```

`X-Request-ID` carries the same UUID and is exposed through CORS. The server
does not trust an inbound request-ID header. Every wrapped response also carries
the fixed, non-secret `X-Merian-Handler: 1` marker. This marker is diagnostic
metadata for distinguishing a handler response from a gateway/router response;
it is never authorization evidence. Authenticated routes use `withEdgeHandler`;
custom-auth, webhook, and intentionally public routes use `serveEdge`. Expected
thrown failures use `PublicHttpError`, while explicit safe response failures use
`publicErrorResponse(...)`. Retained returned `4xx` contracts must contain only
audited validation or caller-state data; the boundary validates/adds their
stable code and request ID. An arbitrary exception is logged privately and
becomes `500 internal_error`; an ordinary returned `5xx` keeps its status but
receives the generic status-derived code/message. Retryable public failures may
additionally include `retry_after_seconds` and a bounded `Retry-After` header.

The Next.js waitlist API uses the equivalent web envelope with `message` in
place of `error`. Its 4 KiB request ceiling, CAPTCHA, database rate limits, and
service-only pre-challenge and insertion RPCs are documented in the web README
and deployment runbook. The distributed IP claim runs before Turnstile; the
tighter verified-attempt and global-growth transaction runs only after a valid
challenge.

### Independent OpenAI consent evidence

Migration `20260926150509_add_independent_openai_consent_stream.sql` must
precede any client collecting OpenAI consent. The iOS live adapter dispatches
known `google_gemini` and `openai` events to their fixed-recipient RPCs and
rejects an unknown provider or mismatched owner before network work. Its seven
authoritative reads include a separate owner-scoped, all-version OpenAI stream
head. The existing ID-scoped AI read-back verifies provider as well as the
entire immutable payload. No Identify DTO or client-selected provider field is
added.

`internal.require_current_ai_consent(uuid,text)` accepts OpenAI evidence only
when its latest provider-wide event is a grant for disclosure `2026-09-26` and
current adult policy and Terms receipts both exist for `2026-08-03`. Missing,
revoked, old or unknown-version heads deny; Gemini permission and its legacy
rollout mode confer no OpenAI permission. The gate uses the version as the
policy identifier. Supplied disclosure/action text remains immutable client
evidence, not server verification of a screen presentation. A material policy
change must update the client version and server gate together and require a
fresh action.

The optional Settings coordinator is not inference authorization. Required
onboarding, `ensureCloudConsentForInference`, `ai_consent_required` recovery and
legacy quota callers still require ordinary Gemini consent. Identification
checks its database-selected recipient after a processor-neutral private quota
core. The beta catalog assigns only `scan_identification` /
`multimodal_photo_v1` to OpenAI; other profiles retain Gemini. Naturebook
controls provider assignment; beta users are not offered OpenAI permission
controls.

Migration `20260926182547_add_identification_recipient_recovery.sql` adds the
private `internal.require_identification_processor_consent(uuid,text)` wrapper
to both identification RPC overloads, for fresh assignments and saved attempts.
The beta correction migration `20260928183305` keeps ordinary required-consent
checks for both recipients and defers all OpenAI-specific enforcement. Absent,
granted, revoked, and older-version OpenAI histories are equally eligible during
beta; admission never reads or rewrites them. Ordinary required-consent denial
retains `ai_consent_required`. The strict receipt validator and immutable
evidence remain unchanged; beta eligibility is never a grant. Unknown recipients
or a missing account raise `ai_provider_assignment_unavailable`, mapped to
service unavailability, rather than asking for permission to an unknown
recipient. Both known consent errors are matched exactly at the Edge boundary,
retain the existing public error envelope, and occur before dispatch. The
transaction rolls back its quota and complimentary holds on denial. No
client-selected recipient field is added.

On iOS, only `403 ai_consent_required` opens required Gemini reapproval. Exact
`403 ai_openai_consent_required` becomes `MerianError.openAIConsentRequired`:
foreground and background recovery retain the original scan, media and local
funding as needs-attention with the new stable code. A successful durable pause
has no retry deadline; Gemini completion cannot resume that row. Foreground
recovery transfers the current scan/attempt/generation to the queue's retirement
owner, which saves the pause before releasing uploads or durable ownership. A
local save failure retries only persistence with capped backoff while that
generation remains claimed and retired. It cannot restart provider dispatch; a
later generic cleanup cannot replace this policy. Unknown codes and other HTTP
statuses do not gain consent semantics. A late or superseded completion cannot
pause a replacement attempt.

OpenAI-specific collection is disabled throughout beta, including Settings and
saved-scan permission sheets. A legacy `ai_openai_consent_required` row displays
a generic saved/paused message. It offers **Retry now** only for an online,
retryable scan whose retained dispatchable funding belongs to the current
observed/SDK account and scan outside a transition. Durable retry repeats those
ownership checks before changing state, then uses ordinary consent
synchronization and fresh recipient preflight. No policy change, navigation, or
receipt update automatically submits a provider request.

Before enabling consent for a public release, every permission-required alert
must offer a direct **Review permission** action to the applicable disclosure.
After review, return to the same saved scan and offer a separate eligible retry;
cancellation or withdrawal must preserve it. Restore native collection, native
enforcement, and backend enforcement together under a reviewed release. The
current beta does not implement or claim that future UX.

The enabled production composition and beta catalog activation select the exact
`openai_photo_v1` / `gpt-6-sol` tuple for still photos with minimum
identification protocol 4, accepting readers 4 and 5. Audio, video snapshots,
mixed photo/audio, text-only and legacy profiles retain Gemini.
`ConsentPolicy.openAIBetaAccessEnabled` mirrors backend beta eligibility;
`canProcessOpenAI` retains the current-account fence while `hasGrantedOpenAI`
remains a truthful receipt projection. The ordinary required consent gate still
handles uncertain consent storage. OpenAI collection actions are disabled even
if the independent collection flag is accidentally enabled. Older app binaries
retain their own local checks until updated. Distribution and full
production-profile qualification are separately tracked; beta activation does
not claim either. See the
[photo rollout](../rfcs/identification-openai-photo-rollout-2026-09-28.md).

## Fleet-Wide Outbound Provider Contract

Production Edge modules use `services/supabase/functions/_shared/outbound.ts`
rather than invoking global or injected fetch transports. Every outbound
provider call carries a hard deadline that is combined with caller cancellation.
Text and JSON responses are streamed through endpoint-specific byte ceilings
before decoding or parsing. Signed R2 requests are the only direct
client-transport calls; CI enumerates those adapter modules and verifies each
call receives a deadline-bound `Request`.

Telemetry follows the same rule even though it is best-effort. PostHog rejects
non-UUID system identities before any consent lookup or capture request. For an
account UUID, capture first resolves the account/provider greatest
`consent_revision` without a disclosure-version filter. A missing head or head
revocation fails closed; only a head grant carrying the current analytics
disclosure permits delivery. A permitted capture has a 2.5-second deadline. A
timeout or provider diagnostic is logged privately and does not become a raw
public API error.

The local identification evaluator can separately compose the OpenAI photo/text
adapter. It uses the same bounded transport and outcome interface but creates no
production authority, consent receipt, quota reservation or public DTO. Its
[provider evaluation contract](../development-guides/22-alternative-identification-provider.md)
is versioned separately from these HTTP contracts. All production identification
and enrichment routes retain Gemini admission and composition.

## Deno `/field-trips` Edge Node

`/field-trips` is an action-based Explore-adjacent social endpoint. It is
authenticated through `withEdgeHandler`; request bodies cannot choose `self_id`
or otherwise assign progress to another user.

All public-schema Field trip/Event `SECURITY DEFINER` functions are Edge-owned.
Execute is revoked from `PUBLIC`, `anon`, and `authenticated` and granted only
to `service_role`; there is no intentionally direct client RPC in this feature.
The `internal.auto_enroll_backyard_safari_level_one()` trigger function is not
an RPC: execution is also revoked from `service_role`, and it runs only from the
database-owned `public.users` insert trigger.

`services/supabase/functions/field-trips/actions.ts` is the canonical action
allowlist. A missing/non-string or unknown action returns `HTTP 400`. Unknown
strings emit `field_trip_action_rejected` with the value truncated to 64
characters so operators can distinguish a stale client from an incomplete Edge
deployment without logging the request body or user identity.

### Catalog

Request:

```json
{
  "action": "catalog",
  "user_region": "us-ca",
  "limit": 40
}
```

Response:

```json
{
  "data": [
    {
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "subtitle": "Observe local species often found in your own backyard.",
      "description": "A starter checklist for neighborhood discoveries.",
      "cover_image_url": "https://...",
      "estimated_duration_minutes": 30,
      "guide_where_to_look": "Look near flowers, fences, planters, and quiet corners.",
      "guide_why_it_matters": null,
      "guide_safety_ethics": "Stay where you have permission and avoid handling animals.",
      "region_tags": ["global"],
      "season_tags": ["all"],
      "habitat_tags": ["neighborhood"],
      "difficulty": "starter",
      "is_pro_only": false,
      "is_rotating_free": true,
      "viewer_has_access": true,
      "access_kind": "starter",
      "active_progress": {
        "user_field_trip_id": "uuid",
        "started_at": "2026-07-08T12:00:00.000Z",
        "current_level_number": 1,
        "completed_at": null,
        "is_profile_visible": true,
        "completed_count": 1,
        "target_count": 2
      },
      "stopped_progress": null,
      "levels": [
        {
          "level_id": "uuid",
          "level_number": 1,
          "title": "Level 1",
          "description": "Start close to home.",
          "items": [
            {
              "item_id": "uuid",
              "prompt": "Bird",
              "match_type": "taxonomy",
              "guide_tip": "Pause and listen before moving closer.",
              "is_completed": true,
              "completed_at": "2026-07-08T12:05:00.000Z",
              "completed_scan_id": "saved-scan-uuid",
              "completed_common_name": "Northern Cardinal",
              "completed_scientific_name": "Cardinalis cardinalis"
            },
            {
              "item_id": "uuid",
              "prompt": "Dog",
              "match_type": "scientific_name",
              "guide_tip": "Dogs count when they are clearly visible and safely observed.",
              "is_completed": false,
              "completed_at": null,
              "completed_scan_id": null,
              "completed_common_name": null,
              "completed_scientific_name": null
            }
          ]
        }
      ]
    }
  ]
}
```

Free users receive starter and rotating-free trips plus locked Pro templates for
upgrade display. Pro users receive the full active catalog. The backend owns
access decisions; iOS uses `viewer_has_access` and `access_kind` only for UI
state.

`completed_scan_id` is a private, viewer-specific link to the exact
`user_field_trip_item_completions.scan_id` that satisfied the item. It is
non-null only for completed standard-outing items; incomplete items return the
key as `null`. The response deliberately does not add a media URL: iOS resolves
the ID against the caller's device-local scan library and renders the normal
photo or video-poster thumbnail. If that record is unavailable locally, clients
retain the curated placeholder. Completion count or array position must never be
used to infer which checklist items are complete.

The catalog and template-detail RPCs are revoked from `PUBLIC`, `anon`, and
`authenticated` and granted only to `service_role`. The authenticated
`/field-trips` action supplies the verified `user.id`; a client cannot call the
RPC directly or request another user's evidence. `completed_scan_id` is not
projected into public profile summaries, publication or challenge snapshots,
Explore feed/map contracts, or capture context.

`template_detail` additionally projects `publication_id` and `published_at`
inside `active_progress` when the caller owns an active, non-deleted Field trip
publication for that outing. Missing/null values mean the outing has no current
public snapshot and the client renders **Private**; a non-null publication ID
renders **Published**. Completion alone must not imply publication. These fields
are detail-only private viewer metadata and are not added to catalog, capture
context, public profile, or Explore-post projections.

An unfinished stopped outing has `active_progress: null` and an optional
`stopped_progress` object with the same saved checklist counts plus
`stopped_at`. Its `levels` include the saved completion state. Clients use
active-or-stopped viewer progress for catalog status, filters, and detail cards,
but active-only surfaces such as Capture and public active summaries continue to
read only active progress.

### Template Detail, Start, and Resume

Template detail request:

```json
{
  "action": "template_detail",
  "template_id": "uuid"
}
```

`slug` may be sent instead of `template_id`. The response is one catalog-shaped
template object with guide fields, levels, item tips, access state, viewer
progress, and the same optional private `completed_scan_id` for completed
standard-outing items. Each currently curated goal can also include a
`reference_species` object used only by the standard outing Goals hero:

```json
{
  "reference_species": {
    "scientific_name": "Passer domesticus",
    "common_name": "House Sparrow",
    "reference_images": [
      {
        "url": "https://...",
        "source": "merian",
        "license": null,
        "attribution": null,
        "width": 1200,
        "height": 800
      },
      {
        "url": "https://...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Photographer",
        "width": 1200,
        "height": 800
      },
      {
        "url": "https://...",
        "source": "gbif",
        "license": "CC BY 4.0",
        "attribution": "Dataset contributor",
        "width": 1200,
        "height": 800
      }
    ]
  }
}
```

The Edge layer maps broad goals to a reviewed illustrative species without
changing the database matching rule, batches the corresponding
`species_dictionary` and `species_reference_images` reads, and returns at most
one sanitized image per source in `merian` (displayed as Naturebook), Wikipedia,
then GBIF order. If the normalized cache has no usable candidate for a
current-level goal, the same database layer uses the shared external enrichment
helper to obtain public Wikipedia/GBIF candidates. This fallback is capped at
six active goals, runs at most three provider lookups concurrently, inherits the
shared 2.5-second request deadline and 256 KiB JSON response ceiling, and fails
open to the otherwise valid template detail. The iOS client treats the resulting
source order as a load-failure waterfall. A completed goal's private local scan
visual replaces its reference inside the same stable goal slot; the API still
never constructs or returns a private evidence URL. `reference_species` is
absent from catalog, capture context, Events, public profiles,
publication/challenge snapshots, and Explore payloads. Start, stop, reset, and
resume responses use this same detail shape.

For template detail only, a published outing's progress includes:

```json
{
  "active_progress": {
    "publication_id": "publication-uuid",
    "published_at": "2026-07-08T13:00:00.000Z"
  }
}
```

Start request:

```json
{
  "action": "start",
  "template_id": "uuid"
}
```

The start action is idempotent for an existing trip. It creates or unhides the
caller's `user_field_trips` row for an accessible template and returns the
refreshed template detail. For a stopped outing it acts as Resume and opens a
new activity period. Matching scans never create or resume a standard outing,
including after Reset.

Lifecycle requests:

```json
{ "action": "stop", "user_field_trip_id": "uuid" }
{ "action": "reset", "user_field_trip_id": "uuid" }
```

Stop preserves standard checklist progress, closes the open activity period, and
removes the outing from Capture/profile active projections. Reset rejects
completed or published outings, clears only unfinished standard progress and
activity periods, and retains the shared outing row so Seasonal Challenge data
is not cascaded away. Both responses contain refreshed template detail and use
the verified Edge caller for ownership.

### Capture Context

Request:

```json
{
  "action": "capture_context"
}
```

Response:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "template_slug": "backyard_safari",
      "outing_title": "Backyard Safari",
      "last_engaged_at": "2026-07-17T18:00:00.000Z",
      "level_number": 1,
      "level_title": "Level 1",
      "completed_count": 1,
      "target_count": 2,
      "targets": [
        {
          "item_id": "uuid",
          "prompt": "Dog",
          "sort_order": 20,
          "has_guide": true
        }
      ]
    }
  ]
}
```

This is a narrow read model for the idle visual Scan surface. It returns only
active, incomplete, non-hidden standard Field trips that the caller can access.
For each field trip it returns unfinished targets from the current unlocked
level; completed targets and later levels are absent. Seasonal Challenge
participation, labels, and challenge-specific completions are not projected.
Joining a challenge reuses the underlying standard `user_field_trips` row, so
that standard field trip remains eligible and continues to show only its normal
Field Trip progress.

Every account receives an active Backyard Safari Level 1 row and activity period
when its `public.users` profile is created; the enrollment migration backfills
the same state for existing accounts. The activity window starts at enrollment,
so historical scans remain ineligible. Existing stopped, reset, and completed
Backyard Safari rows are never resumed by the backfill.

Stopped trips are deliberately absent. A reset Backyard Safari can qualify for
the unstarted introduction again; a stopped one cannot because its
`stopped_progress` proves it has saved viewer progress.

Field trips order by `last_engaged_at DESC`, where engagement is the later of
the trip start and any item completion. `user_field_trip_id` is the stable tie
breaker. Targets order by curated `(sort_order, item_id)`. Field trips with no
unfinished target are omitted, and an account with no eligible field trips
receives `{ "data": [] }`.

Privacy and authorization are deliberately stricter than the catalog contract:

- The request accepts no user identifier. `withEdgeHandler` verifies the caller,
  and the Edge action passes only `user.id` to the database helper.
- `public.get_field_trip_capture_context(uuid)` is `SECURITY INVOKER`, with an
  empty search path and fully qualified database objects. Execute access is
  revoked from `PUBLIC`, `anon`, and `authenticated`, then granted only to
  `service_role`. Its functional-entitlement predicate is the private
  `internal.user_has_effective_pro(uuid)` definer. The invoker therefore needs
  `EXECUTE` on that exact helper; migration
  `20260808215410_restore_field_trip_capture_entitlement_helper_access.sql`
  grants it only to `service_role` and keeps both direct client roles denied.
- The response contains no scan ID, media URL, location, field note, completed
  common/scientific name, or other evidence.

The iOS mapping is `MerianNetworkClient.shared.getFieldTripCaptureContext()`.
Capture treats the request as non-blocking enrichment: it may retain the last
successful account-scoped result and must not show a request error over the
camera.

### Scan Progress

Request:

```json
{
  "action": "apply_scan_progress",
  "scan_id": "saved-scan-uuid",
  "preferred_goal": {
    "user_field_trip_id": "uuid",
    "item_id": "uuid"
  }
}
```

Response:

```json
{
  "data": [
    {
      "user_field_trip_id": "uuid",
      "template_id": "uuid",
      "slug": "backyard_safari",
      "title": "Backyard Safari",
      "current_level_number": 2,
      "current_level_title": "Level 2",
      "completed_count": 1,
      "target_count": 4,
      "is_complete": false,
      "credited_level_number": 2,
      "credited_level_title": "Level 2",
      "credited_completed_count": 1,
      "credited_target_count": 4,
      "removed_item_ids": [],
      "newly_completed_items": [
        {
          "item_id": "uuid",
          "prompt": "Butterfly",
          "common_name": "Monarch",
          "scientific_name": "Danaus plexippus",
          "completed_at": "2026-07-08T12:07:00.000Z"
        }
      ]
    }
  ],
  "challenge_updates": [
    {
      "participation_id": "uuid",
      "challenge_id": "uuid",
      "slug": "summer_pollinator_watch",
      "title": "Summer Pollinator Watch",
      "current_level_number": 1,
      "current_level_title": "Level 1",
      "completed_count": 1,
      "target_count": 2,
      "is_complete": false,
      "badge_awarded_at": null,
      "suggested_hashtags": ["summerpollinators"],
      "credited_level_number": 1,
      "credited_level_title": "Level 1",
      "credited_completed_count": 1,
      "credited_target_count": 2,
      "removed_item_ids": [],
      "newly_completed_items": [
        {
          "item_id": "uuid",
          "prompt": "Butterfly or moth",
          "common_name": "Monarch",
          "scientific_name": "Danaus plexippus",
          "completed_at": "2026-07-08T12:07:00.000Z"
        }
      ]
    }
  ],
  "first_field_trip_achievement": null,
  "first_field_trip_achievement_newly_unlocked": false
}
```

The backing atomic RPC counts only scans owned by the caller, only after the
Field Trip starts, and only against the current unlocked level. Matching accepts
unreviewed AI identifications only at the inference tier's Possible-match
boundary (`Flash >= 0.75`, `Pro >= 0.65`). A weaker match remains uncredited
until the user confirms it or a correction/community resolution supplies a
confirmed species. Those paths use the same scan row and write the same
idempotent item completions. Eligibility is based on the saved biological scan,
not its capture modality, so qualifying photos and videos can count.
Upload/request time does not replace the scan timestamp, so a scan captured
inside a now-closed outing period or Event window can receive delayed first
credit. A single scan is evaluated against every matching current-level item in
every eligible active standard outing, but receives at most one credit per
outing and one per joined live challenge. It may still advance several eligible
active experiences, with every completion row pointing to the same scan.

The optional `preferred_goal` is accepted only for an owned standard outing that
was active at the scan timestamp and whose current visible item matches the
saved identification. It wins inside that outing only. Missing, stale,
unauthorized, completed, and nonmatching hints are ignored. Fallback selection
is exact species, scientific name, taxonomy from genus through kingdom,
including excluded-family and taxonomy-plus-signal variants, semantic tag,
ecology, habitat, curated checklist order, then item ID. A `taxonomy_and_signal`
goal requires at least one taxonomy constraint, at least one
ecology/habitat/semantic constraint, and every populated constraint to match.
The exact catalog is maintained in the
[Field Trips matching contract](../features-and-hardware/25-field-trips.md#active-objective-matching-contract).
Park Pollinators' **Bee or wasp** goal requires order `Hymenoptera` plus either
the `bee` or `wasp` semantic category, so ants, sawflies, and other
broader-order matches do not satisfy it. Compound semantic alternatives are
`|`-separated. Spider goals require order `Araneae`; animal and plant signal
goals also require their named kingdom.

For new scans, the identify ingestion intent stores the validated preference and
the scan-insert trigger invokes the same atomic RPC before scan persistence
commits. Standard progress, Event progress, preference persistence, first Field
trip achievement evaluation, and a private scan-revision receipt therefore
commit or roll back together. `apply_scan_progress` retrieves that receipt for
notification delivery. Relevant identification, confidence, inference-tier, or
explicit-confirmation changes create a new scan revision and re-evaluate
progress through the same transaction. Normal identification corrections only
move or remove credit while an experience is unfinished. Confidence,
inference-tier, or confirmation changes can also remove credit from a completed
experience when the scan becomes weak and unconfirmed, reopening its earliest
incomplete level.

V4 clients should continue reading `data` for normal Field trip progress and may
read `challenge_updates` for joined live challenge progress. Older clients can
ignore `challenge_updates`.

Both arrays add four backward-compatible credited-level fields:
`credited_level_number`, `credited_level_title`, `credited_completed_count`, and
`credited_target_count`. They describe the level that accepted this scan's newly
completed item. If the write finishes a level and advances immediately, the
existing `current_*`, `completed_count`, and `target_count` fields describe the
newly active level while `credited_*` retains the completed level and therefore
reports a full ring instead of the next level's `0/N`. During a staged
database/client rollout, iOS decodes these fields optionally and falls back to
the existing counts when they are absent. Credited counts and
`newly_completed_items` are scoped to completion rows inserted by the current
application attempt. If an older scan is re-identified after level advancement,
its historical completion rows cannot duplicate a destination or replace the new
level's ring.

Both update kinds may also include `removed_item_ids`. While an experience is
unfinished, an identification correction can move or remove this scan's credit
within its original credited level and reset progress to the earliest incomplete
level. Completed outings and challenges are immutable for normal identification
corrections; evidence-policy invalidation is the exception.

Migration `20260722195453_exclude_ants_from_bee_wasp_goal.sql` performs a
one-time repair for ant scans credited before that family exclusion existed. It
removes the standard/Event completion and its private preference/receipt,
reopens the earliest incomplete level, clears any derived Event badge, and
withdraws a now-invalid completion publication until an eligible scan completes
the goal. Migration `20260722211636_tighten_field_trip_goal_matching.sql`
applies the same repair policy to other active goals whose former taxonomy or
signal rule was broader than its label. Park's unverifiable **Spider near
flowers** and **Bird near flowers** prompts become **Spider** and **Bird**; the
former **Pollinator habitat** scene prompt becomes the verifiable
plant-plus-meadow **Meadow plant** goal. Migration
`20260730023042_gate_field_trip_progress_by_confidence.sql` removes standard and
Event credit backed by weak unreviewed identifications, reopens affected
progress, clears derived badges, and withdraws completion publications/entries.
It retains the private selected-goal preference and writes an empty durable
receipt so later confirmation can re-evaluate the pending scan. The same
reconciliation runs on future evidence downgrades, including after completion:
it removes standard/Event credit, reopens progress, clears the Event badge, and
soft-deletes invalid completion publications or entries. Its empty
`newly_completed_items` result cannot generate a completion toast.

Only updates with a nonempty `newly_completed_items` array are eligible for a
scan progress toast. Reapplying an unchanged scan is idempotent and returns its
stored receipt, including the original update payload; this lets a client that
terminated after ingestion recover the unlock notification. iOS acknowledges and
deletes its durable goal-hint outbox after consuming success/terminal state, and
separately deduplicates already released milestones by scan ID. A changed
identification revision replaces the receipt with its correction result.
`preferred_goal` is an optional additive request field. Older clients omit it
and receive the deterministic fallback. The response remains backward-
compatible because credited and removed-item fields decode optionally.

### Scan Contributions

Request:

```json
{ "action": "scan_contributions", "scan_id": "saved-scan-uuid" }
```

Response:

```json
{
  "data": [
    {
      "source_kind": "standard_outing",
      "source_id": "uuid",
      "user_field_trip_id": "uuid",
      "participation_id": null,
      "template_id": "uuid",
      "challenge_id": null,
      "title": "Park Pollinators",
      "slug": "park_pollinators",
      "item_id": "uuid",
      "prompt": "Butterfly or moth",
      "level_number": 1,
      "level_title": "Level 1",
      "completed_count": 1,
      "target_count": 2,
      "is_complete": false,
      "artwork_prompt": "Butterfly or moth",
      "artwork_template_slug": "park_pollinators",
      "destination_kind": "field_trip",
      "destination_template_id": "uuid",
      "destination_checklist_item_id": "uuid",
      "destination_challenge_id": null
    }
  ]
}
```

The authenticated Edge action supplies the verified caller to the private
service-role RPC. It returns one current credit per standard outing/Event for
the supplied saved biological scan. Rows include only labels, counts, artwork
inputs, and typed-routing inputs. They never include media, storage URLs,
coordinates, place labels, notes, or public evidence. Missing, unauthorized,
queued, non-biological, and uncredited scans return an empty array. Current
clients present Event rows alongside standard outings.

### Seasonal Challenges

The challenge API and Events UI are public. Every iOS user receives the Events
segment and the client can request catalogs/details, show badges, follow entry
routes, consume challenge progress from `apply_scan_progress`, and load hashtag
suggestions. All actions continue to enforce the verified viewer and existing
database policies; public client presentation does not change these request or
response shapes or weaken authorization.

Catalog request:

```json
{
  "action": "challenges_catalog",
  "user_region": "us-ca",
  "limit": 20
}
```

Catalog rows include:

```json
{
  "challenge_id": "uuid",
  "template_id": "uuid",
  "template_slug": "park_pollinators",
  "template_title": "Park Pollinators",
  "slug": "summer_pollinator_watch",
  "title": "Summer Pollinator Watch",
  "subtitle": "Find pollinators while flowers are active.",
  "description": "A non-competitive seasonal challenge.",
  "cover_image_url": "https://...",
  "starts_at": "2026-06-01T00:00:00.000Z",
  "ends_at": "2026-08-31T23:59:59.000Z",
  "status": "live",
  "region_tags": ["global"],
  "season_tags": ["summer"],
  "habitat_tags": ["park", "garden"],
  "suggested_hashtags": ["summerpollinators", "pollinators"],
  "is_pro_only": false,
  "is_temporarily_free": true,
  "viewer_has_access": true,
  "access_kind": "temporarily_free",
  "participant_count": 42,
  "completion_count": 9,
  "published_entry_count": 4,
  "viewer_participation": {
    "participation_id": "uuid",
    "user_field_trip_id": "uuid",
    "joined_at": "2026-07-08T12:00:00.000Z",
    "current_level_number": 1,
    "completed_at": null,
    "badge_awarded_at": null,
    "completed_count": 1,
    "target_count": 2
  },
  "template": null,
  "entries": []
}
```

`status` is one of `live`, `upcoming`, or `ended`. Access is
server-authoritative and independent from the linked template's ordinary catalog
access; a challenge can be free, Pro-only, or temporarily free during its
schedule.

Detail and join requests:

```json
{ "action": "challenge_detail", "challenge_id": "uuid", "entries_limit": 12 }
{ "action": "join_challenge", "challenge_id": "uuid" }
```

`challenge_detail` returns one challenge object with linked template guide
context and initial entries. `join_challenge` requires a live accessible
challenge, starts or continues the linked Field trip, creates or returns the
separate participation row, and returns refreshed challenge detail. It is
idempotent for repeated joins.

Challenge progress is updated through `apply_scan_progress`. A scan counts only
when it is owned by the caller, created at or after `joined_at`, created at or
before `ends_at`, satisfies the same Possible-match-or-confirmed evidence
policy, and matches the participant's current challenge level. Challenge
completions are separate from normal Field trip completions and are limited to
one credited item per participation and scan.

Challenge hashtag request:

```json
{ "action": "scan_challenge_hashtags", "scan_id": "saved-scan-uuid" }
```

Response:

```json
{ "data": ["summerpollinators", "pollinators"] }
```

The response is for optional Explore composer suggestions only. The endpoint
does not auto-post, auto-tag, create Explore challenge feeds, or persist private
challenge evidence on device.

### Challenge Entries

Publication list request:

```json
{
  "action": "challenge_publications",
  "challenge_id": "uuid",
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_entry_id": "uuid"
}
```

Rows paginate by `(published_at DESC, entry_id DESC)` and use the same
block/shadowban visibility rules as Field trip publications. Challenge entries
are not `field_trip_publications` and do not create Explore posts.

Publish/detail/like/comment requests:

```json
{
  "action": "publish_challenge_entry",
  "participation_id": "uuid",
  "title": "My Pollinator Watch",
  "description": "Optional"
}
{ "action": "challenge_entry_detail", "entry_id": "uuid" }
{ "action": "set_challenge_entry_like", "entry_id": "uuid", "liked": true }
{ "action": "challenge_entry_comments", "entry_id": "uuid", "limit": 50 }
{ "action": "create_challenge_entry_comment", "entry_id": "uuid", "body": "Nice finds!" }
```

Publishing requires a completed challenge participation and snapshots challenge
item completions into `field_trip_challenge_entry_items`. Challenge entry likes
and comments are stored in challenge-specific tables, not Explore or normal
Field trip publication tables. Joins, likes, badges, and progress updates do not
notify other users in V4.

### Profile Summaries

Request:

```json
{
  "action": "profile_summaries",
  "author_user_id": "uuid",
  "limit": 6
}
```

Response:

```json
{
  "data": {
    "active": [
      {
        "user_field_trip_id": "uuid",
        "template_id": "uuid",
        "slug": "backyard_safari",
        "title": "Backyard Safari",
        "started_at": "2026-07-08T12:00:00.000Z",
        "current_level_number": 1,
        "current_level_title": "Level 1",
        "completed_count": 0,
        "target_count": 2,
        "is_complete": false
      }
    ],
    "pinned": [
      {
        "publication_id": "uuid",
        "title": "Backyard Safari with Sam",
        "description": "A quiet morning checklist.",
        "published_at": "2026-07-08T13:00:00.000Z",
        "like_count": 4,
        "comment_count": 1,
        "slug": "backyard_safari",
        "template_title": "Backyard Safari",
        "cover_image_url": "https://...",
        "item_count": 10,
        "viewer_has_liked": false,
        "is_pinned": true,
        "pin_position": 1
      }
    ],
    "published": [
      {
        "publication_id": "uuid",
        "title": "Backyard Safari with Sam",
        "description": "A quiet morning checklist.",
        "published_at": "2026-07-08T13:00:00.000Z",
        "like_count": 4,
        "comment_count": 1,
        "slug": "backyard_safari",
        "template_title": "Backyard Safari",
        "cover_image_url": "https://...",
        "item_count": 10,
        "viewer_has_liked": false,
        "is_pinned": false,
        "pin_position": null
      }
    ],
    "challenge_badges": [
      {
        "badge_id": "uuid",
        "challenge_id": "uuid",
        "badge_key": "summer_pollinator_watch_complete",
        "title": "Summer Pollinator Watch",
        "awarded_at": "2026-07-08T13:00:00.000Z",
        "challenge_slug": "summer_pollinator_watch",
        "challenge_title": "Summer Pollinator Watch",
        "cover_image_url": "https://...",
        "region_tags": ["global"],
        "season_tags": ["summer"],
        "habitat_tags": ["park"]
      }
    ]
  }
}
```

Active summaries are profile-status only. They must not expose scan IDs, media
URLs, field notes, exact coordinates, public location labels, or private
evidence. Published summaries expose only Field trip publication IDs and
snapshot metadata. `pinned` is capped at 3 and omitted from the general
`published` list. Shadowbanned authors and mutual blocks are excluded. Challenge
badges are lightweight profile rewards only; they expose no scan IDs, media
URLs, exact location, field notes, or private evidence.

Set pinned publications request:

```json
{
  "action": "set_pinned_publications",
  "publication_ids": ["uuid"]
}
```

The response is the refreshed profile summaries payload. The endpoint replaces
the caller's pin list, preserves the supplied order, rejects more than 3 IDs,
and accepts only the caller's visible Field trip publications.

### Community Publications

Request:

```json
{
  "action": "community_publications",
  "mode": "smart",
  "template_id": "optional-template-uuid",
  "user_region": "us-ca",
  "habitat_tags": ["neighborhood"],
  "season_tags": ["spring"],
  "limit": 20,
  "before_rank_bucket": 2,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

Response:

```json
{
  "data": [
    {
      "publication_id": "uuid",
      "template_id": "uuid",
      "title": "Backyard Safari with Sam",
      "description": "A quiet morning checklist.",
      "published_at": "2026-07-08T13:00:00.000Z",
      "like_count": 4,
      "comment_count": 1,
      "slug": "backyard_safari",
      "template_title": "Backyard Safari",
      "region_tags": ["global", "neighborhood"],
      "season_tags": ["spring"],
      "habitat_tags": ["yard"],
      "cover_image_url": "https://...",
      "item_count": 10,
      "viewer_has_liked": false,
      "author_user_id": "uuid",
      "author_name": "River W.",
      "author_username": "river_w",
      "author_avatar_url": "https://...",
      "is_pinned": false,
      "pin_position": null,
      "rank_bucket": 0,
      "community_reason": "following",
      "viewer_is_following_author": true
    }
  ]
}
```

`mode` accepts `smart`, `following`, or `recent`. `smart` is deterministic
bucketed ranking, not ML: followed author plus local/template relevance,
followed author, local/habitat/season/template match, global/no-region fallback,
then other visible fallback. Within each bucket, rows order by
`published_at DESC, publication_id DESC`. `following` filters to existing
`user_follows` relationships. `recent` is reverse chronological for all visible
published Field trips. `template_id` limits results for template-detail
Community previews.

Pagination is stable on
`(rank_bucket ASC, published_at DESC, publication_id DESC)`, so community
cursors must send all three cursor fields together.

Compatibility request:

```json
{
  "action": "recent_publications",
  "user_region": "us-ca",
  "habitat_tags": ["neighborhood"],
  "limit": 20,
  "before_published_at": "2026-07-08T13:00:00.000Z",
  "before_publication_id": "uuid"
}
```

`recent_publications` is a compatibility alias for `community_publications` with
`mode: "recent"`.

Community Publications is Field trips-native and never creates Explore post
rows. The iOS client also reuses this action to mix typed Field trip cards into
unfiltered Explore Recent and Following. Those cards retain Field trip identity
and interactions. Field trips remain absent from Trending, Nearby, map, widgets,
APNs, and public web share surfaces.

### Publication Detail, Likes, and Comments

Publish request:

```json
{
  "action": "publish",
  "user_field_trip_id": "uuid",
  "title": "Backyard Safari with Sam",
  "description": "A quiet morning checklist.",
  "ai_summary": "Optional generated summary."
}
```

Detail request:

```json
{
  "action": "detail",
  "publication_id": "uuid"
}
```

Detail response:

```json
{
  "data": {
    "publication_id": "uuid",
    "user_field_trip_id": "uuid",
    "template_id": "uuid",
    "template_slug": "backyard_safari",
    "template_title": "Backyard Safari",
    "title": "Backyard Safari with Sam",
    "description": "A quiet morning checklist.",
    "ai_summary": null,
    "published_at": "2026-07-08T13:00:00.000Z",
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "like_count": 4,
    "comment_count": 1,
    "viewer_has_liked": false,
    "items": [
      {
        "publication_item_id": "uuid",
        "item_id": "uuid",
        "prompt": "Bird",
        "common_name": "Northern Cardinal",
        "scientific_name": "Cardinalis cardinalis",
        "hero_image_url": "https://...",
        "reference_image_url": "https://...",
        "taxonomy": {
          "kingdom": "Animalia",
          "class": "Aves"
        }
      }
    ]
  }
}
```

Like request:

```json
{
  "action": "set_like",
  "publication_id": "uuid",
  "liked": true
}
```

Comments request:

```json
{
  "action": "comments",
  "publication_id": "uuid",
  "limit": 50,
  "after_created_at": "2026-07-08T13:01:00.000Z",
  "after_comment_id": "uuid"
}
```

Create-comment request:

```json
{
  "action": "create_comment",
  "publication_id": "uuid",
  "body": "Nice finds!",
  "parent_comment_id": null
}
```

Field trip likes and comments are stored in `field_trip_publication_likes` and
`field_trip_publication_comments`, not in Explore post tables. Comment payloads
intentionally mirror the compact `ExploreComment` shape for iOS reuse, with
`post_id` carrying the Field trip publication ID inside this scoped endpoint.

Publishing a Field trip never writes `explore_posts`, Explore feed cards,
Explore map rows, normal Explore post notifications, APNs, widgets, or public
web share pages. Field trip comments, replies, and followed-author publications
may create Field trip-only in-app activity rows that appear in Explore activity
and the unread bell. Sharing is a future layer.

---

## Deno `/generate-upload-urls` Edge Node

To fetch cryptographic keys for direct-to-Cloudflare uploads, the client sends a
structured media manifest. The cross-language contract lives in
`docs/contracts/media-staging-upload-manifest.json`; Swift and Deno tests both
load that file so limits and allowed content types cannot drift silently.

Native request ownership is
`Core/Network/Endpoints/MerianNetworkClient+MediaStorage.swift`; the unchanged
signing DTOs live in `Core/Network/MediaStorageAPIModels.swift`. The signing
method captures the explicit or privately resolved Auth UUID before encoding the
lowercase `user_id` and passes that same UUID to private authenticated
transport. Current-session resolution and live Auth leases remain required. The
30-second deadline, plain required-`urls` decoding, classified-401 refresh, and
ambiguous-replay refusal are unchanged. The signer primitive adds no client
manifest normalization or validation; its callers retain those policies. Raw
Data/file PUTs and foreground video planning live in `Core/Network/Media/`. See
the
[native ownership and verification guide](../../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-ownership).

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID linking RevenueCat and PostHog",
  "files": [
    {
      "fileName": "scan-id_photo_1.webp",
      "mediaKind": "image",
      "contentType": "image/webp",
      "sizeBytes": 124000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "display"
    },
    {
      "fileName": "scan-id_audio_1.wav",
      "mediaKind": "audio",
      "contentType": "audio/wav",
      "sizeBytes": 42000,
      "clientScanId": "00000000-0000-0000-0000-000000000001",
      "mediaRole": "audio"
    }
  ]
}
```

The server extracts the verified user identity from the `Authorization` Header
JWT (`supabaseAdmin.auth.getUser()`), ignoring any `user_id` value in the
request body. To prevent array-abuse memory locking on the Edge Node, the
endpoint strictly requires exactly 1 to 8 `files`, with at most 5 images, 2
audio files, and 1 video file. A video scan can carry five sampled `image/webp`
inference frames, one `video/mp4` playback clip, its companion WAV, and an
optional standalone audio recording. Byte and per-kind limits remain unchanged.
The main app queue builds this manifest through `MediaStagingContract` and must
apply the same filename sanitization as the Edge function before upload URL
generation. For scan uploads, each structured entry may also include
`clientScanId` and `mediaRole`; when present, `/generate-upload-urls` creates a
server-owned staged `scan_media_assets` row before returning the signed URL.
Those staged rows are valid with `scan_id = NULL` until the final scan row
exists and with `url = NULL` until media promotion produces a public URL; they
are keyed by owner, client scan id, deterministic object key, and upload session
for later promotion or cleanup. Image roles may be `display`, `thumbnail`, or
`inference_frame`; video uses `playback`; audio uses `audio`. The Edge parser
rejects unsanitized filenames, duplicate filenames, invalid `mediaKind` values,
invalid role/kind combinations, content-type/kind mismatches, empty media, and
oversized media before signing. Every manifest requires a positive integer
`sizeBytes`; legacy `fileNames`, missing sizes, top-level arrays/non-objects,
and other old request shapes fail with stable `400 size_bytes_required`. Each
URL response includes `requiredHeaders` with the exact `Content-Type` and
decimal `Content-Length`. Signing uses `allHeaders: true`, binding the exact
`content-length;content-type;host` header set. Every iOS data, file, avatar,
repair, restore, foreground, and background PUT applies the returned map. A
file-backed upload retains its signing-time size and re-stats immediately before
task creation. A changed size rejects that PUT; the durable queue returns to
fresh signing, while foreground callers retain their own failure/retry policy.
Pre-signed `PUT` URLs include an `X-Amz-Expires=86400` parameter (24 hours).
This extended window gives iOS `BackgroundTasks` flexibility to transmit
overnight, subject to OS memory, thermal, and Wi-Fi conditions, without hitting
403 errors. Deployed integration tests PUT the exact headers, reject wrong
length/MIME, then HEAD the object to prove the stored size equals the
declaration; a client-declared value alone is not storage evidence.

Audio signing is purpose-aware. An ordinary scan-ingestion entry accepts only
`audio/wav` with a `.wav` filename. `audio/mp4` is available only to an explicit
`scan_share_restore` entry and requires the canonical `.m4a` extension; the same
restore purpose may use `.wav`/`audio/wav`. MIME/extension mismatches and other
audio extensions fail before registration or signing. The inference handler
independently inspects the uploaded bytes, so a correctly named but non-WAV
ordinary object still cannot reach Gemini or durable promotion.

An already-persisted observation that is missing durable sharing media adds
`"uploadPurpose": "scan_share_restore"` to each repair entry. That purpose is
accepted only with `clientScanId`, the canonical media role, and an exact
scan/category-bound deterministic restore filename. For a completed job, the
signer performs a fresh unrestricted scan read. An existing row must be active,
non-tombstoned, and owned by the authenticated caller; a genuinely absent row
may only stage these exact files before guarded owner-row reconstruction. A
missing or nonterminal job can stage for the same guarded flow, but signing
grants no scan-write or publication authority; the recovery route still
validates the owner and payload. Repair and ordinary files cannot mix for one
scan. Ordinary uploads cannot use completed ingestion as a new staging
namespace. Failed-terminal repair is limited to exact `replay_exhausted`, or
exact `media_reconciliation_abandoned` plus matching composite
dead-letter/quota/media-lifecycle proof. Current/later policy, unproven
abandonment, and every other terminal reason remain closed. Signing obtains that
decision from bounded service-only `get_media_abandoned_scan_recovery_proofs`;
database errors, malformed rows, or an unexpected scan id fail before any URL is
returned. This exception is what lets Explore and Ask the Community restore
surviving local image, playback-video, or standalone-audio media after analysis
has durably completed. When camelCase and snake_case compatibility aliases are
both supplied for scan ID, media role, or upload purpose, their values must be
identical; contradictory aliases fail before lifecycle registration.

The Edge function uses the `fileName` parameter from the JSON body (after
applying basic sanitization to prevent path traversal vectors) rather than
generating random internal UUIDs. The verified server identity, not the optional
body `user_id`, determines the `objectKey` owner segment. A client that planned
with a device identity before lazy anonymous authentication must accept the
canonical returned key. Before dispatching any background PUT, the iOS durable
queue requires exact response count/order, matching filenames, one canonical
staging owner, and signed URL paths that resolve to the returned keys. Each
background task carries its exact returned key through suspension.

That whole-manifest validation belongs to the durable queue, not the shared
signing decoder. Foreground video retains its existing response-count check and
sequential file uploads; each raw PUT independently enforces HTTPS, the exact
signed header map, current byte size, and HTTP-200-only success. The extraction
does not add foreground filename/key/lifecycle correspondence checks or move
queue scheduling into Network.

```json
{
  "urls": [
    {
      "fileName": "photo_1.webp",
      "signedUrl": "https://<R2_URL>?X-Amz-Signature=...",
      "objectKey": "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_photo_1.webp",
      "requiredHeaders": {
        "Content-Type": "image/webp",
        "Content-Length": "124000"
      },
      "mediaAssetId": "scan_media_assets row UUID",
      "mediaSessionId": "upload session UUID"
    }
  ]
}
```

`mediaAssetId` and `mediaSessionId` are omitted for non-scan uploads, such as
profile avatars. During `identify-multimodal` finalization, promoted
image/video/standalone-audio staging keys update the matching staged rows and
link them to the completed scan. Consumed extracted `video_audio` staging keys
become `deleted`; moderation, promotion, or scan-insert failures mark
still-staged rows as `failed`. The returned `mediaSessionId` values also let
ingestion recover the exact upload sessions for the staged object keys; those
session ids participate in the `scan_ingestion_jobs` `manifest_checksum`, giving
retries and repair workers a stable server-side description of the requested
media set without storing media bytes.

Scan-media registration is idempotent on
`(authenticated owner, clientScanId, objectKey)`. A retry after a lost signing
response returns the committed asset and original upload session. An exactly
compatible failed row may reactivate when its ingestion job is absent or
retryable. An exact `scan_share_restore` row may also register or reactivate for
completed ingestion when the fresh scan read finds either the active owned row
or no row for the guarded reconstruction; tombstoned, foreign, and
moderation-rejected/moderation-pipeline-failed rows fail closed.
Failed-terminal, deleted, ordinary completed-ingestion, or media-incompatible
rows also fail closed. A partial unique index serializes registration races,
while the repair migration retains historical extras as
`failed / superseded_staging_registration` audit rows. New rows use a
per-client-scan media index, never a flat position among other scans in the
signing request. The eight-item union counts active staged/processing sources;
historical promoted capture rows remain audit evidence but do not consume a
later explicit share-repair budget. Any response manifest mismatch starts no
upload and returns the claimed scans to `.pending` with durable backoff.

> The pre-signed URL is generated with the exact `contentType` from the
> structured manifest. The iOS `URLRequest` must send the same `Content-Type`
> header on the `PUT`, or Cloudflare R2 will reject the upload with
> `403 SignatureDoesNotMatch`.

---

## Deno `/reconcile-scan-media-assets` Internal Worker

This endpoint is not called by iOS. It is invoked hourly by pg_cron with one
exact platform-managed current or legacy server key. Supabase gateway JWT
verification is disabled so pg_net can reach the function, and the function
performs service-key validation internally. Opaque keys use `apikey` only.

Optional request payload:

```json
{
  "limit": 100,
  "repairAfterMinutes": 15,
  "abandonAfterHours": 36,
  "dryRun": false
}
```

Response payload:

```json
{
  "success": true,
  "scanned": 3,
  "promoted": 1,
  "repairedVideoScans": 1,
  "deletedStagingObjects": 2,
  "failedAssets": 1,
  "missingObjects": 0,
  "stillPending": 1,
  "errors": []
}
```

The worker only reconciles media lifecycle state. It can repair an existing scan
that has a surviving staged playback video by promoting the video, updating
`video_storage_urls`, rebuilding `captured_media`, and refreshing ready
`scan_media_assets` rows. It can also delete abandoned staging objects and mark
their staged rows failed. Before treating an orphan as abandoned, it checks the
matching `scan_ingestion_jobs` row: active leases and future retry windows keep
the media pending, repaired scans complete only through the shared
claimed-key/canonical-media finalization routine, and TTL-abandoned media marks
the job `failed_terminal` with a structured terminal reason. Sanitized
`scan_ingestion_intents` rows preserve staged media/audio/video and text-only
replay metadata for operations and `replay-scan-ingestion`, but this worker does
not replay AI inference for scans that never created a cloud scan row.

---

## Deno `/replay-scan-ingestion` Internal Worker

This endpoint is not called by iOS. It is invoked every five minutes by pg_cron
with one exact platform-managed current or legacy server key. Supabase gateway
JWT verification is disabled so pg_net can reach the function, and the function
performs local exact service-key validation internally. Opaque keys use `apikey`
only. The route never uses a database/RLS result as proof, rejects mixed
credentials, and uses its server environment key for database and downstream
multimodal calls.

Optional request payload:

```json
{
  "limit": 5,
  "leaseSeconds": 300,
  "retryAfterMinutes": 5,
  "awaitInvocations": false
}
```

Response payload:

```json
{
  "success": true,
  "claimed": 1,
  "dispatched": 1,
  "completedExisting": 0,
  "skippedExistingIncomplete": 0,
  "failedDispatches": 0,
  "errors": []
}
```

The worker claims due `scan_ingestion_jobs` rows whose paired
`scan_ingestion_intents` are `resumable = true` and not inline-redacted,
reconstructs the staged media/audio/video or text-only request from the
sanitized intent payload, and invokes `/identify-multimodal` with the original
`client_scan_id`. The multimodal endpoint still owns AI inference, moderation,
media promotion, scan insert idempotency, and the strict playback-video
durability gate. A service-authenticated `X-Merian-Replay-Attempt` header
derives a distinct deterministic quota UUID from the scan UUID and durable claim
count. This prevents the original committed reservation from blocking recovery
while keeping each replay metered and idempotent within one claim. Inline
foreground requests remain client-owned because their raw media bytes are never
stored server-side.

Automatic replay is capped at 10 claims per sanitized intent. The claim RPC
excludes over-budget intents from new replay work and marks the paired
`scan_ingestion_jobs` row `failed_terminal` with
`stage = 'server_replay_limit_reached'` in the same bounded claim window, so a
permanently broken replay payload cannot churn forever.

The internal `/identify-multimodal` invocation has a 120-second hard deadline.
`leaseSeconds` is clamped to at least 150 seconds, reserving 30 seconds for
durable failure settlement before a replacement claim is possible. Non-success
diagnostics are retained only within an 8 KiB streamed response ceiling.

Compatibility scan-producing endpoints (`/identify`, `/identify-describe`, and
`/audio-spec`) call `begin_scan_ingestion` before provider dispatch and write
`scan_ingestion_jobs` plus sanitized `scan_ingestion_intents` atomically. A
setup error returns `503 scan_ingestion_unavailable` and refunds unused quota;
an owner-recovery winner reloads the exact owner-scoped completed result and
returns idempotent `200`; neither path calls the provider. A compatibility
fallback conflict is possible only when completion evidence cannot be safely
loaded. Those intents set `endpoint: "identify-multimodal"` inside the replay
payload and preserve the legacy route name as `compatibilityEndpoint`, so staged
legacy image/audio and text-only rows recover through the same replay worker.
Inline base64 media is represented only by redacted counts and is marked
non-resumable. Compatibility setup uses the same per-scan advisory lock as
current claim and recovery. Compatibility completion invokes the response-aware
finalization wrapper; staged inference-only audio must receive R2 2xx or
idempotent 404 deletion confirmation before completion.

If the scan row already exists, the worker invokes
`complete_scan_ingestion_finalization` without replaying AI. That transaction
marks the job complete only after every manifest key has a permitted terminal
disposition and every promoted image/video/audio URL has a ready canonical row.
If the scan row or media is incomplete, the worker leaves the job retryable for
reconciliation or local video restore instead of rerunning inference against an
already-created scan row.

---

## Deno `/scan-media-health` Internal Status

Read-only service-key endpoint for media durability observability. Supabase
gateway JWT verification is disabled for automation reachability, and the
function validates an exact key from the shared current-or-legacy server-key
resolver before querying. Opaque `sb_secret_...` keys are valid only in
`apikey`; legacy service-role JWTs use matching `apikey` and Bearer headers. It
never treats a successful database/RLS response as proof and does not reuse the
request credential for database access.

Optional request payload:

```json
{
  "limit": 25,
  "stuckAfterMinutes": 20,
  "staleAssetAfterMinutes": 15,
  "recentScanLimit": 250
}
```

Response payload:

```json
{
  "success": true,
  "generated_at": "2026-07-05T15:00:00.000Z",
  "status": "warning",
  "thresholds": {
    "stuck_after_minutes": 20,
    "stale_asset_after_minutes": 15
  },
  "counts": {
    "ingestion_jobs_checked": 3,
    "stale_capture_upload_assets": 1,
    "failed_assets": 0,
    "recent_scans_checked": 250,
    "ready_video_assets_checked": 2,
    "explore_video_rows_checked": 10,
    "reconciliation_runs_checked": 5,
    "ingestion_intents_checked": 3,
    "issues": 1,
    "critical_issues": 0,
    "warning_issues": 1
  },
  "asset_breakdown": {
    "stale_capture_upload_assets": [
      { "kind": "image", "role": "display", "count": 1 }
    ],
    "failed_assets": []
  },
  "issues": [
    {
      "code": "stale_capture_upload_assets",
      "severity": "warning",
      "message": "Capture-upload media assets remain staged past the reconciliation window.",
      "count": 1,
      "sample": []
    }
  ]
}
```

The status can be `ok`, `warning`, or `critical`. Critical issues indicate a
durability invariant is already broken or a server-owned ingestion job is stuck
past its lease. Warning issues indicate retry/repair work may still complete but
should be monitored, including missing or non-resumable ingestion intents for
retryable work. The endpoint does not repair media; writers remain
`identify-multimodal`, `reconcile-scan-media-assets`, and the iOS offline queue.
The scheduled **Scan Media Health Monitor** workflow calls this endpoint every
30 minutes, stores JSON/Markdown artifacts, and fails only on `critical` by
default. The monitor's Markdown summary adds an **Incident Actions** table for
each issue code with owner, next step, runbook, and sample-field hints; use that
as the first operational response before querying individual scan/media rows.

---

## Deno `/update-public-avatar` Edge Node

Promotes one user-owned staged R2 image into the durable public avatar prefix.
The iOS Profile tab first requests a signed URL from `/generate-upload-urls`,
uploads the prepared square avatar to `staging/{userId}/...`, then calls this
endpoint.

### Request Payload

```json
{
  "r2_object_key": "staging/a1b2c3d4-e5f6-7890-abcd-ef1234567890/avatar_11111111-1111-4111-8111-111111111111.webp",
  "mime_type": "image/webp"
}
```

Rules:

- `r2_object_key` must be a string owned by the authenticated user under
  `staging/{user.id}/...`.
- Path traversal is rejected with `400`.
- Wrong-user staging keys are rejected with `403`.
- `mime_type` must be `image/webp` or `image/jpeg`, and it must also be in the
  staged image MIME allowlist.

### Response Payload

```json
{
  "avatar_url": "https://media.merian.app/avatars/a1b2c3d4-e5f6-7890-abcd-ef1234567890/22222222-2222-4222-8222-222222222222.webp"
}
```

The function copies the staged object to `avatars/{userId}/{uuid}.webp` or
`avatars/{userId}/{uuid}.jpg`, updates `users.custom_avatar_url`,
`users.custom_avatar_updated_at`, and `users.public_avatar_url`, and deletes
only the previous same-user custom avatar object. OAuth avatars remain fallback
metadata when no custom avatar exists.

---

## Community Identification Edge Nodes

Community Identification is the Ask the Community queue under Explore. It is
backed by `taxon_nodes`, `explore_community_requests`, and
`explore_identifications`, with versioned taxonomy, queued consensus jobs, and
the `explore_observation_projection` public feed boundary.

### `/request-community-identification`

Creates or reopens an Explore post as a `needs_id` community request. The
request is gated to the authenticated user's resolved, non-Human biological scan
with shareable media. The owner-row validator rejects explicit non-biological
state, missing/unresolved selected taxonomy, Human aliases/overrides, and never
uses stored reasoning. It accepts `scan_id`, optional `note`, optional
`location_sharing` (`open`, `obscured`, `private`), optional
`species_common_name`, and optional `restored_object_keys`,
`restored_video_object_keys`, and `restored_audio_object_keys` for bounded media
repair.

Clients attach one UUID `Idempotency-Key` and preserve it across transport,
authentication, and media-restoration retries. Newly created and existing
Explore posts use the same mandatory audio publication gate as
`share-scan-to-explore`: each audible item receives a checksum/policy-derived
child key, and a cache miss reserves `explore_audio_moderation` before provider
dispatch. The database resolves entitlement/model and applies daily plus user/IP
limits. Cache hits refund the provisional reservation. Missing quota,
entitlement, policy, provider, or moderation state fails closed and does not
replace public media.

Taxonomy resolution also completes before publication. The final relational
mutation is service-only `request_community_identification_atomically(...)`: it
locks an existing request before the exact owner scan and commits the post
metadata, complete media snapshot, and `needs_id` request together. An error at
any later request, projection-trigger, or constraint boundary restores the prior
complete post. Reopening withdrawn state resets its public-publish marker,
cached consensus, worker lease/job, and active vote generation while preserving
withdrawn identification rows as audit history. A post-level recheck at the
actual `shared_at` update also rejects an explicit share that lost a concurrent
race with new `needs_id` state.

The final RPC and the companion direct-share RPC are `SECURITY INVOKER`. Forward
migration `20260729044500_grant_atomic_explore_service_privileges.sql` grants
only their required table operation classes to `service_role`. Their existing
`EXECUTE` allowlists still exclude `PUBLIC`, `anon`, and `authenticated`, and
the forward migration grants those browser roles no new writes. A service-role
table permission failure is a deployment/catalog defect, not a reason to weaken
the routine to definer authority.

The endpoint intentionally returns `404 { "error": "Scan not found." }` when
`public.scans` has no row for the authenticated user. The iOS Insight client
handles that specific error by resolving the server `species_dictionary.id` by
scientific name and sending a bounded non-media `recovery_scan` through the
single `/check-scan-status` contract. The server defers to active/retryable
richer ingestion, permits exact structured `replay_exhausted`, and admits exact
`media_reconciliation_abandoned` only with matching composite
dead-letter/quota/media-lifecycle proof. It creates only an absent
authenticated-owner row and reloads it by owner. After status returns `found`,
iOS uploads surviving eligible local images, playback video, and standalone
audio to staging and retries this endpoint with the three category-specific
restored-key arrays. This endpoint itself does not accept `recovery_scan`; the
sequence is compatibility repair for older/interrupted drift, not the expected
current multimodal success path.

Before inspecting or returning an existing active request, the endpoint repairs
any Community request on that `scan_id` whose `requested_by` no longer matches
the authenticated scan owner inside that same transaction. This covers legacy
ghost-account ownership drift and keeps the Identify Yours filter, owner-only
actions, and duplicate-request guard tied to the current account.

The response envelope is:

```json
{
  "success": true,
  "data": {
    "id": "request uuid",
    "post_id": "explore post uuid",
    "scan_id": "scan uuid",
    "status": "needs_id",
    "initial_taxon_node_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid"
  }
}
```

The Edge/database boundary accepts the returned request only when `scan_id` and
`requested_by` equal the requested scan and authenticated owner after canonical
UUID case normalization. PostgreSQL emits lowercase UUID text while Apple
clients may send uppercase UUID strings; casing alone is not an identity
mismatch.

iOS also treats this `200` as candidate evidence. Decode failure, an unknown
status, `success: false`, a mismatched scan, malformed request/post/owner/taxon
UUID, invalid request timestamp, any status other than `needs_id`, or a negative
consensus count becomes `MerianError.invalidResponse`. No Community success
state is cached from that response.

### `/get-community-identification-feed`

Returns unresolved `needs_id` requests for the Identify Community dashboard and
full **Identify requests** stack page. `limit` defaults to 30 and is capped at
100. Optional `scope` accepts `all` or `mine` and defaults to `all`; `mine`
returns unresolved requests created by the authenticated viewer. Optional
`group` accepts `all`, `plants`, `birds`, `insects`, `fungi`, `mammals`, or
`reptiles_amphibians`. Requests and Activity share the same lineage-backed
classifier.

Optional `latitude` and `longitude` must be supplied together and sort local
public-coordinate requests first, followed by recent requests. Cursor fields
`before_requested_at` and `before_request_id` must also be supplied together.
Rows may include `taxonomy_version_id`, `projection_state`,
`consensus_processing_state`, `request_group`, and ordered `media_items`. The
iOS dashboard explicitly requests 12 rows; the complete feed explicitly
requests 30.

### `/get-community-identification-activity`

Returns privacy-filtered, community-wide Identify activity. Optional `scope` and
`group` use the same values as the request feed, so `mine` means activity for
requests created by the authenticated viewer rather than activity performed by
that viewer. `limit` defaults to 30 and is capped at 100. The paired cursor
fields are `before_activity_at` and `before_activity_id`; ordering is
deterministic by `(activity_at DESC, activity_id DESC)`.

The authenticated JSON request is:

```json
{
  "limit": 10,
  "scope": "mine",
  "group": "birds",
  "before_activity_at": "2026-07-30T19:00:00.000Z",
  "before_activity_id": "00000000-0000-4000-8000-000000000002"
}
```

The cursor fields are optional, but supplying only one returns `400`. Unknown
scope/group values, malformed cursor timestamps, and malformed cursor UUIDs also
return `400`. `limit` follows the shared Explore policy: finite numbers are
floored and clamped to `0...100`; missing or nonnumeric values use 30.

The success envelope is:

```json
{
  "data": [
    {
      "activity_id": "00000000-0000-4000-8000-000000000010",
      "activity_type": "suggestion_burst",
      "request_id": "00000000-0000-4000-8000-000000000011",
      "post_id": "00000000-0000-4000-8000-000000000012",
      "scan_id": "00000000-0000-4000-8000-000000000013",
      "hero_image_url": "https://media.example/request.jpg",
      "activity_at": "2026-07-30T20:00:00.000Z",
      "suggestion_count": 3,
      "recent_actor_names": ["river_wren", "moss_grove"],
      "taxon_id": "00000000-0000-4000-8000-000000000014",
      "taxon_common_name": "White-tailed Eagle",
      "taxon_scientific_name": "Haliaeetus albicilla",
      "taxon_rank": "species",
      "consensus_score": 0.78,
      "request_group": "birds",
      "media_items": []
    }
  ]
}
```

Items have type `suggestion_burst`, `consensus_changed`, or `resolved`.
Suggestions on one request lifecycle chain into the same burst when each
suggestion is no more than 60 minutes after the prior suggestion, including the
exact 60-minute boundary. A burst returns its visible suggestion count and up to
three most recent distinct visible actor public usernames. The legacy
`recent_actor_names` key is retained for wire compatibility, but its values are
usernames, not profile/display names. Consensus caused by a suggestion is folded
into the burst's latest taxon metadata. Consensus without a new suggestion is
standalone, and resolution is always a separate immutable milestone.

The Edge Function is the only client entry point. Its RPC and internal
projection are granted to `service_role` only; `PUBLIC`, `anon`, and
`authenticated` cannot invoke or read them directly. Reads apply the same
request visibility, blocking, shadowban, tombstone, unshare, moderation, media
health quarantine, and active-media rules as Identify. Actor attribution is
resolved from visible users' non-null `public_username` values at read time and
is not stored in the projection. Profile/display names are not returned. A
suggestion burst with no actors visible to the viewer is omitted. Fetching this
feed does not read or mutate bell unread state.

`config.toml` deliberately uses `verify_jwt = false` for this route because the
repository owns JWT verification inside `withEdgeHandler`/`requireAuth`.
Anonymous-session and authenticated user JWTs are still required; the setting
does not make the endpoint public. The handler derives `self_id` from the
verified user and never accepts it from the request body, then calls
`public.get_community_identification_activity(...)` through its service-role
client.

The route-local implementation, verification, and compatibility deployment guide
is
[`services/supabase/functions/get-community-identification-activity/README.md`](../../services/supabase/functions/get-community-identification-activity/README.md).

### `/get-community-identification-detail`

Returns one visible request with author identity, current consensus state,
privacy-safe location fields, and the full identification timeline. Tombstoned
scans, unshared posts, blocked relationships, and shadowbanned authors are
filtered out server-side. Identification timeline rows include a computed
`role_label` such as `supporting`, `leading`, `maverick`, or `withdrawn` for
internal consensus/audit behavior; clients should not expose these labels as
user-facing copy. The response also includes additive `suggested_taxa` for the
Suggest ID sheet and the detail header card. The non-null server-derived
`ai_confidence_qualified` flag says whether the recorded execution is compatible
with the established Gemini metric interpretation. Legacy SQL-null provenance
retains existing behavior; unfamiliar present metadata yields `false`. The
public projection omits the full execution configuration. When false, every
suggestion's `confidence_score` is null, candidates retain their recorded order,
and current iOS shows **AI suggestion** without a percentage or Flash/Pro claim.
When true, `inference_tier` selects the established Naturebook Pro/Flash label.
Native omission support is only for the older Gemini-only endpoint. The updated
Edge route rejects a missing/non-boolean flag or unsupported scores; deploy its
migration first. Its invoker RPC is executable only by the authenticated Edge
service caller. Before any alternate provider becomes visible publicly, enforce
compatible supported public-detail clients or a minimum app version; gating new
identification requests alone does not protect older readers. The first
suggestion is the request's `ai_initial` taxon, hydrated from the backing scan's
`ai_confidence_score` and `ai_reasoning` so clients can frame it as Merian's
starting identification without borrowing human consensus or alternative
candidate copy. Confidence is optional and should render as compact card
metadata only when present; reasoning remains collapsed behind the AI reasoning
row. Additional `ai_candidate` suggestions come from resolvable
`scans.candidates` entries in the request's pinned taxonomy version. Suggested
taxa use the same taxon fields as search results and may include
`suggestion_source`, `confidence_score`, and `distinguishing_feature`; for
`ai_initial`, `distinguishing_feature` carries the scan's primary AI reasoning.

Example `suggested_taxa` shape:

```json
[
  {
    "taxon_id": "taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Sweet Orange",
    "scientific_name": "Citrus sinensis",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_sinensis",
    "species_id": "species uuid",
    "suggestion_source": "ai_initial",
    "confidence_score": 0.82,
    "distinguishing_feature": "The glossy evergreen leaves and citrus fruit shape support Sweet Orange."
  },
  {
    "taxon_id": "alternative taxon uuid",
    "taxonomy_version_id": "taxonomy version uuid",
    "common_name": "Mandarin Orange",
    "scientific_name": "Citrus reticulata",
    "rank": "species",
    "path": "plantae.tracheophyta.angiosperms.sapindales.rutaceae.citrus.citrus_reticulata",
    "species_id": "alternative species uuid",
    "suggestion_source": "ai_candidate",
    "confidence_score": 0.61,
    "distinguishing_feature": "Similar foliage, but the visible fruit proportions are less clearly mandarin-like."
  }
]
```

The shared iOS Community request editor treats this detail as candidate input.
Its generation-fenced state owner requires the returned `request_id` to
case-insensitively match the exact requested UUID before hydrating the note or
location choice. Replacement loads and mismatched responses preserve the newer
draft; a current mismatched response follows the normal invalid-response path.

### `/update-community-identification-request`

Updates the authenticated request owner’s editable request info. Accepts
`request_id`, optional `note`, and required `location_sharing` (`open`,
`obscured`, `private`). The backend only updates non-withdrawn requests owned by
the current user and also updates the backing Explore post’s `location_sharing`.

### `/search-community-taxa`

Searches `taxon_nodes` through `taxon_names` by scientific name, common name, or
synonym. Local index search runs first. If results are thin and the query is at
least three characters, the Edge function asks GBIF for additional suggestions,
caches them into the active Community Taxonomy Index, and searches again. GBIF
failures do not block local results. Accepts optional `taxonomy_version_id`;
request detail searches should pass the request's pinned version.

Rows return `taxon_id`, `taxonomy_version_id`, `common_name`, `scientific_name`,
`rank`, `path`, `species_id`, `gbif_taxon_key`, `source`, `is_in_dictionary`,
`accepted_gbif_taxon_key`, and `taxonomic_status`. `species_id = null` is valid
for GBIF-only taxa that have not been materialized into Merian's enriched
Dictionary yet. The Swift client uses `path` to decide whether a selected ID is
exact, descendant, ancestor, or conflicting before presenting any disagreement
sheet.

### `/submit-community-identification`

Accepts `request_id`, `taxon_id`, optional `disagreement_mode`, optional
`reasoning`, and optional `is_genus_best_possible`. The backend validates that
the taxon belongs to the request's pinned taxonomy version, withdraws the
current user's previous active ID, inserts a new audit row, enqueues a consensus
job, and attempts one immediate best-effort processing pass. Consensus rules are
unchanged: active human IDs only, at least two identifications, score strictly
greater than `2 / 3`, sibling/unrelated votes counting against a candidate, and
coarse ancestor IDs staying neutral unless explicitly marked as disagreement.
Species consensus resolves immediately; genus consensus resolves only when at
least one exact genus ID marks genus as best practical.

### `/withdraw-community-identification` and `/restore-community-identification`

Accept `identification_id` and mutate only the authenticated user's own rows.
Withdraw and restore keep the audit trail intact, enqueue consensus work, and
attempt immediate best-effort processing.

### `/refresh-taxonomy-nodes`

Internal service-role endpoint. Rebuilds a draft taxonomy version from
`species_dictionary`, seeds `taxon_names`, activates the version atomically, and
retires the previous Merian dictionary version. Optional body:

```json
{ "source_revision": "species-dictionary-2026-06-20" }
```

### `/sync-community-taxonomy-index`

Internal service-role endpoint. Imports bounded GBIF taxonomy pages into the
active Community Taxonomy Index without materializing `species_dictionary` rows.
v1 supports only the `birds` target, which maps to GBIF taxon key `212` (`Aves`)
and imports accepted species through GBIF species search.

Optional body:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false,
  "refresh_coverage": true,
  "retry": false
}
```

`limit` is capped at `200` and `page_count` is capped at `20`. If `offset` is
omitted, the worker continues from
`taxonomy_coverage_targets.next_import_offset`; explicit offsets remain
available for manual recovery. `retry = true` with no explicit offset replays
the last failed offset when present, otherwise the last successfully imported
page offset. For each successfully fetched page, the worker normalizes the raw
GBIF rows, calls `upsert_gbif_community_taxa(...)` only when normalized taxa
remain, and annotates any created `taxonomy_import_runs` row as
`scope = "gbif_bounded_birds"`. It then checkpoints the raw page's `next_offset`
even when every result normalized out. A live run stops only at GBIF
`endOfRecords`, a raw empty page, or the requested page count; it never stops
merely because the normalized page is empty. After a run imports at least one
row, the worker refreshes coverage once when `refresh_coverage = true`.
`dry_run = true` performs no database writes while advancing the cursor in the
response as if each fetched page had been checkpointed.

### `/process-community-consensus-jobs`

Internal service-role endpoint. Processes pending or retryable failed
`community_consensus_jobs`. Optional body:

```json
{ "limit": 25 }
```

---

## Deno `/identify` Edge Node

### The JSON Request Payload (From Swift `OfflineQueueManager`)

When `NWPathMonitor` goes green, iOS POSTs this payload to Supabase. The server
enforces that all paths within `r2ObjectKeys` begin with `staging/${user.id}/`
and rejects `../` traversal attempts with `HTTP 400`.

The endpoint rejects media JSON requests whose declared `Content-Length` exceeds
the shared `/identify` body ceiling before parsing the body. The body is then
parsed through `_shared/mediaBudgets.ts` using `readRequestJsonWithinBudget`,
making the streaming byte counter authoritative for chunked or missing-length
requests. Inline `imageBase64s` are validated against the shared aggregate
base64 budget; staged `r2ObjectKeys` are validated through
`_shared/identify/media.ts` and R2 bytes are consumed with capped stream readers
before any full response buffer is assembled.

### Server-owned audio comparison

The optional `audio_comparison` request field is accepted only by the disabled
`identify-multimodal` comparison lane. Its exact object is
`{ "planSha256": "<frozen plan SHA-256>", "slot": 1 }`, with integer slots 1–12
from the fixed server table. It conveys no provider, model or DSP override.
`MultimodalPayload` declares the optional input; the executable
shape/authorization validator is `identify-multimodal/comparison/assignment.ts`.
Debug simulator comparison replay sends this handle only after checking the
frozen source bytes and assigning the reserved scan identity. Ordinary native
capture, web and admin clients omit it. Identify JSON response/Swift DTOs are
unchanged.

Eligibility requires the exact authenticated owner, a stable UUID from
`audioComparisonScanId(slot)`, the generated backend/plan hashes and a valid
private server configuration window. The reserved `ac0a0001-` scan prefix
remains guarded when the marker is absent or configuration is disabled. Checks
precede recovery and completed-result lookup; service replay is rejected. The
body has exactly `user_id`, `client_scan_id`, `geoprivacy`, `mimeType`,
`deviceLocale`, `deviceTimeZone`, `currentMonth`, `timeOfDay`, `audioBase64s`,
`audioMediaItems`, `ownerMediaTimeline` and `audio_comparison`. The first two
match the authenticated owner and derived scan ID. Geoprivacy is `open`,
`obscured` or `private`; `mimeType` is the existing `image/webp` envelope value,
while the sole audio provider part remains `audio/wav`. Context is `en`, `UTC`,
numeric `1` and `12:00 PM`. Descriptor/timeline are exactly one standalone audio
at source/input index zero. Extra evidence, telemetry, aliases or fields are
rejected.

The source must match its frozen bytes/length before bounded WAV processing;
processed bytes must match before quota reservation. Real consent, account,
quota, entitlement and durable-ingestion contracts apply. Gemini Pro with
existing effective Pro entitlement and no Flash fallback is required. A reopened
reservation with `attemptCount !== 1` is refunded before ingestion or provider
preparation; uncertainty/failure excludes the slot. The production request,
snapshot and confidence hashes must match before commitment. The expiry and
reservation guard are checked again immediately before commitment. Missing,
malformed, expired or wrong-owner configuration returns
`409 audio_comparison_unavailable`; identity/body/media mismatch returns
`409 audio_comparison_mismatch`; internal replay or a reopened attempt returns
`409 audio_comparison_excluded`. Normal media/auth/quota errors retain their
existing codes. Execution-setting drift refunds before invocation and follows
the existing caller-safe AI failure path (503). No failure includes a proof.

Fresh durable success alone adds `X-Merian-Audio-Comparison`, exposed through
CORS. Its JSON version `1` has `planSha256`, `slot`, `caseId`, `arm`,
`sourceWavSha256`, `processedWavSha256`, `providerRequestSha256`, `policySha256`
and `confidenceSha256`. These are bounded server-table values verified against
the actual execution, with no raw media, provider text or owner/scan IDs. The
existing `X-Merian-Identification` diagnostics accompany it.
Completed/concurrent replays retain only their usual replay header and never
gain a fresh comparison proof. After configuration expiry/removal even completed
comparison requests stop; normal owner Library reads remain available.

See the
[assignment record](../rfcs/identification-audio-comparison-assignment-2026-09-23.md)
for fixed lifetime, source retention and one-attempt limits. The proof concerns
this authenticated response, not app display, complete observation admission or
all account spend. Ordinary requests without both the handle and reserved ID
remain ordinary, including the same audio submitted separately. Other legacy
endpoints gain no comparison support. The
[app integration](../rfcs/identification-audio-comparison-app-integration-2026-09-23.md)
implements native receipt collection and separate finalization/render proof for
complete-window admission. Keep the configuration unset; deployment, activation
and the bounded paid run require the separate operations defined in the
[activation hold](./06-supabase-deployment-runbook.md#audio-comparison-activation-hold).

### Server-owned audio prompt comparison

The separate default-off prompt lane accepts `audio_prompt_comparison` with
exactly `{ "planSha256": "<generated plan SHA-256>", "slot": 1 }`; slots are
integers 1–36. `comparison/promptPlan.ts` is generated from the frozen
[six-case preparation](../rfcs/identification-audio-uncertainty-comparison-plan-2026-09-24.md).
The client supplies no instruction, model or policy. Arm A keeps
`identify_audio_v2`; arm B uses `identify_audio_uncertainty_experiment_v1`. Both
use current DSP, Gemini Pro, the existing audio schema, fixed context and
unchanged confidence semantics. Identify JSON response DTOs are unchanged.

`comparison/promptAssignment.ts` validates the private
`IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1` configuration: exactly `version`
(`1`), `block` (integer 1–3), `ownerId`, `startsAt`, `expiresAt`, `planSha256`
and `backendBundleSha256`. UTC timestamps must form a currently active window of
at most two hours within the generated plan's preparation/retention lifetime.
The authenticated owner, backend bundle, plan, selected block and derived
`ac0b0001-` scan UUID must match. Marked requests and reserved IDs are guarded
before recovery even when configuration or the handle is missing. Internal
replay is excluded. Both comparison markers together are invalid.

The exact body/context contract is the same as the DSP lane above, replacing
`audio_comparison` with `audio_prompt_comparison`. Source WAV length/hash and
current processed WAV hash are checked before reservation. Normal consent,
entitlement, quota and persistence remain authoritative. Only the first Pro
reservation without Flash fallback is eligible. Native request, policy and
confidence hashes must match their generated slot before commitment; expiry is
rechecked there. Failed setup refunds unused quota; a committed attempt retains
ordinary settlement rules and never gains a replacement slot. Unmarked ordinary
requests continue to use their existing binding.

Errors use `409 audio_prompt_comparison_unavailable` for invalid/missing
configuration (including an invalid block), owner or window;
`409 audio_prompt_comparison_mismatch` for a slot outside the active block or
handle, identity, body or media drift; and
`409 audio_prompt_comparison_excluded` for service replay or a reopened attempt.
Normal auth/media/quota errors and caller-safe execution failure paths remain
unchanged. No failed or replayed response receives prompt-comparison proof.

Fresh durable success adds the CORS-exposed `X-Merian-Audio-Prompt-Comparison`
header. Its version-1 JSON has `planSha256`, `slot`, `block`, `repeat`,
`caseId`, `arm` (`A` or `B`), `sourceWavSha256`, `processedWavSha256`,
`providerRequestSha256`, `policySha256` and `confidenceSha256`. The native
generated table validates every field and emits separate prompt-lane
receipt/finalization/draw records. The older DSP plan, namespace and receipt
interpretation remain immutable. The
[measurement contract](../development-guides/21-identification-app-measurement.md#prompt-comparison-observation)
defines native subject-state evidence and its limits. Keep the new configuration
unset until the separate
[prompt activation prerequisites](./06-supabase-deployment-runbook.md#audio-prompt-comparison-activation-prerequisites)
are implemented and verified.

### AI authorization and idempotency

Every authenticated route that can dispatch paid model work uses the same
database boundary. Clients should send a UUID `Idempotency-Key`; scan routes use
the exact `client_scan_id`, and chat sends use `client_message_id`. A validated
body request ID takes precedence over the header. The iOS network layer
preserves the same key across transient transport, auth-refresh,
missing-session, and `5xx` retries.

Before provider dispatch, `reserve_ai_quota` first verifies current account
consent, then atomically verifies entitlement, selects the operation's database
policy/model, and consumes daily/user/IP counters. A consent rejection creates
no provider reservation or entitlement consumption. Reusing a key for a
`reserved` or `committed` attempt does not consume or dispatch again: the API
returns `409 ai_request_in_progress` or `409 ai_request_already_completed`. A
previously explicit `refunded` key may be reserved again. `reserved` attempts
carry a ten-minute lease; abandoned leases are automatically refunded, and every
retry receives a new fencing token so a late settlement from an earlier attempt
is rejected. A provider error changes `committed` to `failed`: the original
counters remain charged, but the same key may begin a newly metered attempt.
This reservation protects cost idempotency; by itself it does not promise to
replay a prior HTTP response body. The scan-specific durable replay contract
below absorbs these quota conflicts when safe completion evidence exists.

Terminal reservations ordinarily prune after 30 days. Exact failed/committed
normal and replay scan reservations remain retained as chronological authority
only while the corresponding owner/scan job is unresolved
`failed_terminal / media_reconciliation_abandoned`. Refunded and unrelated
states retain ordinary retention, and successful recovery or explicit operator
resolution ends the exception.

### Provider-bound identification reservations

The four identification routes build the complete normalized `AIRequest` before
calling `reserveIdentificationProviderCall` in `_shared/aiQuota.ts`. The helper
derives a closed `input_profile` from that request; it never reads a provider,
model, binding or profile selector from HTTP JSON. The service-only
`reserve_identification_quota` nine-argument overload adds this profile to the
existing eight admission inputs and returns it with `provider`, `binding` and
`processor_permission`. An optional recipient-expectation header uses the
compatible ten-argument overload described below. Public Identify JSON payloads
remain unchanged.

The prepared
[3 October Gemini photo return](../rfcs/identification-gemini-photo-return-2026-10-03.md)
changes the catalog assignment for new still photos only. Gemini remains
compatible with existing request/result shapes and confidence readers;
Pro/complimentary uses Pro and free fallback uses Flash. The OpenAI beta
assignment described below is the preceding deployed state. No hosted activation
is claimed.

The backend chooses the assignment. Applicable end-user processing permission
gates that assignment; it cannot select a different provider or fallback. The
beta catalog assigns still-photo rows to the exact OpenAI photo tuple; all other
profiles remain Gemini. The enabled Function bundle was deployed before the
activation migration. The
[beta correction](../incidents/2026-09-beta-openai-consent-gate.md) defers
OpenAI-specific permission collection and enforcement while ordinary onboarding
and processing permission remain required. `identificationInput.ts`
distinguishes descriptions, photos, audio, combined photos/audio and
video-derived frames/audio; compatibility request variants have separate
profiles. Capture indications and lineage conservatively keep sampled video out
of a photo-only lane. This classifies accepted representations, not proof of
biological identity or cryptographically verified capture provenance.

The registry independently recomputes the profile before preparation. Missing,
unknown or mismatched fresh assignment metadata fails with
`503 ai_quota_unavailable` before commitment or dispatch. A missing database
route or denied recipient consent rolls back reservation, counters and held
complimentary credit. Transport corruption cannot authorize inference; an
uncommitted lease retains its existing expiry/refund recovery.

A live or committed reservation returns its existing replay before Edge
assignment validation, even if the duplicate's input differs. Old snapshots stay
unknown where metadata was never recorded. A newly metered retry requires its
previously recorded input profile and gets a separate assignment snapshot under
current policy; it cannot silently change a photo observation into audio under
the same request identifier. Completed scan replay still precedes admission. The
[database schema](./04-database-schema.md#internalai_quota_policies-counters-and-reservations)
owns catalog keys, private quota cores and retention.

A binding's `minimum_client_protocol` gates fresh work using the existing
`X-Merian-Entitlement-Protocol` capability claim. Zero adds no restriction, and
all current Gemini bindings remain zero. Nonzero minima require a recognized
protocol at or above the binding requirement; rejection uses the existing
`426 client_update_required` envelope and rolls back quota/complimentary
effects. The entitlement protocol range remains 1–3. Identification capabilities
4 and 5 are a separate contract and does not raise the global cutoff. This is
compatibility evidence, not authentication or end-user provider selection.

Fresh internal retries ignore any worker protocol header. They require accepted
protocol evidence from the exact original owner's reservation and current
attempt with the same operation, observation and complete-input profile. Old
attempts with no evidence stay unknown and cannot unlock a gated assignment.
Minimum and accepted protocol snapshots remain internal; neither Identify DTOs
nor RPC return shapes change. In-progress/committed quota replays and completed
result/status recovery do not re-evaluate current binding minima. Compatibility
endpoints currently recover through the multimodal endpoint; that changes the
profile (and audio operation). Such transformations remain supported by current
zero-minimum Gemini bindings but do not inherit eligibility for a future gated
binding. Qualifying that recovery path requires a separate durable origin
mapping and provider review. The new identification capability is independent of
the global entitlement protocol. A global entitlement cutoff is not a provider
switch.

Migration `20260927175708_prepare_openai_photo_routing.sql` adds the exact
dormant photo tuple and a separate `provider_model`. The quota policy model and
limits are unchanged; the new reservation returns the saved execution model.
That migration left rows on Gemini; the later beta activation assigns still
photos to OpenAI. The native app adds `p_identification_protocol: 5` to the
six-argument preflight and `X-Merian-Identification-Protocol: 5` to the final
request alongside the recipient expectation. Edge recognizes exactly 4 or 5 and
uses the eleven-argument reservation. Missing headers on external requests keep
legacy ABIs. Internal retries use the eleven-argument ABI with a NULL capability
claim and may omit the recipient expectation; the database recovers proof from
the original attempt. Every supplied expectation still rejects assignment drift.
Invalid or expectation-less capability headers return
`400 ai_identification_preflight_invalid`. No client field chooses a provider.

Bindings store `minimum_identification_protocol` (0 or 4), and new attempts
store that minimum plus recognized `accepted_identification_protocol` (4, 5 or
NULL). Older attempts remain unknown. Internal retries use the original exact
owner/operation/observation/profile generation, not a worker claim. Fresh legacy
admission cannot dispatch an OpenAI tuple. Current photo composition supports
the closed OpenAI tuple; the dormant primary-resolution foundation does not add
another producer or change that assignment.

Capability 4 covers the requesting client's V2 decoder. The separate
[result-reader boundary](#identification-result-readers) checks the current
reader on direct PostgREST reads and completed-result replay. Release a capable
app before enabling V2 results; submission-time capability cannot authorize
another device's history reads.

Apply `20260926174645_add_identification_input_routing.sql`,
`20260926182547_add_identification_recipient_recovery.sql`,
`20260926200227_add_identification_client_compatibility.sql`,
`20260926213316_add_identification_recipient_preflight.sql`,
`20260927165545_accept_openai_identification_provenance_v2.sql`,
`20260927175708_prepare_openai_photo_routing.sql`,
`20260927185833_require_identification_result_reader.sql` and their predecessor
migrations before deploying these Edge callers through the exact-SHA release
procedure. The legacy eight-argument identification RPC and both
`reserve_ai_quota` ABIs remain compatible and Gemini-gated. New callers never
fall back to them if the routing overload is missing. This infrastructure does
not itself activate OpenAI or enable consent collection. Subsequent beta photo
activation and consent deferral are recorded in the
[photo rollout](../rfcs/identification-openai-photo-rollout-2026-09-28.md). The
new primary-resolution migration is also dormant preparation: it preserves
current assignments and requires completed consumers plus separate model
qualification before any explicit-primary producer can be activated. V2
confidence remains unqualified for statistical interpretation.

### Primary identification usage RPCs

`commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)` and
`complete_identification_invocation(uuid,uuid,uuid,text,jsonb)` are service-only
accounting RPCs. The first requires the exact owner, reservation, lease and
attempt plus validated execution provenance, returns
`{invocation_id,
may_dispatch}`, and combines commitment with a unique witness.
Only `may_dispatch=true` permits the current invocation. The second accepts
bounded native usage facts, returning the immutable event UUID; replay cannot
replace that event.

The primary Identify response, iOS DTO and stored result provenance shapes do
not change. `ai_usage_events.outcome` adds `unknown` for missing reports. A
`success` event denotes a provider draft, independently of eventual scan
persistence. The private reconciler, scan-trigger ownership marker, pricing
eligibility, account lifecycle and compatibility coverage are specified in the
[database contract](./04-database-schema.md#primary-identification-attempt-accounting).

### Assigned-recipient preflight

The additive authenticated RPC `get_my_identification_preflight` prepares a
future native recipient check. The native identification client calls it during
request preparation. The existing Capture allowance preview remains unchanged
and serves a different purpose: this RPC reports recipient readiness, not
available quota.

| Input                       | Type              | Meaning                                                                           |
| --------------------------- | ----------------- | --------------------------------------------------------------------------------- |
| `p_operation`               | text              | `scan_identification`, or `scan_audio_identification` only with `audio_compat_v1` |
| `p_input_profile`           | text              | One of the nine complete-input profiles below; `legacy_v1` is not a preview input |
| `p_flash_fallback_eligible` | boolean           | Prospective eligibility for the complete outgoing observation                     |
| `p_original_analysis_id`    | UUID              | This request's `client_scan_id`, not the parent observation of a refinement       |
| `p_client_protocol`         | integer, nullable | Client capability claim; null means unknown; non-null values must be 1–1000       |

The new six-argument overload additionally accepts nullable
`p_identification_protocol`. Exactly 4 and 5 are recognized; 5 also reserves
support for explicit primary-resolution results. The native source now
advertises 5; this does not change `p_client_protocol` or the entitlement
header. The five-argument ABI stays available to older callers and returns
update-required for any binding requiring the new capability.

Accepted profiles are `description_compat_v1`, `vision_compat_v1`,
`audio_compat_v1`, `multimodal_text_v1`, `multimodal_photo_v1`,
`multimodal_audio_v1`, `multimodal_photo_audio_v1`, `multimodal_video_frames_v1`
and `multimodal_video_audio_v1`. Video profiles represent sampled image
snapshots, plus audio where present, rather than a native-video model input.

Identity comes only from `auth.uid()`. There is no account or provider selector,
media, description or location input. Shape and eligibility are advisory hints;
Edge still derives the actual profile and eligibility from validated evidence.
The RPC returns exactly one row:

| Field                     | Type              | Meaning                                                                                                       |
| ------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `input_profile`           | text              | Echo of the validated prospective profile; not proof of the saved input shape                                 |
| `decision`                | text              | `ready`, `permission_required`, `client_update_required`, or `recovery_only`                                  |
| `processor_permission`    | text, nullable    | App-assigned recipient: `google_gemini` or `openai`; null for recovery-only or a global protocol denial       |
| `minimum_client_protocol` | integer, nullable | Greater of global and binding requirements; global minimum alone when it denies early; null for recovery-only |

The six-argument result adds nullable `minimum_identification_protocol`: 0 or 4
for an assignment, NULL for recovery-only or early global denial. Native readers
check it independently of `minimum_client_protocol` and reject unknown
ready/permission minima. A positive future minimum can still signal an explicit
update-required decision.

The global supported-protocol gate runs before recovery and entitlement,
matching public Identify. A caller-owned live or committed reservation then
returns `recovery_only`, without looking up a new binding or inventing
historical recipient proof. Fresh work resolves paid/trial, legacy free,
scan-specific held/consumed complimentary funding, available complimentary
credit, then eligible Flash. It checks the exact policy binding, client
compatibility and the assigned recipient's current consent stream. Missing or
disabled bindings raise `ai_provider_assignment_unavailable`; denied entitlement
raises `ai_entitlement_required`; invalid shape/required inputs raise
`identification_preflight_invalid_request` (`22023`); missing identity raises
`authentication_required` (`42501`). These are PostgREST errors, not Edge error
envelopes. Consumers must fail closed on missing, malformed or unknown results.

`ready` is advisory. Preflight creates no reservation, counters, credit hold,
consent event or provider call. It neither promises daily/rate allowance nor
records approval of a provider. The app owns assignment; processing permission
can only allow or block that assigned recipient.

A client integrating this contract sends the checked recipient in
`X-Merian-Identification-Recipient`, or `recovery_only` for recovery-only work.
The shared Edge admission helper accepts exactly `google_gemini`, `openai`, or
`recovery_only`; other values return `400 ai_identification_preflight_invalid`
if admission is reached. The header is an untrusted, denial-only expectation,
not a signed preflight token or evidence of consent. It never changes
assignment. The service-only ten-argument reservation compares it to the fresh
binding within the existing quota transaction. A mismatch, including
recovery-only after a reservation expires or is pruned, returns
`409 ai_identification_preflight_changed` and rolls back counters, reservation,
attempt and complimentary-hold effects. It creates no provider lease or
automatic fallback. A change of model within the same permitted recipient is not
rejected by this recipient-only check; all other admission and qualification
gates apply.

Live/committed duplicates retain non-dispatchable replay behavior. Completed
result lookup remains before admission. Refunded, failed and expired requests
require fresh admission. Headerless clients continue through the nine-argument
ABI, and eight-argument workers remain compatible; a caller using the new header
never falls back to an older overload on failure.

Native `identify` and `identify-multimodal` preparation derives this metadata
from the exact outgoing body off-main. The authenticated fixed-route RPC uses
the configured pinned Supabase transport and a five-second request timeout. A
missing RPC, unavailable response, unknown decision, wrong profile or malformed
row blocks inference; there is no headerless fallback. The expectation survives
live request reconstruction, Auth/transport retries and the prepared background
URLRequest. Foreground attempts recheck the local owner, exact live generation
and recipient permission before each dispatch. Background preparation rechecks
queue generation and the local gate after each dispatch-related suspension;
completed-result recovery still comes first.

`409 ai_identification_preflight_changed` preserves the observation and lets
durable recovery prepare a new request with a fresh preflight. Permission and
`426 client_update_required` denials pause the saved scan without recording a
network circuit failure. A legacy OpenAI denial still saves needs-attention
before releasing its durable owner, but beta recovery presents an explicit retry
without permission collection. Required Gemini onboarding/synchronization
remains in place. These controls cannot choose another provider or manufacture a
receipt. The photo connection advertises identification capability 5
independently of entitlement protocol 3. Preflight is not an activation path or
evidence of model qualification. Deploy the additive backend contract before
distributing a native build that requires it. See the
[native implementation record](../rfcs/identification-native-recipient-preflight-2026-09-26.md).

### Scan response replay

The `identify-multimodal`, `identify-describe`, `identify`, and `audio-spec`
routes dispatch through the internal
[`_shared/ai/` boundary](../../services/supabase/functions/_shared/ai/README.md).
Their fixed Gemini bindings preserve admitted models, modality-specific settings
and schemas, confidence, and public responses. Main description mode retains its
own schema separately from legacy description. Ordered snapshots, accepted
partial frame sets, and included audio remain inference evidence; playback video
remains a storage/finalization input. Adapter outcomes do not become durable
results until existing owner persistence/finalization succeeds. Legacy image
safety and model/tier settings and legacy audio prompt/token budgets remain
separate profiles. `audio-spec` retains the `scan_audio_identification` quota
operation; the other identification routes retain `scan_identification`.
Compatibility replay intents still target the primary endpoint under its
existing admission and recovery rules. Successful execution configuration is
also saved as bounded immutable `scans.identification_provenance` with an atomic
ingestion-job recovery copy. These fixed facts share the scan's existing Data
API visibility; they contain no evidence or owner/attempt identifiers. Client
`recovery_scan` cannot assert provenance: missing scan insertion reads only the
exact server-owned backup, and legacy/no-backup results remain null. Fresh
Identify envelopes now include optional `data.identification_provenance` from
that same admitted execution snapshot. The executable contract and generated
Swift DTO own its closed versioned shape: bounded provider/binding/model,
variant/operation/policy, prompt/schema/confidence references, nullable
diagnostic and safety settings, timeout, and generation settings. The value
preserves the exact five-field Gemini generation object in version 1. Version 2
uses provider `openai` and an exact three-field generation object:
`max_output_tokens`, `reasoning_effort`, `image_detail`. The generated decoder
selects the version before decoding its generation object; unknown versions,
mixed settings and extra keys fail. Activated OpenAI photo assignments use V2;
other inputs retain their configured provider assignments. Admission and the
result-reader boundary require identification capability 4 or 5 before returning
V2 to an external client; entitlement protocol remains 3. The value contains no
observation or personal data and never enters the model-output schema. Omission
means legacy; an explicitly null or malformed Identify field is rejected.
Required nullable settings retain explicit null when decoded and re-encoded.
Stored envelopes retain their original metadata or original omission. Older
completed jobs reconstruct from the immutable owner scan column; null/missing
columns omit the field, while damaged present metadata fails validation. Neither
path consults today's provider assignment or makes an inference request.

The dormant primary-resolution contract adds optional non-null
`data.primary_identification`: exactly `version: 1`, `resolution`,
`scientific_name` and `common_name`. Resolution is `species`, `genus`, `family`,
`unresolved_biological` or `non_biological`. Both names are required keys with a
sanitized 1–255 UTF-16-unit string or explicit null; the object is bounded to 4
KiB. Species/genus/family require a scientific name; unresolved biological
requires null. The biological flag and top-level names must exactly agree with
the snapshot. The reserved provenance schema `merian_identify_primary_v1`
requires this field, and other schemas reject it. No current profile produces
this schema, and the live Gemini/OpenAI model-output contracts are unchanged.

Explicit non-species results require null candidates and pet identification, no
species enrichment and no new-species flag. Species results allow zero to two
alternatives, each declaring `taxon_rank: "species"`; legacy candidates omit it.
The snapshot does not qualify a model score or prove taxonomic correctness.

Migration `20260929144441_prepare_primary_identification_resolution.sql` adds
matching immutable scan/job snapshots. Both snapshots and provenance are copied
in one owner-scoped transaction. Replay verifies their agreement, retains the
original labels rather than replacing them from today's dictionary, and checks
biological/species-association contradictions before any dictionary query. An
invalid stored envelope can reconstruct from a valid matching scan; a lost or
conflicting required snapshot is an integrity failure. If an owner insert
commits between the initial job read and the scan read, replay re-reads its
exact owner backup before comparing. Client `recovery_scan` never supplies this
field. The generated Swift DTO maps to native `PrimaryIdentification`; V53 saves
the original label and rank on live/queued completion and owner history. Missing
required snapshots, contradictory flags and duplicate identity changes fail
validation. Broader results retain their labels and a genus/family caption,
while species hydration, candidates, references, novelty and species statistics
require species rank. Typed review cannot promote that rank. Validated
confirmation authority is now consumed by the dormant native review/history
path. Shared consumers now evaluate original AI evidence separately from
verified species selection. Public labels, Field Chat, species totals, Field
Trip credit and new export snapshots retain that distinction. The native reader
source now advertises protocol 5 across preflight, dispatch, retries and SDK
reads. It accepts existing minimum-0 Gemini and minimum-4 OpenAI assignments,
and recognizes a future minimum 5 without accepting arbitrary higher versions.
The capability claim does not register or activate a new producer. Deploy the
additive backend before distributing this app; signed install-over verification
remains a release gate. See the
[implementation sequence](../rfcs/identification-primary-resolution-contract-2026-09-29.md).

Owner history selects `identification_provenance` and `primary_identification`.
SwiftData stores provenance in the field introduced by V52 as content-free JSON
bytes in optional `LocalScanRecord.identificationProvenanceData`; V51 rows
migrate to nil. Missing legacy cloud metadata cannot erase an existing value.
Malformed history rows remain quarantined with raw-row pagination intact. Both
provenance versions use the same opaque JSON storage. The separate V53
primary-identity migration adds snapshot and reserved confirmation storage; it
does not change provenance or the existing confidence policy. Recognized exact
V1 Gemini profiles retain the existing confidence presentation. The exact V2
`openai_photo_v1` profile separately receives display-only Strong (`>= 0.95`),
Possible (`>= 0.60` and `< 0.95`), or Weak (`< 0.60`) labels on every plan tier.
Recognition explicitly allows the original prompt `openai_identify_vision_v1`,
`openai_identify_vision_observed_traits_v1` and the active
`openai_identify_vision_confidence_v1` with the same `merian_openai_identify_v1`
schema and all other exact configuration checks. Observed-traits changes its
trait instruction and schema description; the confidence revision changes the
confidence instructions and description. Provenance V2 and response
fields/bounds remain unchanged. Saved results keep their original prompt
identity. After the additive backend/migration prerequisites above are deployed,
distribute the updated native reader before deploying this prompt revision:
older readers decode this shape but show Needs review for the new prompt.
Capabilities 4/5 do not distinguish these prompt revisions. The app presents
these as model estimates; neither `openai_unqualified_v1` nor the stored score
changes. Unknown or damaged present profiles use neutral review guidance.
Absence keeps legacy behavior. These display thresholds do not qualify OpenAI
for candidate filtering, automatic verification, sharing recommendations,
rewards, public metrics, or the historical evaluator's strong/diagnostic
metrics. The separate `identification_openai_confidence_assessment_v1` study
measures named-answer confidence with a frozen taxonomy and its own report; it
does not qualify automatic policies or alter historical reports. Each native
prompt now owns an explicit display mapping. The original and observed-traits
mappings stay 0.95/0.60; revised confidence also retains that fallback until its
study passes. The completed study selected no cutoff. Production now selects
this prompt through the existing photo binding, while its assessment binding
remains evaluation-only. The owner reports a released reader and has explicitly
requested production activation; see the
[activation record](../release-evidence/openai-confidence-activation-2026-09-30.md)
for deployment evidence and reader-verification limits. There is no new response
field or primary-rank capability. See the
[assessment contract](../rfcs/identification-openai-confidence-assessment-2026-09-30.md)
and
[display threshold decision](../rfcs/identification-openai-confidence-display-2026-09-28.md).
This compatibility rule is not empirical calibration, and public Explore
suggestion projections still require separate provider qualification. See the
[server provenance record](../rfcs/identification-provider-result-provenance-2026-09-26.md)
and
[client integration record](../rfcs/identification-client-result-provenance-2026-09-26.md)
for rollout order and remaining activation work. The admission and replay rules
below remain authoritative.

`/identify-multimodal`, `/identify`, `/identify-describe`, and `/audio-spec` use
the canonical scan UUID as both the response identity and paid-provider request
identity. Before resolving staged media or reserving quota, each route loads
`scan_ingestion_jobs` by both `scan_id` and authenticated `user_id`. A
`complete` job with its owner scan returns `200` and
`X-Merian-Idempotent-Replay: stored|reconstructed` when the current caller can
read its metadata. An unsupported V2 reader receives the `426` below instead.

### Identification result readers

Migration `20260927185833_require_identification_result_reader.sql` preserves
the two `scans` SELECT policies' existing owner/public visibility predicates.
Each policy evaluates the invoker helper
`internal.require_identification_result_reader` only after its original
visibility condition succeeds. Null/V1 metadata remains readable by older
clients when no explicit primary result is present. A visible V2 row requires
the exact normalized PostgREST header `x-merian-identification-protocol: 4` or
`5`. The primary-resolution migration adds the two-argument reader helper and
requires exactly 5 whenever a primary snapshot or its required schema marker is
present. The one-argument helper remains a compatibility wrapper and still
recognizes the schema marker. A missing, malformed or unsupported claim raises
SQLSTATE `PT426` with message `client_update_required` and a fixed update hint.
This applies even when a query omits the provenance column. A mixed page fails
as a whole rather than filtering out newer results. Invisible private, non-live
or tombstoned rows do not trigger a reader error.

The native `MerianSupabaseClientFactory` supplies
`X-Merian-Identification-Protocol: 5` globally for SDK reads, including history
pages, single-scan recovery and metadata update/readback. The constant is shared
with identification dispatch. It describes decoder capability only: it grants no
identity, visibility, processing permission or provider choice. Existing table
grants, update-column restrictions and service-role projections remain
unchanged. Source scores and immutable provenance are never rewritten.

All four identification endpoints apply the same current-reader check at every
stored/reconstructed completion emission, including quota and ingestion races.
Their service client bypasses table RLS, so they cannot rely on that RLS or the
original producer's capability. Unsupported callers receive the standard Edge
`426 client_update_required` envelope without result data. The primary handler
also checks fresh V2 emission. Only the separately service-authenticated
internal replay worker bypasses the client decoder check; inbound worker-like
headers do not grant that exception. This reader failure makes no new provider
call.

The current native UX classifies the exact PostgREST code/message pair and the
Edge HTTP-status/stable-code pair through the shared update flow. Account-lease
and inference-generation checks precede effects. A dismissed prompt never clears
paused work, and same-build manual retry cannot re-enable blocked work. The
[presentation contract](../system-architecture/10-event-and-presentation-routing.md#update-required-presentation)
owns app-version recovery and the App Store destination.

OpenAI V2 needs a verified capability-4-or-5 reader; explicit-primary results
need capability 5. Deploy the additive reader/storage backend before
distributing the capability-5 app, and verify its signed upgrade before
separately activating a qualified explicit producer. Older binaries may show
their existing generic history-sync error, retain local observations, and fail
to hydrate mixed cloud history until updated; this change cannot add an upgrade
screen to an installed old binary. Null/V1-only reads continue normally. Turning
fresh assignments back to Gemini does not remove this reader requirement while
V2 rows exist. Keep the guard and compatible readers during rollback.

### Completed-result recovery

Migration `20260728220000_persist_idempotent_scan_responses.sql` makes current
completions persist the executable-contract-validated success envelope inside
the same transaction that proves scan/media completion. Persistence is immutable
for that generation and excludes raw media bytes. Older complete jobs without an
envelope reconstruct a conservative valid response from the exact owner scan and
species summary. Deletion-request and owner-removal triggers clear the stored
response.

If quota reports the same scan UUID as in progress or already completed, the
route waits up to 70 seconds for the original invocation to reach that boundary
and then replays success. It never makes a second provider call. Only an
unresolved or malformed completion may fall back to the stable `409`; current
iOS retains the queued scan and shows **Restoring scan** rather than a network
timeout for the four exact replay codes.

Shared authorization errors are:

| Status | Code                                                        | Meaning                                                                                    |
| ------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `400`  | `ai_request_id_invalid`                                     | Supplied body/header request key is not a UUID                                             |
| `402`  | `pro_required`                                              | Operation is disabled for the effective plan                                               |
| `426`  | `client_update_required`                                    | Public identification client does not implement the cutover entitlement protocol           |
| `409`  | `ai_request_in_progress` / `ai_request_already_completed`   | Duplicate paid-provider attempt; an in-progress response retries after the remaining lease |
| `429`  | `ai_quota_daily_exceeded`                                   | Database UTC-day safety ceiling reached                                                    |
| `429`  | `ai_user_rate_limit_exceeded` / `ai_ip_rate_limit_exceeded` | Shared minute ceiling reached                                                              |
| `503`  | `ai_entitlement_unavailable` / `ai_quota_unavailable`       | Durable authorization could not be verified                                                |

Rate-limit and temporary entitlement responses may include both the
`Retry-After` header and `retry_after_seconds` JSON field. Clients must not
silently fall back to a paid tier or alternate model on any of these failures.

### Complimentary entitlement protocol and metadata

Authenticated clients read their current server state through the Supabase RPC
`get_my_entitlement()`. It returns one own-account row with:

| Field                      | Type    | Meaning                                                                        |
| -------------------------- | ------- | ------------------------------------------------------------------------------ |
| `current_plan`             | string  | `pro_paid`, `pro_complimentary`, `free`, or pre-cutover/historical `pro_trial` |
| `current_tier`             | string  | Functional `pro` or `free`                                                     |
| `is_paid`                  | boolean | Raw current paid status; authoritative for public Pro badges                   |
| `scans_remaining`          | integer | Grant minus consumed credits, including in-flight holds                        |
| `scans_available_to_start` | integer | Credits that can fund a new primary Pro analysis                               |
| `in_flight_count`          | integer | Active held credits                                                            |
| `entitlement_version`      | integer | Monotonic account-plus-rollout version                                         |

The RPC derives its owner from `auth.uid()` and accepts no target user ID.
Failures to verify current state fail closed for complimentary-only client
behavior.

After atomic cutover, public requests to all four scan-producing routes must
send `X-Merian-Entitlement-Protocol: 3`:

- `/identify`
- `/identify-describe`
- `/identify-multimodal`
- `/audio-spec`

Missing or obsolete public protocol receives `426 client_update_required` before
provider dispatch. Authenticated server replay bypasses only this public
protocol comparison and retains the exact original `client_scan_id`, owner,
quota, and credit linkage.

A successful scan envelope may contain the additive top-level member below. The
member is optional so historical stored envelopes remain decodable.

```json
{
  "success": true,
  "data": { "scan_id": "scan-uuid" },
  "entitlement": {
    "user_id": "authenticated-owner-uuid",
    "plan_used": "pro_complimentary",
    "credit_consumed": true,
    "entitlement_after": {
      "current_plan": "pro_complimentary",
      "current_tier": "pro",
      "is_paid": false,
      "scans_remaining": 2,
      "scans_available_to_start": 2,
      "in_flight_count": 0,
      "entitlement_version": 43
    }
  }
}
```

`plan_used` records the funding classification retained by the original
analysis. `credit_consumed` records whether the durable result is funded by a
consumed complimentary row; on replay it does not mean the replay invocation
performed a second transition. Clients validate `user_id` and apply
`entitlement_after` only after a current-launch `get_my_entitlement()` baseline
has succeeded and only when its version is not stale.

Flash fallback is server-classified from the accepted evidence shape. It uses
the independent daily free policy and returns `plan_used = "free"`; an exhausted
balance permits a non-video photo or standalone audio plus at most one note, or
one description alone, only while that daily allowance remains. Video-derived
evidence, additional physical media, multiple descriptions, and Pro-only work
remain ineligible.

The normative balance equations, settlement rules, offline behavior, and rollout
fence are in [`18-complimentary-pro-scans.md`](./18-complimentary-pro-scans.md).

> **Important IDOR Constraint:** The `user.id` resolved by the Deno Edge
> Function from the Supabase JWT is always a **lowercase** Postgres UUID format.
> Swift's `UUID().uuidString` evaluates to uppercase by default. Therefore, the
> iOS client must explicitly lowercase any user UUID injected into
> `r2ObjectKeys` payloads; otherwise, the case-sensitive string matching
> (`!r2ObjectKey.startsWith`) will fail the IDOR check and return a
> `403 Forbidden`.

```json
{
  "r2ObjectKeys": [
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_1.webp",
    "staging/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/uuid_filename_2.webp"
  ],
  "imageBase64s": [
    "<base64 encoded string array for instant processing within the shared aggregate budget>"
  ],
  "user_id": "Supabase Auth UUID linking via GoTrue Session",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "depthScaleText": "1.2 meters",
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Sunny",
  "weatherTemperatureF": 72.5,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 3,
  "timeOfDay": "2:00 PM",
  "timestamp": "2026-03-21T09:46:03.000Z",
  "zoomFactor": 2,
  "estimated_size_cm": 15.2,
  "description": "Small brown moth, roughly 2 cm wingspan, spotted resting on bark at night",
  "observation_context": {
    "organism_class": "Insect",
    "colors": ["brown", "grey"],
    "size": "small",
    "habitats": ["woodland", "garden"],
    "behaviors": ["resting", "nocturnal"],
    "markings": "subtle eyespot pattern on forewings",
    "textures": "dusty wing scales",
    "free_text": "Found near porch light after dark"
  }
}
```

`description` is an optional plain-text string generated client-side by
`ObservationContext.serialized()` — a pre-rendered prompt summary of the user's
structured observation. The Foundation-only value declaration lives in
`Models/Media/ObservationContext.swift`; Capture owns staging and request
projection rather than a second wire model. The rendered string is appended to
the Gemini context at the edge function to ground identification before the
vision model runs. `observation_context` is the full structured JSON object
matching that iOS value; it is persisted server-side as
`public.scans.user_observation_context` (JSONB) and lands in the local
mixed-media scan representation via `LocalScanRecord.observationContextsJSON`,
the scalar `capturedMediaJSON` timeline, and the V41 `capturedMediaEntries`
relationship mirror. Both fields are `null` for image-only scans. The edge
function accepts an array guard (`!Array.isArray(observation_context)`) before
writing to prevent an accidental array submission from being persisted as
malformed JSONB.

`zoomFactor` is sent when the capture used a non-default camera zoom. The Edge
function persists it to `public.scans.zoom_factor` for owner-facing context such
as Insight scan information and Field chat; it is omitted for 1x captures and
non-visual submissions.

`currentMonth` and `timeOfDay` are derived from the image's own capture date
(`telemetry.timestamp`) when available — not always from the current wall clock.
For gallery photos with a valid EXIF date, this ensures Gemini receives the
correct season and light context for the original photo (e.g., an October photo
scanned in April sends `Month: 10`, not `Month: 4`). Falls back to current
date/time for live captures and gallery photos with no EXIF.

`timestamp` is omitted (null) for gallery photos with no EXIF date rather than
sending the current submission time. The server defaults `scans.timestamp` to
`now()` in that case, which honestly represents when the scan was submitted.
`deviceTimeZone` (IANA identifier, e.g. `"America/Los_Angeles"`) and
`deviceRegion` (ISO 3166-1, e.g. `"US"`) are permission-free geographic signals
sent as fallback context when GPS is not authorised. The Edge function injects
them into the Gemini context string as `TZ:` and `Region:` tokens alongside
`Locale:`, `Month:`, and `Time:` — grounding the model's regional species priors
without requiring location permission. `deviceTimeZone` is also persisted to
`scans.device_time_zone` for timezone-aware public profile streaks and heatmaps;
`deviceRegion` remains inference-context only.

`geoprivacy` is optional for backward compatibility. Valid values are `open`,
`obscured`, and `private`. When absent or invalid, the Edge insert helper reads
`users.default_geoprivacy`. Private scans may still persist exact owner-owned
telemetry, but public projections are scrubbed: public coordinates,
`coordinate_uncertainty_in_meters`, and `public_location_label` are cleared by
insert helpers and database triggers. Current iOS clients omit
`publicLocationLabel` when `geoprivacy == "private"` and send sanitized labels
for open/obscured scans.

### The JSON Response Schema (From Gemini Back to Swift)

To optimize API expenditures, the `identify` Deno Edge node uses two strategies:

- **Model Routing**: The vision identification call routes effective Pro users
  to `gemini-2.5-pro` (maximum depth for rare species, fossils, subspecies, and
  cultivars) and effective free users to `gemini-2.5-flash` (2–3× lower
  latency). Effective Pro includes paid subscribers and accounts with an
  available or in-flight complimentary Pro scan. The server does not trust an
  iOS tier hint. Protocol-2 identification routes atomically call the extended
  `reserve_ai_quota` before provider work; that transaction resolves paid Pro →
  complimentary Pro → free, links the original analysis, acquires a credit hold
  when applicable, selects an allowlisted model from
  `internal.ai_quota_policies`, and consumes separate daily/user/IP provider
  counters under the request idempotency key. Text-only enrichment currently
  selects `gemini-2.5-flash` through the same database policy. A missing user
  row, entitlement query failure, disabled/missing policy, or unsupported model
  fails closed before Gemini. Both identification models use the structured
  schema generated from `merianModelContract`.
- **Conditional biological fields**: The static executable contract makes
  biological-only fields optional and nullable. The runtime parser enforces the
  response shape, and the processed-material guard independently demotes
  manufactured or processed source-material false positives. Neither boundary
  determines which visible object occupies the primary-subject role. **Geology
  Bypass**: Gemini's prompt explicitly instructs the LLM to output
  `scientific_name` and `common_name` for identifiable geological subjects
  despite `is_biological_subject=false`. This surfaces rocks cleanly in the iOS
  layer while routing them out of the main biological dictionary.

**Visual primary-subject guidance and current enforcement boundary**:
`/identify` and the image-only branch of `/identify-multimodal` use
`getSystemInstruction(...)`. That provider instruction asks Gemini to select the
intended whole-frame visual subject before taxonomy, using relative area,
centrality, focus, framing, repeated coverage, and explicit observation text as
evidence. A client `focusRegion` from Vision objectness is only a tentative
saliency hint. Under that guidance, a laptop filling the frame should remain
non-biological when plant leaves are merely in the background, at the periphery,
in a reflection, or on a display/depiction.

This is model guidance, not a trusted post-parser classification. Runtime
validation proves the response structure; `normalizeProcessedMaterialSubject`
can demote manufactured/processed objects, but no current runtime guard can
infer visual prominence or independently demote a plausible plant result because
the plant was incidental. A provider false positive can therefore still pass
validation and reach dictionary/persistence work.

Mixed image+audio requests use the separate
`MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION`, retain the established visual/acoustic
arbitration, and do not currently interpolate the complete image-only
primary-subject instruction. A still photo with an accepted `focusRegion`
receives the tentative per-photo warning; unhinted stills and sampled video
frames do not. The base `merianModelContract.is_biological_subject` description
also flows into blended generation and is inherited by
`merianDescribeModelContract`; its current visual-only wording is a known
cross-modality semantic mismatch, not a universal enforcement rule.

Because the changed executable contract/schema modules are shared, the
repository deployment planner selects `audio-spec`, `identify`,
`identify-describe`, and `identify-multimodal` together. Validation or green CI
does not authorize deploying those functions.

The canonical source for every model and final response key is
`services/supabase/functions/_shared/identify/contract.ts`. It generates the
provider schema and Swift wire DTO block, infers the deployed TypeScript
payloads, and recursively validates live values. Provider output is validated
immediately after JSON syntax extraction. After name sanitization, cache
hydration, candidate enrichment, and server-added fields, the complete
`{ "success": true, "data": ... }` envelope is validated again before
persistence or HTTP success.

Successful Identify responses always contain `blur_score`, `colors`,
`candidates` (nullable), `estimated_size_cm` (nullable), `image_quality`, and
`pet_identification` (nullable); the contract rejects an omitted key even though
generated root Swift properties remain optional for staggered rollout
compatibility. The Describe model contract also rejects `is_live_capture=true`
and nonzero image-quality values.

For an intentional response change, edit the executable contract, run
`make generate-edge-dto-contract`, review the generated
`InferenceEdgeDTOs.swift` diff, and run `make validate-edge-dto-contract`. Do
not hand-edit or extend a generated wire DTO. The final server contract is
strict; generated root Swift properties are optional only to support older
cached payloads and staggered rollout.

> **Image format**: All images in this pipeline are encoded as lossy **WebP**
> (`image/webp`). The `inlineData.mimeType` field passed to the Gemini SDK in
> `index.ts` must always be `"image/webp"`. Gemini 2.5 Flash and Pro both accept
> `image/webp` natively. If this value is changed to `image/jpeg` while the
> actual bytes are WebP, Gemini will reject or misinterpret the payload.

**`common_name` source**: On **Cache Miss** (first-ever scan of a species),
`common_name` is taken directly from the Gemini vision model output. On **Cache
Hit**, `index.ts` overrides the Gemini-supplied `common_name` with the canonical
`species_dictionary.common_names.en` value so repeat scans of the same species
always show a consistent display name regardless of which Gemini response
generated it. Cache-miss writes preserve an existing `common_names.en` and only
fill it from the scan when the dictionary row does not already have an English
name, preventing a single malformed scan label from overwriting canonical
species naming. The Swift decoding layer applies `.capitalized` on rendering for
display consistency. For geological targets, it relies wholly on the Gemini
output (no cache override applies).

**`pet_identification` source**: Dog and cat scans may include a separate
display object when the primary species is `Canis lupus familiaris` or
`Felis catus`. This object is not taxonomy. It is sanitized after Gemini
generation and dropped when the label is generic, below `0.70` confidence, or
attached to any non-dog/cat taxon. Dog labels may be a breed or visible mix; cat
labels prefer visible coat pattern or body type unless a true breed is visually
supported. Clients can use the label for Insight, search, sharing, and Explore
display, while `common_name` and `scientific_name` remain authoritative.

**`is_new_to_merian_dictionary` source**: The biological identify routes
(`/identify`, `/identify-multimodal`, `/identify-describe`, and `/audio-spec`)
return this boolean in the client payload. It is `true` only when the scan is a
biological subject and the initial `species_dictionary` lookup found no existing
row for the normalized scientific name. iOS decodes the field as
`SpeciesData.isNewToMerianDictionary` and uses it to show the bottom in-app
`New to Naturebook` milestone notification. Do not infer global dictionary
novelty from missing enrichment fields such as `alternative_common_names`; cache
gaps, GBIF gaps, and partial rows are not milestone signals. Existing dictionary
rows with incomplete taxonomy/enrichment are still treated as not new to the
Naturebook dictionary.

**Audio subject semantics**: Audio-only `/identify-multimodal` requests and the
compatibility `/audio-spec` route share one subject-selection instruction,
private provider contract, and structural normalizer. The provider contract
requires an internal `audio_subject_type` discriminator so Human breathing can
be distinguished from unresolved non-human wildlife without reading model
reasoning. The discriminator is validated, consumed, and removed before payload
assembly. The wire shape is unchanged; no audio-only response field, DTO,
database column, or public wire version is introduced, and the image/Describe
model contract remains generic.

| Primary audio evidence                                            | `is_biological_subject` | `common_name`           | `scientific_name` |
| ----------------------------------------------------------------- | ----------------------- | ----------------------- | ----------------- |
| Resolved non-human animal, including wildlife, pets, or livestock | `true`                  | Resolved common name    | Resolved taxon    |
| Confident non-human animal presence with unresolved species       | `true`                  | `Unidentified Wildlife` | Omitted / `null`  |
| Human-only biological sound                                       | `true`                  | `Human`                 | `Homo sapiens`    |
| No confident biological source                                    | `false`                 | `No Wildlife Detected`  | Omitted / `null`  |

Audio confidence V2 defines the existing `confidence_score` by result state:

| Audio result                   | Confidence target                                         | Species-match presentation |
| ------------------------------ | --------------------------------------------------------- | -------------------------- |
| Identified non-human           | Returned taxon, supported by diagnostic acoustic evidence | Existing tier bands        |
| Unidentified non-human         | Non-human animal presence only                            | Hidden                     |
| Human only                     | Returned Human identity                                   | Existing Human badge       |
| No confident biological source | Source-classification decision                            | Hidden                     |

Clear animal presence cannot inflate confidence in a guessed taxon. When calls
cannot support taxonomy, return unresolved wildlife; location, season and local
abundance cannot inflate acoustic confidence. These scores remain model
estimates, not calibrated probabilities. Parsing checks shape and bounds, not
acoustic truth. Both audio-only prompts and the private schema share this
definition; blended image/audio retains its separate contract. No stored or
replayed score is rewritten.

A confidently detected non-human animal always outranks Human in the same
recording. Human-only speech, breathing, coughing, snoring, or another
unmistakable biological human sound is a resolved Human result; handling noise
alone is not. Unresolved wildlife, Human, and non-biological audio return no
candidates. Unresolved wildlife does not enter dictionary enrichment because it
has no scientific name. The post-parser guard combines the private structured
discriminator with exact identity fields, canonicalizes Human aliases such as
malformed `Homo sapien`, and never classifies from `ai_reasoning`. Mixed
visual/audio inference applies the same acoustic non-human-over-Human tie-break
while retaining the existing cross-modal arbitration. A resolved non-human
animal retains its normal candidates. When that result has a blank, unresolved,
or incorrectly Human common name, the server uses the resolved scientific name
as the display fallback rather than changing the non-human classification.

iOS treats Human as biological but suppresses candidate review, external
reference imagery, Explore/Community sharing, and Field Chat. Audio-only
unresolved biological records suppress species-match confidence and sharing.
Historical `Unknown Subject` / `Taxonomy Unavailable` audio remains immutable
compatibility data: the client presents safe unresolved copy and offers
reanalysis when source media is available rather than inferring Human from old
reasoning or migrating stored rows.

Historical owner sync preserves the stored `is_biological_subject` value. Both
the shared iOS Explore-eligibility predicate and `/share-scan-to-explore`
independently reject explicit non-biological state, missing/unresolved selected
taxonomy, Human taxonomy (including legacy malformed `Homo sapien`), and a Human
user override. Ask the Community reuses that server validator. `/insight-chat`
independently requires a resolved, non-Human selected taxonomy rather than
relying on toolbar visibility. Neither endpoint derives eligibility from stored
reasoning. Field Trip progress independently requires resolved non-Human
taxonomy and the existing tier threshold or explicit confirmation. High presence
confidence and confirmation cannot override an ineligible subject. Human
override edits also invalidate the atomic progress receipt and withdraw prior
credit.

**Processed-material guardrail**: The identify routes demote manufactured or
processed objects to `is_biological_subject=false` before cache lookup,
dictionary upsert, candidate enrichment, or milestone evaluation. Wool rugs,
kilims, leather goods, wooden furniture, paper/cardboard, cotton or linen
fabric, prepared food, toys, artwork, ornaments, and species depictions are not
biological observations even when made from biological material. The response
keeps the object `common_name` when useful for the non-biological result, clears
source-species `scientific_name`, strips candidates, and never sets
`is_new_to_merian_dictionary`. iOS also treats `is_biological_subject=false` as
authoritative during decode, forcing `SpeciesData.isNewToMerianDictionary=false`
and `SpeciesData.candidates=nil` even if a stale or malformed Edge response
includes those fields.

Processed-material response shape:

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": false,
  "is_live_capture": false,
  "is_new_to_merian_dictionary": false,
  "common_name": "Wool Kilim Rug",
  "scientific_name": null,
  "confidence_score": 0.82,
  "candidates": null,
  "insight_data": {
    "ai_reasoning": "The subject is an inanimate, man-made textile rather than an organism.",
    "hazard_type": "none"
  }
}
```

Operational cleanup for historical pollution is intentionally manual. Use
`services/supabase/scripts/repair_processed_material_scan_pollution.ts` in dry
run first; apply mode only patches rows whose scan evidence explicitly contains
artifact/process terms and then nulls scan species links, marks the scan
non-biological, clears biological metadata, and restores/removes polluted
dictionary English names.

**Critical Edge Limitation (Gemini 2.5):** The model returns `400 Bad Request`
when enum fields include descriptive strings. `ecology_type` must be formatted
as a structural JSON `enum: ["wild", "urban", "domesticated", "unknown"]`
constraint in the Deno schema.

```json
{
  "scan_id": "Generated via crypto.randomUUID() on Deno Edge",
  "is_biological_subject": true,
  "is_live_capture": true,
  "is_new_to_merian_dictionary": false,
  "ecology_type": "wild",
  "scientific_name": "Danaus plexippus",
  "common_name": "Monarch Butterfly",
  "pet_identification": null,
  "confidence_score": 0.98,
  "blur_score": 0.1,
  "is_invasive": false,
  "invasive_status_region": "Central Texas",
  "invasive_rationale": "The original AI assessment did not flag this species as invasive for the scan region.",
  "invasive_confidence": 0.78,
  "colors": ["orange", "black", "white"],
  "estimated_size_cm": 15.2,
  "life_stage": "adult",
  "reproductive_condition": "not_applicable",
  "sex": "female",
  "sex_confidence": 0.84,
  "sex_evidence": "dimorphic wing pattern",
  "individual_count": 1,
  "ecological_interactions": ["pollinating Asclepias syriaca"],
  "extracted_visual_traits": [
    "orange and black wing pattern",
    "white-spotted margins",
    "ventral silver spots"
  ],
  "insight_data": {
    "ai_reasoning": "The distinctive orange and black wing pattern with white-spotted margins, combined with the milkweed habitat context, is diagnostic for Danaus plexippus. The ventral hindwing silver spots confirm this is not the mimicking Viceroy.",
    "hazard_type": "none"
  },
  "// Cache Hit only — sourced from species_dictionary:": "",
  "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
  "wikipedia_overview": "The monarch butterfly or simply monarch is a milkweed butterfly in the family Nymphalidae...",
  "reference_image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Monarch_In_May.jpg/320px-Monarch_In_May.jpg",
  "taxonomy": {
    "kingdom": "Animalia",
    "phylum": "Arthropoda",
    "class": "Insecta",
    "order": "Lepidoptera",
    "family": "Nymphalidae",
    "genus": "Danaus"
  },
  "iucn_red_list_status": "least_concern",

  "// Cache Hit, all tiers — sourced from species_dictionary (REST, not AI-generated):": "",
  "gbif_taxon_key": 5130978,

  "// Cache Hit, all tiers — sourced from species_dictionary:": "",
  "species_insights": {
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains."
  },

  "// Cache Hit — sourced from species_dictionary.alternative_common_names (populated from GBIF vernacular names on first enrichment):": "",
  "alternative_common_names": ["Monarch", "Common Tiger"],

  "// Present when confidence_score < diagnosticTrigger (0.99 both Flash and Pro — intentionally above strong threshold so Strong match scans can still persist candidates as an escape hatch). Server strips to null at or above 0.99. Client display is separately gated by CandidateReviewVisibilityPolicy. See _shared/identify/thresholds.ts.": "",
  "candidates": [
    {
      "scientific_name": "Limenitis archippus",
      "common_name": "Viceroy",
      "confidence_score": 0.71,
      "distinguishing_feature": "Hindwing black postmedian band broader and more irregular than Monarch"
    },
    {
      "scientific_name": "Danaus gilippus",
      "common_name": "Queen",
      "confidence_score": 0.58,
      "distinguishing_feature": "Forewing lacks white spots in the black apex band"
    }
  ]
}
```

> **Vision schema lean principle**: The vision model response (`identify`) is
> optimised strictly for identification and ecosystem measurement.
> Data-as-a-Service fields (`estimated_size_cm`, `life_stage`,
> `reproductive_condition`, `sex`, `sex_confidence`, `sex_evidence`,
> `individual_count`, `ecological_interactions`) are fully generated on the
> primary pass avoiding secondary inference loops. `extracted_visual_traits`
> executes a Micro-CoT pass before taxonomic grouping to anchor the model to
> reality and avoid visual pareidolia. `insight_data.ai_reasoning` is always
> present for biological subjects because it is the Gemini vision model's
> per-scan reasoning about the specific photo submitted. LLM field caps are
> declared in the structured model contract and enforced again in `index.ts`
> after scientific name sanitization. All model `NUMBER` fields use explicit
> `0...1` bounds. Image-quality integer bounds are `1...10` for `sharpness`,
> `framing`, and `diagnostic_utility`, and `0...100` for `overall_score`;
> `individual_count` is `1...99999`. The DTO deployment validator requires
> finite bounds for every numeric schema before accepting the corresponding
> Swift wire type. Runtime caps remain defense in depth: `colors`,
> `extracted_visual_traits`, and `ecological_interactions` are each capped at 10
> items; `ai_reasoning` is truncated to 2000 characters; `individual_count` is
> validated as a positive integer <= 99999; client-supplied `estimated_size_cm`
> is validated as a positive finite number <= 50000; and `candidates` is capped
> at 5 items before `payloadReadyForClient` is built. GPS coordinates are
> range-checked and out-of-range values are sanitized to `null` rather than
> aborting identification. `taxonomy`, `iucn_red_list_status`, `gbif_taxon_key`,
> `species_insights`, and `alternative_common_names` are species-dictionary
> cache fields, not scan-specific model output. `similar_species` is never
> included in the `identify` response; it is generated asynchronously by
> `/enrich-scan`, and iOS renders validated entries with the stable "Similar
> species" label. `hazard_type` inside `insight_data` comes from
> `species_dictionary` on Cache Hit; on Cache Miss the live response defaults to
> `"none"` until later enrichment fills species-level hazard metadata.
> `pet_identification` is optional and nullable. For a confident dog scan, the
> value may look like
> `{"species_group":"dog","label":"Australian Cattle Dog mix","label_type":"breed_mix","confidence_score":0.82,"evidence":["blue-roan ticking","black saddle patch","compact herding-dog build"]}`.
> The stored species would still be `Domestic Dog` / `Canis lupus familiaris`.
>
> `candidates` is required in `merianModelContract`; biological subjects are
> instructed to return exactly 2 alternatives, while non-biological subjects
> return an empty array. The identify routes strip candidates to `null` when
> `confidence_score >= diagnosticTrigger` (`0.99` for both Flash and Pro),
> preserving candidates for Possible, Weak, and Strong biological scans below
> that near-certain threshold. Non-biological and processed-material results are
> stripped to `null` regardless of confidence. Candidates are scan-specific and
> persist to `public.scans.candidates` plus `LocalScanRecord.candidatesData`,
> while client display is separately gated by `CandidateReviewVisibilityPolicy`.
> The server constants in `_shared/identify/thresholds.ts` remain canonical; iOS
> mirrors their Flash and Pro bands in
> `Core/AI/Inference/Result/InferenceConfidencePolicy.swift`. A threshold change
> must update both owners and their focused contract tests in the same change.
>
> **Executable validation**: Numeric bounds, enums, nested required fields,
> nullability, safe-integer semantics, string lengths, and array cardinalities
> above are enforced by the Edge runtime, not only documented in the provider
> schema. Unknown provider/server keys follow the contract's explicit strip
> policy. A malformed provider object returns retryable HTTP `503`. If the final
> server-enriched envelope violates its wire contract, the route returns HTTP
> `502` with stable code `identify_response_invalid` before persistence or
> client delivery.

### Durable Ingestion & Media Moderation

For `/identify-multimodal`, the route completes the owner-row durability work
before returning HTTP `200 OK`. A successful response therefore guarantees the
returned `scan_id` is available to Field Chat, Explore sharing, field trips, and
owner sync. The durability task handles:

1. **Scan-user profile prerequisite** — calls service-only
   `ensure_scan_user_profile(authenticated_user_id)` before the `scans` FK
   insert. An existing profile is unchanged. A missing profile is created only
   for the exact Auth identity with canonical mandatory public-identity fields;
   account deletion, merged-ghost retirement, and cleanup races fail closed.
2. **Content moderation** (`_shared/identify/moderation.ts`) — evaluates Gemini
   safety ratings and promotes media from staging to public storage
3. **Species dictionary enrichment** (Cache Miss only) — calls
   `fetchExternalEnrichment` for Wikipedia/GBIF data
4. **`insertScan`** — writes the final scan row to `public.scans`, including
   sanitized `pet_identification` when present
5. **Owner read-back** — reloads by `scan_id` and authenticated `user_id`;
   duplicate no-op or cross-owner collision cannot be reported as success
6. **Optional post-insert work** — schedules analytics, group tags, and
   candidate enrichment through `EdgeRuntime.waitUntil`

**Media promotion**: Safe image media is moved from
`staging/{userId}/{filename}` to `public_uploads/{tier}/{userId}/{filename}`
inside Cloudflare R2, and the CDN URL
(`https://media.merian.app/public_uploads/...`) is stored in
`scans.image_storage_urls`. For the `imageBase64s` path, the bytes are uploaded
directly to the public destination without a staging step, and `r2ObjectKeys` is
empty: only genuine staged sources belong in the strict ingestion/promotion
manifest. Safe video media is moderated through five sampled frames, then the
staged upload-bounded playback `.mp4` is promoted separately and persisted in
`scans.video_storage_urls`. Multimodal inserts also write
`scans.captured_media`, a canonical ordered media timeline that attaches video
playback URLs and poster thumbnails together; this prevents sampled video
inference frames from hydrating as standalone Insight carousel images. The
required finalization transaction refreshes ready display/playback scan-media
asset rows and proves the canonical representation before ledger completion, so
server-side composer/status reads can prefer lifecycle media rows before falling
back to compatibility arrays. Any image promotion failure aborts the entire
batch and immediately rolls back any already-promoted public objects from that
same batch before returning `ERROR`; scans are not inserted with partial image
arrays. Video promotion failure is also a durability failure for video captures:
the edge cleans up promoted objects/staging where possible and does not insert a
frame-only scan row.

Canonical proof does not reinterpret sampled video inference frames as
standalone user images. After migration
`20260729012153_fix_video_scan_canonical_finalization.sql`, the finalizer
validates the structured captured-media visual timeline when usable; legacy
video rows validate only the standalone image prefix
`max(images - videos × 5, 0)`, every playback video, and standalone audio. Each
projected item must still have a ready normalized row matching the exact scan
owner, kind, and URL. A missing playback row, real standalone image row, audio
row, promoted capture mapping, or claimed storage disposition still fails the
request before completion and before a fresh HTTP `200`.

**Moderation failure handling**: If Gemini's `finishReason === "SAFETY"` or any
`safetyRating.probability` is `"MEDIUM"` or `"HIGH"`, the staging object is
deleted, `users.abuse_strikes` is incremented, and the scan is not inserted. At
3+ strikes `users.is_shadowbanned` is set to `true`; public/social projections
exclude that author. The flag is not currently a blanket veto for every later
safe private scan insert. The rejected current multimodal request returns
generic `400 observation_rejected` rather than a successful phantom scan. See
[Safety & Moderation](../development-guides/10-safety-and-moderation.md) for
full details.

**R2 rollback**: A returned scan-insert rejection is followed by an exact
`(scan_id, user_id)` read. Public objects are deleted through
`deleteR2ObjectIfPresent` only when that read definitively proves the owner row
is absent. A thrown/lost write response, a reported-success response without a
verifiable owner row, or unavailable verification is
`ScanPersistenceOutcomeUnknownError`: the route returns retryable HTTP 503 but
does not fail committed quota, retire staged assets, or delete promoted media
that a committed scan may reference. A same-UUID retry reconciles from the exact
owner row before another provider call. Mid-loop promotion failures still roll
back objects whose creation is known to that promotion batch.

### Error Responses

| Status | Body                                                                                                                              | Meaning                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `400`  | `{ "error": "Bad Request: Path traversal detected." }`                                                                            | `r2ObjectKeys` contains a `../` traversal attempt                                            |
| `400`  | `{ "error": "Forbidden: r2ObjectKey does not belong to the requesting user." }`                                                   | IDOR — key does not belong to the authenticated user                                         |
| `400`  | `{ "error": "We couldn’t process this observation. Please try a different photo or recording.", "code": "observation_rejected" }` | Provider policy or durable media moderation rejected the observation                         |
| `413`  | `{ "error": "Payload Too Large: Combined images exceed 5MB limit." }`                                                             | Combined image payload exceeds 5 MB                                                          |
| `502`  | `{ "error": "AI response validation failed. Please retry.", "code": "identify_response_invalid" }`                                | Final server-enriched payload violated the executable wire contract                          |
| `503`  | `{ "error": "Processing Error: Malformed AI response." }`                                                                         | Gemini returned malformed or structurally invalid output; offline delivery may retry         |
| `503`  | `{ "error": "AI processing error. Please try again." }`                                                                           | Transient Gemini failure (API error, rate limit, timeout, non-SAFETY non-STOP finish reason) |
| `503`  | `{ "error": "We couldn’t finish saving this observation. Please try again.", "code": "scan_persistence_failed" }`                 | Durable moderation pipeline, media promotion, species resolution, or scan insertion failed   |

All producer `SAFETY` / `PROHIBITED_CONTENT` branches and durable moderation
rejections return the exact `400 observation_rejected` envelope. iOS removes
only that rejected queue generation, presents the terminal recapture guidance,
and does not count the outcome against the network circuit. All other Gemini
errors return `503` so the offline queue retries with persisted
`queueNextRetryAt` / `OfflineJobRecord.nextRunAt` metadata. For
`scan_persistence_failed`, an owner-row status probe wins first. If a readable
exact-owner probe proves no scan row exists, the server transitions the
committed provider reservation to `failed` so the stable request UUID can
reserve a fenced metered retry, while iOS clears potentially consumed staged
keys and performs a fresh upload from durable local files. If the insert outcome
cannot be proved, quota and media remain fenced and intact until the next
owner-row recovery. A post-insert failure retains the committed reservation
because owner-row reconstruction is the no-provider-call recovery surface.
Malformed paid-provider output is 503, not 422, and its ingestion ledger remains
`failed_retryable` with a bounded `retry_after`; the linked hold remains held
for same-UUID recovery.

All four scan producers obtain the ordinary `failed_retryable` deadline from
`_shared/scanIngestionRetry.ts`. The default is deterministically 30 seconds for
`identify-multimodal` and the compatibility path used by `identify`,
`identify-describe`, and `audio-spec`. This changes no request or response
field: an explicit server `Retry-After` / `retry_after` remains authoritative to
iOS and may exceed the client's ordinary 30-second local cap within existing
safety bounds.

Migration `20260728232000_ensure_scan_user_profile.sql` must precede deployment
of all four scan-producing Edge bundles. It preserves the mandatory Explore
identity constraints instead of retrying the obsolete partial
`users(id, subscription_tier)` insert that production logs proved could return
503 after provider work.

## The Standardized JSON Return Payload (From Supabase to Swift)

The compatibility `/identify` Edge Function resolves the canonical `scan_id`
from the client idempotency UUID and does not return `data` when Gemini alone
finishes. Profile repair, required media promotion, exact-owner scan insertion,
and complete-last response finalization are attempted and awaited in the
required task. A pre-insert failure returns retryable 503. If only finalization
or bookkeeping fails after exact-owner insertion, the compatibility route may
return its already validated response from that durable owner-row surface while
the ledger remains retryable for no-provider-call reconciliation. Only
analytics, group tags, candidate enrichment, and other nonessential work may run
behind `EdgeRuntime.waitUntil`. Current app traffic uses `/identify-multimodal`;
a fresh provider-owning invocation additionally requires completed canonical
finalization before its initial HTTP success. A later request may return
`X-Merian-Idempotent-Replay: reconstructed` from the exact owner row while the
canonical ledger remains retryable, without another provider call. Both routes
make the same non-negotiable owner-row durability promise.

### Gemini Parsing and Error Mitigation

To prevent ReDoS from hallucinated markdown payloads, the endpoint parses raw
Gemini output using a `substring(indexOf)` approach rather than unbounded regex.
If extraction or executable provider validation fails, the endpoint returns HTTP
503 and marks the exact ingestion generation retryable. The iOS offline queue
therefore retains and backs off the durable job instead of classifying a paid
transient/provider-format failure as terminal.

> **Note on Wikipedia Extraction:** During a "Cache Miss" (first discovery
> globally), the Edge Router fires the Wikipedia HTTP extraction _concurrently_
> alongside Gemini Text Inference latency via a `Promise.all` envelope. This
> guarantees high-resolution encyclopedia metadata maps directly to the user
> natively on the very first roundtrip without requiring the iOS app to skeleton
> load.

```json
{
  "success": true,
  "data": {
    "is_biological_subject": true,
    "ecology_type": "wild",
    "scientific_name": "Danaus plexippus"
  }
}
```

This data contract maps into the Swift Codable layer where nested JSON `Data` is
verified to prevent `JSONDecoder()` failures on double-escaped strings.

```swift
struct IdentifyResponse: Codable {
    let success: Bool
    let data: SpeciesData?
    let error: String?
}
```

**Client Authentication Caveat**: `MerianNetworkClient` abstracts GoTrue
anonymous hardware tokens. The backend extracts cryptographic JWT identity from
the `Authorization: Bearer` header via `supabaseAdmin.auth.getUser()`, ignoring
any `user_id` in the request body. The Swift payload uses the
`SupabaseManager`'s active session UUID only as a proxy string for syncing
RevenueCat identifiers — actual API validation runs over GoTrue JWT verification
only.

**Offline Ghost Overwrite Protection**: Before calling
`SupabaseManager.shared.getValidAuthHeaders()`, the iOS client checks
`UserDefaults.standard.bool(forKey: "Merian_HasAuthenticatedOAuth")`. If an
authenticated user goes offline long enough for their JWT to expire, the Swift
client throws `NetworkError.invalidResponse` immediately. This prevents a guest
UUID from overwriting the user's Pro status or stranding their `.sqlite` data,
and causes `CaptureWorkspaceView` to prompt re-authentication instead.

---

## Public Species Dictionary Edge Node

The separate authenticated `POST /resolve-species-dictionary` accepts a bounded
`scientific_name` and returns a version-1 identity receipt containing
`requested_scientific_name`, `species_id`, and the saved `scientific_name` (the
verified accepted name for a new record). It may materialize one exact
GBIF-verified taxon or fill an exact-name legacy record's missing GBIF key; the
public read below does not write. The receipt binds verified synonym changes,
and iOS requires the follow-up detail UUID to match it exactly. Expected
identity conflicts return a nondisclosing unavailable response. Request limits,
status codes, admission, and rollout ordering are defined by the
[resolver contract](../../services/supabase/functions/resolve-species-dictionary/README.md).

The `/species-dictionary` Edge Function returns species-level dictionary data
for the standalone Species Dictionary Page, Explore Dictionary catalog, and
server-rendered `/species/[speciesId]/[slug]` web route. The UUID-only web route
is retained as a permanent compatibility redirect. It is deliberately separate
from both the Insight scan and Explore post-detail contracts:

- Insight scan data can include local media, user review state, field notes, and
  per-scan AI reasoning.
- Explore detail data can include a public shared scan projection.
- Species dictionary data includes only canonical dictionary fields and
  reference imagery.

Related Explore cards are intentionally fetched afterward through the separate
authenticated `/get-explore-species-posts` contract below; they are never added
to the publicly cached dictionary payload.

The function has `verify_jwt = false` in `services/supabase/config.toml`.
Detail, catalog, and overview requests do not call `requireAuth`; they may
receive normal app auth headers from `MerianNetworkClient`, but identity is not
read and must not affect those responses.

Only a name-only request whose normalized scientific name is absent locally may
use bounded GBIF/Wikipedia enrichment to construct a non-persisted public
fallback. A request that supplied a UUID never reaches external enrichment: an
exact UUID hit wins, a dual UUID/name request may recover only to an existing
local row with that exact normalized name, and a dual miss returns `404`. An
existing ineligible local row also returns `404`. The fallback never invokes
Gemini. Model-backed habitat, lookalike, and group-tag refreshes belong to
authenticated quota-guarded enrichment or service-only scheduled workers; the
anonymous public route is not an alternate provider-cost surface.

The response is built through the shared public species projection in
`services/supabase/functions/_shared/publicSpeciesProjection.ts`. That module
owns common-name fallback, alternate-name dedupe, normalized/legacy
reference-image mapping, nullable taxonomy shape, and contract tests for
private-field leaks. SQL-only Explore detail lookalikes use matching database
helpers so the same species DTO rules apply outside Deno.

### `/species-dictionary`

Request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Compatibility POST bodies are stream-bounded to 4 KiB before JSON decoding.

Validation rules:

- Either `species_id` or `scientific_name` is required.
- `species_id`, when present, must be a valid UUID. UUID lookup runs first. If
  it misses and a scientific name was also supplied, only an exact normalized
  local name match may recover the request; external enrichment is forbidden for
  the complete dual-identity request.
- `scientific_name`, when present, must be a string and non-empty after
  trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.
- The only supported explicit modes are `catalog` and `overview`. The retired
  `tree` mode and every other unknown mode return `400`.

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "id": "uuid",
    "scientific_name": "Danaus plexippus",
    "common_name": "Monarch Butterfly",
    "content_quality": "complete",
    "alternative_common_names": [],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    },
    "hazard_type": "none",
    "iucn_red_list_status": "least concern",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly...",
    "habitat_description": "Often found in open meadows and milkweed patches.",
    "gbif_taxon_key": 5139790,
    "group_tags": ["animal", "insect"],
    "reference_images": [
      {
        "url": "https://media.merian.app/public_uploads/...",
        "source": "merian",
        "license": "Used with permission via Naturebook",
        "attribution": "Ayla E.",
        "author_user_id": "uuid",
        "author_username": "ayla"
      },
      {
        "url": "https://upload.wikimedia.org/...",
        "source": "wikipedia",
        "license": "CC BY-SA 4.0",
        "attribution": "Example Photographer",
        "width": 1200,
        "height": 800
      },
      { "url": "https://static.inaturalist.org/...", "source": "gbif" }
    ],
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://...",
        "iucn_red_list_status": "least concern",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      }
    ]
  }
}
```

`schema_version = 1` marks the current public species contract shared by
`/species-dictionary`, Explore detail similar species, and the public web
species surface. Within this version, new response keys must be additive,
existing nullable fields may remain `null`, and clients should ignore unknown
keys. A versioned endpoint path should be introduced only for a breaking change
such as removing/renaming fields or changing a field's type.

#### Public web consumer

`apps/web/lib/species.ts` validates the route segment as a UUID before invoking
the Edge Function with `{ "species_id": "..." }` through the server-only
Supabase client. It requires `schema_version = 1`, validates the returned
identity, and explicitly maps only public fields. The web route must never query
`species_dictionary`, scan, profile, or Explore tables directly to reconstruct
this response.

The mapper runs `publicWebReferenceImageAttributionIssues(...)` before any
reference image is rendered or selected for Open Graph/Twitter metadata. Images
missing `license` or `attribution` are omitted. Similar-species thumbnails are
not rendered because the current lookalike payload does not carry those rights
fields; name and canonical UUID navigation remain available.

The web canonical path is `/species/{speciesId}/{slug}`. The UUID remains the
only Edge request and identity field; the web layer derives its lowercase ASCII
slug from `common_name`, then `scientific_name`, then `species`. UUID-only and
stale-slug requests redirect after successful UUID resolution, so name changes
require neither a database migration nor an Edge contract revision.

Invalid route UUIDs and marked handler-owned Edge `404` responses map to a
non-indexable Next.js not-found page. An unmarked Edge `404` is a
platform/router failure and remains a server error, as do missing server
configuration, network errors, other Edge failures, unsupported schema versions,
malformed payloads, and identity mismatch. Transient errors are therefore never
cached as missing species. Successful pages revalidate every 300 seconds.

Overview mode:

```json
{ "mode": "overview", "user_region": "US" }
```

The `your_region` category includes the English country title in `region` and
the canonical ISO 3166-1 alpha-2 value in additive `region_code`. Country rows
in `regions` likewise include additive `code`. Counts and representatives come
from `species_country_occurrences`, using exact country equality and positive
GBIF occurrence counts. The underlying provider query is limited to PRESENT,
georeferenced records without geospatial issues; the product language is
"recorded in," never a native-range claim. A valid user country remains in the
response with `count = 0` while its durable backfill is pending, allowing iOS to
show a non-interactive coverage state instead of silently removing the card.
Legacy English region-title matching is retained only when that country has no
normalized occurrence coverage, for deployed-client and backfill compatibility.
Migration `20260901180000_add_public_biological_species_eligibility.sql` makes
`species_dictionary.is_public_biological` a stored generated invariant. It
requires a nonblank scientific name plus either a positive GBIF taxon key or a
non-placeholder kingdom and at least one non-placeholder downstream taxonomy
rank. Overview rows and the country-summary routine apply that exact value
before range reads or aggregation.

Catalog mode:

```json
{
  "mode": "catalog",
  "query": "Danaus",
  "limit": 40,
  "cursor": {
    "scientific_name": "Danaus plexippus",
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
  }
}
```

- `mode: "catalog"` returns a compact cursor-paginated list for the Explore
  Dictionary catalog.
- `limit` defaults to `40` and is capped at `100`.
- `query` is optional, trims/collapses whitespace, and filters scientific names.
- `category: "region"` requires `region`. ISO country codes and English country
  titles normalize to an exact `species_country_occurrences.country_code` filter
  once coverage exists; broad free-text ranges are not treated as canonical
  country membership.
- `cursor` carries the last `scientific_name` and `species_id` returned.
- The generated `is_public_biological` predicate is applied before the query's
  limit and cursor. Partial indexes cover both alphabetical and Recently Added
  keysets, so a page cannot become short merely because ineligible rows occupied
  its pre-filter window.
- Response rows include `id`, `scientific_name`, `common_name`,
  `content_quality`, nullable `taxonomy`, status fields, `group_tags`, and one
  `reference_image_url`; full page content still requires a detail request.

Caching:

- Detail and catalog `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- Overview `200 OK` responses include `Cache-Control: no-store` and
  `Vary: Accept-Encoding`.
- `400`, `404`, and `500` responses do not include public cache headers.
- iOS requires exact `schema_version = 1` and a valid request/response identity
  before adding anything to the 10-minute, 64-key in-memory memo cache in
  `MerianNetworkClient`. It stores only the returned canonical UUID and returned
  normalized scientific name. It never stores a stale requested UUID alias or an
  `external:` ID. The cache is route-local only and never persists species pages
  to disk.
- Refreshed dictionary rows become visible after the iOS memo TTL and public
  HTTP freshness window expire. Future public web curation flows that require
  immediate visibility should add CDN/cache purge tooling to the write path.

Content quality:

- `content_quality` is additive and may be `complete`, `sparse`, or
  `needs_enrichment`.
- The Edge projection classifies quality from four public content signals: at
  least one reference image, a usable Wikipedia overview, habitat/distribution
  data, and meaningful taxonomy.
- `complete` means all four signals are present. `sparse` means two or three
  signals are present. `needs_enrichment` means fewer than two signals are
  available.
- iOS treats the field as optional and estimates the same state for older
  payloads. Sparse and needs-enrichment pages render an intentional status card
  rather than leaving the missing sections unexplained.
- iOS sends species dictionary analytics through `AppTelemetry` to PostHog.
  Events include `entryPoint`, `contentQuality`, and image `source` where
  relevant; species names, species IDs, scan IDs, Explore post IDs, user
  locations, field notes, comments, image URLs, and review state are not
  attached.

Name and imagery mapping:

- `common_name` resolves from `common_names.en`, then the first non-empty
  `common_names` value, then `scientific_name`.
- `alternative_common_names` is trimmed, deduped, and excludes the resolved
  primary common name.
- `reference_images` prefers ordered rows from `species_reference_images`. Each
  item includes `url` and `source`, plus optional `license`, `attribution`,
  `width`, and `height` when present. A currently promoted `merian` item also
  includes `author_user_id` and the contributor's current `author_username` when
  its promoted private source row matches the species and exact image URL;
  external items never receive those fields.
- If no normalized image rows exist, `reference_images` falls back to the
  comma-separated `species_dictionary.reference_image_url` field by splitting,
  trimming, and deduping URLs.
- `source` is `merian` for Merian-published app media, `wikipedia` for
  Wikimedia/Wikipedia hosts, and `gbif` for external occurrence imagery. If
  `wikipedia_url` exists, the first unresolved legacy image also maps to
  `wikipedia`; otherwise unresolved legacy images map to `gbif`.
- Normalized rows are ordered Merian first, then Wikipedia, then GBIF.
- Normalized rows and legacy strings are filtered through
  `_shared/externalImagePolicy.ts` before source mapping or first-image
  selection. The current exact rule removes every original/resized/query variant
  below `inaturalist-open-data.s3.amazonaws.com/photos/605615444/`. If it was
  first, the next permitted ordered image is promoted. If none remain, existing
  image fields are empty/null according to their existing types; no moderation
  field is added and the species or lookalike row is not removed.
- `similar_species` is hydrated from `species_lookalikes` using the explicit
  PostgREST hint `species_dictionary!lookalike_id` and includes `species_id` for
  canonical tap-through routing. Similar-species thumbnails prefer the first
  normalized `species_reference_images` row and fall back to the legacy
  dictionary cache. Additive relation metadata includes `reason`,
  `visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
  and `sort_order`; rejected rows are omitted from public projections.

Image licensing and attribution:

- `species_reference_images.license` and `species_reference_images.attribution`
  are the canonical public media rights fields.
- `/species-dictionary` preserves `license` and `attribution` on each normalized
  `reference_images` item when the metadata exists. Legacy comma-separated
  fallback images usually have only `url` and `source`.
- For a promoted Naturebook image, the Edge data layer uses the private source
  row's stable `(species_id, image_url)` key to resolve only the public author
  ID and current username. This works even if the nullable `reference_image_id`
  link is absent. Scan IDs, post IDs, source media indexes, confidence data, and
  locations remain private.
- iOS shows a truncated, tappable `@username` badge over Naturebook images and
  opens the existing public profile sheet. It renders no attribution/license
  footer below the species gallery. The fullscreen viewer uses its bottom
  overlay for fuller credit: `@username · Naturebook` for Naturebook images,
  without falling back to stored display-name or permission wording, or external
  attribution/license/source metadata when present. A Naturebook image missing
  username data shows only the source label.
- The web species mapper calls `publicWebReferenceImageAttributionIssues(...)`
  from `_shared/publicSpeciesProjection.ts` before rendering reference media or
  selecting metadata images, and omits any image with missing license or
  attribution.

Provenance and refresh metadata:

- The response shape does not yet expose provenance fields.
- Dictionary writers record field-level source/freshness rows in
  `species_content_provenance` for common names, alternate names, taxonomy,
  Wikipedia content, habitat, GBIF keys, reference images, group tags,
  hazard/conservation fields, and lookalikes.
- `refresh-species-content` uses `public.get_species_content_refresh_queue(...)`
  as its legacy fallback rather than scanning `species_dictionary` directly for
  stale content. First-class `gbif_wikipedia_reference` jobs come from
  `species_enrichment_jobs`; `refresh-species-model-content` owns the paired
  `habitat`, `lookalikes`, and `group_tags` jobs. Common-name overrides,
  conservation, and hazard data remain curation-owned.
- Reference image refreshes call `public.replace_species_reference_images(...)`
  so normalized rows stay aligned with the legacy compatibility cache while
  preserving existing license/attribution metadata.

Error responses:

| Status | Body                                                                       | Meaning                                                                     |
| ------ | -------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `400`  | `{ "error": "Missing required parameter: species_id or scientific_name" }` | Missing, non-string, or blank lookup                                        |
| `400`  | `{ "error": "species_id must be a valid UUID." }`                          | Invalid species ID                                                          |
| `400`  | `{ "error": "scientific_name must be a string when provided." }`           | Non-string scientific name was supplied alongside a valid species ID        |
| `400`  | `{ "error": "scientific_name is too long." }`                              | Scientific name exceeds the request bound                                   |
| `404`  | `{ "error": "Species not found" }`                                         | UUID-only miss, dual UUID/name local miss, or existing ineligible local row |
| `500`  | `{ "error": "Internal Server Error" }`                                     | Database or unexpected function failure                                     |

Swift mapping:

```swift
MerianNetworkClient.shared.getSpeciesDictionary(scientificName:)
MerianNetworkClient.shared.getSpeciesDictionary(speciesId:scientificName:)
```

decodes into `SpeciesDictionaryResponse` / `SpeciesDictionaryEntry` in
`Core/Network/SpeciesDictionaryAPIModels.swift`, which contains wire DTOs only.
`Core/Network/SpeciesDictionaryIdentity.swift` owns canonical UUID/name and
cache key normalization. The six existing detail/catalog/overview/stats read
variants and the authenticated resolution method live in
`Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift`;
`Decoding/SpeciesDictionaryResponseValidator.swift` owns typed schema/identity
checks and `Caching/SpeciesDictionaryResponseCache.swift` contains the locked
per-client detail/stats memos. `MerianNetworkClient` keeps that cache instance
private; its fixed-result request bridges perform lookup, authenticated load,
validation, and insertion without exposing cache mutation to endpoint callers.
It retains private configuration, Auth, transport, retries, and cancellation.
`Features/SpeciesDictionary/Shared/Models` owns the route, entry-point,
taxonomy, and cross-surface reference-image presentation values; Detail Models
adapt hydrated lookalikes and detail-only quality policy.

The client canonicalizes UUIDs and drops invalid, synthetic, or `external:`
route IDs. A usable name then becomes a name-only request. On response, an exact
requested UUID is accepted even if its display-name hint was stale; a changed
UUID is accepted only for dual-identity local recovery with the same normalized
name. A name-only response must match the requested name and return either a
canonical UUID or an `external:` identity. Schema/identity validation occurs
before cache insertion.

---

## Public Species Observation Stats Edge Node

The `/species-observation-stats` Edge Function returns public, global
iNaturalist observation aggregates for a species. It is deliberately separate
from local Merian observation aggregation:

- iOS aggregates local `LocalScanRecord` data on-device through
  `SpeciesObservationStatsDatabaseActor` and `SpeciesObservationStatsReducer`.
- The Edge Function receives only `species_id` and `scientific_name`.
- The Edge Function returns only public iNaturalist-derived species aggregates
  and cache metadata.

The function has `verify_jwt = false` in `services/supabase/config.toml` because
anonymous public reads remain supported. The first-party iOS client sends its
normal session headers. A valid JWT adds a per-user rate bucket; a missing
header or project publishable/anon key uses only the IP bucket; an invalid
supplied user token returns `401`. Every request consumes the atomic IP
preflight before optional token validation, so malformed tokens cannot amplify
Auth traffic. Identity never changes the response body.

### `/species-observation-stats`

Preferred request:

```text
GET /functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

Compatibility request body:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

Validation rules:

- `species_id` is required and must be a canonical RFC-variant dictionary UUID
  using version 1...8. Dictionary rows are UUIDv4 today; accepting newer
  versions keeps the HTTP parser aligned with the database identity boundary.
- `scientific_name` is required.
- `scientific_name` must be a string and non-empty after trimming.
- Internal whitespace is collapsed before lookup.
- Names longer than 160 characters return `400`.
- A service-only database RPC binds the UUID to its canonical normalized name.
  Unknown UUIDs and mismatched names return `404` before provider work.

Current response shape:

```json
{
  "schema_version": 2,
  "data": {
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "scientific_name": "Danaus plexippus",
    "source": {
      "provider": "inaturalist",
      "scope": "global",
      "inaturalist_taxon_id": 48662,
      "fetched_at": "2026-05-17T12:00:00.000Z"
    },
    "status": "fresh",
    "total_observations": 450448,
    "last_observation_date": "2026-05-17",
    "fetched_at": "2026-05-17T12:00:00.000Z",
    "provider_errors": [],
    "seasonality": [{ "month": 5, "count": 1200 }],
    "history": [{ "year": 2026, "month": 5, "count": 1200 }],
    "life_stage": [
      {
        "key": "adult",
        "label": "Adult",
        "values": [{ "month": 8, "count": 100 }]
      }
    ],
    "sex": [
      {
        "key": "female",
        "label": "Female",
        "values": [{ "month": 8, "count": 12 }]
      }
    ]
  }
}
```

`schema_version = 2` marks mandatory dictionary identity and the bounded
population path. The response shape remains compatible with version 1. New
response keys must be additive, existing nullable fields may remain `null`, and
clients should ignore unknown keys. The current iOS client requires schema
version 2 or newer, checks the returned UUID and normalized scientific name
against the request, and does not cache a legacy or identity-mismatched
response. It also rejects malformed UUIDs and names outside the 1...160
character bound before making a network request.

Status values:

- `fresh`: provider fetch completed and data exists.
- `no_data`: exact taxon resolution found no match, or the provider completed
  but no observation buckets were found. The result is negatively cached.
- `partial`: one or more provider buckets failed, but useful data is still
  available. On cold cache misses, core stats may be returned as `partial` while
  life-stage and sex annotation buckets refresh in the background. If provider
  calls fail and no useful bucket exists, the result is `unavailable`, not an
  empty `partial`.
- `stale`: a usable stale cache payload was returned while refresh work is
  deferred off the response path.
- `unavailable`: provider refresh failed and no usable cache existed.

Series shapes:

- `seasonality`: month-of-year counts, `month` in `1...12`.
- `history`: rolling monthly counts from January of current year minus six
  through the current month.
- `life_stage`: category series with month-of-year values.
- `sex`: category series with month-of-year values. This remains part of the
  backend payload for provider parity, but the current iOS chart does not render
  Sex as a tab; per-scan AI sex appears in the Overview card.

iNaturalist mapping:

- Taxon lookup prefers `species_dictionary.inaturalist_taxon_id`.
- If absent, the current lease owner resolves the canonical database
  `scientific_name` exactly through `/v1/taxa`.
- Observation and histogram calls require a positive `taxon_id`. There is no
  caller-controlled `taxon_name` fallback.
- Observation totals and latest dates use `/v1/observations`.
- Seasonality, history, life stage, and sex use `/v1/observations/histogram`.
- Life Stage annotation IDs use `term_id = 1` with values Adult `2`, Teneral
  `3`, Pupa `4`, Nymph `5`, Larva `6`, Egg `7`, Juvenile `8`, and Subimago `16`.
- Sex annotation IDs use `term_id = 9` with values Female `10`, Male `11`, and
  Cannot determine `20`.

Caching:

- Backend cache table: `species_observation_stats_cache`.
- Cache key: `species_id + source + scope`.
- Source: `inaturalist`.
- Scope: `global`.
- Fresh TTLs: seven days (`fresh`), 24 hours (`no_data`), one hour (`partial`),
  and five minutes (`unavailable`).
- Positive data has a 30-day additional stale window. Negative `no_data` has a
  seven-day stale refresh window; `unavailable` is never served stale.
- Cold misses fetch taxon lookup, observation summary, seasonality, and history
  synchronously, then queue life-stage and sex annotation refresh via
  `runBackground`.
- Usable stale rows return immediately. A 90-second database lease suppresses
  cross-isolate duplicate refreshes; fenced finalization prevents an expired
  generation from overwriting newer work.
- If that refresh fails, a positive payload within 37 days of its original
  `fetched_at` remains intact. Finalization marks it `stale`, records the latest
  row-level cache `provider_error`, preserves its original age, and applies a
  five-minute retry backoff. Cold/negative/too-old rows instead use the
  five-minute `unavailable` cache.
- Atomic request limits are 60/user/minute and 120/IP/minute. Cold population
  additionally allows 12/user/minute, 30/IP/minute, and four globally/minute.
- Every provider fetch has a five-second timeout. Foreground/background work has
  15/45-second deadlines and each response body is stream-limited to 1 MiB.
- Database RPCs and cache reads are client-aborted after five seconds; the
  privileged RPCs independently enforce a five-second statement timeout.
- Fresh and `no_data` `200 OK` responses include
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`.
- `partial`, `stale`, and `unavailable` `200 OK` responses use
  `Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=300`
  and `Vary: Accept-Encoding`.
- Successful payloads do not vary by Authorization because identity affects only
  abuse accounting, not the public body. This avoids per-token cache
  fragmentation. Errors remain `private, no-store` and vary by Authorization.
- iOS adds a 5-minute, 64-alias-key in-memory stats memo in the per-client
  `Core/Network/Caching/SpeciesDictionaryResponseCache` owner, keyed by
  normalized `species_id` and scientific name. It is separate from the 10-minute
  detail memo; TTL is insertion-time and reads do not refresh it. Only
  schema-v2-or-newer responses with an exact canonical identity match enter that
  cache.

Privacy:

- Local Merian logs are never sent to Supabase.
- The response must not include scan IDs, user IDs, Explore post IDs, field
  notes, comments, user locations, local media, local observation counts, or
  preferred-name overrides.

Error responses:

| Status | Code                                                  | Meaning                                            |
| ------ | ----------------------------------------------------- | -------------------------------------------------- |
| `400`  | `species_stats_invalid_request` or validation message | Missing/invalid UUID or bounded name               |
| `401`  | `invalid_session_token`                               | Invalid supplied user credential                   |
| `404`  | `species_stats_species_not_found`                     | Unknown dictionary UUID or canonical-name mismatch |
| `413`  | validation message                                    | Compatibility POST body exceeds 4 KiB              |
| `429`  | `species_stats_rate_limited`                          | Request or cold-population budget exhausted        |
| `503`  | `species_stats_refresh_in_progress`                   | Another isolate owns the cold lease                |
| `503`  | `species_stats_unavailable`                           | Database/security boundary unavailable             |

`429`/`503` retry responses include `retry_after_seconds` and `Retry-After`.
Every error response is `private, no-store`.

Swift mapping:

```swift
SpeciesObservationStatsDependencies.live
// Services adapts MerianNetworkClient.getSpeciesObservationStats(
//     speciesId:scientificName:
// ) for the feature ViewModel.
```

decodes into `SpeciesObservationStatsResponse` / `SpeciesObservationStatsEntry`
in `SpeciesObservationStatsAPIModels.swift`.
`Core/Network/Endpoints/MerianNetworkClient+SpeciesDictionary.swift` maps the
authenticated GET's ordered ID/name query. The client's fixed-result stats
bridge retains the 20-second deadline and exclusively accesses its private memo
through lookup, authenticated load, validation, and insertion.
`SpeciesDictionaryResponseValidator` checks typed schema/identity before cache
insertion; raw wire-decoding errors are not remapped. Core Network's
authenticated dispatcher retains private per-attempt Auth/session dispatch, and
its request-scoped executor retains the shared retry, cancellation-checkpoint,
and Auth-recovery behavior. `Services/SpeciesObservationStatsDependencies.swift`
is the live endpoint adapter; `SpeciesObservationStatsViewModel` never resolves
the network client directly. The view model combines that public baseline with
local SwiftData aggregates for `SpeciesObservationChartsCard`, which currently
renders seasonality, history, and life-stage series.

---

## Explore Edge Nodes

Explore traffic is intentionally separate from the identify pipeline. The iOS
client uses dedicated Edge Functions for feed reads and social interactions, all
authenticated through the same Supabase session headers used elsewhere in the
app.

### Explore Public Identity Contract

Explore payloads distinguish between the public display label and the canonical
handle:

- `author_name`: display label for Explore rows. Logged-in authors with safe
  provider/account names keep labels such as `Emre E.`.
- `author_username`: stable public username stored without `@`. Clients render
  it as `@author_username` for profile handles and for default/ghost author
  rows.
- `author_avatar_url`: optional copied public avatar projection.

`public_author_name` is not a mention handle. Comment mentions and other
handle-based features must use `public_username` / `author_username`. The field
is additive and optional for rollout tolerance; older clients may ignore it.

### `/get-explore-species-posts`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns visibility-safe Explore cards whose effective canonical species is the
requested dictionary UUID. Confirmed identifications use the confirmed species;
community-resolved observations use the projected resolved taxon. Genus-level
and merely similar-species posts do not match.

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "limit": 30,
  "before_image_quality_score": 87,
  "before_shared_at": "2026-07-14T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

- `species_id` must be a UUID and `limit` must be an integer from 1 through 100.
- Omit all cursor fields for the first page. `before_shared_at` and
  `before_post_id` must be supplied together. An omitted/null quality field with
  those two fields represents a cursor in the unscored tier.
- Ordering is `image_quality_score DESC`, then `shared_at DESC`, then post UUID
  descending. Null quality scores sort after every scored post.
- The response is `{ "data": [<standard Explore cards>], "next_cursor": ... }`.
  `next_cursor` contains the three ordering fields or is `null` when exhausted.
- `image_quality_score` is never included in a card. It is used only inside the
  service-role RPC and in `next_cursor`.
- Image, video, audio, legacy, and text-first presentation variants use the
  standard Explore card/media metadata and species reference-thumbnail fallback.
- The shared Explore projection continues to exclude unshared, tombstoned,
  blocked, shadowbanned, identification-pending, and media-less posts.
- The SQL RPC grants `EXECUTE` only to `service_role`; clients call the
  authenticated Edge Function, never PostgREST directly.

### `/get-explore-feed`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns public Explore feed cards for the shipped `recent`, `following`,
`trending`, `nearby`, and `liked` modes. The backend routes to a dedicated SQL
RPC per mode and already filters out:

- unshared posts
- tombstoned scans
- scans with no remaining published image, video, or audio media
- shadowbanned authors
- both directions of user blocking

Post `location_sharing` controls public location output, not ordinary feed
visibility. `private` posts can still appear in Recent, Following, Trending,
Liked, profile, hashtag, and detail surfaces, but their public location fields
are empty. The `nearby` filter is spatial and uses post-owned public
coordinates; for non-owned posts this means only saved
`location_sharing = "open"` posts with a stored public coordinate can match the
radius query.

Primary request shapes:

Recent feed, which is also the default when `filter` is omitted:

```json
{
  "limit": 20,
  "filter": "recent",
  "before_shared_at": "2026-04-28T21:18:00.000Z",
  "before_post_id": "uuid"
}
```

Liked feed uses `filter: "liked"` with the same cursor and advanced-filter
fields as Recent. Only the authenticated viewer’s current likes on visible
observations qualify; ordering is by shared date, not like time. Identity comes
from the validated JWT, never a request-supplied user ID. The response shape is
unchanged. Deploy the SQL migration and Edge support before distributing an app
that sends this filter.

Following feed:

```json
{
  "limit": 20,
  "filter": "following",
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Trending feed:

```json
{
  "limit": 20,
  "filter": "trending",
  "before_ranking_value": 12,
  "before_shared_at": "2026-05-02T16:45:00.000Z",
  "before_post_id": "uuid"
}
```

Nearby feed:

```json
{
  "limit": 20,
  "filter": "nearby",
  "latitude": 30.2672,
  "longitude": -97.7431,
  "nearby_radius_miles": 25,
  "before_shared_at": "2026-05-03T11:22:00.000Z",
  "before_post_id": "uuid"
}
```

Optional advanced filters for every mode:

```json
{
  "species_categories": ["birds", "insects"],
  "media_types": ["audio", "video"],
  "shared_since": "2026-06-26T12:00:00.000Z"
}
```

Validation rules:

- `recent`, `following`, `nearby`, and `liked` page on
  `(shared_at DESC, post_id DESC)`. Omit both cursor fields for the first page.
- `following` returns only posts by followed authors that remain visible to the
  requester.
- `trending` pages on `(ranking_value DESC, shared_at DESC, post_id DESC)`. The
  cursor is only valid when `before_ranking_value`, `before_shared_at`, and
  `before_post_id` are all supplied together.
- `nearby` requires both `latitude` and `longitude`.
- `nearby_radius_miles` is used only by `nearby`, defaults to `50`, and must be
  between `1` and `100`.
- `species_categories` accepts the same taxonomy groups as Explore Map:
  `plants`, `fungi`, `birds`, `mammals`, `reptiles`, `amphibians`, `fish`,
  `insects`, `arachnids`, and `other`.
- `media_types` accepts `image`, `audio`, and `video`; mixed-media posts match
  when any saved public media item has a selected kind.
- `shared_since` is an inclusive ISO-8601 cutoff over `shared_at`.
- Values are OR-ed within species/media groups and AND-ed across all populated
  groups. The SQL RPCs apply them before ordering and `LIMIT`; clients must not
  fetch a page and discard non-matching rows locally.
- `before_ranking_value` is rejected for `recent`, `following`, `nearby`, and
  `liked`.
- `trending` is freshness-biased rather than all-time top. The ranking value is
  the post's like activity from the trailing 30 days.
- `nearby` reads `explore_posts.public_latitude` / `public_longitude` and limits
  non-owned coordinate-bearing posts to the requested radius around the supplied
  viewer location before applying recency sort. `obscured` and `private` posts
  remain visible in non-spatial feeds but do not expose coordinates for Nearby.

`Recent` remains the iOS default for first load and for the Explore-tab unread
badge refresh path.

Current response shape:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-26T17:22:11.000Z",
      "author_user_id": "uuid",
      "author_name": "Emre E.",
      "author_username": "emre_e",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "hashtags": ["citybioblitz", "springcount"],
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 3,
      "comment_count": 1,
      "ranking_value": 12,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false,
      "reactions": [],
      "reactions_next_cursor": null
    }
  ]
}
```

`author_username` is the copied public handle stored on
`public.users.public_username` without `@`. `author_avatar_url` is a copied
public projection stored on `public.users.public_avatar_url`. Neither field is
read directly from `auth.users` on the client. `ranking_value` is populated for
`trending` rows and omitted or `null` for `recent`, `following`, and `nearby`.
Feed-card hashtag hydration is a batched lookup over the page's `post_id`
values. `hashtags` is returned by the updated feed function as normalized public
tag text without leading `#`; it is `[]` for untagged posts.
`species_common_name` is the post snapshot selected by the author when sharing
or editing. It should be preferred over dictionary names for the public post
projection, while clients may still apply viewer-local preferred-name display on
top of the DTO for personalized native surfaces. When `pet_identification` is
non-null, native clients may use `pet_identification.label` as the visible
dog/cat card title. That label does not replace `species_common_name`,
`species_scientific_name`, dictionary routes, or species stats.

### `/get-explore-post`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns the same Explore card projection as `/get-explore-feed`, but for a
single post:

```json
{
  "post_id": "uuid"
}
```

This endpoint exists for notification routing and native deep links. It solves
the case where the tapped post is not already present in the currently loaded
in-memory feed page. Public web routes do not call this viewer-parameterized RPC
directly; they use the dedicated fixed-anonymous server projection described
below.

Current response shape:

```json
{
  "data": {
    "post_id": "uuid",
    "scan_id": "uuid",
    "hero_image_url": "https://...",
    "media_items": [
      {
        "kind": "video",
        "url": "https://media.merian.app/public_uploads/pro/.../video_playback.mp4",
        "thumbnail_url": "https://media.merian.app/public_uploads/pro/.../poster.webp",
        "order_index": 0,
        "duration_seconds": 8.2,
        "has_audio": false
      }
    ],
    "shared_at": "2026-04-26T17:22:11.000Z",
    "author_user_id": "uuid",
    "author_name": "Emre E.",
    "author_username": "emre_e",
    "author_avatar_url": "https://lh3.googleusercontent.com/...",
    "hashtags": ["citybioblitz", "springcount"],
    "species_common_name": "Monarch Butterfly",
    "species_scientific_name": "Danaus plexippus",
    "pet_identification": null,
    "public_location_label": "Austin, TX",
    "location_sharing": "open",
    "time_of_day": "afternoon",
    "current_month": 4,
    "weather_condition": "clear",
    "weather_temperature_f": 78.2,
    "like_count": 3,
    "comment_count": 1,
    "viewer_has_liked": false,
    "is_owned_by_viewer": false,
    "reactions": [],
    "reactions_next_cursor": null
  }
}
```

If the post is no longer visible to the viewer because it was unshared, blocked,
tombstoned, or lost media, the endpoint returns `404`.

The recent `get_explore_feed` SQL projection additionally exposes
`reference_thumbnail_url` beside `hero_image_url` and `media_items`. Public web
grid cards use the species reference thumbnail for audio posts, while detail and
social-preview surfaces retain the audio spectrogram from the canonical media
snapshot.

### Public-web Explore database projection

`https://naturebook.earth/explore/post/{postId}` and the anonymous discovery
grid are server-rendered. `apps/web/lib/explore.ts` invokes the card routine for
the grid:

```json
{
  "rpc": "get_public_web_explore_posts",
  "args": {
    "p_target_post_id": "uuid-or-null",
    "p_max_limit": 16
  }
}
```

and the atomic page routine for detail and metadata:

```json
{
  "rpc": "get_public_web_explore_post_page",
  "args": {
    "p_target_post_id": "uuid"
  }
}
```

The Next.js helper is `server-only` and uses the validated platform-managed
server API key. All public-web SQL routines call
`internal.require_service_role()`, fix the canonical viewer to `NULL`, and are
revoked from `PUBLIC`, `anon`, and `authenticated`; callers cannot supply or
configure a synthetic viewer. The card result exposes no viewer-dependent
engagement state: `like_count` and `comment_count` are zero, while
`viewer_has_liked` and `is_owned_by_viewer` are false. Card visibility,
moderation, tombstone, media health, shadowban, block, and location redaction
remain owned by `explore_projected_post_cards(NULL)`.

The detail routine independently inner-joins that canonical card projection.
`get_public_web_explore_post_page(target_post_id)` returns `post_payload` and
`detail_payload` from one statement/MVCC snapshot, and the page helper uses only
that combined routine. A direct detail call and the combined call therefore
return no row for content excluded by canonical anonymous visibility. The server
must not reconstruct this DTO through direct privileged table reads. Public-web
wrappers select their detail fields explicitly and do not forward the native
detail endpoint's optional `map_point`. Exact-SHA verification is tracked in the
[release assurance record](./14-dwca-and-public-web-release-hold-2026-07-27.md).

### `GET /api/explore/audio?url={canonicalWavUrl}` (Public Web)

Next.js same-origin stream used only after a visitor activates **Boost audio**.
It accepts HTTPS `.wav` URLs on exact host `media.merian.app` below
`/public_uploads/`, forwards byte ranges and safe cache/media headers, and
rejects arbitrary hosts, credentials, staging/private paths, unsupported
formats, missing upstream media, and oversized non-range responses. It stores no
bytes and does not change the public recording or moderation state.

### `/get-explore-post-detail`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns the public species-detail payload for a single Explore post. The backend
reads from `public.get_explore_post_detail(...)`, which enforces the same
filters as the main feed:

- unshared posts are excluded
- tombstoned scans are excluded
- scans with no remaining published image, video, or audio media are excluded
- shadowbanned authors are excluded
- both directions of user blocking are excluded

Post `location_sharing` is returned for edit hydration and controls public
location fields. It does not hide an otherwise visible detail page.

Request body:

```json
{
  "post_id": "uuid"
}
```

Current response shape:

```json
{
  "schema_version": 1,
  "data": {
    "post_id": "uuid",
    "reactions": [],
    "reactions_next_cursor": null,
    "location_sharing": "open",
    "map_point": {
      "latitude": 41.873,
      "longitude": -87.632,
      "coordinate_visibility": "exact"
    },
    "hashtags": ["citybioblitz", "springcount"],
    "species_dictionary_id": "uuid",
    "alternative_common_names": ["Milkweed Butterfly", "Common Tiger"],
    "taxonomy_kingdom": "Animalia",
    "taxonomy_phylum": "Arthropoda",
    "taxonomy_class": "Insecta",
    "taxonomy_order": "Lepidoptera",
    "taxonomy_family": "Nymphalidae",
    "taxonomy_genus": "Danaus",
    "ai_reasoning": "The bright orange wings with black veining and white-spotted margins are consistent with a monarch rather than the mimicking viceroy.",
    "habitat_description": "Often found in open meadows, milkweed patches, and migration corridors.",
    "gbif_taxon_key": 5130978,
    "iucn_red_list_status": "least_concern",
    "hazard_type": "poisonous",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Monarch_butterfly",
    "reference_image_url": "https://upload.wikimedia.org/.../Monarch.jpg,https://inaturalist-open-data.s3.amazonaws.com/photos/123/original.jpg",
    "wikipedia_overview": "The monarch butterfly is a milkweed butterfly in the family Nymphalidae...",
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://upload.wikimedia.org/.../Viceroy.jpg",
        "iucn_red_list_status": "least_concern"
      }
    ],
    "field_notes": "Found at the shaded meadow edge after rain."
  }
}
```

For Insight Share-state hydration, this response is advisory. The Sharing state
owner accepts its hashtags, location choice, and Field Notes visibility only
when the returned `post_id` case-insensitively matches the exact requested post
UUID and the same scan/generation/reconciliation request still owns the open
Insight. A foreign or stale detail cannot clear or replace already confirmed or
optimistic Share metadata.

This endpoint exists so Explore can render public species cards on the detail
page without loading private scan state or the Insight `InferenceEngine`.

`map_point` is an additive nullable object used by the native Observation card.
It is present only when the post's current saved `location_sharing` is `open`
and its post-owned `public_latitude`, `public_longitude`, and
`public_coordinate_visibility` projection is complete. It never reads the
backing scan's exact GPS fields. Protected-species or uncertainty rules may
return an already-sanitized point with `coordinate_visibility = "obscured"`.
Post settings `obscured` and `private` return `null`, and older deployed
responses may omit the key entirely. Explore feed/card responses and public-web
detail projections remain coordinate-free.

`hashtags` uses the same normalized public tag edge table as feed cards. Detail
renders tags as centered wrapping chips; tag taps route into the tagged-post
collection rather than querying field notes, comments, or private scan state.

`schema_version = 1` uses the same public species contract marker as
`/species-dictionary`. Older clients can continue decoding the `data` field and
ignore the wrapper key; newer clients may use it to gate future additive UI
behavior.

`alternative_common_names` is sourced from
`species_dictionary.alternative_common_names` and returned as an empty array
when no alternate names are available.

For posts owned by the current viewer, iOS also uses `field_notes` as a repair
source for the local insight sheet. `FieldNotesRepository` checks
`LocalScanRecord.fieldNotes`, `OfflineQueuedScan.fieldNotes`, and then the
legacy `FieldNotesStore` bridge before accepting the Explore value. If all
local/private stores are empty but the public Explore post still has notes, the
repository promotes the public value back into SwiftData and mirrors the bridge.
Existing local/private notes are preserved and are not overwritten by the
Explore copy.

`reference_image_url` remains a comma-separated compatibility field for Explore
detail clients, but the RPC now composes it from ordered
`species_reference_images` rows first and falls back to
`species_dictionary.reference_image_url` for older species rows. Before
returning the field, the RPC passes that ordered projection and the backing
scan's `image_storage_urls` through
`public.public_species_reference_image_urls_excluding_media(...)`. Exact current
scan URLs are removed while other scans' Merian references and external
Wikipedia/GBIF references retain their order. The helper reuses the existing
projection, so blocked-image filtering and legacy fallback behavior are
unchanged. If every candidate belongs to the current scan, the field is `null`.

This is a read-time, exact-scan exclusion. It does not remove normalized rows,
filter all contributions by the author, or perform perceptual matching across
different storage objects. The reference-image key and type remain unchanged.
Explore detail uses the field to render the public reference gallery below the
post's AI reasoning without making an extra authenticated scan fetch.

`similar_species` is hydrated from `species_lookalikes` for the post's resolved
dictionary species through `public.public_species_similar_species(...)`. Each
entry contains public species-level data only and is shaped like the existing
lookalike DTO: `species_id`, `scientific_name`, `common_name`,
`reference_image_url`, and `iucn_red_list_status`, plus optional relation
metadata (`reason`, `visual_traits`, `confidence`, `source`, `review_status`,
`is_bidirectional`, `sort_order`). The lookalike image URL prefers the first
normalized `species_reference_images` row and falls back to the legacy
dictionary cache. Empty lookalike sets return an empty array, and iOS omits the
section. Older clients can continue to route by `scientific_name`; new clients
prefer `species_id` for dictionary sheet lookup.

`ai_reasoning` is returned conditionally from the backing `scans` row, not
copied into `explore_posts`. It is only exposed when the scan still reflects the
original AI identification:

- `user_review_state != 'user_overridden'`
- `user_identification_override IS NULL`

Report flags do not hide reasoning because moderation workflow state does not
rewrite the identification. The Explore detail page hides reasoning only after
the user overrides the AI identification, preventing stale reasoning from being
presented for a replacement identification.

### `/get-explore-author-profile`

Returns a privacy-scoped public author profile for an Explore author. This
endpoint supplies the typed Author Profile destination opened from Explore
feed/detail author headers.

Request body:

```json
{
  "author_user_id": "uuid",
  "preview_limit": 9
}
```

Validation and availability rules:

- `author_user_id` is required and must be a UUID.
- `preview_limit` is optional, defaults to `9`, and is capped at `30`.
- For another viewer, the endpoint returns `404` if the target author has
  neither a currently visible Explore post nor a visible Field trip profile
  surface. The authenticated owner may load their own zero-visible-post profile
  so media recovery remains explainable.
- Automatic Backyard Safari enrollment creates a profile-visible active Field
  trip surface, so a known account ID normally satisfies this gate immediately,
  including at `0/N` progress, until the unfinished starter is stopped or reset.
  This endpoint does not enumerate account IDs.
- Shadowbanned authors and either direction of user blocking return no profile.
- Profile aggregates are computed from all non-tombstoned scans owned by the
  author.
- Species count and achievement progress use biological species-backed scans via
  `COALESCE(confirmed_species_id, species_id)`.
- Public achievement progress includes the full current app achievement catalog,
  including domestic cat and dog scan achievements.
- Preview posts use the same Explore visibility rules as feed/library posts and
  never include unshared, tombstoned, media-less, system-quarantined, or
  non-species-backed posts. Confirmed-missing items are omitted. Private post
  location sharing withholds location but does not hide the post.
  Administratively hidden posts (`moderated_at IS NOT NULL`) are also excluded
  from both profile discoverability and previews.
- Achievement progress never includes qualifying scan IDs.
- Follower/following counts are aggregate-only and do not expose browsable
  identities.
- `viewer_is_following` is specific to the requesting viewer and drives the
  Author Profile follow control.
- `viewer_can_report` is viewer-scoped and is `true` only for a non-self profile
  returned by this visibility contract. It controls whether the overflow menu
  offers **Report user**; `/report-user` independently revalidates the target.

Current response shape:

```json
{
  "data": {
    "author_user_id": "uuid",
    "author_name": "River W.",
    "author_username": "river_w",
    "author_avatar_url": "https://...",
    "species_count": 42,
    "current_streak": 5,
    "published_post_count": 5,
    "follower_count": 124,
    "following_count": 17,
    "viewer_is_following": false,
    "viewer_can_report": false,
    "owner_publication_summary": {
      "publication_intent_count": 38,
      "visible_post_count": 5,
      "recovery_needed_post_count": 33,
      "degraded_post_count": 0,
      "quarantined_post_count": 33
    },
    "heatmap": {
      "total_captures": 124,
      "current_month_captures": 8,
      "year_string": "2026",
      "weeks": [
        {
          "month_label": "May",
          "days": [
            { "count": 1, "date": "2026-05-03T00:00:00Z" },
            { "count": 0, "date": "2026-05-04T00:00:00Z" },
            { "count": -1, "date": "2026-05-05T00:00:00Z" }
          ]
        }
      ]
    },
    "awards": [
      {
        "type": "explorer",
        "current_count": 5,
        "last_interaction_at": "2026-05-03T12:00:00.000Z"
      }
    ],
    "preview_posts": [
      {
        "post_id": "uuid",
        "scan_id": "uuid",
        "hero_image_url": "https://...",
        "shared_at": "2026-05-03T12:00:00.000Z",
        "author_user_id": "uuid",
        "author_name": "River W.",
        "author_username": "river_w",
        "author_avatar_url": "https://...",
        "species_common_name": "River Birch",
        "species_scientific_name": "Betula nigra",
        "pet_identification": null,
        "public_location_label": "Austin, TX",
        "time_of_day": "day",
        "current_month": 5,
        "weather_condition": "clear",
        "weather_temperature_f": 74.0,
        "like_count": 8,
        "comment_count": 1,
        "viewer_has_liked": false,
        "is_owned_by_viewer": true,
        "ranking_value": null
      }
    ],
    "field_trips": {
      "pinned": [],
      "active": [],
      "published": []
    }
  }
}
```

Heatmap day `count = -1` marks future days in the fixed 52-week grid and renders
as empty/clear in `ScansHeatmap`. The backend chooses the author's latest valid
persisted `scans.device_time_zone` for day-boundary calculations and falls back
to UTC when no timezone is available.

`follower_count` and `following_count` are public aggregate counts on visible
profiles only. They do not imply browsable lists. `viewer_is_following` is
specific to the requesting user and should replace any optimistic client follow
state after a write. `viewer_can_report` is an authorization-aware UI hint, not
authority to bypass the report endpoint's self-report and visibility checks.
`published_post_count` and `preview_posts` use the same canonical
`explore_projected_post_cards(self_id)` projection.

`owner_publication_summary` is non-null only for the authenticated owner. It
separates preserved, active publication intent from current canonical visibility
and reports active degraded/quarantined recovery totals. Other viewers receive
`null`; the object is not a public author statistic. `field_trips` is hydrated
separately after the core profile RPC and contains only privacy-scoped active
progress and published snapshots; it never exposes scan IDs, field notes, exact
coordinates, or private evidence.

### `/get-explore-author-posts`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns a paginated grid library of an author's currently visible published
Explore scans. The response shape is the same card projection used by
`/get-explore-feed`, with `ranking_value = null`.

First page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "author_user_id": "uuid",
  "limit": 30,
  "before_shared_at": "2026-05-03T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Validation and pagination rules:

- `author_user_id` is required and must be a UUID.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint filters unshared posts, tombstoned scans, scans with no image
  media, scans without a species key, system-quarantined posts, shadowbanned
  authors, and both directions of user blocking. Confirmed-missing items are
  omitted. Post `location_sharing` controls public location fields, not feed
  visibility.
- The card projection includes batched `hashtags` arrays just like the feed.
- The Edge function fetches `limit + 1`; `next_cursor` is non-null only when
  another page exists. Clients stop only when it is `null`.

Response envelope:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "shared_at": "2026-05-03T12:00:00.000Z",
      "reactions": [],
      "reactions_next_cursor": null
    }
  ],
  "next_cursor": {
    "before_shared_at": "2026-05-03T12:00:00.000Z",
    "before_post_id": "uuid"
  }
}
```

At the end of the collection, `next_cursor` is `null`. Clients must not infer
completion from a short page or a separately fetched profile count.

### `/get-explore-hashtag-posts`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns a paginated collection of currently visible Explore posts tagged with
one normalized public hashtag. iOS opens this collection when the viewer taps a
hashtag chip on a feed card or post detail page; the native collection uses
observation cards with the shared reaction action row. The response shape is the
same card projection used by `/get-explore-feed`, with `ranking_value = null`
and a `hashtags` array hydrated for each row.

First page request:

```json
{
  "hashtag": "#CityBioBlitz",
  "limit": 30
}
```

Follow-up page request:

```json
{
  "hashtag": "citybioblitz",
  "limit": 30,
  "before_shared_at": "2026-05-12T12:00:00.000Z",
  "before_post_id": "uuid"
}
```

Rules:

- `hashtag` is required. Display input may include leading `#`; the Edge
  function trims it, lowercases it, and requires 2 to 40 letters, digits, or
  underscores.
- `limit` is optional, defaults to `30`, and is capped at `100`.
- `before_shared_at` and `before_post_id` must be omitted together or supplied
  together.
- Pagination is stable on `(shared_at DESC, post_id DESC)`.
- The endpoint applies the same unshared, tombstoned, missing-media,
  missing-species, shadowban, and mutual-block filters as the Explore feed. Post
  `location_sharing` controls public location fields, not tagged-post
  visibility.
- The backing RPC is `public.get_explore_hashtag_posts(...)`, which reads the
  normalized `(tag, post_id)` edge index from `public.explore_post_hashtags`.

### `/get-explore-map-points`

Returns privacy-safe Explore map data for the currently visible bounds. The
request body is:

```json
{
  "north_latitude": 30.489,
  "south_latitude": 30.139,
  "east_longitude": -97.517,
  "west_longitude": -98.001,
  "zoom_level": 10.7,
  "limit": 500,
  "species_categories": ["birds", "insects"],
  "media_types": ["image", "audio"]
}
```

- `north_latitude`, `south_latitude`, `east_longitude`, and `west_longitude` are
  required numeric bounds.
- `zoom_level` is used only to decide whether the response should be clustered
  or return individual posts.
- `limit` is optional and capped at `500`.
- `species_categories` is optional. Allowed values are `plants`, `fungi`,
  `birds`, `mammals`, `reptiles`, `amphibians`, `fish`, `insects`, `arachnids`,
  and `other`.
- `media_types` is optional. Allowed values are `image`, `video`, and `audio`.

The Edge Function reads `public.get_explore_map_posts(...)` and then applies
species-category and media-type filters plus zoom-aware clustering in
`services/supabase/functions/get-explore-map-points/cluster.ts`. The shipped
behavior is:

- category counts are computed after applying media filters, while media-type
  counts are computed after applying species filters
- selected values use OR within each filter group and AND between species and
  media groups; both groups are applied before clustering
- when the visible result set is small, return `mode: "posts"`
- when the viewport is broad or dense, return `mode: "clusters"`
- at close zooms, individual posts are still capped to prevent annotation
  overload

Current response shapes:

```json
{
  "mode": "clusters",
  "visible_count": 243,
  "category_counts": [
    { "category": "birds", "count": 82 },
    { "category": "insects", "count": 51 }
  ],
  "media_type_counts": [
    { "media_type": "image", "count": 132 },
    { "media_type": "video", "count": 71 },
    { "media_type": "audio", "count": 40 }
  ],
  "clusters": [
    {
      "id": "3015:2057",
      "latitude": 30.267,
      "longitude": -97.743,
      "post_count": 36
    }
  ],
  "posts": []
}
```

```json
{
  "mode": "posts",
  "visible_count": 24,
  "category_counts": [
    { "category": "birds", "count": 12 },
    { "category": "insects", "count": 8 }
  ],
  "media_type_counts": [
    { "media_type": "image", "count": 14 },
    { "media_type": "video", "count": 6 },
    { "media_type": "audio", "count": 4 }
  ],
  "clusters": [],
  "posts": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "latitude": 30.267,
      "longitude": -97.743,
      "coordinate_visibility": "obscured",
      "hero_image_url": "https://...",
      "shared_at": "2026-04-28T21:18:00.000Z",
      "author_user_id": "uuid",
      "author_name": "Nina P.",
      "author_username": "nina_p",
      "author_avatar_url": "https://...",
      "species_common_name": "Monarch Butterfly",
      "species_scientific_name": "Danaus plexippus",
      "pet_identification": null,
      "taxonomy_kingdom": "Animalia",
      "taxonomy_class": "Insecta",
      "public_location_label": "Austin, TX",
      "location_sharing": "open",
      "time_of_day": "afternoon",
      "current_month": 4,
      "weather_condition": "clear",
      "weather_temperature_f": 78.2,
      "like_count": 12,
      "comment_count": 3,
      "viewer_has_liked": false,
      "is_owned_by_viewer": false,
      "media_items": [
        {
          "kind": "image",
          "url": "https://...",
          "thumbnail_url": "https://...",
          "order_index": 0,
          "duration_seconds": null,
          "has_audio": false
        }
      ]
    }
  ]
}
```

Privacy and filtering rules:

- the map excludes unshared posts, tombstoned scans, scans with no remaining
  published image/video/audio media, non-open post `location_sharing`,
  shadowbanned authors, and both directions of user blocking
- media filters match authoritative `media_items.kind` values, not poster images
  or a video's `has_audio` flag; legacy rows without media items count as images
  only when they retain a non-empty hero image
- `category_counts` reflects the active media selection and `media_type_counts`
  reflects the active species selection; absent facet values are omitted rather
  than returned with zero counts
- `coordinate_visibility` communicates whether an open post point is exact or
  approximate because species-safety or uncertainty rules rounded the public
  projection
- the shipped map projection comes from post-owned public coordinates on
  `explore_posts`, not from raw scan GPS at read time
- the map returns the post-owned scrubbed `public_location_label`; it does not
  derive labels from raw semantic location fields

### `/get-explore-comments`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns comment rows for a single Explore post. The read path enforces the same
visible-post and mutual-block filters as the feed. Comment rows include the
public author label, the stable author username handle, the optional public
author avatar projection, and three viewer capability flags:

- `viewer_can_delete`: The viewer authored this comment and may delete it.
- `viewer_can_moderate`: The viewer owns the Explore post and may remove someone
  else's comment from that post.
- `viewer_can_report`: The viewer may report this comment for abuse review.

This endpoint powers both the feed's bottom-sheet comments view and the inline
comment thread on the Explore detail page.

Current response shape:

```json
{
  "data": [
    {
      "comment_id": "uuid",
      "post_id": "uuid",
      "author_user_id": "uuid",
      "author_name": "Nick H.",
      "author_username": "nick_h",
      "author_avatar_url": "https://lh3.googleusercontent.com/...",
      "body": "Oooh mucho gusto",
      "created_at": "2026-05-12T20:43:00.000Z",
      "viewer_can_delete": false,
      "viewer_can_moderate": false,
      "viewer_can_report": true,
      "mentions": [
        {
          "user_id": "uuid",
          "username": "ash_b",
          "display_name": "Ash B.",
          "avatar_url": "https://..."
        }
      ],
      "reactions": [
        {
          "emoji": "👍",
          "count": 1,
          "viewer_has_reacted": false,
          "order": 333
        }
      ],
      "reactions_next_cursor": null
    }
  ]
}
```

`author_avatar_url` is sourced from `public.users.public_avatar_url`, the same
copied public projection used by feed cards, map previews, and author profiles.
The client must treat it as optional and fall back to iconography when it is
`null`.

`mentions` is an additive array of resolved `@username` spans in `body`. The raw
body remains plain text; the client links only usernames that appear in
`mentions`. Unresolved `@text` stays normal text. Each `mentions[].username` is
the historical token snapshot that still appears in `body`, not a projection of
the user's current handle. Clients match the span by that snapshot and navigate
with the durable `mentions[].user_id`; `display_name` and `avatar_url` may
reflect the user's current public profile.

The request body supports cursor pagination on
`(created_at ASC, comment_id ASC)`:

```json
{
  "post_id": "uuid",
  "limit": 100
}
```

Follow-up page requests send:

```json
{
  "post_id": "uuid",
  "limit": 100,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

### `/get-explore-comment-replies`

Each returned row includes the additive `reactions` preview and nullable
`reactions_next_cursor` described in the
[reaction contract](#explore-emoji-reactions-2026-09-18): at most 12 groups in
canonical catalog order, then pages of 32 through `/get-explore-reactions`.
Missing fields from older projections render empty in native clients; a reaction
cursor is independent of the post/comment collection cursor.

Returns one page of visible replies under a top-level Explore comment. Replies
use the same row shape as `/get-explore-comments`, including `author_username`,
`author_avatar_url`, `reactions`, and `mentions`.

Request:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25
}
```

Follow-up page requests send both cursor fields:

```json
{
  "parent_comment_id": "uuid",
  "limit": 25,
  "after_created_at": "2026-04-28T10:00:00.000Z",
  "after_comment_id": "uuid"
}
```

Replies stay one level deep. A reply cannot be the parent of another reply.

### `/share-scan-to-explore` and `/unshare-explore-post`

- Both Scan Library quick-share and the full Insight composer call
  `/share-scan-to-explore` with the signed-in user's access token.
  `withEdgeHandler` authenticates that user, and the route verifies scan
  ownership and share eligibility. Only then does its server-side admin client
  call service-only author-maintenance and publication RPCs. The iOS client
  never receives or submits a service-role key.
- Privileged database execution has two layers. The exact RPC signature must be
  granted to `service_role` through `internal.privileged_routine_grants`, and
  the routine body calls `internal.require_service_role()`. Migration
  `20260727010340_fix_service_role_authorization_guard.sql` lets that helper
  recognize either a legacy JWT claim or PostgREST's protected `service_role`
  impersonation for an opaque server key; it does not add an `authenticated`
  grant.
- `service_role authorization required` in Edge/database logs is an internal
  deployment or server-key compatibility failure, not a scan-eligibility
  rejection or a user-facing `401`/`403`. Apply the compatibility migration and
  verify the service-only ACL. Never recover by granting the maintenance RPC to
  the user role or putting a service key in the app.
- `share-scan-to-explore` creates or reactivates a manual-share Explore post for
  an eligible resolved, non-Human biological scan with shareable public media.
  Ask the Community reuses this subject validator. If a scan's public media URLs
  expired but the client can provide owner-scoped `restored_object_keys`, the
  function promotes safe image media back into `image_storage_urls` before
  sharing. If the local scan still has the original playback `.mp4` and the
  cloud row is missing durable video media, clients may provide
  `restored_video_object_keys`; the function promotes those videos into
  `video_storage_urls`, rebuilds `captured_media`, makes a best-effort
  `scan_media_assets` refresh for ready playback rows, and then writes the
  public Explore snapshot.
- If the authenticated owner's local observation exists but its cloud row does
  not, current clients may combine those validated staging keys with a bounded
  non-media `recovery_scan` object. The handler derives and verifies the owner,
  inserts with duplicate protection, reloads by both scan and owner, and then
  follows the normal eligibility and media-promotion path. The server refuses
  media-less owner recovery with `409 scan_restore_media_required` before the
  recovery RPC is invoked, and proves every supplied key's exact scan/kind/role
  upload-ledger binding before that mutation. It also refuses this repair while
  richer ingestion is active or retryable and after a known terminal moderation
  or provider safety-policy rejection.
- Sharing snapshots image, video, and standalone-audio URLs into
  `explore_post_media`, ordered for the public carousel. `hero_image_url`
  remains the backward-compatible image field; author-post reads also return
  `reference_thumbnail_url` for compact audio tiles. Video media without an
  image thumbnail is rejected with `Video thumbnail unavailable.`
- New clients may pass ordered `media_items` using owner-scoped
  `source_media_id` values from `/get-explore-composer-media`; legacy
  `source_index` and `thumbnail_source_index` are accepted only when they map to
  eligible scan image/video/audio URLs. Empty selections, unsupported media
  kinds, Describe/observation context, AI/reference images, and Dictionary media
  are rejected or ignored before the public post snapshot is written.
- `source_media_id` values are resolved through the same media source list
  returned to the composer: ready display/playback/audio `scan_media_assets`
  rows first, `captured_media` second, and legacy image/video/audio URL arrays
  last. This keeps video playback URLs and poster thumbnails paired even when
  sampled inference frames remain in compatibility image URL arrays. Share-state
  visibility requires a saved `explore_post_media` row, preventing failed media
  writes from appearing as existing Explore posts. When a selected video source
  is missing from the cloud row, the endpoint returns a clean validation error
  so the iOS client can attempt local `.mp4` repair instead of publishing an
  image-only historical row. Scan finalization now proves this same canonical
  projection, so a valid playback scan can reach the completed prerequisite
  consumed here without requiring inference frames to become separately
  selectable media. The manifest branch always uses the executable Captured
  Media Wire V1 compatibility parser and its strict canonical projection.
  Malformed, insecure, credentialed, or arbitrary-key manifests fall back to
  durable URL columns; device-local references and nested inference-only video
  audio are removed before composer rows are built.
- Video `has_audio` metadata is copied from verified ready playback metadata.
  Historical compatibility manifests may still provide a nested video-audio
  reference as read evidence, but strict Captured Media Wire V1 canonicalization
  removes that field. V1 manifest sources and legacy URL-array sources therefore
  default to false unless independent durable playback metadata proves audio.
- `restored_audio_object_keys` accepts at most two owner-scoped
  `staging/{userId}/` WAV/M4A keys for legacy scans that still have local audio
  but no durable cloud audio. iOS admits only structurally valid WAV or
  audio-only ISO base-media input and requests canonical `.wav`/`audio/wav` or
  `.m4a`/`audio/mp4` restore signing; unsupported and video-bearing files are
  skipped rather than mislabeled. Successful repair promotes the objects, writes
  `audio_storage_urls`, drops unusable device-local references from
  `captured_media`, appends the newly durable reference, preserves `sourceIndex`
  on already-durable audio items, refreshes normalized assets, and then enters
  the normal moderation gate. Newly restored legacy items remain unindexed when
  the restore request cannot prove their original identity. Promotion failure,
  or a returned persistence rejection plus exact-owner proof that the URLs are
  absent, publishes nothing and rolls back promoted objects. A lost/unreadable
  update response returns retryable `scan_media_restore_unavailable` and
  preserves them until same-owner retry settles the outcome.
- If any selected item is standalone audio or an audio-bearing video, every
  audible item must have a matching content-addressed attestation or pass the
  database-selected structured audio classifier (currently `gemini-2.5-flash`)
  before the Explore post/media upsert runs. Attestations match SHA-256, model,
  and the automatically derived policy-contract hash; changed bytes or rules
  force a new decision. A rejected clip returns `422`; provider/configuration
  failures return `503`. Neither failure creates, reactivates, or changes a
  public post. Successful shares return `200` with
  `publication_status = published`. The transcript and non-speech description
  are not persisted, and the Edge runtime reuses `GEMINI_PAID_API_KEY`. Cache
  lookup/store failures degrade to live classification rather than approving by
  default.
- iOS accepts a `200` share response only when `success` is true, `scan_id`
  exactly echoes the requested scan UUID, `post_id` is a UUID, `shared_at` is a
  parseable ISO-8601 timestamp, `location_sharing` is authoritative, and
  `publication_status` explicitly equals `published`. A missing, malformed, or
  contradictory response is `MerianError.invalidResponse`: the post ID is not
  cached, the composer remains open with its draft intact, and the user can
  retry.
- After media restoration, selection, thumbnail work, and moderation, the Edge
  route performs exactly one final publication mutation through
  `publish_scan_to_explore_atomically(...)`. That service-role-only invoker RPC
  locks and revalidates the owner scan, locks and rechecks community readiness,
  and replaces post metadata, selected media, hashtags, and resolved-community
  publication state in one transaction. A transaction-time `needs_id` request
  returns conflict only when PostgreSQL reports the exact reviewed `P0001`
  condition and canonical message; matching text on another SQLSTATE is not
  downgraded to a user conflict. A failure in any relational step restores the
  prior complete snapshot and returns no published response.
- Forward migration `20260729044500_grant_atomic_explore_service_privileges.sql`
  provides the service role's narrow table-operation allowlist for both atomic
  invoker RPCs. Browser roles retain no direct publication write and neither RPC
  uses definer authority.
- Clients send one UUID `Idempotency-Key` for the share and preserve it through
  transport/auth/media-restoration retries. Each audible checksum and policy
  version receives a deterministic child reservation ID, allowing multiple clips
  without duplicate provider spend on an ambiguous retry. Cache hits explicitly
  refund the provisional reservation. Cache misses atomically apply the
  `explore_audio_moderation` daily and per-user/IP limits before dispatch.
- After standalone WAV audio passes moderation, `share-scan-to-explore` and
  media edits through `update-explore-field-notes` generate or reuse a
  deterministic PNG spectrogram beside the durable recording and store its URL
  in both the post snapshot and matching normalized scan asset. This
  presentation step is non-blocking: unsupported legacy codecs and generation
  failures retain playback plus the volume-icon fallback. The service-role-only
  `/backfill-explore-audio-spectrograms` endpoint accepts an optional bounded
  `{ "limit": 1...200 }` batch size and repairs older blank WAV thumbnails;
  repeat while `generated_count` is greater than zero.
- When the scan has an active Identify request, sharing to Explore is blocked
  until that request resolves. Publishing a resolved Identify request marks the
  request with `explore_published_at`, materializes any new GBIF-backed resolved
  species into `species_dictionary`, sets the scan's `confirmed_species_id`, and
  queues species-content hydration/provenance rows before promoting the existing
  post into normal Explore surfaces without creating a duplicate post.
- `unshare-explore-post` soft-removes the post from the public feed via
  `unshared_at` without deleting the underlying scan.
- `field_notes` is optional and capped at 1000 characters. It is a public copy
  controlled by the user, not the private local source of truth.
- `species_common_name` is optional. When provided it must be a string; the Edge
  function trims it, collapses internal whitespace, caps it at 200 characters,
  and stores it as the Explore post's public common-name snapshot. When omitted
  or empty, legacy dictionary fallback behavior is preserved.
- `hashtags` is optional. The share endpoint accepts at most five hashtag
  strings, strips leading `#`, lowercases them, deduplicates them, and requires
  each tag to be 2 to 40 letters, digits, or underscores. Resharing replaces the
  post's public hashtag edges with the submitted normalized set; omitted
  hashtags clear the set for that share request.
- Unsharing also purges any Explore notifications tied to that post so the
  activity feed cannot route into hidden content.
- `location_sharing` is optional for backward compatibility. If omitted, the
  atomic publication transaction resolves the share from the scan's current
  geoprivacy after locking the exact owner row. A concurrent privacy change
  cannot publish with a stale pre-lock default. Valid values are `open`,
  `obscured`, and `private`; legacy `hidden` is treated as `private`.
- The Explore map reads post-owned public coordinates from `explore_posts`. Only
  posts whose saved `location_sharing` is `open` can appear on the map or match
  non-owned Nearby radius queries. Protected-species and uncertainty rules can
  still store rounded public coordinates with
  `coordinate_visibility = "obscured"`.
- Updating the user's global/default geoprivacy or the backing scan's
  `geoprivacy` later does not overwrite an existing Explore post's explicit
  `location_sharing` choice.

### `/backfill-explore-audio-spectrograms` (Internal)

Service-role-only `POST` worker for historical standalone WAV
`explore_post_media` rows with a null/blank thumbnail. `verify_jwt = false`
allows server automation through the gateway; the function still requires an
exact environment-managed credential through `_shared/serviceRoleAuth.ts`.
Current `sb_secret_...` keys use `apikey` only; legacy service-role JWTs may use
matching Bearer and `apikey` transport. It must never be called by iOS or public
web code.

Request:

```json
{ "limit": 50 }
```

`limit` defaults to 50 and is clamped to 1...200. Oldest candidates run first.
Each successful item reuses or creates the deterministic PNG, updates the
post-owned thumbnail, and best-effort updates the matching normalized scan
asset. The worker does not change moderation, visibility, recording URLs, or
species data.

Response counters are `scanned_count`, `generated_count`, `unsupported_count`,
and `failed_count`, plus bounded per-media `errors`. Repeat bounded calls while
`generated_count` is greater than zero. Non-WAV legacy audio is not selected;
malformed/mislabeled WAV increments `unsupported_count` and retains the playback
fallback.

### `/update-explore-field-notes`

Updates public share options on an already-shared Explore post owned by the
current viewer. Despite the legacy endpoint name, this includes field notes,
hashtags, the public common-name snapshot, and post-level `location_sharing`.
This endpoint does not mutate the private local notes stored in SwiftData; iOS
continues to treat `FieldNotesRepository` as the local source of truth. The
Insight editor receives this endpoint as the caller-supplied
`FieldNotesVisibilityConfiguration` action, while its local repository and
speech effects cross the Field Notes `Services/` boundary; Views and Components
do not invoke transport directly.

Request body:

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured"
}
```

Response body:

```json
{
  "success": true,
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "hashtags": ["deer", "urbanwildlife"],
  "species_common_name": "Black-Tailed Deer",
  "location_sharing": "obscured"
}
```

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- `post_id` must be a valid UUID.
- `field_notes` may be a string or `null`.
- Empty or whitespace-only strings are normalized to `null`.
- Non-empty notes are trimmed and capped at 1000 characters.
- `species_common_name` is optional. If omitted, the existing
  `explore_posts.species_common_name` snapshot is preserved. If provided, it
  follows the same validation as `/share-scan-to-explore`: string-only, trimmed,
  internal whitespace collapsed, and capped at 200 characters. Empty strings and
  `null` clear the snapshot so read RPCs can fall back to dictionary names.
- `hashtags` is optional and, when provided, replaces the post's public hashtag
  edges using the same normalization as `/share-scan-to-explore`.
- `location_sharing`, when provided, updates only this Explore post. Valid
  values are `open`, `obscured`, and `private`; legacy `hidden` is treated as
  `private`.
- `media_items`, when provided, replaces the post's public media snapshot. New
  clients submit `source_media_id` values from `/get-explore-composer-media`;
  those IDs resolve through the same asset-first source list as
  `/share-scan-to-explore`, so captured-media videos keep their playback `.mp4`
  and poster thumbnail paired during edit/reorder flows. Video `has_audio`
  metadata follows the selected source's actual audio evidence instead of the
  media kind. Legacy URL-based reorders are accepted only for rows already
  present on the post.
- An edit that includes audible media uses the same fail-closed attestation gate
  as initial sharing. Unchanged bytes normally reuse the checksum/model/policy
  decision; replaced bytes or a changed moderation contract call Gemini again.
  Editing text or location without `media_items` does not re-moderate media.
- Changing `location_sharing` reprojects only the post-owned public location
  fields. It does not mutate `scans.geoprivacy` or the user's global default.
- The update is scoped by `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned or unshared posts return 404.

### `/update-public-username`

Updates the current user's canonical public username handle. Usernames are
stored without `@`; clients should render them as `@username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "username": "stone_glen_72"
}
```

Rules:

- Requires an authenticated user through `withEdgeHandler`.
- Input may include a leading `@`; normalization strips it.
- Whitespace and punctuation separators normalize to underscores.
- The stored username must be lowercase ASCII letters, numbers, and underscores;
  3 to 24 characters; start with a letter; end with a letter or number; and
  contain no repeated underscores.
- Protected brand namespaces (`explore`, `merian`, `naturebook`, and
  `naturebookearth`), official/system roles such as `admin`, `security`,
  `support`, and `verified`, and exact brand-role combinations in either order
  are rejected with `400`. The policy is not prefix-based, so an ordinary handle
  such as `naturebook_fan` remains valid. Usernames never grant administrative
  authorization. The complete current groups are maintained in
  [Public Usernames](../features-and-hardware/21-public-usernames.md#reserved-name-policy).
- Duplicate normalized usernames return `409`.
- Alias-source users also have `public_author_name` updated to the username so
  ghost/default Explore rows render as `@username`. Derived/display-name users
  keep their existing Explore display label.

### `/update-public-display-name`

Updates or clears the authenticated viewer's custom public display name.
`display_name` is a required string; a missing or non-string value returns
`400`. The handler trims/collapses whitespace, rejects control-character names,
and enforces the 40-character limit.

A non-empty value sets the public author name and
`public_identity_source = 'display_name'`. Sending `{"display_name": ""}` clears
the custom override, restores the current `public_username` as the author name,
and sets `public_identity_source = 'alias'`. A successful response contains the
resolved `display_name` at the top level, including the username alias after
clearing; it does not echo an empty request value.

The iOS editor calls shared `ProfileViewModel`, which uses the public-profile
endpoint extension and adopts the server projection. See
[Public Display Name UX](../features-and-hardware/06-profile-and-gamification.md#public-display-name-ux)
for editor validation and save-state behavior. Endpoint extraction changes none
of these existing rules.

### `/check-public-username`

Validates a candidate username for the current authenticated user without
updating their profile. The endpoint uses the same normalization, reserved-name
rules, and cross-user uniqueness check as `/update-public-username`.

Request body:

```json
{
  "username": "@Stone Glen 72"
}
```

Response body:

```json
{
  "available": true,
  "username": "stone_glen_72",
  "error": null
}
```

Invalid or taken usernames return `200` with `available: false` and an `error`
message for inline UI. The current user's own username is considered available.

### `/get-scan-explore-share-state`

Returns the current viewer's authoritative Explore share mapping for one owned
scan. This endpoint exists to revalidate the Insight sheet's fast local cache
after relaunch or on a second device, so the Share button can switch back to
`View post` when a scan is still live in Explore without relying on device-local
memory alone.

Request body:

```json
{
  "scan_id": "uuid"
}
```

Current response shape:

```json
{
  "data": {
    "scan_id": "uuid",
    "post_id": "uuid",
    "shared_at": "2026-04-29T22:18:03.000Z",
    "community_request_id": "uuid-or-null",
    "community_request_status": "needs_id|resolved|withdrawn|null",
    "is_explore_feed_visible": false,
    "location_sharing": "obscured"
  }
}
```

Behavior notes:

- the Edge wrapper derives owner identity from the validated user JWT; the
  underlying `SECURITY INVOKER` routine is executable only by `service_role`,
  and `PUBLIC`, `anon`, or `authenticated` cannot submit a replacement `self_id`
  directly
- the lookup is owner-only: it reads only scans where `scans.user_id = self_id`
- when a live Explore post exists, `location_sharing` is the post-owned value
  used to hydrate share/edit options
- `community_request_id` and `community_request_status` restore the Identify
  request state for scans that have been made public as community ID requests
- `is_explore_feed_visible` is true only when the post belongs in normal Explore
  feed/map/author/hashtag surfaces, including the same moderation,
  post-media-health, and item-health predicates as the canonical public
  projection
- pending Identify requests and resolved-but-unpublished Identify requests
  return their request state with `is_explore_feed_visible = false`; resolved
  requests become feed-visible only after the owner explicitly publishes them to
  Explore
- a fully media-quarantined or moderated post preserves owner-only `post_id`,
  `shared_at`, and its location choice while returning
  `is_explore_feed_visible = false`, even when there is no Community request; a
  degraded post remains visible when at least one non-missing item is eligible
- when no live post exists, `location_sharing` falls back to the scan's current
  geoprivacy so a new share composer can seed the default option
- the endpoint does not mutate scan or post geoprivacy
- if the scan still has an active Explore publication snapshot, `post_id` and
  `shared_at` are returned even when an independent server visibility boundary
  currently hides it
- if the scan exists but the Explore post was unshared or the scan is no longer
  a valid live snapshot because it was tombstoned, lost every media row, no
  longer resolves to a species, or its owner is shadowbanned, the endpoint
  returns the same `scan_id` with `post_id = null`; Private location sharing
  hides location, not the post
- if the scan no longer exists for the current viewer, the Edge Function still
  returns `200` with `post_id = null` so the client can safely clear stale local
  cache without branching on `404`

### `/set-explore-post-like`

Idempotently toggles liked state for the current viewer and returns:

- `post_id`
- `viewer_has_liked`
- `like_count`

Important regression note: boolean request bodies must treat `liked: false` as a
valid value, not as a missing parameter. The shared `requireParams` helper was
hardened accordingly.

Notification side effects:

- Like notifications are maintained server-side through
  `explore_post_notifications`.
- The server aggregates likes into one row per recipient/post rather than
  inserting one notification row per like.
- Self-likes do not create notifications.

### `/set-user-follow`

Idempotently follows or unfollows a visible Explore author profile.

Request body:

```json
{
  "author_user_id": "uuid",
  "is_following": true
}
```

Response body:

```json
{
  "success": true,
  "author_user_id": "uuid",
  "follower_count": 12,
  "following_count": 4,
  "viewer_is_following": true
}
```

Validation and behavior:

- `author_user_id` is required and must be a UUID.
- `is_following` is required and must be a boolean. `false` is a valid request
  value.
- Self-follow is rejected with `400`.
- Follow inserts require no mutual block, a non-shadowbanned target, and a
  currently visible Explore author profile for the requester.
- Follow writes use the `(follower_user_id, followee_user_id)` primary key and
  are idempotent.
- Unfollow deletes the relationship even if the target profile is no longer
  visible.
- The returned state is authoritative and should replace optimistic client
  counts.

Notification side effects:

- Follow creates a postless in-app notification for the followed user.
- Unfollow removes the corresponding follow notification.
- Blocking either direction removes follow rows and follow notifications.
- Follow notifications are not sent to APNs.

### `/create-explore-comment` and `/delete-explore-comment`

- Create/delete plain-text comments on Explore posts.
- Server-side body cap: 500 characters.
- The response returns the updated `comment_count` so the feed can stay
  optimistic without a full reload.
- The created comment response includes `author_username` from
  `public.users.public_username` and `author_avatar_url` from
  `public.users.public_avatar_url` so the newly-appended row matches the
  subsequent `/get-explore-comments` read payload.
- The created comment response includes `mentions`, an array of resolved
  `@username` tokens from the saved body.
- Each returned mention keeps the exact normalized username snapshot that
  appears in the immutable body and the durable mentioned user ID. A later
  profile rename or reservation-policy expansion changes neither field; current
  display-name/avatar projections may still change.
- Mention resolution is scoped to the post author, visible participants in the
  relevant thread, and followed users. It does not allow arbitrary public-user
  tagging.
- The resolver skips self, blocked, shadowbanned, invisible-profile, duplicate,
  and ineligible mentions, then stores at most five unique eligible users.
- Mention notifications use `comment_mention` and are deduped against existing
  `comment` or `comment_reply` notifications for the same recipient/comment.
- Comment notifications are created and removed server-side through triggers on
  `explore_post_comments`.
- Self-comments do not create notifications.

Removal semantics:

- If the current viewer authored the comment, `/delete-explore-comment` sets
  `deleted_at`.
- If the current viewer owns the Explore post but did not author the comment,
  `/delete-explore-comment` performs an owner moderation action by setting
  `moderated_at` and `moderated_by_user_id`.
- Both paths remove the comment from public reads and decrement `comment_count`,
  but they remain distinguishable in the database for auditability.

### `/get-explore-mention-suggestions`

Returns eligible `@username` suggestions for the current comment composer. The
endpoint is intentionally scoped and is not a global public-user search.

Request:

```json
{
  "post_id": "uuid",
  "parent_comment_id": "uuid",
  "query": "as",
  "limit": 8
}
```

- `post_id` is required.
- `parent_comment_id` is optional. When present, it must be a visible top-level
  comment on the same post and thread-participant suggestions are scoped to that
  reply thread.
- Empty or short queries may return the post author and visible thread
  participants.
- Followed-user suggestions require a typed query so the endpoint cannot become
  a follower-list browser.

Response:

```json
{
  "data": [
    {
      "user_id": "uuid",
      "username": "ash_b",
      "display_name": "Ash B.",
      "avatar_url": "https://...",
      "source": "thread"
    }
  ]
}
```

`source` is one of `post_author`, `thread`, or `following`.

### `/toggle-explore-comment-reaction`

**Older-client compatibility only.** Current native reaction UI uses
`/set-explore-post-reaction` or `/set-explore-comment-reaction` with an explicit
`selected` state. This legacy endpoint validates against the same Unicode
catalog and canonicalizes recognized presentation aliases.

Toggles an emoji reaction for the current viewer on a specific comment and
returns:

- `success`
- `comment_id`
- `emoji`

Request body:

```json
{
  "comment_id": "uuid",
  "emoji": "👍"
}
```

- If the viewer has not yet reacted with this emoji, the reaction is inserted.
- If the viewer has already reacted with this emoji, the reaction is removed.
- This is a toggle, not an idempotent absolute-state setter. Legacy iOS callers
  must not replay it after an ambiguous transport or server failure.
- Reactions are aggregated into a `reactions` JSON array by the
  `/get-explore-comments` read endpoint.
- The server also maintains aggregated Explore notification rows per
  `(comment author, comment, emoji)` so comment authors can be notified when
  other viewers react.

### `/report-explore-comment`

Creates or updates a moderation report for an Explore comment without removing
it immediately.

- Required body fields: `comment_id`, `reason`
- Optional body field: `details`
- Current allowed `reason` values: `Spam`, `Harassment`,
  `Inappropriate content`, `Other`
- Users cannot report their own comments.
- Duplicate reports by the same user collapse into a single row keyed by
  `(comment_id, reporter_user_id)`.

### `/report-explore-post`

Creates or updates a moderation report for a visible Explore post without
changing the underlying identification review state.

```json
{
  "post_id": "00000000-0000-0000-0000-000000000001",
  "reason": "Inappropriate content",
  "details": "Optional context"
}
```

- Required body fields: `post_id`, `reason`
- Optional body field: `details` (trimmed and capped at 500 characters)
- Allowed reasons: `Spam`, `Harassment`, `Inappropriate content`, `Other`
- Users cannot report their own or an unavailable post.
- Current iOS feed, post-detail, and Community Identification detail report
  actions use this endpoint. The Community adapter sends the detail's exact
  `postId`, fixed `Inappropriate content` reason, and
  `Reported from Community request` context.
- Confirmed reports hide the post for that account across authenticated Explore,
  Community Identification, discussions, notifications and interactions,
  including reused reference photos. Pending, dismissed and actioned reports all
  apply. See
  [reported content visibility](../features-and-hardware/30-reported-content-visibility.md).
- Duplicate reports collapse on `(post_id, reporter_user_id)` and preserve an
  existing moderation status rather than reopening dismissed or actioned work.
- Writes only `explore_post_reports`; it never calls `/flag-issue`, inserts an
  identification `flagged_reviews` row, or sets `scans.is_flagged`.
- Returns `HTTP 200` with `success`, `post_id`, and a moderation message.
  Missing authentication returns `HTTP 401`; invalid input or self-reporting
  returns `HTTP 400`; unavailable posts return `HTTP 404`.
- The anonymous public web page does not call this endpoint. Its report action
  opens a support email containing the immutable public post id.

### `/get-explore-notifications`

Optional request field `supports_post_reactions` is a boolean, default false.
Current native clients send true. False/omitted selects the legacy row set; post
reactions are excluded consistently from lists and unread counts and are left
untouched by mark-read. True includes eligible `post_reaction` groups. These RPC
paths are service-only behind the authenticated Edge handler.

Returns the viewer's in-app Explore activity feed. The request body is optional:

```json
{
  "limit": 50,
  "supports_post_reactions": true
}
```

- `limit` defaults to `50` and is capped server-side.
- The ordinary activity read path mirrors Explore visibility rules: unshared
  posts, tombstoned scans, quarantined/media-less posts, shadowbanned owners,
  blocked actors, and soft-deleted comments are filtered out. Owner-scoped
  `media_missing` and `media_restored` lifecycle rows remain visible even while
  the affected post is quarantined. Post `location_sharing` controls public
  location fields, not notification visibility.
- Follow notifications are validated against an active follow relationship and
  blocked or shadowbanned actors are filtered out.
- Community Identification notifications include `community_request_id` plus
  display fields for the current or resolved taxon, and the client routes them
  to the Community request detail instead of regular post detail.
- Field trip activity notifications include `field_trip_publication_id`; the
  client routes them to `FieldTripPublicationDetailView`.
- `media_missing` routes to Scan Library recovery. `media_restored` routes to
  ordinary post detail when the post remains published.
- Pagination is cursor-based on `(updated_at DESC, notification_id DESC)`.
  Follow-up page requests send:

```json
{
  "limit": 50,
  "before_updated_at": "2026-04-27T12:05:00.000Z",
  "before_notification_id": "uuid"
}
```

Current response shape:

```json
{
  "data": [
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "like_aggregated",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User C",
      "comment_body": null,
      "recent_actor_names": ["User C", "User B"],
      "action_count": 2,
      "is_read": false,
      "community_taxon_common_name": null,
      "community_taxon_scientific_name": null,
      "community_request_display_name": null,
      "created_at": "2026-04-27T12:00:00.000Z",
      "updated_at": "2026-04-27T12:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User D",
      "comment_body": "Beautiful find",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:06:00.000Z",
      "updated_at": "2026-04-27T12:06:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment_mention",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User M",
      "comment_body": "Looping in @ash_b",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-04-27T12:07:00.000Z",
      "updated_at": "2026-04-27T12:07:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "comment_reaction",
      "comment_id": "uuid",
      "reaction_emoji": "🔥",
      "triggering_user_id": "uuid",
      "triggering_user_name": "User E",
      "comment_body": "Beautiful find",
      "recent_actor_names": ["User E", "User F"],
      "action_count": 2,
      "is_read": false,
      "created_at": "2026-05-05T10:00:00.000Z",
      "updated_at": "2026-05-05T10:05:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": "uuid",
      "community_request_id": "uuid",
      "field_trip_publication_id": null,
      "type": "community_request_resolved",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": null,
      "triggering_user_name": null,
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "community_taxon_common_name": "Pinwheel",
      "community_taxon_scientific_name": "Aeonium haworthii",
      "community_request_display_name": "Pinwheel",
      "created_at": "2026-06-20T19:30:00.000Z",
      "updated_at": "2026-06-20T19:30:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": null,
      "community_request_id": null,
      "field_trip_publication_id": "uuid",
      "type": "field_trip_comment",
      "comment_id": "uuid",
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User T",
      "comment_body": "Great Field trip.",
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-07-08T16:00:00.000Z",
      "updated_at": "2026-07-08T16:00:00.000Z"
    },
    {
      "notification_id": "uuid",
      "post_id": null,
      "community_request_id": null,
      "field_trip_publication_id": null,
      "type": "follow",
      "comment_id": null,
      "reaction_emoji": null,
      "triggering_user_id": "uuid",
      "triggering_user_name": "User F",
      "comment_body": null,
      "recent_actor_names": [],
      "action_count": 1,
      "is_read": false,
      "created_at": "2026-05-11T16:10:00.000Z",
      "updated_at": "2026-05-11T16:10:00.000Z"
    }
  ]
}
```

`post_id` is nullable because follow notifications and Field trip activity are
not Explore-post-backed. Field trip activity rows include
`field_trip_publication_id` and route to `FieldTripPublicationDetailView`;
follow rows remain informational and do not attempt post navigation.

### `/get-explore-unread-notification-count`

Optional request field `supports_post_reactions` is a boolean, default false.
Current native clients send true, for example
`{"supports_post_reactions": true}`. False/omitted selects the legacy row set;
post reactions are excluded consistently from lists and unread counts and are
left untouched by mark-read. True includes eligible `post_reaction` groups.
These RPC paths are service-only behind the authenticated Edge handler.

Returns the unread bell badge count for visible Explore and Field trip in-app
activity notifications:

```json
{
  "unread_count": 3
}
```

Unlike most read endpoints, this response returns the scalar at the top level
rather than nesting it under `data`.

The iOS client enters this request globally through the source-compatible
`AppIconBadgeCoordinator`, while injected mutable state lives in
`AppIconBadgeController` and the live endpoint closure lives in Core
Notifications Services. Concurrent callers await one in-flight request, and a
successful count may be reused for 10 seconds. Explore-post activity uses
Realtime as the primary refresh path, while routine five-minute polling also
covers Field trip-only rows, missed events, and subscription failure. Realtime
events and notification-sheet dismissal force a fresh count. Keep the server
endpoint side-effect-free so this deduplication remains safe. Accepted account
cleanup and local mark-read both cancel the active load and advance the
controller's state generation. Cleanup additionally clears the cached timestamp
and persisted count before refreshing the OS badge. A stale result is rejected
even when its loader does not honor cancellation.

### `/mark-explore-notifications-read`

Optional request field `supports_post_reactions` is a boolean, default false.
Current native clients send true. False/omitted selects the legacy row set; post
reactions are excluded consistently from lists and unread counts and are left
untouched by mark-read. True includes eligible `post_reaction` groups. These RPC
paths are service-only behind the authenticated Edge handler.

Example request: `{"supports_post_reactions": true}`.

Marks the viewer's Explore notifications as read and returns the number of rows
updated:

```json
{
  "success": true,
  "marked_count": 3
}
```

The current iOS client calls this only after `/get-explore-notifications`
succeeds, matching the shipped "clear the unread badge when the sheet opens
successfully" behavior.

### `/register-push-device`

Registers or refreshes the current iOS device for optional remote Explore
activity pushes:

```json
{
  "device_token": "lowercasehex...",
  "platform": "ios",
  "environment": "sandbox",
  "explore_enabled": true,
  "comment_mentions_enabled": true,
  "community_identifications_enabled": true,
  "supports_post_reactions": true
}
```

- The endpoint is authenticated with the viewer's existing Supabase session,
  just like the other Explore nodes.
- Core Notifications includes the normalized current account ID in its local
  registration snapshot so an in-flight call for one account cannot satisfy an
  otherwise-identical request for a replacement account. That account scope is
  coordination metadata only: `PushRegistrationService` deliberately omits it
  from this JSON payload.
- `device_token` is normalized to lowercase and upserted by
  `(device_token, platform, environment)`. It must contain only hexadecimal
  characters and be 32...512 characters long. The Edge Function may express that
  complete policy as the JavaScript regex `/^[0-9a-f]{32,512}$/i` because
  JavaScript accepts that repetition bound. PostgreSQL enforces the same policy
  as separate format and length constraints because its regex engine rejects
  repetition bounds above 255. Do not "repair" the valid Edge Function regex or
  recombine the database checks.
- `explore_enabled` is feature-specific. Users can opt into Explore activity
  pushes without also enabling discovery-result alerts. New installs default
  this setting on.
- `comment_mentions_enabled` is optional for compatibility with older clients.
  New installs default this setting on. When omitted, the server treats the
  mention preference like the submitted `explore_enabled` value for older
  clients. When present, `comment_mention` payloads require
  `comment_mentions_enabled` to be true. Other Explore activity payloads require
  `explore_enabled` to be true.
- `community_identifications_enabled` is optional for compatibility with older
  clients. New installs default this setting on. When omitted, the server treats
  the Community preference like the submitted `explore_enabled` value for older
  clients. Community Identification payloads require
  `community_identifications_enabled` to be true.
- `supports_post_reactions` is an optional boolean capability, default false.
  Post-reaction pushes require it and `explore_enabled`; registration does not
  enable notification permission or opt-in. Omitting it during registration
  records false, keeping older apps from receiving the new type. Counts in push
  badges use that device's capability. Other notification types retain their
  existing preferences.
- The server stores these rows in `public.user_push_devices`. Delivery failures
  from APNs feed back into that table via `last_error_*` fields and `is_active`.
- Migration `20260720174209_fix_push_device_token_constraint.sql` is a
  database-only repair. It does not require an Edge Function deployment. After
  applying it, the next notification-permission/token synchronization retries
  registration through the existing function.

### iOS Mapping

The Explore iOS mapping, state, and presentation layers are:

- `apps/ios/Merian/Core/Network/Models/Explore/`
- `apps/ios/Merian/Core/Network/Models/Explore/ExploreLocationSharingAPIModels.swift`
  for the shared Codable/raw-value post-location contract; visible labels,
  symbols, and explanatory copy remain in
  `apps/ios/Merian/Features/Explore/Shared/Models/ExploreLocationSharingPresentation.swift`,
  while cross-feature semantic-location redaction remains in
  `apps/ios/Merian/Core/Models/ExploreLocationPrivacy.swift`
- `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ExploreBrowsing.swift`
  for the eight Feed/Map/post/detail/author/hashtag/species browsing payloads
  and typed projections; feature adapters and state remain below their existing
  owners, and comments/mutations/composer/publication/recovery/cache methods are
  not part of this extension
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ExploreInteractions.swift`
  for 12 comment/reply/mention, like/follow, comment mutation, reporting, and
  blocking methods; feature Services and Core's social guard retain adapters and
  state. Seven methods decode existing DTOs; reaction/report/block `Void`
  methods preserve HTTP-only success and ignore successful bodies. The shared
  transport retains its three-read/nine-mutation ambiguous-replay split and
  classified-401 refresh behavior
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+CommunityIdentification.swift`
  for Community request/activity feeds, detail, request editing, taxonomy
  search, and submit/withdraw/restore payloads and typed response projections
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ScanPublication.swift`
  for the direct Explore-share and Ask-the-Community payloads, stable
  idempotency keys, typed response projection, and strict success validation;
  record-based compatibility orchestration lives in `Core/Network/Recovery/`,
  and local publication-media planning/upload lives in `Core/Network/Media/`
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+ExplorePostManagement.swift`
  for composer media, authoritative share state, owner media incidents, unshare,
  legacy public-notes edits, and full post edits. It preserves existing payload
  and response validation, selective decoding-error mapping, and HTTP-only
  unshare success. Full edits supply one retry-stable idempotency key per call;
  legacy notes edits on the same route supply none. Feature state and
  publication/upload/recovery orchestration remain outside this extension
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+FieldTrips.swift`
  for Field Trips actions and typed response projections
- `apps/ios/Merian/Core/Network/Models/FieldTrips/` for the eight focused Field
  Trips network-model contract families; UI presentation, Insights route
  projection, milestone policy, and preference persistence remain with their
  owning domains
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+Notifications.swift`
  for notification catalog/count/read-state and push-registration requests.
  Three methods decode existing DTOs; mark-read returns the count without
  interpreting its required `success` flag, and push registration ignores
  successful bodies. Feature Notification Services/ViewModels retain catalog
  state; Core Notifications retains system push, account-aware latest-state
  registration, and badge lifecycle. Its account scope remains local and does
  not change the endpoint payload
- `apps/ios/Merian/Core/Network/Endpoints/MerianNetworkClient+PublicProfile.swift`
  for username/display-name/avatar updates and username availability. All four
  preserve raw payload values and typed server projections, including
  unavailable usernames and display-name clearing. Shared `ProfileViewModel`
  retains identity state/events and avatar signing/upload orchestration; only
  final avatar promotion belongs to this extension. Together these eight methods
  retain the existing shared transport, 30-second deadlines,
  three-read/five-mutation ambiguous-replay split, and classified-401 refresh
  path
- `apps/ios/Merian/Features/Explore/Feed/Services/` for live Feed,
  comment/interaction, post-detail, composer-image, presentation, and
  unread-realtime adapters
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Interactions.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreFeedViewModel+Notifications.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExploreHashtagPostsViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/ViewModels/ExplorePostDetailViewModel.swift`
- `apps/ios/Merian/Features/Explore/Feed/Models/ExploreFeedRoutes.swift`
- `apps/ios/Merian/Features/Explore/Feed/Views/` and grouped `Components/` for
  network-free rendering and view-local focus, scroll, and presentation timing
- `apps/ios/Merian/Features/Explore/Map/Models/` for Map-only request, focus,
  filter, region, and cache policy
- `apps/ios/Merian/Features/Explore/Map/Services/ExploreMapViewModelDependencies.swift`
  for the live map-points adapter
- `apps/ios/Merian/Features/Explore/Map/ViewModels/` for spatial loading,
  filtering, request-generation, and selection state
- `apps/ios/Merian/Features/Explore/Notifications/Services/` for the live
  notification catalog/read, comment/reply, current-viewer, telemetry, and error
  adapters
- `apps/ios/Merian/Core/Notifications/` for push permission/token
  synchronization, latest-state remote-registration coordination, local
  scheduling/routing, and generation-fenced app-icon badge refresh/cache policy;
  its `Services/` directory alone adapts the notification endpoints
- `apps/ios/Merian/Features/Profile/Settings/Notifications/Services/NotificationSettingsDependencies.swift`
  for the Settings permission/remote-registration adapter; Settings state does
  not construct push payloads
- `apps/ios/Merian/Features/Profile/Shared/ViewModels/ProfileViewModel.swift`
  for public-identity updates/availability, shared identity values/events, and
  avatar signing/upload orchestration; Profile editors call this owner rather
  than resolving the network client
- `apps/ios/Merian/Features/Explore/Notifications/ViewModels/` for
  generation-fenced catalog and notification reply-thread state
- `apps/ios/Merian/Features/Explore/Notifications/Models/` for decoded activity,
  stable row presentation, and typed notification reply routes
- `apps/ios/Merian/Features/Explore/Notifications/Views/` plus grouped
  `Components/` for network-free rendering and sheet-local lifecycle timing
- `apps/ios/Merian/Features/Explore/AuthorProfile/Models/` for typed routes and
  deterministic presentation mapping
- `apps/ios/Merian/Features/Explore/AuthorProfile/Services/ExploreAuthorProfileViewModelDependencies.swift`
  for the live profile, library, follow, and report adapters
- `apps/ios/Merian/Features/Explore/AuthorProfile/ViewModels/` for
  profile/library/follow and report-form state
- `apps/ios/Merian/Features/Explore/AuthorProfile/Views/` and grouped
  `Components/` for navigation and network-free rendering
- `apps/ios/Merian/Features/Explore/Map/Views/` and grouped `Components/` for
  MapKit camera/gesture ownership and network-free rendering
- `apps/ios/Merian/Features/Explore/Shell/Models/` for root/initial navigation
  policy and the typed notification destination, open token, and preparation
  outcome
- `apps/ios/Merian/Features/Explore/Shell/Services/ExploreShellDependencies.swift`
  for the app-event stream, app-level Scans-library route adapter, and narrow
  haptic actions
- `apps/ios/Merian/Features/Explore/Shell/ViewModels/ExploreNotificationNavigationCoordinator.swift`
  for latest-wins post preparation, token-checked success/failure commits, and
  the staged-to-pending dismiss handoff
- `apps/ios/Merian/Features/Explore/Shell/Views/` plus `Components/` for the
  network-free root navigation, lifecycle, presentation, and chrome
- `apps/ios/Merian/Features/Insights/Sharing/Services/` for the live direct
  publication, Community request, detail, authoritative share-state, cache,
  app-event, preferred-name, and feedback adapters
- `apps/ios/Merian/Features/Insights/Sharing/ViewModels/` for generation-fenced
  Explore publication and editing, share-state reconciliation, Community
  mutation, and the observable request draft
- `apps/ios/Merian/Features/Insights/Sharing/Views/` plus `Components/` for the
  stable network-free Share and Community request presentations

The extracted endpoint owners use typed-response and body-ignoring overloads of
one internal JSON POST bridge. The typed overload preserves optional idempotency
keys and endpoint-specific decoding failures without catching transport
failures; private session, Auth lease, refresh, retry, and cancellation behavior
remains in `MerianNetworkClient.swift`. The two `requestCommunityIdentification`
scan-publication overloads are split between
`Endpoints/MerianNetworkClient+ScanPublication.swift` and
`Recovery/MerianNetworkClient+OwnedScanRecovery.swift`; restored local media is
owned by `Media/ScanPublicationMediaRestorer.swift`. This is a source ownership
split, not a change to these API contracts. Feed, Insights Sharing, and Scans
Shell retain composer/edit, reconciliation, and private incident state. See the
[Core Network guide](../../apps/ios/Merian/Core/Network/README.md#meriannetworkclient)
for the endpoint and test boundaries.

Feed views and components do not resolve endpoint clients. The Feed state owners
invoke small initializer-injected closure groups; only their live
implementations under `Feed/Services` bridge to `MerianNetworkClient`, Supabase
realtime, identity/entitlement services, telemetry, or image loading. Wire DTOs
and JSON contracts remain in `Core/Network/Models/Explore/`.

Insights Sharing follows the same boundary. Its views and components invoke
initializer-injected closure values; only the live implementations under
`Sharing/Services` bridge to `MerianNetworkClient`, the local Share-state cache,
the typed app-event publisher, preferred-name persistence, or haptic feedback.
The focused Sharing view-model extensions remain attached to the Shell-owned
`InsightSheetViewModel` rather than introducing a second root state owner.

Notifications uses the same rule: only live closures under
`Notifications/Services` bridge to `MerianNetworkClient` or viewer identity. The
catalog state owner fences refresh against pagination and read completion; the
reply-thread state owner fences route loads and pagination. Notification views
and components do not resolve endpoint clients. A failed first-page refresh
preserves the last successful catalog cursor, and a later server reply replaces
the bounded notification fallback with the authoritative comment. These client
recovery rules do not alter `/get-explore-notifications`,
`/mark-explore-notifications-read`, comment/reply payloads, or cursor semantics.

Explore Shell has no endpoint adapter. Its narrow `Services` value exposes only
the process-local typed app-event stream and the app-level Scans-library route
request. Notification post loading continues through the Feed state owner's
injected single-post dependency; the Shell coordinator only fences and maps the
result. Moving the Field-trip route declarations to
`FieldTrips/Models/FieldTripRoutes.swift` changes no request, response, JSON, or
cursor contract.

The current feed UI uses only a subset of the payload for visible card
rendering:

- `author_name`
- `author_username`
- `author_avatar_url`
- `public_location_label`
- `species_common_name` (displayed through `ExploreFeedViewModel`'s
  SwiftData-backed preferred-name cache when the viewer has a
  `UserSpeciesPreference`; dog/cat pet labels can sit above this display
  resolver when `pet_identification` is present)
- `species_scientific_name`
- `pet_identification`
- `hero_image_url`
- `reference_thumbnail_url` (author-post grids; nullable species reference image
  used for audio-backed compact thumbnails)
- `hashtags`
- `like_count`
- `comment_count`
- `viewer_has_liked`
- `reactions` and `reactions_next_cursor` for the shared reaction strip

The Explore detail page additionally uses:

- `/get-explore-post` for notification-driven navigation into posts that are not
  already loaded in the current feed page
- `/get-explore-post-detail` for taxonomy and habitat/distribution data
- `/get-explore-hashtag-posts` when a feed or detail hashtag chip opens its
  visible tagged-post collection
- `time_of_day` + `current_month` to derive broad public observation context
  such as `Morning • April`
- `weather_condition` + `weather_temperature_f` for optional public weather
  telemetry
- `/set-explore-post-reaction`, `/set-explore-comment-reaction`, and
  `/get-explore-reactions` through the injected reaction dependencies for
  selection and group pagination across cards, detail, and comment/reply sheets
- `/get-explore-comments` for the inline thread and composer state
- `/get-explore-comment-replies` for reply pagination under top-level comments
- `/get-explore-mention-suggestions` for trailing-token `@username` autocomplete
- `mentions` from comment and reply rows for tappable mention spans that open a
  typed `ExploreAuthorProfileRoute` destination
- `author_username` from post/profile/comment rows for stable handle display and
  default/ghost author labels
- `author_avatar_url` from comment rows for both `ExploreCommentsSheet` and
  `ExplorePostDetailView`
- cursor-based comment pagination on `(created_at, comment_id)` so long threads
  page safely in both the sheet and detail view
- `/get-explore-unread-notification-count` through `AppIconBadgeCoordinator` for
  the bell badge, and `/get-explore-notifications` plus
  `/mark-explore-notifications-read` through Notifications Services for the
  in-app activity sheet; the state owners keep refresh, pagination, and
  read-clearing policy outside the endpoint extension
- cursor-based activity pagination on `(updated_at, notification_id)` so the
  notifications sheet does not skip or duplicate rows during active usage
- `/set-user-follow` through the Author Profile live dependency adapter;
  `ExploreAuthorProfileViewModel` owns the optimistic state and rollback
- `/check-public-username` and `/update-public-username` through shared
  `ProfileViewModel` for the Profile account card username editor; display-name
  edits and final avatar promotion use the same shared owner and public-profile
  endpoint extension
- `/register-push-device` through Core Notifications' `PushRegistrationService`,
  coordinated by `PushRegistrationCoordinator` and entered through
  `PushNotificationManager`, to sync the APNs token, environment,
  Explore-specific push preference, independent comment-mention push preference,
  independent Community Identification push preference, and the
  `supports_post_reactions` capability. A changed token/settings/account
  snapshot admitted during an active request drains afterward instead of being
  dropped; the account scope remains local and is not an additional wire field.

The Explore map additionally uses:

- `/get-explore-map-points` for cluster or waypoint payloads in the current
  visible region
- `ExploreMapPointsResponse`, `ExploreMapCluster`, and `ExploreMapPost` from
  `Core/Network/Models/Explore/ExploreMapAPIModels.swift`
- `ExplorePostStore` as the shared in-memory post state layer, so likes,
  unshares, reports, and blocks stay synchronized between the feed tab, map
  preview card, detail route, and notification-driven navigation
- a two-step interaction in `ExploreMapView`: tap a waypoint to select and
  preview, then open `ExplorePostDetailView`
- a zoom-aware annotation treatment in `ExploreMapView`, where cluster payloads
  stay aggregate at broad zooms and individual `ExploreMapPost` payloads can
  render either simple dots or thumbnail-backed markers depending on the current
  client camera zoom and visible post count

Time and weather metadata remain in the contract for future Explore presentation
experiments, but are not currently rendered on the primary feed card.

Remote Explore APNs delivery is layered on top of this contract through the
internal `send-push-notification` webhook path. That webhook is not called by
the iOS client directly; it is triggered server-side from
`public.explore_post_notifications`. Follow notifications are excluded from push
dispatch and remain in-app only. Comment mention pushes are dispatched only to
devices with `comment_mentions_enabled` enabled; regular Explore activity pushes
use `explore_enabled`; post-reaction additions also require the registered
`supports_post_reactions` capability, and removals do not send a push. Community
Identification pushes include `communityRequestId` and use
`community_identifications_enabled`. The in-app notification row is still
retained even when the related push toggle is off. `media_missing` uses the
ordinary Explore preference and dispatches only when the incident row is first
inserted. `media_restored` remains in app only. Each APNs delivery has a
10-second deadline, a 4 KiB diagnostic-body ceiling, and an `apns-collapse-id`
equal to the durable notification UUID. Replaying the same notification
therefore does not intentionally create a second presented push.

Preferred species display names are not part of the Explore endpoint payload.
The iOS client syncs `user_species_preferences` directly through PostgREST under
Supabase RLS. The exact row/upsert models and sole direct client live in
`Core/Data/SpeciesPreferences/Models` and `Services`; the initializer-injected
`SpeciesPreferredNameCloudSyncCoordinator` owns pagination, account fencing, and
convergence, while `SpeciesPreferenceLocalRecovery` repairs interrupted local
mutations and enforces the union bound before planning and after an upsert
suspension. This does not change the table or JSON contract. Explore hydrates
`ExploreFeedViewModel.preferredSpeciesNamesByScientificName` from local
SwiftData, and applies those names in feed cards, map previews, comments, detail
titles, and share text.

---

## Deno `/identify-multimodal` Edge Node

A unified identification pipeline that merges the active capabilities of
`/identify` and the app's shipped non-visual flows into a single multi-modal
entry point. The current iOS client routes new inference traffic here. Supports
ordered compositions of images, audio, and descriptive context.

### The JSON Request Payload (From Swift `OfflineQueueManager`)

On iOS, the hand-written `IdentifyVisualMediaItem`, `IdentifyAudioMediaItem`,
and `IdentifyOwnerMediaTimelineItem` request/replay descriptors live in
`Capture/Submission/Models/IdentifyMediaDescriptors.swift`.
`CaptureSubmissionMediaProjection.swift` is the single aligned projection from
the ordered Capture timeline into audio paths/descriptors, video paths,
observation contexts, and `ownerMediaTimeline`. `Capture/Staging` owns only the
ephemeral draft and chronological nodes. These request descriptors are separate
from the generated response DTOs in `Core/AI/InferenceEdgeDTOs.swift`; moving
their owner does not change the payload below or the executable Deno contract.
`Core/Network/Endpoints/MerianNetworkClient+Inference.swift` owns the native
`/identify` and `/identify-multimodal` entry points. Its sibling
`Core/Network/Inference/InferencePayloadBuilder.swift` owns the shared JSON
mapping, while the media/request policy and immutable value files own local
budgets, staged-key account checks, conflict classification, and request
binding. `Core/Network/Transport/` owns pure route/error/replay and Auth
recovery policy, including value-only refresh-target selection, plus the
request-scoped executor that applies bounded retry, cancellation checkpoints,
and injected effects. `PinnedNetworkTransport` owns the single configured
session/TLS boundary, and `AuthenticatedTransportDispatcher` owns per-attempt
Auth/session validation and upload progress. `MerianNetworkClient.swift` injects
both behind narrow bridges. The endpoint separately owns cancellation-aware
off-main request-body preparation; this source split changes no key,
optionality, header, timeout, or server contract.

```json
{
  "r2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_image_1.webp",
    "staging/a1b2c3d4.../uuid_frame_0.webp"
  ],
  "videoR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_video_1.mp4"
  ],
  "videoFrameCount": 1,
  "visualMediaItems": [
    {
      "kind": "image",
      "sourceIndex": 0,
      "focusRegion": {
        "x": 0.125,
        "y": 0.25,
        "width": 0.5,
        "height": 0.4,
        "source": "vision_objectness"
      }
    },
    { "kind": "video_frame", "clipIndex": 0, "frameIndex": 0 }
  ],
  "audioMediaItems": [
    { "kind": "video_audio", "clipIndex": 0 }
  ],
  "ownerMediaTimeline": [
    { "kind": "image", "sourceIndex": 0 },
    { "kind": "video", "clipIndex": 0 },
    { "kind": "description", "contextIndex": 0 }
  ],
  "audioR2ObjectKeys": [
    "staging/a1b2c3d4.../uuid_audio.wav"
  ],
  "imageBase64s": [],
  "audioBase64s": [],
  "user_id": "Supabase Auth UUID",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Chicago",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "depthScaleText": "1.3 meters",
  "zoomFactor": 2.0,
  "estimated_size_cm": 11.5,
  "timestamp": "2026-03-21T09:46:03.000Z",
  "observation_contexts": [
    {
      "freeText": "Heard rustling before spotting it"
    }
  ]
}
```

- Features dynamic `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` execution if audio
  and visual evidence are both present, regardless of whether the audio arrived
  inline, from R2 staging, or as extracted audio from a video scan.
- Video scans send five ordered sampled frames through the image payload path,
  extracted accompanying audio through the audio payload path when available,
  and stage the upload-bounded playback `.mp4` in `videoR2ObjectKeys`. That
  staged video is normally a compressed 720p export, but clients may fall back
  to the original recording when it is already within the hard video byte cap.
  New clients send `visualMediaItems` (or snake-case `visual_media_items`) with
  one entry per resolved visual input so the prompt can distinguish still photos
  from ordered `video_frame` samples by `clipIndex` and `frameIndex`;
  `audioMediaItems` (or `audio_media_items`) identifies standalone audio versus
  `video_audio` by `clipIndex`. New clients also send `ownerMediaTimeline` (or
  `owner_media_timeline`) in user order. Its image item uses `sourceIndex`; an
  audio item uses both raw `audioInputIndex` and standalone `sourceIndex`; video
  and description items use `clipIndex` and `contextIndex`. A present owner
  timeline must exactly and uniquely cover every owner-visible input and agree
  with the raw descriptors; invalid, duplicate, gapped, or out-of-range metadata
  fails with `400 invalid_owner_media_timeline` before quota, provider, R2
  promotion, or deletion work. Without this additive field, legacy requests are
  processed conservatively and every resolved audio input remains durable. iOS
  therefore omits the field when an older queued visual scan lacks aligned
  `visualMediaItems`, or when persisted standalone-audio identities are sparse;
  those stored identities are preserved rather than renumbered. Replay intents
  also preserve absent versus explicitly present timelines, so schema-v1 jobs do
  not become invalid empty authoritative timelines after an upgrade. The
  playback clip is promoted only after its sampled frames pass moderation and is
  not used as Gemini inference or reference-media input. If `videoR2ObjectKeys`
  is non-empty, the scan is only successful when every requested video key is
  promoted and persisted into `video_storage_urls` and `captured_media`;
  otherwise the client receives a retryable failure rather than a frame-only
  video scan. Uploads signed with `clientScanId`/`mediaRole` already have staged
  `scan_media_assets` rows; this endpoint links those rows to the scan as
  durable media. Only a validated owner timeline authorizes consumed extracted
  `video_audio` rows to become `deleted`; failed finalization rows become
  `failed`.
- Still-photo descriptors may include `focusRegion` using top-left-normalized
  coordinates for the same complete post-crop image. The edge accepts only
  finite positive rectangles contained within `[0, 1]` with
  `source = vision_objectness`; invalid regions and all video-frame regions are
  stripped without rejecting the scan. Valid regions add a tentative attention
  hint to that photo's prompt entry; they do not prove or force the primary
  subject, and the full image remains the only Gemini visual part. The sanitized
  region survives `scan_ingestion_intents` replay; no raw image bytes or
  completed-scan field are added.
- Before inference work starts, the endpoint claims a `scan_ingestion_jobs` row
  for the authenticated user and `client_scan_id`. The claim records media
  counts, genuine staged image/audio/video source keys, recovered upload-session
  ids, and a normalized `manifest_checksum`; subsequent stage updates make
  `/check-scan-status`, health checks, and reconciliation agree on whether the
  scan is processing, retryable, complete, or terminal. Claim and compatibility
  owner-row recovery share one transaction-scoped advisory lock for that scan. A
  recovery-first winner writes a completed recovery ledger, causing claim to
  return `already_complete` before any provider call and the route replays the
  completed owner response as `200`; a claim-first winner makes recovery defer.
- Before normal retry work, a failed post-insert generation can invoke
  `recover_inline_scan_ingestion_completion`. The service-only routine repairs
  only an exact already-owned job/intent/media topology. Redacted inline-image
  counts prove when an image key was merely a historical filename hint; zero
  inline-image bytes prove queued image keys are real sources. Every real
  image/audio/video key requires one exact active owner upload row and a
  one-to-one canonical URL filename match. Only migration-marked superseded
  registration rows may coexist. A validated owner timeline proves standalone
  promotion versus companion deletion. Ambiguous shapes return `not_applicable`;
  exact shapes recompute both ledgers and call the canonical finalizer in one
  transaction.
- Before that claim, staged-media resolution, or quota reservation, the endpoint
  checks for a stored completion or an exact reconstructible owner row. A
  lost-response retry returns the stored canonical envelope, or reconstructs the
  exact durable owner row through the executable response contract even while
  its canonical ledger remains retryable. Concurrent quota conflicts coalesce
  for at most 70 seconds. Successful replay carries
  `X-Merian-Idempotent-Replay: stored|reconstructed` and cannot dispatch Gemini.
- The endpoint also records a `scan_ingestion_intents` row for server recovery.
  That row stores a sanitized replay payload with telemetry, every observation
  context, media descriptors, the owner timeline, staged keys, upload-session
  ids, and a `payload_checksum`. It never stores raw base64 media bytes or local
  device paths. Requests that used inline foreground media are marked
  `resumable = false` with `inline_media_redacted = true`; queued/staged
  media/audio/video and text-only requests are resumable. Server-side replay of
  those resumable intents is capped at 10 automatic claims before the paired job
  becomes `failed_terminal / server_replay_limit_reached` with
  `terminal_reason_code = replay_exhausted`.
- Completion is one service-only transaction. It validates every submitted
  promoted/deleted key against the claimed media manifest, permits deletion only
  for claimed audio companions, locks the owner scan, rebuilds canonical media,
  verifies every promoted capture URL has a matching ready image/video/audio
  row, writes `media_finalization_complete` last, and immutably stores the
  validated success envelope through the response-aware wrapper. Replay and
  media reconciliation use this routine rather than updating the ledger
  directly. Scan deletion clears the envelope at tombstone insertion before
  asynchronous media erasure starts.
- The edge writes `captured_media` for new multimodal scan rows. With a
  validated owner timeline, that JSON preserves the exact submitted order of
  still images, standalone audio, collapsed playback videos, and every
  description. Ordered `video_frame` samples become one video item with a
  thumbnail reference. Extracted companion audio is inference-only and is not
  emitted as a standalone or nested server media reference. Downstream video
  `has_audio` must therefore come from independent durable playback metadata,
  never from video kind alone. The required finalization transaction refreshes
  ready image/audio/video `scan_media_assets` rows from the same manifest,
  aligns their `order_index` to manifest ordinality (description positions
  intentionally leave gaps), and proves them before completion.
- Captured Media Wire V1 is executable in `_shared/capturedMediaContract.ts`.
  Every new manifest is strictly validated before persistence and preserves the
  deployed outer-key/`_0` wrappers. New descriptions contain only bounded
  `freeText`; chronology belongs to the validated owner timeline and manifest
  array order. Strict V1 rejects an empty array, and server writers persist
  `null` when canonicalization leaves no durable item. Compatibility readers
  accept historical `[]` as a missing manifest; iOS then uses the durable
  URL/context fallback columns. The generated iOS decoder accepts legacy key
  aliases, ignores any retired `addedAt`/`added_at` value without decoding it,
  tolerates and ignores device-local `localFile` references, and retains
  historical nested video-audio compatibility. Identify finalization, Explore
  media restoration, and media reconciliation all pass new manifests through the
  same strict writer; repair rewrites canonicalize readable legacy rows before
  persistence.
- Each canonical standalone-audio reference includes `sourceIndex`, copied from
  the validated descriptor. The request timeline's `audioInputIndex` binds that
  identity to its raw audio byte/key position, including when extracted video
  audio is interleaved. The client derives both arrays and the owner timeline
  from one projection. A malformed present timeline is rejected; a request with
  no timeline follows the legacy conservative builder, retains every audio clip,
  strips ambiguous standalone identity rather than guessing, and appends every
  validated description after the grouped legacy media. The legacy projection
  cannot reconstruct the original cross-modal interleaving. Its sanitized replay
  intent classifies every unproven audio input as unindexed durable audio, so
  post-insert recovery uses the same retain-all decision as the original write.
- Authenticated iOS history hydration treats a nonempty `captured_media`
  manifest as authoritative only when mapping yields a usable image or video. It
  keeps request/DTO values in `Core/Data/Database/HistoricalSync/Models`,
  row-isolated decoding in `HistoricalSync/Decoding`, and the exact live
  scan/collection projections plus account lease in
  `HistoricalSync/Services/HistoricalSyncCloudClient.swift`. `ScanRepository`
  orchestrates these owners but no longer resolves the Supabase client or
  constructs PostgREST queries directly. It dual-reads `audio_storage_urls`,
  `image_storage_urls`, `video_storage_urls`, and `user_observation_context` so
  `[]`, device-only references, or an otherwise incomplete legacy manifest
  cannot erase durable media or description provenance. Those existing scan
  columns are compatibility fallbacks, never public-feed projections. Because
  they do not retain cross-modal positions, legacy hydration appends missing
  audio in stored-array order, then appends the stored context.
  `audio_storage_urls` is supplemental recovery data, not deletion authority.
  Cloud audio replaces an existing standalone clip only when its exact path or a
  unique `sourceIndex` matches. Unindexed legacy and restore references never
  consume a local clip by ordinal guess; unmatched references are retained,
  which can temporarily expose both a local alias and a durable URL but cannot
  delete the wrong recording. Unmatched local descriptions are retained because
  this compatibility column stores only one context. History pages decode each
  PostgREST row independently: a malformed row is quarantined with bounded
  structural diagnostics while valid rows on the same page continue reconciling.
  A targeted completed-result read classifies a malformed row as a contract
  mismatch rather than a transport failure.
- The same authenticated history projection requires the nullable
  `explore_posts(id, unshared_at)` relation key on every accepted scan row.
  Because `explore_posts.scan_id` is unique, PostgREST embeds this as one object
  or explicit `null`. An omitted key is a contract mismatch and cannot clear the
  local share cache. An object with `unshared_at = null` restores
  owner-preserved active publication intent; explicit relation `null` or a
  non-null `unshared_at` removes it. Per-request reconciliation revisions ensure
  a stale response cannot overwrite a newer local share, unshare, deletion,
  purge, or history response.
- Parses `audioBase64s` and `audioR2ObjectKeys` as mutually exclusive arrays of
  nonempty strings before any `.length`, key, decode, or fetch operation. A
  malformed shape returns `400 invalid_audio_transport`; two nonempty transports
  return `400 ambiguous_audio_transport`.
- Requires every resolved inference clip to have a RIFF/WAVE container before
  executing `processMultimodalWAV` in Deno to enforce mono/16kHz processing
  before Gemini ingestion. A different container returns
  `400 unsupported_audio_codec`; a malformed WAV returns
  `400 invalid_audio_content`. The request fails as a unit, so mixed
  visual/audio inference cannot silently drop invalid audio or persist it under
  an `audio/wav` label. For `video_audio` mapped to a clip by a present,
  validated owner timeline, preprocessing retains the original audio when
  silence trimming alone would leave less than 0.5 seconds. The source must
  still be a valid WAV of at least 0.5 seconds. Standalone and legacy unproven
  audio keep the strict post-trim duration check.
- Shared WAV preparation (also used by `/audio-spec`) measures every 20 ms RMS
  window, including a final partial window using its actual sample count. The
  0.008 silence threshold and two padding windows remain unchanged. Sample-rate
  conversion uses a Blackman-windowed sinc low-pass filter with a
  90%-of-lower-Nyquist cutoff, radius 32 at the lower rate and 128 interpolated
  fractional phases. Endpoint replication supplies boundary samples; output
  length remains `floor(trimmedFrames * 16000 / sourceSampleRate)`. Output is
  mono PCM16 WAV with no added tail, time offset or signal gain normalization.
  Already-16 kHz audio bypasses resampling. The 16 kHz representation cannot
  retain frequencies above 8 kHz; it is a Merian policy, not a claimed provider
  requirement.
- Each source and encoded output WAV is bounded to 2,700,000 bytes. The output
  limit allows at most 1,349,978 mono PCM16 frames (84.373625 seconds at 16
  kHz), so low-rate uploads that previously expanded beyond that size now fail.
  Resampling is additionally bounded to 2,000,000 stored coefficients and
  100,000,000 filter taps per clip, checked before allocation/convolution.
  `WavProcessingBudgetError` returns `413 payload_too_large` from both handlers
  before provider admission, with a shorter-recording message; malformed or
  non-finite PCM retains the invalid-audio response. These are processing
  ceilings, not changes to native recording duration, model or prompt policy.
- Queued replay audio uses `audioR2ObjectKeys`; queued and live video use
  `videoR2ObjectKeys`; live foreground audio uses size-preflighted inline
  `audioBase64s`. The edge rejects oversized declared media JSON
  `Content-Length` before body parsing, then parses through
  `readRequestJsonWithinBudget` so missing-length/chunked bodies are still
  capped. Clip count, byte budgets, IDOR ownership, and path traversal are
  validated through `_shared/identify/media.ts` before decode/fetch.
- The canonical request contract is camelCase telemetry (`gpsLatitude`,
  `semanticLocation`, `publicLocationLabel`, `geoprivacy`, `deviceTimeZone`,
  etc.), `ownerMediaTimeline`, plus `observation_contexts: [{ freeText }]`,
  matching `MerianNetworkClient.buildMultiModalRequest(...)` in
  `Endpoints/MerianNetworkClient+Inference.swift` and the iOS
  `ObservationContext` model. `InferencePayloadBuilder` in the sibling
  `Inference/` folder also backs `/identify` so visual and multimodal requests
  share telemetry formatting, user context, and pre-serialization inline media
  budget validation. Legacy `addedAt`/`added_at` input is accepted only for
  rolling compatibility and discarded before replay intent or scan persistence.
  New `scan_ingestion_intents` use schema version 3 and persist text-only
  contexts; schema-v2 rows remain readable and are normalized through the same
  discard path during replay.
- If `geoprivacy` is missing, invalid, or supplied by an old queued payload, the
  Edge insert helper resolves the scan privacy from `users.default_geoprivacy`.
  Private scans clear `public_location_label` server-side even if a stale client
  supplied one.
- `deviceTimeZone` is persisted to `public.scans.device_time_zone` when present
  so public profile streaks and heatmaps can use the author's local day
  boundary. Missing or invalid legacy rows fall back to UTC at profile-read
  time.
- The server still accepts legacy snake_case telemetry aliases (`gps_latitude`,
  `semantic_location`, `time_of_day`, etc.) and legacy `free_text` context keys
  so offline queue replays and older internal tooling do not break
  mid-migration.
- Candidate handling now matches `/identify`: the response strips `candidates`
  when `confidence_score >= diagnosticTrigger`, enriches forwarded candidates
  with cached English common names when available, and schedules background
  enrichment for cache misses.
- The multimodal durable-ingestion path shares the same `_shared/identify` DB,
  media, schema, threshold, and moderation primitives as `/identify`.

The Gemini object and final server-enriched response are both parsed through
`_shared/identify/contract.ts`. The second parse occurs before durable image or
video finalization and HTTP success, so cache/provider drift cannot reach the
generated Swift decoder or durable scan state. Contract failures use stable
public code `identify_response_invalid`; detailed path errors remain in
structured server logs.

### Latency and Authentication Contract

Ordinary request and JSON response bodies remain backward-compatible. The
optional, separately gated
[audio comparison handle](#server-owned-audio-comparison) does not change
ordinary clients. The endpoint emits diagnostic response headers:

- `Server-Timing`: `auth`, `body_read`, `tier`, `pre_gemini_db`, `gemini`,
  `quota_commit`, `provider`, `video_promotion`, `primary_enrichment`,
  `database_finalization`, `dictionary`, `post_gemini`, and `edge_total`
  durations in milliseconds.
- `X-Merian-Edge-Region`: the runtime region reported by the Edge environment,
  when available.
- `X-Merian-Identification`: bounded JSON diagnostics on fresh durable success
  only. Version `1` contains `provider`, `requestedModel`, nullable
  `returnedModel`, `backendBundleSha256`, and nullable `usage`. Usage contains
  nullable nonnegative integer `promptTokens`, `candidateTokens`,
  `thinkingTokens`, `totalTokens`, `cachedTokens` and `toolTokens` (maximum
  10,000,000 each). Current provider/model values come from the admitted Gemini
  attempt; returned model is a bounded Gemini version token. No provider text,
  modality dictionary, owner or request identifiers enter this header.

The identification header is exposed to browser clients on fresh success and is
absent on errors and stored/reconstructed replays. It changes no Identify JSON
envelope, ledger persistence or billing contract. Its generated bundle
fingerprint covers the Function's local runtime graph/configuration/lock, not a
Git SHA, database or environment revision. The native diagnostic parser rejects
unknown header versions and projects only bounded fields, keeping absent usage
and source values unknown. Native measurement logs include an optional fixed
`timingStatus` reason to distinguish an absent timing header from a rejected
one, without retaining its text. This local diagnostic does not change the HTTP
header or Identify JSON schema. The
[app measurement guide](../development-guides/21-identification-app-measurement.md)
owns passive recording, app source identity, separate timing boundaries and
offline primary-attempt cost estimates.

The successful `multimodal/latency` event also includes `quota_commit_ms`,
`provider_ms`, `video_promotion_ms`, `primary_enrichment_ms`, and
`database_finalization_ms`, matching the new header spans. `provider` measures
only the awaited Gemini SDK call, including provider transport; the legacy
`gemini` / `gemini_latency_ms` still includes quota commit for comparison with
older logs. `video_promotion` measures playback promotion after its job-state
checkpoint. `primary_enrichment` measures the awaited primary external lookup,
including a caught lookup failure, and excludes optional candidate enrichment.
`database_finalization` covers the scan-insert checkpoint, insertion, and
canonical finalization/read-back; it excludes earlier species-dictionary work.
Optional phases that do not run report zero. These components do not partition
`edge_total`: moderation, audio promotion, dictionary work, and other overhead
remain in the existing broader spans. Failure responses and idempotent replay
responses do not emit this successful-request event.

The request may include `X-Merian-Constrained-Network: true|false` for aggregate
latency segmentation. Logs and headers never contain user ID, scan ID, species,
location, media keys, or request contents. `gemini` stops immediately after the
single `generateContent` call returns.

`/identify-multimodal` verifies the bearer token with the cached ES256 JWKS path
through `auth.getClaims(token)`, then explicitly validates issuer, audience,
expiration, not-before, role, and `sub`. Both anonymous and authenticated user
JWTs are accepted. Service-role tokens are rejected on this public endpoint. The
request body's `user_id` is never an authority source. The existing
`X-Merian-Internal-Replay` path is checked before public claims auth and retains
its exact platform-managed service-key verification plus explicit replay-user
header. Legacy service-role JWTs use Bearer transport; named non-JWT
`sb_secret_...` values use `apikey` only. The accepted request value is not
reused by the privileged database client.

Before Gemini, one service-role-only `begin_scan_ingestion` RPC performs upload
session lookup, ingestion claim, sanitized intent recording, and the
`ai_inference_started` stage transition atomically. It returns the recovered
upload-session ids plus manifest and payload checksums canonicalized from the
exact stored values. This is also the pre-provider boundary for `/identify`,
`/identify-describe`, and `/audio-spec`; no route falls back to separate writes.
The client fails closed on malformed UUID/checksum/stage/completion output.
After Gemini, eligible biological results use at most one
`hydrate_identification_dictionary` RPC to return cached primary-species data
and candidate common names. Primary Wikipedia/GBIF cache misses, moderation,
required media promotion, and scan insertion complete before success for every
current multimodal observation. Analytics, group tags, and candidate enrichment
remain optional `EdgeRuntime.waitUntil` work.

## Deno `/update-scan-context` Edge Node

Adds late WeatherKit/geocoding data to the owner's active ingestion job or
completed scan without rerunning identification.

On iOS, `Core/Network/Endpoints/MerianNetworkClient+ScanEnrichment.swift` owns
the request's unchanged 15-second HTTP boundary. Capture Submission's service
keeps durable local context and its delayed retry; an empty native
optional-field set returns without Auth/transport only after configuration
validation. Native payload, error-ordering, and caller regressions belong to the
[enrichment/export/feedback matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification).

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-0000-4000-8000-000000000000",
  "gps_elevation": 42.5,
  "weather_condition": "Partly Cloudy",
  "weather_temperature_f": 68.0,
  "semantic_location": "Zilker Park"
}
```

`scan_id` is required and must be a UUID. Every other field is optional, but at
least one valid late-context field must be present. The endpoint accepts
camelCase aliases and normalizes them before the database call. Empty strings
and non-finite/out-of-range numeric values are omitted; a request with no valid
context returns `400`.

### Response

```json
{ "success": true, "applied": true }
```

`applied` is `true` when the owner's scan already exists and `false` when the
update is staged until ingestion creates it. The endpoint verifies the same
anonymous/authenticated user claims as `/identify-multimodal`. The
service-role-only `apply_or_stage_scan_context` RPC owns the update, so a caller
cannot attach context to another user's scan.

The route returns `409` when neither the owner scan nor its ingestion claim is
visible yet. On iOS, `CaptureSubmissionDeferredContextService` first preserves
the same context in the durable local queue, then attempts this endpoint and
retries the remote update at most once after 500 ms. The service is the
Submission network boundary; Capture view-model extensions do not call the
endpoint. Endpoint, transport, or task cancellation is terminal and never starts
the retry; the durable local copy remains available for normal queue recovery.
This condition never causes a second identification request.

## Text-Only Describe Path

The current app routes text-only observations through `/identify-multimodal`
with `observation_contexts` populated and no images or audio attached. Locally,
that request is still assembled from the same canonical mixed-media timeline
used by image and audio submissions; the server simply receives an empty media
body plus the description payload.

### Request Payload

```json
{
  "user_id": "Supabase Auth UUID",
  "client_scan_id": "UUID generated by iOS for idempotency",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "semanticLocation": "Zilker Park",
  "publicLocationLabel": "Austin, Texas",
  "geoprivacy": "obscured",
  "weatherCondition": "Partly Cloudy",
  "weatherTemperatureF": 68.0,
  "deviceLocale": "en",
  "deviceTimeZone": "America/Los_Angeles",
  "deviceRegion": "US",
  "currentMonth": 4,
  "timeOfDay": "10:30 AM",
  "timestamp": "2026-04-14T10:30:00.000Z",
  "observation_contexts": [
    {
      "freeText": "Medium-sized bird, vivid blue upperparts, rust-orange breast, perched on fence post in suburban garden. Heard a clear flute-like song before spotting it."
    }
  ]
}
```

`client_scan_id` is generated by the iOS client and forwarded as
`generatedScanId` to the edge function. The current multimodal text-only path
inserts through the shared `insertScan` contract using the same idempotent scan
ID semantics as image and audio requests.

The current iOS client does not send a top-level `description` field on this
path. The edge function concatenates the `observation_contexts[*].freeText`
entries into the multimodal prompt server-side. A validated owner timeline
places every context into canonical `captured_media` at its submitted position;
the first structured context is also persisted to
`public.scans.user_observation_context` as a legacy compatibility projection.
The iOS client guards on `ObservationContext.isEmpty` before allowing
submission.

Legacy `/identify-describe` requests still use a top-level `description` field,
but that compatibility endpoint records a multimodal-shaped
`scan_ingestion_intents` row before returning success. Retryable text-only
compatibility rows therefore recover through `/identify-multimodal` with the
same `client_scan_id`.

`r2ObjectKeys`, `imageBase64s`, and `audioBase64s` are intentionally absent —
there is no media in a text-only submission. `scans.image_storage_urls` is
written as an empty image array by the shared insert path because there is no
promoted media to persist.

### Response Schema

The response shape mirrors the `/identify` / `/identify-multimodal` JSON
response exactly and is validated by the same executable final wire contract.
The Describe provider schema is generated from a text-only contract variant that
requires every `image_quality` value to be exactly zero. `scan_id` is returned
as the scan UUID generated for that text-only request.

### IDOR & Auth

The server extracts the user identity from the verified `Authorization: Bearer`
JWT claims. The `user_id` in the request body is ignored for auth purposes.

### Error Responses

| Status | Body                                                                                                                              | Meaning                                                                            |
| ------ | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `400`  | `{ "error": "At least one media element or description is required" }`                                                            | No image, audio, or non-empty `observation_contexts[*].freeText` text was provided |
| `400`  | `{ "error": "We couldn’t process this observation. Please try a different photo or recording.", "code": "observation_rejected" }` | Permanent Gemini safety / policy failure                                           |
| `503`  | `{ "error": "Processing Error: Malformed AI response." }`                                                                         | Gemini returned malformed or structurally invalid output; delivery may retry       |
| `502`  | `{ "error": "AI response validation failed. Please retry.", "code": "identify_response_invalid" }`                                | Final server-enriched payload violated the wire contract                           |
| `503`  | `{ "error": "AI processing error. Please try again." }`                                                                           | Transient Gemini failure                                                           |

---

## Deno `/enrich-scan` Edge Node

An enrichment endpoint that asynchronously surfaces habitat, taxonomy, and
similar species data for a scan. The iOS client schedules missing scopes for
eligible current or historical biological scans under its hydration admission
and backoff policy. `HabitatAndDistributionCard` shows a loading skeleton while
the metadata scope is in flight.

The native `fetchEnrichment` request is owned by
`Core/Network/Endpoints/MerianNetworkClient+ScanEnrichment.swift`.
`Core/AI/Inference/Hydration/InferenceSpeciesEnrichmentService+Live.swift` is
the sole Core AI endpoint adapter; the injected core resolves no live client
directly and maps each scoped wire projection into a typed domain patch.
`InferenceHydrationPersistenceService+Live.swift` owns local database effects
and off-main lookalike encoding. `InferenceSpeciesEnrichmentCoordinator` keeps
scope scheduling, retry, and current-presentation application/fencing;
`InferenceHydrationCoordinator` owns task admission, lifetime, and backoff.
`InferenceSpeciesPresentationCoordinator` exposes observable-state callbacks and
retains bounded write admission behind the stable `InferenceEngine` facade.
`EnrichScanResponse` remains hand-written below the generated Identify block in
`Core/AI/InferenceEdgeDTOs.swift`. The native client sends all five fields
including `scope`, preserves its 30-second deadline, and serializes before
requiring a UUID `scan_id` for the canonical lowercase `Idempotency-Key`. It
forwards the serialized bytes through the existing authenticated transport and
uses plain JSONDecoder without remapping decoding failures or adding
success/data requirements. See the
[native verification matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification).

### Request Payload

```json
{
  "scan_id": "A1B2C3D4-0000-4000-8000-000000000000",
  "scientific_name": "Danaus plexippus",
  "confidence_score": 0.91,
  "inference_tier": "flash",
  "scope": "enrichment"
}
```

The Edge function requires `scientific_name` and `scope`. The scientific name
must be a non-empty string of at most 500 characters; scope must be exactly
`"enrichment"` or `"lookalikes"`. A supplied, non-null `scan_id` must be a UUID.
The handler lowercases it into `originalAnalysisId` for either scope's
provider-quota reservation; it is not a caller-selected authorization identity.
`confidence_score` and `inference_tier` remain native compatibility fields and
are not consumed by this handler.

The native endpoint forwards scope unchanged to preserve its existing request
contract. Tests using legacy or invalid scopes verify that forwarding, not
server acceptance; the public route still rejects unsupported scopes.

### Architecture

**No Tier Gate**: Available to all authenticated users, with uncached provider
work subject to quota admission. Data is cached in `species_dictionary` at the
species level and can be reused when the requested scope's cache requirements
are satisfied.

**No Confidence Gate**: The Edge function accepts `confidence_score` for
telemetry compatibility but does not use it to decide whether similar species
should be generated or returned. Similar-species generation is gated by taxonomy
quality and cache state, not confidence, and the iOS gallery renders validated
entries with the stable "Similar species" label.

**Provider boundary**: Cache misses reserve the existing
`scan_overview_enrichment` or `scan_lookalike_enrichment` quota, prepare the
matching `_shared/ai/` task with that user permission/model/reservation, then
commit immediately before invocation. Gemini remains the only live provider.
Same-scope waiters await the cache write; if the leader fails, the original
rejection reaches waiters and a new attempt requires fresh admission. An
observer also handles failures when no waiter exists. Existing usage writes add
bounded task/provider/version/duration/outcome metadata. Internal execution
metadata is excluded by the public response formatters; no request or response
field changes. The independent `sharedContent.ts` acceptance guard requires the
retained Gemini content profiles before quota commitment; unsupported profiles
refund without invocation. This guard covers foreground enrichment, optional
group tags and claimed public refresh jobs. Existing canonical cache content is
not relabeled or invalidated. Warm-isolate coalescing uses task/profile
namespace, canonical species ID (or name fallback), exact input name, locale and
taxonomy fields, so materially different inputs do not share a pending result.

**Scoped Cache Hits**: Each request checks its own cache requirements and
returns only that scope's fields without AI work when satisfied. A metadata
cache hit does not imply a lookalike cache hit. Missing alternative names can
still require a GBIF fetch on the metadata path; the iOS caller combines the
independently arriving projections.

**Two-Layer Lookalike Strategy**:

- **Layer 1 — Taxonomy trigger (zero token cost)**: A Postgres `AFTER INSERT`
  trigger (`trg_link_taxonomy_lookalikes`) auto-populates `species_lookalikes`
  with same-genus links whenever a new species row is inserted, but only when
  both rows have a real genus and matching kingdom. Placeholder taxonomy such as
  `"Unknown"` is normalized away and never participates in trigger linking. The
  trigger is transaction-scoped off while the scheduled model worker
  materializes an exact-GBIF candidate; that path writes only its explicit
  directional relation.
- **Layer 2 — Gemini Flash for cross-family visual mimics**:
  `fetchSimilarSpecies` requires usable primary taxonomy and an unsatisfied
  lookalike cache gate. That gate accepts at least one resolved non-null common
  name or a prior `lookalikes_flash_attempted` flag. Same-species waiters first
  await in-flight work and re-read its cache; provider admission remains subject
  to quota. Flash receives the species' normalized taxonomy (`kingdom`, `class`,
  `order`, `family`) from `cachedSpecies` and is constrained by the system
  instruction to return lookalikes from the **same taxonomic order** — not
  merely the same kingdom. After Gemini returns entries,
  `resolveLookalikesToJoinTable` validates the candidates again before writing
  anything durable.

**Taxonomy Grounding (`fetchSimilarSpecies` + `resolveLookalikesToJoinTable`)**:
Flash is passed normalized `kingdom`, `class`, `order`, and `family` from
`species_dictionary`. Placeholder strings like `"Unknown"` or blank values are
collapsed to `null` before prompting. The system instruction explicitly forbids
cross-order results (e.g. grasses as lookalikes for Narcissus — both Plantae but
different orders). `resolveLookalikesToJoinTable` now requires a real
`primaryKingdom` and at least one higher-rank discriminator (`primaryOrder` or
`primaryFamily`). Each resolved candidate must have a real matching `kingdom`,
and then either a matching `order` or, if order is unavailable on both sides, a
matching `family`. The foreground path omits candidates with missing taxonomy or
no existing `species_dictionary` row. The scheduled model worker can create a
missing row only after exact accepted GBIF resolution and repeats the same
taxonomy checks inside `persist_species_model_lookalikes(...)`. **Early-exit on
insufficient taxonomy**: On a foreground lookalike cache miss, missing usable
primary taxonomy prevents a Flash call. The response still uses the scoped
formatter's legacy-name fallback, or `similar_species: null` when no fallback
exists. Foreground `enrich-scan` sets `lookalikes_flash_attempted` only when
`resolveLookalikesToJoinTable` returns `persisted: true`. The scheduled worker
also sets it for a resolution-complete empty, incompatible, duplicate, or
reviewed-rejected outcome. A partial result that writes at least one relation
sets the flag while leaving the queue job retryable; a retryable failure with no
persisted relation leaves it false.

**Automatic Stale Contamination Detection**: On each `lookalikes` scope request,
`index.ts` compares the primary species' normalized `order` or `family` against
cached join-table entries. If the primary species has a known `order` and every
cached entry has a different known order, or if order is unavailable but family
is known and every cached entry has a different known family, the stale rows are
automatically cleared via `clearLookalikesForSpecies`,
`lookalikes_flash_attempted` is reset to `false`, and a fresh validated attempt
can run. This is self-healing for the characteristic contamination signature
created by old placeholder-taxonomy writes.

**Recovery ownership**: Do not infer a failed attempt from an empty
`species_lookalikes` set or reset the attempt flag with a blanket data update.
Empty is a valid terminal result after complete validation. Proven
cross-order/cross-kingdom contamination is still cleared by the foreground
stale-cache detector above. Legacy empty successes and exhausted failures are
repaired by the versioned scheduled-worker claim, which grants one attempt only
when no nonrejected relation exists and records the version atomically at claim
time. The worker's `dry_run` preview uses the same eligibility predicate without
locks, writes, or marker changes.

**Migration Path**: If the join table is empty but `similar_species TEXT[]` has
legacy name strings (populated by older pipeline versions), they are resolved to
the join table at zero token cost before returning, using the same
kingdom/order/family validation as fresh Flash output.

**Independent Scoped Requests**: The stable
`InferenceEngine.fetchAndApplyEnrichment` facade delegates through the species-
presentation bridge to the species-hydration owner. Its private-state enrichment
sub-coordinator uses a task group to ask `InferenceSpeciesEnrichmentService` for
missing metadata and lookalikes separately. The service's live adapter makes one
endpoint call for the typed scope; each handler invocation performs only its own
scope's work, and there is no combined `Promise.all` generation branch. Provider
calls use the model selected by the quota reservation, and lookalike generation
requires usable primary taxonomy. After both initially requested scopes finish,
iOS may retry only lookalikes once if the presentation is still current, no
similar species are present, and usable taxonomy is now available. That retry
disables further lookalike retries and remains subject to the existing hydration
admission/backoff.

### Response Schema

An `"enrichment"` response contains metadata only:

```json
{
  "success": true,
  "data": {
    "scope": "enrichment",
    "habitat_description": "Frequently spotted in milkweed patches, meadows, and open plains.",
    "gbif_taxon_key": 5130978,
    "alternative_common_names": ["Monarch", "Common Tiger"],
    "taxonomy": {
      "kingdom": "Animalia",
      "phylum": "Arthropoda",
      "class": "Insecta",
      "order": "Lepidoptera",
      "family": "Nymphalidae",
      "genus": "Danaus"
    }
  }
}
```

A `"lookalikes"` response contains only its discriminator and similar species:

```json
{
  "success": true,
  "data": {
    "scope": "lookalikes",
    "similar_species": [
      {
        "species_id": "uuid",
        "scientific_name": "Limenitis archippus",
        "common_name": "Viceroy",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": "LC",
        "reason": "Similar orange-and-black wing pattern.",
        "visual_traits": ["orange wings", "dark venation"],
        "confidence": 0.86,
        "source": "model_enrichment",
        "review_status": "unreviewed",
        "is_bidirectional": false,
        "sort_order": 0
      },
      {
        "species_id": "uuid",
        "scientific_name": "Danaus gilippus",
        "common_name": "Queen",
        "reference_image_url": "https://inaturalist-open-data.s3.amazonaws.com/...",
        "iucn_red_list_status": null
      }
    ]
  }
}
```

`gbif_taxon_key` can be `null` or absent when there is no cached GBIF key. The
lookalike formatter prefers resolved entries, falls back to legacy
`similar_species TEXT[]` names when present, and otherwise returns
`similar_species: null`. The usable-taxonomy guard suppresses new provider work;
it does not change that formatter's legacy fallback. Resolved entries come from
the `species_lookalikes` join table joined to `species_dictionary` — providing
`species_id`, `common_name` (English), `reference_image_url`,
`iucn_red_list_status`, and additive relation metadata (`reason`,
`visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`,
`sort_order`) when available. The image URL prefers the first
`species_reference_images` row and falls back to the legacy dictionary cache.
Raw Gemini names with no dictionary/taxonomy validation are no longer returned
or persisted; legacy `similar_species TEXT[]` fallbacks may omit `species_id`
and relation metadata until they are resolved into the join table. Successful
enrichment writes also record source/freshness metadata in
`species_content_provenance`; this does not change the client response.

`alternative_common_names` is `string[] | null`. It can be `null` when no
alternative names are available, including a missing cached GBIF key or no
additional English vernacular names returned by GBIF. The enrichment scope
serves this field from `species_dictionary.alternative_common_names` on a cache
hit. When that column is `null` (covering pre-V34 cached species,
compatibility-route timing, or a current model response that preceded its
awaited dictionary resolution), and a cached GBIF taxon key is available, the
Edge function calls `fetchGBIFVernacularNames` live to retrieve English
vernacular names from the GBIF API and populates the field from the result. This
route's scoped formatter retains the legacy `"Unknown"` fallback for a taxonomy
rank missing from both generated and cached data. That placeholder is not usable
taxonomy: the native lookalike eligibility policy normalizes it away. These
compatibility details are unchanged by the native endpoint extraction.

**iOS mapping**: The array is decoded as
`[EnrichScanResponse.SimilarSpeciesEntry]` (snake_case Codable DTO in
`InferenceEdgeDTOs.swift`) and mapped to the domain `SimilarSpecies` struct
(camelCase, in `apps/ios/Merian/Models/Species/SimilarSpecies.swift`) by the
initializer-injected `InferenceSpeciesEnrichmentService`, whose core has no
direct live-client dependency. The enrichment coordinator applies that typed
patch only to the current presentation through the species-presentation
callback, then submits an immutable snapshot through the bridge's bounded write
admission. `InferenceHydrationPersistenceService+Live` encodes
`[SimilarSpeciesEntry]` off-main and delegates the admitted mutation to
`BackgroundDatabaseActor`, which persists the `Data` blob as
`LocalScanRecord.lookalikesData` (added in `MerianSchemaV27`) — the primary
SwiftData storage for rich lookalike data. The metadata mapping crosses the
persistence boundary as domain `TaxonomyData`; wire DTOs do not enter the
database actor. The legacy `LocalScanRecord.similarSpecies: [String]?` field is
retained as a backwards-compatible fallback for pre-V27 records where
`lookalikesData` is nil. `InferenceHistoricalRecordProjection`, constructed by
`InferenceHistoricalLoadCoordinator` behind `InferenceEngine.load(from:)`, owns
that fallback and turns the injected reset decision into a value-only hydration
plan. The load coordinator publishes the initial projection and registers
`InferenceHistoricalHydrationCoordinator`, which submits only the projected
metadata and lookalike scopes through the shared species coordinator.
`InferenceLookalikeCacheResetService` owns reset admission; only its live
adapter reads/writes the installed `UserDefaults` version and schedules the
coalesced database-actor wipe. Previously poisoned `lookalikesData` blobs are
therefore ignored and refreshed through the hardened backend validation path.
`SimilarSpeciesGallery` always labels validated entries as "Similar species";
identification uncertainty is handled by the separate candidates/review surface.

**Authoritative quota**: Cache hits perform no paid provider work and consume no
AI quota. A cache miss reserves either `scan_overview_enrichment` or
`scan_lookalike_enrichment` before generation. Their shared UTC-day ceilings are
4 for free, 100 for complimentary Pro, and 500 for paid Pro, with additional
shared per-user/IP minute ceilings. iOS uses the stable scan UUID as the
`Idempotency-Key` for both scopes (the operation is part of the database
namespace), so later app-level retries cannot allocate a fresh reservation.
Provider attempts consume quota even if the provider response is malformed; a
pre-provider cache/no-op path may refund.

### Error Responses

| Status      | Body                                                                | Meaning                                       |
| ----------- | ------------------------------------------------------------------- | --------------------------------------------- |
| `400`       | `{ "error": "Missing required parameters..." }`                     | Required enrichment input absent              |
| `400`       | `{ "code": "ai_request_id_invalid", ... }`                          | Supplied request key is not a UUID            |
| `400`/`500` | `{ "error": "AI processing error during enrichment..." }`           | Provider or enrichment persistence failure    |
| `429`       | `{ "code": "ai_quota_daily_exceeded", "retry_after_seconds": ... }` | Plan's UTC-day AI ceiling reached             |
| `429`       | `{ "code": "ai_user_rate_limit_exceeded", ... }`                    | Per-user minute ceiling reached               |
| `429`       | `{ "code": "ai_ip_rate_limit_exceeded", ... }`                      | Network minute ceiling reached                |
| `503`       | `{ "code": "ai_entitlement_unavailable", ... }`                     | Entitlement/quota state could not be verified |

---

## Deno `/insight-chat` Edge Node

Private Pro follow-up chat for completed, resolved non-Human biological Insight
sheets. The endpoint uses the authenticated Supabase user from
`withEdgeHandler`, verifies ownership of `scan_id`, and rejects explicit
non-biological state, unresolved selected taxonomy, Human taxonomy aliases, and
a Human user override before reading durable effective tier through
`_shared/entitlement.ts`. The selected relation is confirmed taxonomy first,
then the original species. This guard never reads `ai_reasoning`. Each provider
action then reserves its operation in the database, which repeats entitlement
verification atomically with quota and model selection.

### iOS Ownership and Application Boundary

Core Network owns the Codable wire DTOs in `InsightChatAPIModels.swift`, the 17
source methods in `Endpoints/MerianNetworkClient+FieldChat.swift`, and strict
stateless response validation in `Decoding/FieldChatResponseDecoder.swift`.
`Core/Network/Transport/` owns stateless replay, route/error classification,
retry-account binding, and value-only Auth-recovery decisions through
`UnauthorizedRefreshTarget`. Its request-scoped executor applies those decisions
and injected effects. `PinnedNetworkTransport` owns the single session/TLS
boundary, `AuthenticatedTransportDispatcher` owns per-attempt Auth validation
and its upload delegate, and `MerianNetworkClient.swift` injects both. Field
Chat cloud-readiness and eligible owned-row recovery live in
`Recovery/MerianNetworkClient+OwnedScanRecovery.swift`; Field Chat does not
restore public media. The narrow encoded-body POST bridge returns bytes to the
decoder without adding a retry or task owner. See the
[Core endpoint guide](../../apps/ios/Merian/Core/Network/README.md#field-chat-endpoints-and-validation)
for the unchanged per-action timeout and idempotency policies.
`Features/FieldChat/Services/FieldChatEndpoint.swift` adapts `FieldChatSource`
to the exact Insight, Explore-post, or Species Dictionary route, while the
feature's narrow dependency value owns its live effects.
`Features/FieldChat/ViewModels` owns main-actor conversation state and the
subject, request, prompt, and preparation generations. Host features retain
eligibility, entitlement, navigation, and their typed presentation slots; Field
Chat views and components call no endpoints.

These client boundaries do not change the JSON contract. They ensure a canceled
send leaves the exact current pending bubble failed and retryable under its
original UUID, the newest prompt trigger wins even when task scheduling is
reordered, and canceled readiness work cannot commit into a replacement subject.

### Request Payload

```json
{
  "action": "send",
  "scan_id": "A1B2C3D4-...",
  "message_text": "What traits support this identification?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

Feedback and field-notes summary actions use the same endpoint:

```json
{
  "action": "feedback",
  "scan_id": "A1B2C3D4-...",
  "message_id": "33333333-3333-4333-8333-333333333333",
  "feedback_rating": "wrong",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "feature_feedback",
  "scan_id": "A1B2C3D4-...",
  "feature_feedback_sentiment": "positive",
  "feedback_note": "Optional short private note"
}
```

```json
{
  "action": "summarize_notes",
  "scan_id": "A1B2C3D4-..."
}
```

AI-generated quick prompts use the same endpoint and never include user draft
text:

```json
{
  "action": "suggest_prompts",
  "scan_id": "A1B2C3D4-..."
}
```

`action` accepts `load`, `send`, `delete`, `feedback`, `feature_feedback`,
`summarize_notes`, or `suggest_prompts`. `load` returns the single saved
conversation for the scan when one exists. `send` creates that conversation when
missing, and requires both `message_text` and a UUID `client_message_id` for
idempotency. `delete` clears the scan's saved chat. `feedback` stores private
owner-only answer feedback for an assistant `message_id` with `feedback_rating`
(`helpful`, `not_helpful`, `wrong`, `unsafe`, `other`) and optional
`feedback_note`. `feature_feedback` stores private owner-only feedback on the
Field chat sheet itself with optional `feature_feedback_sentiment` (`positive`
or `negative`) and optional `feedback_note`; at least one is required.
`summarize_notes` returns a reviewable field-notes draft from the current saved
chat and scan context; the client must append it only after user confirmation
and must never replace existing field notes. `suggest_prompts` returns three
short, non-persisted prompt chip suggestions plus allowlisted categories for
telemetry; it uses the same owned scan context and recent saved chat history,
does not consume the daily send limit, and is best-effort so load/send chat
behavior remains independent if prompt generation fails. The server caps v1 at
600 characters per user message, 30 total persisted message rows per
conversation, and 20 sends per Pro user per day across all of that user's
Insight, Explore, and Species Dictionary chats. A new request reserves room for
its user and assistant rows together; an incomplete retry already owns its user
row but must still have one slot for the assistant. Functional Pro includes paid
access and current server-verified complimentary access.

`send` uses `client_message_id` as the UUID provider idempotency key. The iOS
client sends a UUID `Idempotency-Key` header for `suggest_prompts` and
`summarize_notes`; every automatic network/auth/server retry preserves the same
value. For a send, the UUID is also the durable saved request identity: the
server canonicalizes it to lowercase, binds it to the user row and assistant
safety metadata, then projects it as `client_message_id` on both messages.
Reusing the UUID with different normalized text returns
`409 field_chat_idempotency_conflict`. The server rechecks that binding after a
duplicate/waited replay, while the service-only `reserve_field_chat_send(...)`
RPC performs the authoritative check and user-row insert atomically. It
serializes every user's cross-table UTC-day admission before conversation
admission, rejects a second different UUID while an answer is missing, and
checks both conversation slots and the daily send before the row is visible.
Thus contradictory same-UUID requests and different-key capacity races cannot
both pass an earlier Edge read. The assistant row has a deterministic UUIDv8
derived from conversation and request identity. A duplicate or quota replay
either returns that exact pair, waits a bounded interval for the original
in-flight answer, or returns retryable `503 field_chat_send_in_progress`. A
failed provider or assistant-persistence attempt may resume under the same UUID
without inserting another user question. An ambiguous assistant insert is
read-after-write reconciled before failure; deterministic identity prevents a
concurrent local refusal from saving two answers. iOS manual retry preserves the
failed UUID.

If an invocation terminates after quota commit but before assistant persistence,
same-UUID retries remain in progress during a ten-minute safety window. After
that window, `recover_stale_field_chat_quota(...)` may mark only the exact
subject/user/request reservation failed after proving the user row exists and
its bound assistant is absent. The route re-reads the pair before reserving a
newly metered provider attempt. A live or completed pair cannot be reopened.
`load`, delete, feedback, and local safety refusals do not invoke Gemini and do
not consume AI quota, although a newly admitted local refusal still counts as
one of the user's 20 Field Chat sends.

### Prompt and Privacy Boundary

The server builds chat context from stored text data only: species names,
taxonomy, hazard type, confidence, candidates/lookalikes, habitat/Wikipedia
overview, invasive flag plus its original AI region/rationale/confidence,
identification provenance, user review state, observed traits, ecological
annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata. It does not include raw image bytes, R2 object keys, cloud image URLs,
internal scan IDs, exact GPS coordinates, Explore comments, public post
metadata, or Darwin Core export payloads.

Owned Insight answers, prompt suggestions, and field-note drafts include the
existing scan's `extracted_visual_traits` as `AI-extracted observation traits`.
The server trims entries, discards non-string/empty values, and limits output to
ten traits, 500 characters per trait, and 2,000 characters including quoting and
separators. Missing or empty traits render as `Unavailable`. Quoted traits are
data rather than instructions and remain fallible evidence from the original AI
scan, including after an identification correction. They do not establish
physical measurements without supporting scale evidence or imply fresh image
inspection. This internal context addition requires no HTTP payload change, scan
backfill, or extra AI call; Explore and Dictionary projections are unchanged.

Private Field Chat also reads the saved inference tier and result provenance to
qualify metric interpretation. Only historical SQL-null or exact qualified
Gemini configurations at policy version 1 keep primary/candidate, sex/invasive
confidence and model image-quality values. Unknown or missing metadata supplies
unavailable metric values and bounded descriptive candidate names/features.
Stored observations, reasoning, confirmation and local blur/zoom remain usable.
Full execution configuration is not added to any prompt.

Location-aware answers may use only the saved private location label, month,
elevation, ecology type, and weather. The prompt explicitly forbids inferring,
requesting, revealing, or reconstructing exact GPS coordinates.

The Gemini request uses `gemini-2.5-flash` with a stable prompt prefix,
`maxOutputTokens: 700`, no streaming, no Google Search grounding, and thinking
disabled. Assistant text is normalized to a nonempty fallback and capped at
4,000 Unicode code points before persistence. Assistant messages store
model/token telemetry, including cached tokens when Gemini reports implicit
cache hits.

Prompt suggestions are generated with the same text-only privacy boundary. The
model must return exactly three short prompt strings with safe categories such
as `evidence`, `lookalike_compare`, `habitat`, `season`, `hazard`, `invasive`,
`confidence`, `field_notes`, or `generic`. The guardrail prompt forbids edible
certainty, medical/veterinary treatment, illegal collection, pesticide/poison
instructions, exact-location requests, and human-subject identification. The
send-time classifier and post-generation filter match direct unsafe action
intent rather than isolated words, so harmless names such as poison ivy and
educational questions about animal foraging, bee stings, or discouraged handling
remain usable and are not automatically refused.

### Response Payload

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "messages": [
      {
        "id": "33333333-3333-4333-8333-333333333333",
        "conversation_id": "22222222-2222-4222-8222-222222222222",
        "scan_id": "A1B2C3D4-...",
        "role": "user",
        "text": "What traits support this identification?",
        "client_message_id": "11111111-1111-4111-8111-111111111111",
        "created_at": "2026-06-26T16:20:00.000Z",
        "is_refusal": false,
        "refusal_reason": null
      },
      {
        "id": "44444444-4444-4444-8444-444444444444",
        "conversation_id": "22222222-2222-4222-8222-222222222222",
        "scan_id": "A1B2C3D4-...",
        "role": "assistant",
        "text": "The saved evidence points to...",
        "client_message_id": "11111111-1111-4111-8111-111111111111",
        "created_at": "2026-06-26T16:20:02.000Z",
        "is_refusal": false,
        "refusal_reason": null
      }
    ],
    "limits": {
      "max_user_message_chars": 600,
      "max_messages_per_conversation": 30,
      "daily_send_limit": 20,
      "sends_remaining_today": 19
    }
  }
}
```

iOS treats this HTTP `200` as candidate evidence. Before replacing the current
thread it requires `subject_id` to echo the requested scan even when the thread
is empty, the exact v1 message/conversation limits, a bounded message count,
unique UUID message IDs, a valid envelope conversation UUID whenever messages
are present, and exact agreement between each message's `conversation_id`,
envelope conversation, and requested `scan_id`. Message text must be exactly
trimmed, nonempty, and at most 4,000 characters, and the JSON body must not
exceed the reviewed 1 MiB decode ceiling. A send response must contain exactly
one user and one assistant message carrying the requested `client_message_id`.
Any decode, identity, incomplete-pair, size, duplicate, limit, or conversation
mismatch is `MerianError.invalidResponse`; a pending send stays failed and
retryable under the same UUID.

For `suggest_prompts`:

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "conversation_id": "22222222-2222-4222-8222-222222222222",
    "prompts": [
      {
        "text": "Which leaf detail should I check next?",
        "category": "evidence"
      },
      {
        "text": "Could this be a lookalike?",
        "category": "lookalike_compare"
      },
      {
        "text": "Does this habitat fit?",
        "category": "habitat"
      }
    ]
  }
}
```

For `feedback`:

```json
{
  "data": {
    "ok": true,
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "message_id": "33333333-3333-4333-8333-333333333333",
    "rating": "wrong"
  }
}
```

For `feature_feedback`:

```json
{
  "data": {
    "ok": true,
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "id": "44444444-4444-4444-8444-444444444444",
    "sentiment": "positive"
  }
}
```

For `summarize_notes`:

```json
{
  "data": {
    "subject_id": "11111111-1111-4111-8111-111111111111",
    "summary_text": "Concise reviewed draft text for append-only field notes."
  }
}
```

iOS validates each action-specific `200` before applying success. Every action
must echo the exact requested scan through `subject_id`. Answer feedback must
also report `ok: true`, the requested message UUID, and the requested rating.
Feature feedback must report `ok: true`, a valid saved-feedback UUID, and the
requested optional sentiment. A field-note summary must be nonempty, no longer
than 4,000 characters, and contain no canonical internal UUID, including current
UUIDv7 identifiers. Prompt suggestions permit zero through three unique, trimmed
strings of at most 120 characters, require an allowlisted category and optional
valid conversation UUID, and repeat the server's
unsafe-action/exact-location/human-subject intent filter as client defense in
depth. Any mismatch is `MerianError.invalidResponse`; prompt generation falls
back locally, while feedback and summary surfaces remain unsuccessful.

Roll this contract out backend-first. Apply
`20260729163616_reserve_field_chat_sends_atomically.sql` before deploying either
new chat function; deploying a function that calls the RPC against an older
catalog fails closed with `field_chat_admission_unavailable`. Then deploy the
additive `subject_id` field and assistant request-pair projection to both
`/insight-chat` and `/explore-post-chat`, verify empty-thread/action responses,
different-key concurrency, cap boundaries, stale recovery, and an ambiguous
same-UUID send replay in staging, and only then ship the hardened iOS validator.
Existing iOS versions ignore the additive response fields; the corrected version
deliberately fails closed against an older anonymous-success envelope or a send
that cannot prove its persisted pair.

Before release acceptance, also apply
`20260730180000_bind_field_chat_rows_to_subjects.sql`. It is compatible with
both old and corrected chat functions: impossible historical cross-bound private
rows are removed first, then deferred composite foreign keys require every
retained Insight conversation to match its exact scan owner and every retained
message and rating to match its exact conversation, scan-or-post, and viewer
identity at commit. Conversation-optional feature feedback also matches its
exact scan owner without relying on a parent thread. Insight answer and feature
feedback lose their legacy direct authenticated Data API writes and remain
available only through the authenticated action envelopes above. This structural
boundary prevents one malformed persisted row from making every future strict
load of that thread fail.

### Safety and Errors

The system prompt states the assistant has no raw image access. All three Field
Chat routes use `_shared/fieldChat/speciesKnowledge.ts` to permit
well-established general species knowledge when the supplied text lacks a
detail, such as typical fragrance. The supplied scientific name and
identification uncertainty bound the subject; answers qualify relevant
individual or cultivar variation. Claims about a particular observation still
require supplied observation evidence or explicit observations reported by the
user. General knowledge cannot establish current/local facts or justify invented
citations or claims of live retrieval.

Each route appends those rules after its bounded context block. The rule defines
`Unavailable` as a missing record field rather than a missing species fact,
resolves casual pronouns in typical-trait questions to the identified species,
and requires a direct one-to-three-sentence answer before relevant variation.
Few-shot examples distinguish a general fragrance question from a claim about
the current individual. `_shared/fieldChat/reply.ts` owns the common Gemini
model request and JSON extraction so all three routes and the synthetic provider
check exercise one configuration. Insight summary and prompt-generation actions
use the context and safety instruction without chat-answer examples or schema.

Insight field-note summary prompts admit only recorded scan evidence and
explicit user observations. General species facts in dictionary text or
assistant replies, questions, hypotheticals, and suggested checks must not
become recorded observations.

The Edge Function refuses or redirects edible/foraging certainty,
medical/veterinary treatment, dangerous handling, illegal collection,
pesticide/poison instructions, and human-subject identification requests.

| Status | Body                                             | Meaning                                                                |
| ------ | ------------------------------------------------ | ---------------------------------------------------------------------- |
| `400`  | `{ "code": "unsupported_scan", ... }`            | Scan is non-biological, unresolved, Human, or request shape is invalid |
| `402`  | `{ "code": "pro_required", ... }`                | Effective tier is not functional Pro                                   |
| `404`  | `{ "code": "scan_not_ready", ... }`              | No owned completed scan row exists yet                                 |
| `409`  | `{ "code": "field_chat_idempotency_conflict" }`  | UUID was reused with different normalized text                         |
| `429`  | `{ "code": "daily_limit_reached", ... }`         | Daily send cap reached                                                 |
| `429`  | `{ "code": "ai_quota_daily_exceeded", ... }`     | Database AI safety ceiling reached                                     |
| `429`  | `{ "code": "ai_user_rate_limit_exceeded", ... }` | Shared user minute ceiling reached                                     |
| `429`  | `{ "code": "ai_ip_rate_limit_exceeded", ... }`   | Shared network minute ceiling reached                                  |
| `503`  | `{ "code": "field_chat_send_in_progress", ... }` | Same or different in-flight send has no answer yet                     |
| `503`  | `{ "code": "field_chat_admission_unavailable" }` | Atomic admission could not be verified                                 |
| `503`  | `{ "code": "field_chat_recovery_unavailable" }`  | Stale-request recovery could not be verified                           |
| `503`  | `{ "code": "ai_entitlement_unavailable", ... }`  | Entitlement/quota lookup failed closed                                 |

The iOS client treats `404 scan_not_ready`, action-level `message_not_found` /
`conversation_not_found`, and a preflight status `not_found` as retryable state.
None may set scan-scoped permanent unavailability or hide the Field Chat action.
Only terminal ownership failure, `unsupported_scan`, and unavailable
Explore-post sources identified by `post_not_available` do so. In particular,
Explore feedback’s `message_not_found` does not hide chat for the healthy post.

Telemetry emits `InsightChatSent`, `InsightChatAnswered`, `InsightChatRefused`,
`InsightChatRateLimited`, `InsightChatModelError`,
`InsightChatPromptsGenerated`, `InsightChatFeedbackSubmitted`,
`InsightChatFeatureFeedbackSubmitted`, and `InsightChatNotesSummarized` with
latency and token fields when available. Send/answer events include a
deterministic `answer_category` so token cost can be reviewed by broad question
type. Prompt generation events include prompt categories, fallback/error state,
and token usage when available. iOS also emits `InsightChatActionTapped` to
PostHog for local answer actions, prompt-chip taps, the sheet options menu, and
feedback affordances. When iOS detects local identification-concern intent -
direct wrong-ID language, soft doubt, alternate-ID suggestions, trait mismatch,
or recheck/reanalysis requests - it can attach local
`review_alternatives_from_identification_concern` and
`reanalyze_species_from_identification_concern` actions to the next assistant
reply; these actions route through existing on-device candidates/reanalysis
flows and do not change the `/insight-chat` response payload.

---

## Deno `/explore-post-chat` Edge Node

Private Pro Field chat for any active Explore post visible to the viewer,
including their own. The endpoint authenticates with `withEdgeHandler`, derives
the viewer from the verified JWT, requires the post to be visible to that
viewer, and resolves functional Pro access server-side. Each
`(post_id, viewer user_id)` pair has its own conversation. Other viewers cannot
load or mutate it; the post author may own a conversation when viewing their own
published post.

The Pro gate uses the durable Supabase projection of an active RevenueCat store
subscription, receipt-backed free trial, or explicitly approved finite beta
promotion. RevenueCat's developer project plan, client-only subscription state,
and a database edit do not authorize this route. The separate, exactly verified
`pro_complimentary` functional tier also qualifies while an available credit or
active hold remains; it is not RevenueCat or paid status. The beta promotion
operation remains release-held under the
[RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md).

Model sends reserve `explore_post_chat_reply` using
`client_message_id`/`Idempotency-Key` before provider dispatch and use the
database-selected model. Local safety refusals and deterministic prompt
suggestions do not call Gemini and do not consume AI quota. Explore and Insight
model chat share the `ai_chat` quota buckets. `client_message_id` is required
for `send`, binds the persisted user/assistant pair, and is reused by automatic
and manual retries. Quota replays coalesce into the saved pair or return the
same retryable in-progress contract as Insight Chat.

Request bodies use `post_id` and support `load`, `send`, `delete`, `feedback`,
and `suggest_prompts`:

```json
{
  "action": "send",
  "post_id": "22222222-2222-4222-8222-222222222222",
  "message_text": "How can I distinguish this species from lookalikes?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

The response reuses the iOS `InsightChatResponse` envelope. For compatibility,
each message's `scan_id` field contains the Explore post ID; it never exposes
the owner's source scan ID. Top-level `subject_id` also contains the requested
Explore post ID on every thread, feedback, and prompt-suggestion response,
including an empty thread. Conversations allow 600 characters per user message,
30 total persisted rows, and share the 20-send UTC daily allowance with the
viewer's Insight and Species Dictionary chats. New sends reserve room for user
and assistant rows together through the same atomic cross-table RPC, which also
rejects a different request while one bound user row remains unanswered. Request
UUIDs are canonical lowercase values; UUID reuse with different normalized text
returns `409 field_chat_idempotency_conflict`, and deterministic assistant
UUIDv8 rows make answer persistence idempotent. A charged request missing its
assistant follows the same exact-row-bound ten-minute stale recovery contract as
Insight Field Chat. Assistant text is capped at 4,000 Unicode code points before
persistence. Prompt suggestions and feedback do not consume a send. The same iOS
candidate-success validation binds the envelope and every returned message to
the requested post ID and one conversation; a send also requires its exact
two-message `client_message_id` pair, exact acknowledged user text, and bounded
response body before the private thread can be displayed, a pending send can be
cleared, or an action can show success.

The model context is built from explicitly selected fields in the
privacy-filtered `get_explore_post` and `get_explore_post_detail` projections
plus public Species Dictionary fields. It does not add `map_point` to the model
prompt and excludes private owner scan rows, coordinates, unpublished notes,
comments, owner chat history, and media bytes/URLs. Questions that require
direct inspection of the post's media must be answered without claiming media
access. These technical boundaries remain server-enforced even though the iOS
empty state presents only the concise trust message:
`This Field chat is
private and visible only to you.`

`404 post_not_available` covers missing, unpublished, or blocked posts;
`402
pro_required` covers non-Pro viewers; `404 message_not_found` covers
feedback targeting a non-owned assistant message; and `429 daily_limit_reached`
returns the current conversation envelope with no new send. Shared `409`, `429`,
and fail-closed `503` AI quota errors follow the authorization table above.
Unpublishing a post deletes all of its private viewer conversations.

---

## Deno `/species-dictionary-chat` Edge Node

Private Pro Field Chat for any canonical biological Species Dictionary UUID in
the iOS app. This is an authenticated route distinct from the public, cacheable
`/species-dictionary` endpoint. Public web species pages do not call it.
`withEdgeHandler` derives the viewer from the verified session, and each
`(species_id, viewer user_id)` pair has one saved conversation.

Requests support `load`, `send`, `delete`, `feedback`, and `suggest_prompts`:

```json
{
  "action": "send",
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "message_text": "How can I distinguish this species from lookalikes?",
  "client_message_id": "11111111-1111-4111-8111-111111111111"
}
```

`species_id` must be present and parse as a UUID. Missing or malformed input
returns `400 invalid_request`. A syntactically valid UUID that is absent or does
not resolve to an available canonical biological dictionary row returns
`404 species_not_available`. Functional Pro is resolved server-side through the
same paid, trial, projected promotion, and exactly verified complimentary
authority as the other Field Chat routes; other viewers receive
`402 pro_required`.

Every success uses the strict shared Field Chat envelope. Top-level `subject_id`
equals the requested species UUID. Thread messages repeat that UUID in
compatibility `scan_id`; it is not a scan identifier in this route. Feedback
echoes the exact subject, message UUID, and rating. Prompt suggestions echo the
subject and optional conversation UUID. iOS applies none of these responses
until the shared 1 MiB, limits, identity, bounded-text, and exact send-pair
validations pass.

Each send reloads the latest bounded canonical source projection: common,
alternative, and scientific names; kingdom through genus; overview; habitat;
hazard; IUCN conservation status; group tags; and up to six nonrejected
lookalikes with names, rationale, and visual traits. The system prompt fences
all source values as untrusted reference data and never follows instructions
inside them. The projection and prompt exclude Community sightings, local and
global observation charts/counts, scans, notes, users, locations, media,
reference URLs, licenses, and attribution identities. Questions that require
those sources are answered with the limitation rather than invented context.

The shared Field Chat species-knowledge rules also permit stable general facts
absent from that projection. Missing reference prose alone must not block a
general species answer; answers still distinguish species traits from individual
observations and cannot claim live retrieval or unsupported current/local facts.

`send` uses `species_dictionary_chat_reply` and the database-selected
`gemini-2.5-flash` model with 700 output tokens, JSON output, no Search
grounding, and thinking disabled. Local safety refusals and deterministic prompt
suggestions do not invoke the provider. Assistant text is normalized and capped
at 4,000 Unicode code points. Product telemetry includes only broad action,
length, refusal, latency, and plan fields—never species names or IDs. The
private AI usage ledger records operational conversation/message linkage and
`source_type = species_dictionary`, with no species `source_id`.

Migration `20260821030027_add_species_dictionary_field_chat.sql` adds the
Edge-only conversation/message/feedback tables and extends
`reserve_field_chat_send(...)` and `recover_stale_field_chat_quota(...)` to the
third subject and operation. The 30-row conversation cap, exact same-UUID
replay/conflict contract, one-unanswered-request fence, deterministic assistant
identity, and ten-minute exact-row stale recovery match the other chat routes.
All three families share the authoritative 20-send UTC-day limit. Dictionary
conversations also participate in anonymous-account merge handling.

The 20-send limit is defined over admitted sends, regardless of whether a user
later deletes conversation content. Migration
`20260824210544_preserve_field_chat_daily_usage.sql` stores the authoritative
content-free count in `internal.field_chat_daily_admissions`, keyed by user and
UTC day. `reserve_field_chat_send(...)` increments it atomically only for a new
admission; same-key replay does not consume it. The same transaction finds or
creates the subject-bound conversation and inserts the user row, returning the
authoritative `conversation_id`. A quota, cap, or cutover denial therefore
creates neither a conversation nor a message. Conversation cascades never delete
the aggregate, and the service-only `get_field_chat_daily_usage(...)` read fails
closed rather than counting live messages.

The retained-row seed is necessarily a lower bound because messages deleted
earlier that day cannot be reconstructed. While short-locking all six
conversation/message tables, the migration removes historical message-less
threads and then creates `internal.field_chat_admission_cutover` with a
PostgreSQL-derived next-UTC-day `not_before_utc`, guards direct conversation
inserts for already-deployed bundles, permanently revokes conversation `INSERT`
from API roles, and checks `internal.assert_field_chat_admission_open()` after
exact replay but before every novel ledger write. Only the `SECURITY DEFINER`
reservation routine can create a thread. Corrected bundles map a reservation
rejection to retryable `503 field_chat_admission_cutover_pending`; an older
create-before-admission bundle can instead surface an unnormalized permission or
trigger failure, but it cannot leave an empty thread even after activation.
Load, delete, feedback, and exact replay remain available. The bounded
service-only `get_field_chat_admission_cutover_status()` response contains only
migration ID, database time, seed time, not-before time, nullable activation
timestamp, nullable activation candidate SHA, nullable activation migration
SHA-256, nullable Explore/Insight/Species Dictionary bundle SHA-256 values, and
`pending`/`ready`/`active` state. Crossing the UTC boundary changes `pending` to
`ready` but does not open admission. Database `ready` force-selects all three
routes in the final plan even when the migration is already the last successful
baseline. Each live route must then return both
`X-Merian-Field-Chat-Contract: atomic-admission-v1` and its exact
`X-Merian-Field-Chat-Bundle-SHA256`, derived from the candidate's transitive
runtime graph, Deno configuration, and dependency lock. The service-only
`activate_field_chat_admission_cutover(candidate_sha, migration_sha256,
explore_bundle_sha256, insight_bundle_sha256,
species_dictionary_bundle_sha256)`
RPC performs the one-way transition and persists all five identities. A failed
deployment, rollover, old marker-only route, or digest mismatch therefore leaves
admission closed.

The Ghost policy handler is added to the effective hardcoded allowlist with
source-drift guards, followed by the full coverage assertion. Disposable SQL
fixtures define real reserve-delete-fresh-reserve cases for all three families,
no-write quota denial, and a current-UTC-day
public-reservation/full-orchestrator merge race. Those source fixtures are not
production evidence until the complete Docker-backed candidate database gate
executes on the exact release SHA.

iOS sends the send UUID as both `client_message_id` and `Idempotency-Key`,
preserves it for manual retry, and now includes `species-dictionary-chat` in the
audited idempotency-aware Function allowlist. The network regression loses the
first retryable response, replays automatically with the same lowercase UUID,
and accepts only one persisted pair.

The route-contract test proves source registration with `withEdgeHandler`.
`handler_test.ts` directly invokes the post-authenticated handler core with a
synthetic user and covers the five actions, ownership, exact replay/conflict,
refusal, provider ordering, stale-quota recovery, and denial before provider or
admission. It also executes `withEdgeHandler` with deterministic accepted and
refused authenticators, proving auth-before-route ordering and refusal
short-circuiting. Send handlers use an existing conversation ID or a fresh UUID
candidate without inserting a row; the database returns the converged ID only
after admission succeeds. A hosted real-token HTTP authentication smoke remains
a separate release-evidence requirement.

Deno and Swift execute the versioned
`docs/contracts/species-dictionary-prompt-label-policy.json` fixture. Both count
the normalized label in Unicode scalars, cap it at 64, accept Unicode letters,
marks, decimal digits, and the enumerated punctuation (including ASCII hyphen
and U+2013 EN DASH), collapse only the enumerated whitespace scalars (including
U+0085), and reject U+FEFF. Identical vectors cover combining marks, exact
scalar boundaries, non-BMP input, punctuation, U+FEFF, and U+0085. The
checked-in `species_dictionary_chat_production_hold` is inactive under the
owner-authorized beta decision above. Exact-SHA backend validation and live
repository controls remain mandatory; incomplete device/hosted/external evidence
stays on the full-release checklist. Hold status is an operational control, not
an API compatibility promise.

| Status | Body                                                 | Meaning                                                 |
| ------ | ---------------------------------------------------- | ------------------------------------------------------- |
| `400`  | `{ "code": "unsupported_action", ... }`              | Action is not one of the five supported values          |
| `400`  | `{ "code": "invalid_request", ... }`                 | Required input is missing, malformed, or out of bounds  |
| `402`  | `{ "code": "pro_required", ... }`                    | Effective tier is not functional Pro                    |
| `404`  | `{ "code": "species_not_available", ... }`           | Canonical biological dictionary subject unavailable     |
| `404`  | `{ "code": "message_not_found", ... }`               | Feedback target is not the viewer's assistant row       |
| `409`  | `{ "code": "field_chat_idempotency_conflict" }`      | UUID was reused with different normalized text          |
| `429`  | `{ "code": "daily_limit_reached", ... }`             | Shared three-family daily send cap reached              |
| `503`  | `{ "code": "field_chat_send_in_progress", ... }`     | Bound request has no answer yet                         |
| `503`  | `{ "code": "field_chat_admission_cutover_pending" }` | Novel sends await UTC eligibility and bundle activation |
| `503`  | `{ "code": "field_chat_admission_unavailable" }`     | Atomic admission could not be verified                  |
| `503`  | `{ "code": "field_chat_recovery_unavailable" }`      | Stale recovery could not be verified                    |

The client marks only exact `404 species_not_available` as permanent for that
loaded dictionary subject. Feedback `message_not_found`, daily/AI quotas,
network failure, and platform route failure remain retryable and do not hide a
healthy loaded page's toolbar action.

---

## Deno `/sync-collections` Edge Node

Synchronizes locally created Scan Collections with the PostgreSQL `collections`
and `collection_scans` schemas, handling diffing and missing FK references.

iOS request ownership lives in
`Core/Network/Endpoints/MerianNetworkClient+Collections.swift`. Its private wire
DTO maps the Core Data-owned `CollectionSyncSnapshot` to the canonical keys and
uses the shared authenticated encoded-body transport. Durable job and
single-flight state remain in `OfflineQueueManager`; account-lease transaction
ownership remains in `CollectionSyncService`; local projection and conditional
tombstone purge remain in `BackgroundDatabaseActor+CollectionSync.swift`.

### Request Payload

```json
{
  "collections": [
    {
      "id": "A1B2C3D4-...",
      "name": "My Favorites",
      "created_at": "2026-03-23T12:00:00Z",
      "scan_ids": ["B2C3D4E5-..."],
      "is_deleted": false
    }
  ]
}
```

The active iOS V53 model names the durable application value
`ScanCollection.isPendingDeletion` and maps it to the released SwiftData
`isDeleted` column with `@Attribute(originalName:)`. The two released V50 model
graphs differ only in their Swift-side property name and keep that same physical
column. The collection-sync DTO explicitly projects the active value to the
canonical `is_deleted` JSON key. The optional `isDeleted` request alias remains
a server-side compatibility read for historical encoder output; clients do not
need to send both keys. The checksum-qualified V50→V51 migrations change neither
this collection shape, payload, nor deletion semantics.

### Safety and Transactional Integrity

1. **Dual Casing Delete Parsing**: The current iOS client emits `is_deleted`. To
   protect historical Swift encoder output, the Edge function also accepts
   `isDeleted` when resolving the deleted tombstone array.
2. **Atomic Ownership Upsert**:
   `upsert_owned_collections(p_user_id, p_collections)` performs one
   `INSERT ... ON CONFLICT ... DO UPDATE` and returns every input ID as accepted
   or rejected. It inserts new rows and updates only `name` and `created_at`
   when the existing owner equals `p_user_id`. A foreign or concurrently
   colliding UUID remains unchanged. Only accepted IDs are passed to membership
   hydration and delta calculation. The RPC adapter throws on error, so no
   downstream membership read or write can run after uncertain admission.
3. **Skippable Foreign IDs**: Rejected collection IDs are logged and skipped
   without changing the successful-sync response. This preserves offline
   reconciliation when one device retains a stale UUID while preventing a
   service-role write from reassigning it. Ownership is resolved from the JWT;
   collection JSON never supplies `user_id`.
4. **Delete IDOR Guard**: `deleteCollections` scopes the DELETE query with
   `.eq("user_id", userId)` as a defence-in-depth layer. `deleteCollections` now
   throws on database error rather than logging silently, preventing
   false-success `200` responses when the deletion fails.
5. **Owner-Joined Membership Insertion**: Applying `collection_scans`
   relationships in bounded set-based RPC chunks avoids N+1 query timeouts.
   `insert_owned_collection_scans(p_user_id, p_rows)` joins both the requested
   collection and scan to `p_user_id` before insertion. A scan grouped while
   offline may not exist in PostgreSQL yet; missing and foreign scans are
   skipped, leaving the local relationship for the next sync pulse. The RPC
   cannot create a cross-owner membership, and a database trigger independently
   rejects direct writes whose parent owners differ. Existing memberships are
   hydrated for all accepted owner collections with one keyset-paginated
   `.in("collection_id", ownedIds)` query ordered by `(collection_id, scan_id)`,
   rather than one pagination loop per collection. Each bounded page resumes
   after its last composite primary key instead of paying progressively higher
   range/OFFSET costs. This keeps latency sublinear for users with many
   collections while bounding each page in V8 memory.
6. **RLS and Direct-Grant Boundary**: Authenticated RLS separates own-collection
   select/delete from own-collection-plus-own-scan insert; membership updates
   are unsupported. `service_role` has no table-wide collection UPDATE and may
   directly update only `name` and `created_at`. Ghost merge reparenting stays
   behind its existing privileged merge function. Both owner RPCs are invoker
   functions with empty search paths and explicit `service_role`-only execute
   grants.
7. **Array-Bound Diffing Deletes**: Identifies obsolete collections by running
   `.select()` across the user's DB rows, building a `toDelete` array in memory
   and passing it to `.delete().in("id", toDelete)`. This avoids
   `.not("id", "in", "(...)")` string-builder failures.
8. **Strict Upstream Concurrency Latch**: Because `BackgroundTaskWrapper` calls
   push network traffic simultaneously out-of-order, the iOS client strictly
   clamps `sync-collections` invocations behind a shared collection
   single-flight latch. `OfflineQueueManager` retains the active
   `collectionSyncTask`, so concurrent callers await the same request instead of
   launching parallel pushes. A monotonic `collectionSyncRevision` is captured
   when each request starts; the coalesced
   `OfflineJobRecord(id:
   "collection-sync")` is marked complete only if no
   newer collection mutation was enqueued while that request was in flight. This
   prevents race conditions where a stale `.upsert()` snapshot lands after a
   newer `.delete()`, causing ghost resurrections.
9. **Account and Acknowledgement Fencing**: `CollectionSyncService` holds one
   outer account-work lease for the snapshot/request/commit transaction and
   revalidates it immediately before dispatch and after the HTTP response. The
   commit uses a fresh database actor and deletes only acknowledged IDs still
   marked `isPendingDeletion`. A local reactivation during an in-flight request
   therefore survives; its newer dirty revision remains queued for the next
   desired-state push.
10. **Non-Reentrant Auth Recovery**: A classified `401` is returned to the
    durable collection job without starting ordinary session recovery inside the
    request. Auth recovery must quiesce this exact collection task and its outer
    account-work lease; initiating it from inside the task would create a
    self-wait. The local desired state and its job remain durable for a bounded
    retry after Auth becomes stable. This exception is collection-specific; the
    shared encoded-body transport keeps classified-401 recovery enabled by
    default.

> **Parameter naming**: The `syncMembershipDelta` function parameter names were
> updated from `validCollections`/`activeIds` to `ownedCollections`/`ownedIds`
> to reflect that all inputs are pre-ownership-checked by the time they reach
> that function.

**Authentication ownership**: `sync-collections` is configured with
`verify_jwt = false`, so the handler owns JWT validation and authorization
through the shared auth boundary. Raw iOS requests send the public project key
in `apikey` and the signed-in user's JWT in `Authorization: Bearer …`.
`verify_jwt = false` does not make the route public and should not be explained
as gateway header stripping.

---

## Deno `/check-scan-status` Edge Node

Provides a lightweight outbox confirmation endpoint. Current
`/identify-multimodal` success already includes durable owner-row insertion;
polling remains useful for compatibility endpoints, interrupted older requests,
and queued recovery.

iOS request mapping lives in
`Core/Network/Endpoints/MerianNetworkClient+ScanLifecycle.swift`, with unchanged
explicit-key DTOs in `ScanLifecycleAPIModels.swift` and strict response checks
in `Decoding/ScanLifecycleResponseDecoder.swift`. The raw-response JSON bridge
preserves recovery-owner binding through the client's private authenticated
transport. `Core/Network/Recovery/` owns recovery payload construction,
missing-row classification, and record-based compatibility orchestration;
durable scheduling stays in Core Data. See the
[iOS ownership and verification guide](../../apps/ios/Merian/Core/Network/README.md#scan-lifecycle-endpoints-and-decoding).
The compatibility poller propagates caller cancellation before interpreting a
late successful status response or launching another probe or recovery action;
it does not translate cancellation into a recovery outcome. This is an iOS
lifecycle guarantee and does not change the request or response contract below.

### Request Payload

```json
{ "scan_id": "<UUID>", "required_video_count": 1 }
```

`required_video_count` is optional. Omit it for legacy/image status probes. When
present and greater than zero, the endpoint returns `"found"` only if the scan
row exists for the authenticated user and has at least that many public
`video_storage_urls` plus matching ready playback entries in `scan_media_assets`
or video entries in `captured_media`.

For one local observation whose owner row is absent, iOS may include a
`recovery_scan` object containing validated non-media fields. Its `id` must
match `scan_id`, its `user_id` must match the authenticated user, and
`image_storage_urls` must be empty. The endpoint delegates to one atomic
service-only routine, which takes the ingestion claim's per-scan advisory lock,
inserts only a missing scan, and writes `client_recovery_complete` in the ledger
within the same transaction. It cannot overwrite an existing scan. Direct media
URLs are rejected, and recovery is not supported in bulk probes. Processing,
finalizing, retrying, retryable, policy, legacy-unknown, and every other
terminal state are never preempted. A missing ledger row also fails closed. Only
an existing `complete` ledger whose owner row is unexpectedly absent or an
explicit `terminal_reason_code = replay_exhausted` state is recoverable without
additional provenance. Exact `media_reconciliation_abandoned` additionally
requires an owner/scan-matching post-result `failed_scan_ingestions` row no
earlier than the latest charged exact normal/replay quota attempt, no exact
reserved attempt or invalid terminal timestamp lineage, and no
moderation-rejected or moderation-pipeline-failed capture lifecycle row.
Pre-rollout unstructured evidence must be one of the exact dead-letter IDs
snapshotted by the hardening migration, predate the private database cutoff, and
either follow a failed latest authority or match the historical first committed
normal attempt with no charged replay. Timestamp alone is not authority: an
older producer insert blocked by migration DDL can resume later while retaining
an earlier transaction-start `failed_at`; the immutable ID snapshot excludes
that row. Legacy evidence must come from the audited multimodal post-safety
error lineage, not the known pre-safety user prerequisite or a moderation
failure. Post-rollout structured evidence must bind the exact quota
reservation/request IDs, validated provider output, and completed Identify
safety evaluation. All exact failed/committed normal and replay reservation keys
are retained as chronological authority across ordinary quota pruning until the
terminal ledger is resolved. The recovery and proof routines are service-only,
recorded in `internal.privileged_routine_grants`, and probed in production
through exact null-input SQLSTATE `22023` no-write boundaries. A handler-owned
`503 service_unavailable` while processing `recovery_scan` therefore means the
guarded database recovery boundary was not authoritative; the client must
preserve local media and must not proceed to restore signing. This check is also
the rollout fence. The baseline and hardening SQL files are separate
migration-file transactions, so exact-SHA fail-closed `generate-upload-urls`,
`check-scan-status`, and `share-scan-to-explore` consumers predeploy before
either file. A recovery call proves that the service-only
`get_media_abandoned_scan_recovery_proofs` surface is available before it can
invoke `recover_missing_owned_scan`; an empty proof set is valid readiness for
non-media-abandonment outcomes, but malformed, foreign, missing, or denied
responses stop the flow. The structured Identify producer deploys only after
both migrations commit.

If the exact owner row is still absent, the route also invokes service-only
`recover_stranded_scan_ingestion_attempt` before projecting client-safe job
state. This narrow reconciliation applies to single and bulk probes and may
adjust only an already-existing scanless job/quota/staging topology whose
endpoint, operation, lease, owner, and optional merge handoff agree. It never
guesses or inserts a scan row, refunds dispatched usage, reparents arbitrary
state, or exposes the authorized source identity.

### Response Payload

```json
{
  "status": "found",
  "job_status": null,
  "job_stage": null,
  "job_attempt_count": null,
  "retry_after": null,
  "last_error": null,
  "complimentary_state": "consumed"
}
```

`status` remains the compatibility field and is still only `"found"` or
`"not_found"`. When the scan row is not complete yet, newer clients and ops
tools can inspect the optional job fields backed by `scan_ingestion_jobs`:
`job_status` may be `processing`, `finalizing`, `retrying`, `failed_retryable`,
`failed`, or `complete`; `failed` is the client-safe projection of a
`failed_terminal` ledger row. iOS also accepts the legacy `failed_terminal`
response spelling. `job_stage` names the precise server step, including
`server_replay_limit_reached` when the scheduled replay budget is exhausted.
`retry_after` and `last_error` are only populated for failed jobs.
`complimentary_state` is additive (`held`, `consumed`, `released`, or `null`)
and is read for the whole bulk request through one service-only, owner-scoped
`get_complimentary_scan_states_service` call so deferred Flash ordering does not
create per-scan funding lookups. This state-only read does not refresh the
entitlement balance. A terminal `consumed` blocker remains locally reserved
until a later successful `get_my_entitlement()` proves the installed snapshot
includes settlement; terminal `released` or terminal absence also requires that
refresh before reclassification. Nonterminal absence creates no capacity. iOS
decodes the full response via `ScanStatusResponse`: queued scans use these
fields to keep server-owned `.inferencing` rows from being resubmitted while
media promotion or scan insertion is still finalizing, and to surface terminal
server replay exhaustion as needs-attention instead of continuing automatic
retry.

### Authentication & IDOR

The `Authorization: Bearer` JWT is verified by `withEdgeHandler`. The DB query
enforces ownership with a dual `.eq("id", scan_id).eq("user_id", user.id)`
constraint — a user cannot probe another user's scan IDs. Recovery additionally
derives the canonical owner from the authenticated user and validates UUIDs,
numeric ranges, bounded text, enums, and geoprivacy-derived public coordinates.
The atomic database write enforces ownership and ingestion-generation state
independently of iOS polling. The query returns only the media fields needed for
the durability check (`id`, `video_storage_urls`, `captured_media`, normalized
scan-media asset rows, and the user's own scan-ingestion job state); no private
scan content is transmitted.

### Architecture

Follows the domain-driven module pattern: `index.ts` orchestrates auth,
parameter validation, optional owner-row recovery, narrow stranded-attempt
reconciliation, and video-count gating; `db.ts` owns status reads,
`_shared/scanRecovery.ts` owns DTO validation and atomic row repair, and
`_shared/scanIngestionJobs.ts` owns stranded-attempt response validation. Read
or repair errors are caught by `index.ts` and mapped to a structured
`logStructuredError` + 500 response.

---

## Deno `/get-filtered-discovery-feed` Edge Node

Fetches the global social feed of public biological captures, excluding the
requesting user and any users they have blocked.

This remains a deployed backend route, but the current iOS app has no endpoint
owner or caller for it. Native Explore feed loading uses `/get-explore-feed`.
Keeping this section documents the backend contract; it does not make
`get-filtered-discovery-feed` part of the iOS replay allowlist.

### Feed Query Strategy

Block list and feed are fetched in **parallel** via `Promise.all`:

```typescript
const overFetchLimit = limit + Math.max(20, Math.ceil(limit * 0.2));
const [blockedIds, rawFeed] = await Promise.all([
  fetchBlockedUserIds(user.id, supabaseAdmin),
  fetchDiscoveryFeed(user.id, overFetchLimit, supabaseAdmin),
]);
const excludedSet = new Set(blockedIds);
const feedData = rawFeed.filter((s) =>
  s.user_id != null && !excludedSet.has(s.user_id)
).slice(0, limit);
```

`fetchDiscoveryFeed` excludes only the requesting user at the DB level
(`.neq("user_id", selfId)`). Blocked user filtering is applied post-query in
TypeScript. To compensate for rows removed by the block filter, the DB query
over-fetches by `Math.max(20, 20% of limit)` rows. For the default limit of 20,
this fetches up to 40 rows. Block list filtering happens on the fast in-memory
`Set`, not in the SQL query — this eliminates a SQL variable-length array
parameter that required manual escaping.

### Authentication Enforcement

The endpoint extracts user identity from the `Authorization: Bearer` header via
`supabaseAdmin.auth.getUser()`, ignoring any `userId` in the request body.

**Raw-client header requirement**: Any direct `URLSession` client must send both
`Authorization: Bearer <user JWT>` and `apikey: <public project key>`. The
gateway can reject a request that does not identify the project, while the
handler independently validates the Bearer user JWT. The current iOS
`MerianNetworkClient` does not expose this route. Do not describe the gateway as
stripping Authorization.

Any request with a manipulated JSON body but no valid JWT signature in the
header returns `401 Unauthorized`.

### Global Geoprivacy & Endangered Species Shielding

To prevent location tracking and poaching of IUCN Endangered, Vulnerable, or
Near-Threatened species, the endpoint runs a post-processing `map` loop before
JSON transmission. The `.gps_lat_exact` and `.gps_long_exact` fields are removed
from every scan in the payload, regardless of the user's geoprivacy setting.
Additionally, if the taxonomy flags a capture as a protected species, the
endpoint rounds `gps_lat_public` coordinates to 11km tiles.

---

## Deno `/resolve-purchase-principal` Edge Node

Additive authenticated resolver for the stable StoreKit purchase identity. The
route accepts `POST` only, limits JSON to 2 KiB, sends
`Cache-Control: no-store`, and rejects unknown or missing fields. `config.toml`
uses `verify_jwt = false` only to keep JWT validation inside the shared handler;
`withEdgeHandler` still requires a live user from
`supabaseAdmin.auth.getUser()`.

The current iOS candidate sends the exact protocol-v3 resolve request.
`Core/Security/PurchaseIdentity/Models/PurchasePrincipalWireModels.swift` owns
the client protocol and decoded response DTOs;
`Services/PurchasePrincipalRemoteService+Live.swift` privately owns the exact
request payloads and all four calls to this route. Earlier resolve protocols
remain accepted only while rollout is in the legacy compatibility window; stable
activation requires minimum protocol 3:

```json
{
  "operation": "resolve",
  "installation_capability": "43-character base64url value",
  "client_protocol": 3,
  "binding_intent_generation": 42
}
```

The installation capability is 256 random bits generated with
`SecRandomCopyBytes`, written to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
and read back before first use. It authorizes possession of one installation
purchase identity; it is not a caller-selected user or provider ID. Edge hashes
it with SHA-256 before any RPC, passes only the authenticated user's ID, and
never logs either value. `binding_intent_generation` is a positive,
device-persisted monotonic counter. iOS advances and read-verifies it before
each resolver request. Postgres accepts only a value newer than the latest value
for that capability, and completion must present that exact accepted value. A
delayed request from an older Auth session therefore cannot overwrite a newer
binding even if its HTTP work finishes last. The maximum is JavaScript's
exact-integer limit (`9007199254740991`) across Swift, Edge, and Postgres.

The resolver first calls `begin_purchase_principal_resolution`. While rollout is
disabled—or when the client protocol is below the server minimum—a new or
pending capability receives the successful compatibility response:

```json
{
  "success": true,
  "mode": "legacy",
  "minimum_client_protocol": 3
}
```

No RevenueCat request is made in legacy mode. A new client may also use this
legacy branch only when the additive route is definitively absent (`404`); auth,
configuration, timeout, and other service failures remain fail-closed. That
missing-route fallback is available only before the exact device capability has
ever activated stable mode. iOS persists a device-only activation fingerprint,
after first validating its exact 64-character lowercase SHA-256 shape before the
secure write; after activation, both `404` and `mode: legacy` fail closed
without changing the RevenueCat identity. An already active capability never
falls back to an Auth-UUID customer during rollback: it continues to receive
`mode: stable` and may rebind. If that active principal requires a newer
protocol, the endpoint fails closed with `426` instead of rotating provider
identity.

In stable mode, begin returns a server-owned pending or active principal. Edge
fetches authoritative RevenueCat v1 CustomerInfo for that immutable App User ID,
rejects stale/future snapshots, derives StoreKit state only from explicit
`store: app_store` records, and derives account-grant compatibility state only
from explicit `store: promotional` records. The service-only completion RPC
atomically stores those separate states and binds the principal to the exact JWT
user. A detached `pro_week` history record is admitted on first adoption only
when the existing Supabase Pro projection has the exact same finite expiry;
Postgres rechecks that evidence under the locked user row before activation. An
active principal reuses its durable pass-policy flag instead of inferring from
RevenueCat history. Success is:

```json
{
  "success": true,
  "mode": "stable",
  "purchase_principal_id": "UUID",
  "revenuecat_app_user_id": "server-owned custom ID",
  "binding_generation": 2,
  "account_grants_allowed": false,
  "minimum_client_protocol": 3
}
```

iOS must compare all stable fields with its current Auth-event generation before
changing RevenueCat. The provider-neutral `RevenueCatIdentityCoordinator`
serializes SDK-identity work through closures supplied by `RevenueCatManager`,
fences exact request execution and commit, and binds readiness to the returned
provider ID, Auth UUID, and binding generation. A durable-handoff state
transition raises a monotonic in-memory generation fence that dominates
account-grant permission captured by older suspended provider work, even when
the handoff clears before that work resumes. Only a fresh exact binding begun
after the fence may commit that permission once the handoff is clear. The
manager writes no email, display name, avatar, username, or Auth UUID attribute
to a stable customer. When a legacy customer is first adopted, iOS deletes those
legacy attributes and synchronizes the deletion before declaring the stable
identity ready. Apple and Google continuation use ordinary resolution. Stable
sign-out instead uses three exact protocol-3 operations on this route. While the
linked source JWT is live, iOS persists a random rotation UUID and 43-character,
256-bit base64url secret before sending:

```json
{
  "operation": "prepare_signout_rotation",
  "installation_capability": "43-character base64url value",
  "client_protocol": 3,
  "rotation_id": "UUIDv4",
  "rotation_secret": "43-character base64url value",
  "expected_binding_generation": 2
}
```

Edge hashes both secrets and Postgres accepts preparation only from the exact
linked, non-anonymous source at that generation. The 30-day authorization
lifetime is returned by the server; clients must never manufacture or extend it.
Preparation succeeds with HTTP 200:

```json
{
  "success": true,
  "operation": "prepare_signout_rotation",
  "rotation_id": "UUIDv4",
  "rotation_status": "prepared",
  "expires_at": "RFC 3339 timestamp",
  "purchase_principal_id": "UUID",
  "revenuecat_app_user_id": "server-owned custom ID",
  "binding_generation": 2,
  "already_prepared": false
}
```

The client validates every continuity field and persists the server expiry
before closing the source session. Its bounded RFC 3339 policy accepts the 20–40
UTF-8-byte fractional PostgreSQL timestamp emitted by the route and the
whole-second shape retained by installed local evidence; malformed or oversized
values fail closed before secure persistence. A live reservation blocks ordinary
resolution and every other binding writer. Preparation also records the latest
two-phase resolver intent, permanently invalidating every completion begun
before the reservation even after claim, cancellation, or expiry. A later normal
resolver must begin with a newer intent. After local Auth sign-out, only a
different anonymous JWT identity whose `auth.users.created_at` is not older than
the reservation may claim it:

```json
{
  "operation": "claim_signout_rotation",
  "installation_capability": "43-character base64url value",
  "client_protocol": 3,
  "rotation_id": "UUIDv4",
  "rotation_secret": "43-character base64url value"
}
```

The atomic claim response is HTTP 200:

```json
{
  "success": true,
  "operation": "claim_signout_rotation",
  "rotation_id": "UUIDv4",
  "rotation_status": "completed",
  "expires_at": "RFC 3339 timestamp",
  "purchase_principal_id": "same UUID",
  "revenuecat_app_user_id": "same server-owned custom ID",
  "binding_generation": 3,
  "account_grants_allowed": false,
  "already_claimed": false
}
```

Exact same-destination replay with the same secret returns this receipt with
`already_claimed: true`; a different, older, or permanent destination is
terminal. If the original source remains or is restored, it may send the same
request shape with `operation: "cancel_signout_rotation"`. Cancellation also
safely tombstones a write-ahead request whose prepare response was lost and
returns HTTP 200:

```json
{
  "success": true,
  "operation": "cancel_signout_rotation",
  "rotation_id": "UUIDv4",
  "rotation_status": "cancelled",
  "expires_at": "RFC 3339 timestamp",
  "already_cancelled": false
}
```

An exact cancellation replay sets `already_cancelled: true`. If the exact source
cancels after the preparation has expired, the successful receipt instead uses
`rotation_status: "expired"`; an anonymous claim after expiry returns the 410
error below. iOS removes the Keychain journal only after exact claim, RevenueCat
identity readiness, a `true` result from `EntitlementManager.beginSession(...)`,
and current-session verification, or after exact source cancellation. That
verification includes the same anonymous manager-published user, nonexpired SDK
session, captured Auth generation, cancellation state, and transition context
immediately before proof removal. A retry without a transition owner is stale as
soon as another Auth transition opens. Every other session remains fail-closed.
No stable operation calls `syncPurchases()` or a RevenueCat customer-transfer
API. The rotation secret, its hash, the rotation UUID, and journal fields never
enter logs. The legacy sign-out proof remains unchanged while mode is `legacy`.

On iOS, `PurchasePrincipalResolver` is the source-compatible orchestration
facade over Purchase Identity's focused domain/wire models, deterministic
policies, verified capability/resolver-state stores, secure-random helper, and
typed resolver service. Only its live adapter imports Supabase, defines the
request payloads, invokes this route, and classifies definite `404` fallback
eligibility. `Stores/PurchaseIdentityHandoffStore.swift` separately owns both
installed journal codecs, validation before writes and after reads, exact
device-only Keychain policy, read-back verification, and removal.
`Core/Network/Auth/Coordinators/PurchaseIdentitySignOutWorkflow.swift` owns the
deterministic preparation/sign-out/completion order and checks cancellation
before entry and between every identity phase, while
`PurchaseIdentitySignOutCoordinator.swift` owns stable/legacy selection,
pending-proof continuation, anonymous retry admission, recovery-only reset
admission, and fail-closed stable-journal verification. Recovery drains
account-bound work before loading or completing against the anonymous SDK
session. `PurchaseIdentitySourceHandoffCoordinator.swift` owns aggregate
fail-closed journal projection, exact-source preparation and abandonment, and
failed-sign-out restoration. Cancellation after compatibility preparation's
final SDK-session read cannot report success; the proof persisted before that
read remains available for recovery. Both abandonment routes recheck the exact
transition or unowned account-work lease after the initial suspended SDK session
read and before remote cancellation; stable retirement repeats that fence after
its final SDK read and before durable proof removal.
`PurchaseIdentityHandoffAuthJournal.swift` owns Auth error translation over the
Core Security store, while `PurchaseIdentityHandoffPreparationCoordinator.swift`
contains `PurchaseHandoffPreparationCoordinator`, which owns construction and
stable `preparing`/`prepared` durability checkpoints plus compatibility-proof
persistence before honoring cancellation.
`PurchaseIdentityHandoffCoordinator.swift` owns stable and compatibility
completion keyed by destination, Auth generation, and transition owner;
exact-session and cancellation fences; terminal-only legacy proof retirement;
and proof removal. `PurchaseIdentitySessionCoordinator.swift` owns binding
state, durable-handoff-to-provider-fence projection, and keyed resolver task
lifetime with late superseded-result rejection, while
`PurchaseIdentityReadinessCoordinator` owns foreground
journal/provider/entitlement repair behind exact account and session fences. The
typed legacy-profile service's live adapter alone owns the unchanged `users`
query used by legacy linking. The task-free `PurchaseIdentitySessionLiveService`
owns legacy attribute precedence and provider/entitlement/diagnostic boundary
assembly; its `+Live` adapter alone acquires RevenueCat, `EntitlementManager`,
the resolver, profile service, Supabase client, and privacy-safe logger. The
service's reference lifetime preserves fail-closed facade teardown for deferred
legacy linking and entitlement refresh without changing a wire contract.
`SupabaseManager` injects Auth state, exact-session/account-work, session,
journal, handoff, and recovery closures and revalidates the exact Auth
transition through the source-handoff coordinator around suspended source
discovery and stable preparation. Legacy completion checks cancellation before
dispatching its server destination-bind request and after every asynchronous
phase, retaining the durable proof whenever completion does not reach its
verified terminal state. Fresh deletion and ordinary or purchase-safe sign-out
also reject preflight cancellation before transition admission, persistence, or
Auth mutation. Before an operation may replace the Auth identity, the
source-handoff coordinator rereads both store-backed journal types and derives
readiness from those durable values. An unavailable secure read is treated as
pending, and that derived pending projection keeps paid mutations closed. A
cached false value alone is not authority to replace the identity. This
ownership split changes none of the request, response, error, expiry, or retry
contracts above.

Errors use `{ "code": "...", "error": "..." }` plus the shared request ID.

| HTTP    | Code                                                                                                                            | Meaning / client action                                                                                                             |
| ------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 400/413 | `invalid_request`                                                                                                               | Malformed, oversized, non-exact, or invalid capability payload                                                                      |
| 401     | shared auth error                                                                                                               | Missing, expired, invalid, or non-live JWT                                                                                          |
| 409     | `purchase_principal_capability_revoked`                                                                                         | Terminal device capability; block paid mutations and require reviewed recovery                                                      |
| 409     | `purchase_principal_signout_rotation_required`                                                                                  | A prepared sign-out owns this principal; do not resolve normally, link RevenueCat, or open paid readiness                           |
| 409     | `purchase_principal_signout_rotation_invalid`                                                                                   | Rotation, proof, capability, or caller does not match; retain the journal and fail closed                                           |
| 409     | `purchase_principal_signout_rotation_unavailable`                                                                               | Capability or active principal is unavailable; retain or restore the exact source and never select a fallback                       |
| 409     | `purchase_principal_signout_rotation_already_prepared`                                                                          | Another live reservation owns this principal; retain the current journal and require reviewed source recovery                       |
| 409     | `purchase_principal_signout_rotation_terminal_conflict`                                                                         | Rotation is terminal for another state or destination; retain the journal and require source recovery                               |
| 409     | `purchase_principal_signout_anonymous_destination_required` / `purchase_principal_signout_fresh_anonymous_destination_required` | Caller is not the exact fresh anonymous destination; never fall back to ordinary resolution                                         |
| 409     | `purchase_principal_signout_binding_changed`                                                                                    | Expected source binding or generation no longer matches; retain the journal and investigate the conflicting transition              |
| 410     | `purchase_principal_signout_rotation_expired`                                                                                   | Claim window expired; retain the journal, close paid readiness, and restore the source to cancel/recover                            |
| 426     | `purchase_principal_client_upgrade_required`                                                                                    | Active stable identity requires a newer supported protocol; retain its provider identity and require an app update                  |
| 503     | `purchase_principal_rollout_changed`                                                                                            | Mode changed between begin and completion; retry resolution from the current session                                                |
| 503     | `purchase_principal_binding_intent_stale`                                                                                       | An older Auth request lost the monotonic ordering race; ignore it and let the newest current-session resolution finish              |
| 503     | `purchase_principal_entitlement_projection_changed`                                                                             | The pass-adoption projection changed between read and locked completion; retry from current authoritative state                     |
| 503     | `purchase_principal_account_deletion_in_progress`                                                                               | Account deletion won the lifecycle race; do not mutate provider identity and retry only while the current Auth session remains live |
| 409/503 | `purchase_principal_signout_source_not_available`                                                                               | Source is anonymous/ineligible or its Auth/profile row disappeared; retain the journal and retry only after exact source recovery   |
| 503     | `purchase_principal_signout_account_deletion_in_progress` / `purchase_principal_signout_ghost_merge_in_progress`                | A lifecycle transition conflicts with prepare or claim; keep the journal and let one exact transition reach terminal state          |
| 503     | `purchase_principal_signout_binding_audit_missing`                                                                              | Atomic binding-audit invariant failed; no client repair is authorized, so retain the journal and escalate                           |
| 503     | `purchase_principal_user_not_available`                                                                                         | Auth/profile lifecycle race; retain the session and retry                                                                           |
| 503     | `purchase_principal_unavailable`                                                                                                | Provider, secret, timeout, lock, or database dependency unavailable; retain the session and retry                                   |

The checked-in endpoint is not a rollout authorization. The database defaults to
`legacy` / `dual_read`; stable activation requires the release runbook's exact-
SHA, database replay, provider, old-client, monitoring, and account-grant gates.

### Owner-only purchase identity rollout control

This is an operator/database contract, not an Edge or client API. Migration
`20260813040000_add_purchase_identity_rollout_control.sql` creates the private
`purchase_identity_rollout_operations` ledger and
`apply_purchase_identity_rollout_operation(...)`. The routine accepts one
versioned operation ID, the fixed production environment/project reference, the
exact live PostgreSQL system identifier, one action, exact 40-hex source SHA,
evidence, approval, and approved-plan SHA-256 digests, exact expected
modes/protocol, target protocol, and an optional rollback reference. It is
executable only by the database owner and changes exactly one rollout axis in
the same transaction that records its identity-free receipt.

Operators use `services/supabase/scripts/control_purchase_identity_rollout.ts`.
The default command is read-only and writes a canonical plan plus digest. It
verifies that the clean checkout is at the supplied SHA, binds the database URL
to the checked-in production project reference, records the live database system
identifier, and rejects evidence older than 24 hours or more than five minutes
in the future. Artifact URLs and pass/fail values remain explicit
trusted-operator attestations; the tool does not authenticate external CI,
device, or RevenueCat systems. Apply requires `--apply`, the exact
`--approved-plan-sha256`, the unchanged dry-run JSON through
`--approved-plan-json`, and
`MERIAN_PURCHASE_IDENTITY_ROLLOUT_APPLY_CONFIRMATION` equal to
`<target>:<action>:<source-sha>:<plan-sha256>`. Evidence must prove the
exact-SHA candidate/deploy, disposable DB and iOS gates, clean Apple and Google
devices, RevenueCat transfer setting and product matrix, zero anonymous provider
IDs, zero stable-rotation sync/transfer calls, old-client compatibility,
attribute scrub, required health, and zero projection divergence. Account-grant
authority also requires issuance cutover and rollback rehearsal.

Evidence schema version 2 makes the protocol-3 safety matrix explicit. It
requires rotation-specific database concurrency, device recovery,
unrelated-session rejection, entitlement-gate retention, live-rotation rollback
support, required rotation health, and expiry/count-threshold evidence in
addition to the earlier aggregate statuses. The parser rejects unknown fields
and version-1 evidence rather than silently treating a broad `concurrency` or
`required_principal_health` result as proof of those distinct controls.

`enable_stable`, `rollback_stable`, `enable_authoritative`, and
`rollback_authoritative` are distinct operations. A rollback names the unique,
unused enable receipt it reverses. The tool and ledger enforce evidence; they do
not confer permission. Production application requires **separate explicit
authorization** naming the operation and target. Candidate/deploy workflows must
never invoke the mutating routine or the tool's apply path.

### Owner-controlled account-access issuance

This is also an operator/database contract, not a public API. New beta,
promotion, and support access is issued by
`services/supabase/scripts/grant_account_access_entitlements.ts`; the legacy
RevenueCat beta utility is permanently dry-run-only and rejects apply. The new
tool accepts reviewed user/cohort/Auth-audit artifacts, a finite expiry, grant
kind, operation UUID, clean source SHA, target, and approval digest. Its dry run
reads the live rollout modes and database system identity and emits only
aggregate counts and SHA-256 digests—never account IDs.

Apply requires the unchanged dry-run JSON, exact plan digest, and
`MERIAN_ACCOUNT_ACCESS_GRANT_APPLY_CONFIRMATION` equal to
`<target>:account-access-grant:<source-sha>:<operation-id>:<plan-sha256>`. Under
one serializable transaction it revalidates the live plan, invokes the existing
service-guarded `record_account_access_grant(...)` routine for every sorted
account, and records `internal.account_access_grant_operations`. The receipt is
immutable and identity-free. Exact replay after a lost response is a no-op; a
changed cohort, grant, database, rollout mode, or reused conflicting operation
ID fails closed. This tool never calls RevenueCat, and running it against
production still requires separate explicit authorization naming the target and
operation.

---

## Deno `/transfer-signout-purchases` Edge Node

Preserves StoreKit-backed access when a linked account explicitly signs out to
one fresh anonymous Supabase account. The route accepts `POST` only, limits JSON
to 2 KiB, and never accepts a source or destination UUID. `config.toml` uses
`verify_jwt = false` so the gateway does not couple this route to one JWT
signing scheme; `withEdgeHandler` still requires the Authorization header and
resolves the live Supabase Auth user before the handler runs.

On iOS, `LegacyPurchaseHandoffRemoteService.swift` is the typed
prepare/bind/complete/cancel boundary. Its `+Live` adapter alone owns this
route's private wire DTOs, all four operations across three Supabase SDK
invocation paths, exact handoff/destination response validation, and the
terminal `handoff_expired`/`handoff_invalid` classifier.
`PurchaseIdentityHandoffCoordinator.swift` owns the keyed completion task,
exact-session/cancellation admission, provider and entitlement phase ordering,
and proof removal through injected operations. `SupabaseManager` constructs both
owners and supplies live effects; it does not own this route's DTOs or
completion task state.

The sign-out route coordinator drains account-bound work before a foreground
recovery reads the anonymous SDK session. During preparation, iOS persists a
successful compatibility response before honoring cancellation; cancellation
then prevents the next session read or Auth mutation while retaining the only
one-use recovery proof.

The task key includes transition ownership as well as destination and Auth
generation. A transition-owned request therefore replaces older ownerless work
for the same session instead of joining a task whose exact-session policy has
already become stale. Both caller admission and the coordinator-owned task body
reject cancellation before selecting or reading either durable journal.

### Prepare

```json
{ "operation": "prepare" }
```

Only a non-anonymous session may prepare. The handler fetches authoritative
RevenueCat CustomerInfo for the caller's canonical uppercase UUID, excludes
account-issued promotional/beta access, and snapshots only active
StoreKit-backed access. A matching entitlement/product is insufficient:
subscriptions and non-subscription transactions must carry RevenueCat v1's
explicit `store: app_store` discriminator. Promotional subscription records use
`store: promotional`; unknown or missing stores fail closed. A detached
seven-day-pass history item is eligible only when the existing server projection
confirms its exact active expiry, which prevents a refunded historical purchase
from being resurrected.

The server generates the 256-bit bearer secret and passes only its SHA-256 hash
to the service-role issue RPC. The `201` response is `Cache-Control: no-store`:

```json
{
  "success": true,
  "handoff_id": "UUID",
  "handoff_secret": "43-character base64url secret",
  "expires_at": "RFC 3339 timestamp"
}
```

iOS must persist that proof with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
and verify the write before closing the linked session. A prepare or Keychain
failure leaves that session unchanged. `PurchasePrincipalTimestampPolicy`
validates `expires_at` before that write using the same 20–40 UTF-8-byte policy
as stable rotation: fractional PostgreSQL and whole-second RFC 3339 are
accepted; malformed and oversized values fail closed.

### Bind and cancel

```json
{
  "operation": "bind",
  "handoff_id": "UUID returned by prepare",
  "handoff_secret": "One-time URL-safe secret"
}
```

Bind requires an anonymous JWT. The database derives the destination from
`auth.uid()`, requires it to have been created no earlier than the proof, locks
source and destination Auth rows in UUID order, rejects an active account-
deletion job for either identity, and permits exactly one destination.
Same-destination replay is idempotent. The capability expiry limits only the
initial bind; a bound proof remains completable after that timestamp because the
receipt may already have moved.

`operation: "cancel"` uses the same proof fields and is allowed only while the
restored linked source still owns an unbound `prepared` handoff. Cancellation is
same-source idempotent. Bound or completed handoffs fail closed and cannot be
discarded.

Both operations return `200`, `success`, the same `handoff_id`, their operation
timestamp, and an `already_bound` or `already_cancelled` replay flag. Bind also
returns the database-derived `destination_user_id`; iOS must compare it with a
freshly read anonymous session before any RevenueCat identity or receipt
mutation.

### Complete

After bind, iOS links RevenueCat to the anonymous account's canonical uppercase
UUID and calls `Purchases.syncPurchases()`. It then submits the same proof with
`operation: "complete"`. The handler independently fetches destination
CustomerInfo and requires its StoreKit horizon to cover the prepared horizon. If
a finite prepared horizon elapsed while completion was pending, it also
refreshes source CustomerInfo: a source renewal must be covered by the
destination, while a source that is now free permits completion as free. The
service-only completion RPC records the authenticated Edge boundary's
authoritative destination snapshot and exact verified StoreKit tier/expiry in an
idempotent receipt and makes the canonical source and destination reconciliation
rows due; clients cannot mark a handoff verified directly. It never changes
profile ownership, deletes the source, or grants entitlement. The service
boundary then claims only the destination queue row and applies the prepared
StoreKit horizon, or the exact destination state after that guarded
natural-expiry check, through the existing lease-fenced reconciliation RPC.
Detached pass history is excluded after expiry because passes cannot renew and
purchase mutations remain fenced. If the response is lost, replay uses the
immutable attested state and snapshot instead of depending on later mutable
CustomerInfo; newer webhook/reconciliation watermarks still prevent stale access
from being restored.

Successful response: HTTP 200.

```json
{
  "success": true,
  "handoff_id": "UUID",
  "completed_at": "RFC 3339 timestamp",
  "already_completed": false
}
```

The client removes the Keychain proof only after this response, a successful
fresh entitlement read, and verification that the same anonymous session is
still active. Temporary failure retains the proof and disables
purchase/restore/redeem until relaunch or retry completes it.

Error bodies use `{ "code": "...", "error": "..." }`.

| HTTP    | Code                                                                  | Meaning / client action                                                                                            |
| ------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 400/413 | `invalid_request`                                                     | Malformed, oversized, or non-exact payload; do not retry unchanged                                                 |
| 401     | shared auth error                                                     | Missing, invalid, expired, or non-live user JWT                                                                    |
| 403     | `linked_session_required`                                             | Prepare/cancel requires the linked source                                                                          |
| 403     | `anonymous_session_required`                                          | Bind/complete requires the anonymous destination                                                                   |
| 403     | `handoff_forbidden`                                                   | Authenticated caller does not own this transition                                                                  |
| 404     | `handoff_invalid`                                                     | Unknown, superseded, or wrong-destination proof; remove only this terminal proof                                   |
| 409     | `handoff_not_cancelable`                                              | Receipt continuity is already bound; retain and complete on that destination                                       |
| 410     | `handoff_expired`                                                     | Unbound capability expired; remove the terminal proof                                                              |
| 503     | `purchase_projection_pending`                                         | Source pass/projection evidence is not yet safe; leave the linked session unchanged                                |
| 503     | `purchase_transfer_pending`                                           | Destination receipt state does not cover the active prepared horizon or a current source renewal; retain and retry |
| 503     | `purchase_continuity_unavailable` / `handoff_temporarily_unavailable` | Provider, configuration, lock, or database dependency unavailable; retain and retry                                |

The RevenueCat project must use **Transfer to new App User ID** restore behavior
before a client with this route is released. This route transfers store receipt
access only. Promotional and beta grants stay on the linked source account. An
issued proof remains bound to the legacy destination UUID even if purchase-
principal rollout mode changes before completion. The client must finish this
route on that exact RevenueCat UUID and may adopt a stable principal only after
the device proof is durably cleared.

The compatibility route must not be replaced with a direct RevenueCat V2
customer transfer. That action cannot filter subscriptions by StoreKit versus
promotion provenance and documents no idempotency key. The accepted long-term
separation of Auth, purchase, and account-grant identity is in
[`purchase-principal-auth-separation.md`](../rfcs/purchase-principal-auth-separation.md).

---

## Deno `/merge-ghost-profile` Edge Node

Securely transfers a Ghost profile only when direct OAuth identity linking
cannot preserve its UUID. The route accepts `POST` only, has a 4 KiB JSON body
limit, and uses `verify_jwt = true`. An anonymous Supabase session JWT is
required for prepare; a non-anonymous user JWT is required for complete and
identity refresh. `withEdgeHandler` resolves the live Auth user after the
gateway check.

The iOS client may enter this fallback only for Supabase Auth code
`identity_already_exists`. `OAuthSignInCoordinator` owns that routing and
requires the provider-bound proof to prepare before its injected replacement-
session effect. `OAuthIdentityTokenPolicy` validates the bounded token subject;
`OAuthSignInWorkflow` reports installed, failed, or cancelled replacement so a
cancelled new target cannot be republished as successful. The SDK-facing
`SupabaseAuthSessionService` maps provider-neutral credentials and its `+Live`
adapter owns the Supabase link and replacement calls. `SupabaseManager` retains
Ghost prepare, exact-session replacement reconciliation, observable publication,
and fail-closed cleanup assembly around that injected service. The live install
boundary records the mutation and exact installed identity as the transition's
recovery expectation before post-install cancellation can escape; this permits
cleanup only for that target and is not successful-account publication. Other
identity-link failures do not switch sessions. No request or response field
changes at this boundary.

### Prepare

```json
{
  "operation": "prepare",
  "provider": "apple",
  "provider_subject": "Provider ID-token subject"
}
```

The live anonymous session is the source authority. The response contains
`handoff_id`, a one-time 256-bit `handoff_secret`, and `expires_at`; it is
marked `Cache-Control: no-store`. The database stores only the secret hash and
binds it to `auth.uid()` plus the exact provider identity for 30 days. Provider
subjects must be 1–255 UTF-16 code units with no C0, C1, or DEL Unicode control
scalars. iOS persists the proof in a versioned Keychain queue using
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` before changing sessions.
`Core/Security/GhostProfileMerge/Stores/GhostProfileMergeStore.swift` is the
sole native codec, legacy-migration, validation, and verified-persistence owner
for that queue. It validates the server timestamp's syntax but leaves expiry
classification to this server contract.
`Core/Security/GhostProfileMerge/Services/GhostProfileMergeRemoteService+Live.swift`
is the sole native owner of the prepare, complete, and identity-refresh payload
DTOs and Supabase Function invocation.

Before invoking prepare, the native coordinator requires the owned Auth
transition to encode the same provider. It validates the exact anonymous source
session both before the request and after the response; source-session drift
leaves the returned server capability unpersisted. Prepare transfers no profile
data, and the unused server capability remains subject to the existing 30-day
expiry policy. Caller cancellation is honored only after a still-valid returned
capability becomes durable. These are client admission and recovery guarantees,
not additional wire fields or server error codes.

Successful response: HTTP 201.

```json
{
  "success": true,
  "handoff_id": "UUID",
  "handoff_secret": "43-character base64url secret",
  "expires_at": "RFC 3339 timestamp"
}
```

### Complete

```json
{
  "operation": "complete",
  "handoff_id": "UUID returned by prepare",
  "handoff_secret": "One-time URL-safe secret"
}
```

The permanent destination is derived from the completion JWT and never from a
request UUID. For the pending schema-aware hardening, the completed
single-transaction RPC contract is:

1. verifies the source remains anonymous and the destination owns the prepared
   provider subject;
2. serializes concurrent attempts by source and locks both users;
3. verifies the source-controlled policy covers every eligible user foreign key
   before the first mutating helper;
4. resolves reviewed uniqueness conflicts, moves scans before other ownership,
   and verifies the exact per-species ledger for both users;
5. executes only reviewed reparent/derived/preserve/delete semantics, including
   conflict-safe Community actor handling and durable destination RevenueCat
   repair, while refusing stale, blocked, or composite topology; and
6. records an idempotent receipt before commit.

The current draft implements the policy/topology and scan-ledger parts of that
contract. Its Community lock order and unconditional destination RevenueCat
repair remain release blockers; step 5 is not complete until the rollout
[runbook's proof matrix](./06-supabase-deployment-runbook.md#required-proof-matrix)
passes.

The Edge Function deletes the anonymous Auth user only after commit. A cleanup
failure returns a retryable `503`; replay by the same destination is safe. The
client queues independent handoffs rather than overwriting an older interrupted
upgrade. It removes a queue item only after success or terminal
`handoff_expired`/`handoff_invalid`. A 403 for a different active destination is
retained so the proof can complete when its bound account signs in.

On iOS, `Core/Network/Auth/Policies/GhostProfileMergePolicy.swift` owns stable
queue replacement and terminal-code classification, while
`Core/Network/Auth/Coordinators/GhostProfileMergeWorkflow.swift` owns server
completion → purchase sync → local-evidence sync → proof removal with
cancellation checks between phases. `GhostProfileMergeCoordinator` owns durable
preparation, exact source and provider-transition admission, exact target
admission, target-and-transition-keyed completion, retry, terminal cleanup, and
suppression through injected dependencies. The provider-neutral
`PublicAuthorIdentityRefreshCoordinator` owns the restored-session ordering from
retained Ghost completion through `refresh_identity`, nested account-work
leases, exact-session validation, and identity-change publication. It rejects a
stale scheduling target before task replacement and checks cancellation before
lease/remote admission and after the remote suspension; these are client-side
admission guarantees and do not change the Function payload or response.
`SupabaseManager` assembles the live session, provider, consent, Keychain,
lifecycle, remote-service, event, and logging effects. These native ownership
boundaries do not change the request, response, error, or idempotency contract
above.

Successful response: HTTP 200.

```json
{
  "success": true,
  "target_user_id": "UUID",
  "merged_at": "RFC 3339 timestamp",
  "already_merged": false,
  "message": "Signed-out profile securely upgraded."
}
```

`already_merged` is `true` on an idempotent replay by the original destination.

### Error contract

Error bodies use `{ "code": "...", "error": "..." }`.

| HTTP | Code                                       | Meaning                                                                                               | Client action                                                             |
| ---- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 400  | `invalid_request`                          | Invalid JSON, unsupported fields, provider/subject, UUID, or secret                                   | Do not switch away during prepare; fix the request                        |
| 413  | `invalid_request`                          | JSON body exceeds 4 KiB                                                                               | Do not retry unchanged                                                    |
| 401  | shared auth error                          | Missing, invalid, expired, or non-live user JWT                                                       | Refresh/re-authenticate                                                   |
| 403  | `ghost_session_required`                   | Prepare caller is not anonymous                                                                       | Do not retry as that session                                              |
| 403  | `permanent_session_required`               | Complete/refresh caller is anonymous                                                                  | Sign in to the permanent account                                          |
| 403  | `handoff_forbidden`                        | Destination is not the exact bound provider identity                                                  | Retain the queued proof for the correct account                           |
| 404  | `handoff_invalid`                          | Unknown, superseded, consumed by another destination, or unusable source                              | Remove that queued proof                                                  |
| 409  | `source_already_merged` / `merge_conflict` | Source already upgraded or conflicting concurrent state                                               | Refresh state; do not create an unproved fallback                         |
| 410  | `handoff_expired`                          | 30-day recovery window elapsed                                                                        | Remove that queued proof                                                  |
| 503  | `auth_cleanup_pending`                     | Data merge committed; Auth deletion still pending                                                     | Retain and retry safely                                                   |
| 503  | `merge_temporarily_unavailable`            | Timeout, deadlock, serialization/lock failure, guarded schema drift, or scan-ledger invariant failure | Retain and retry; guest data is unchanged; alert operations on repetition |
| 500  | `merge_failed`                             | Unexpected server failure                                                                             | Retain and retry; investigate logs                                        |

`ghost_merge_species_ledger_mismatch` and `user_species_scan_count_underflow`
are internal database diagnostics, not public response codes. Both must map to
HTTP 503 `merge_temporarily_unavailable` and the message “Account upgrade is
temporarily unavailable. Your signed-out profile data is unchanged.” This
mapping is a release gate: the current schema-aware hardening must not be
deployed until the Edge mapper and its unit test cover both diagnostics.

`{"operation":"refresh_identity"}` is the separate permanent-session operation
for refreshing public provider identity when no merge is required. It returns
`{"success":true}`.

### Durable Auth cleanup

`/reconcile-ghost-profile-merges` is not a client API. A five-minute `pg_cron`
job calls it with one exact platform-managed current or legacy server key; the
function uses `verify_jwt = false` only so that server credential can reach
Deno, then performs an exact timing-safe comparison. It leases at most 100
merged receipts, deletes the obsolete anonymous Auth users, and records each
claim-token-bound outcome. HTTP 404 and exact Auth code `user_not_found` are
idempotent cleanup success. Its response contains aggregate counts and bounded
machine failure codes only; receipt, Auth-user, RevenueCat, and raw
provider/database identities are never returned or logged.

---

## Deno `/register-apple-revocation-token` Edge Node

Captures the server credential needed to revoke Sign in with Apple during a
later account deletion. It requires an authenticated permanent Supabase session
and accepts only `POST`.

```json
{
  "registration_id": "11111111-1111-4111-8111-111111111111",
  "authorization_code": "one-use Apple code",
  "identity_token": "Apple JWT"
}
```

The handler checks the token-free registration receipt before code exchange,
verifies the presented Apple token, exchanges the code at Apple's `/auth/token`
endpoint, verifies the returned token, and requires both subjects to match. The
database then requires that subject on the authenticated user's Apple identity
and atomically stores the refresh token in Vault. The client ID is fixed to
`app.merian.Merian`; a fresh five-minute ES256 client secret is generated from
the hosted Team ID, Key ID, and `.p8` private key.

Success is `200`:

```json
{
  "success": true,
  "status": "registered"
}
```

Repeating the same registration UUID returns the same success without consuming
the code again. A successful exchange followed by failed persistence triggers an
immediate compensating Apple revocation. Validation/expired-authorization
failures are bounded `4xx`; dependency, configuration, or persistence failures
are retryable `503`. Public responses and logs never contain an Apple code,
identity token, refresh token, client secret, or provider response body. The
native `OAuthSignInWorkflow` owns the bounded same-request retry, and
`OAuthSignInCoordinator` requires registration before profile metadata, purchase
binding, entitlement, or final Auth publication. It rejects a missing Apple
registration effect, an Apple-only effect attached to Google, or credentials
whose provider does not match the owned OAuth transition before session
mutation. Cancellation after registration does not retry and cannot advance the
remaining native completion phases; an already-mutated session reaches
completion-owned local cleanup. `AppleOAuthAuthorizationLiveProvider` owns the
raw Apple credential and maps its one-use code into identity-token-free
provider-neutral registration evidence. The provider-neutral OAuth credentials
remain the sole native identity-token source, and the live registration adapter
forwards that same token after session installation.
`AppleOAuthCredentialRegistrationService+Live` alone owns the private wire DTOs,
lowercased registration UUID, and authenticated Edge invocation; its provider-
neutral service accepts only `success == true`, `status == "registered"`. The
adapter performs exactly one authenticated Function invocation per service call.
It owns neither retry policy nor asynchronous task state; `OAuthSignInWorkflow`
remains the retry owner. `OAuthProviderSignInCoordinator` owns callback/task
admission. `SupabaseAuthSessionService` and its `+Live` adapter own the
corresponding OIDC/session/profile-metadata adaptation and Supabase Auth calls,
while `SupabaseManager` retains the exact-session fences, diagnostics,
publication, and cleanup assembly around both injected services. This ownership
split changes no request or response field.

The hosted-secret, rotation, rollout, and production evidence requirements are
normative in the
[Sign in with Apple account-deletion contract](./20-sign-in-with-apple-account-deletion.md).

---

## Deno `/safe-delete` Edge Node

Deletes a user's account and account-owned content from PostgreSQL and
Cloudflare R2 while retaining mandatory ownerless Scientific Data on each
submitted observation.

The exact retained-versus-cleared field boundary is normative in the
[scientific-observation retention contract](./17-scientific-observation-retention.md).

The prepared enrolled-observation detachment materializer adds no request or
response field. Its `scans.retained_identification` is a restricted, immutable
scientific snapshot, with no new client column grant; it is neither a history
result nor a source of current review/publication authority. Selection/review
writers and deletion serialize on the owner; inconsistent selected state aborts
the relational transaction before erasure. Legacy detachment stays unchanged.

The iOS wire methods live in
`Core/Network/Endpoints/MerianNetworkClient+AccountDeletion.swift`, with
accepted/recovery receipt and status DTOs, the operation-specific preparation
receipt, and v2 preparation/commit payloads in `AccountDeletionAPIModels.swift`.
Three request-only DTOs remain private to the endpoint file; pure
operation-specific receipt/proof validation lives in
`Decoding/AccountDeletionResponseDecoder.swift` and
`AccountDeletionRecoveryValidation.swift`. Route-fixed client bridges retain
private transport. `Core/Network/Auth/` owns deterministic error/session
classification, pure phase sequencing, and separate dependency-injected fresh
deletion and recovery coordinators. `AuthRuntimeState` retains live transition,
generation, and exact-session lease/drain state; `SupabaseManager`, Core
Security, and `AppDIContainer` retain endpoint and SDK calls, proof and marker
persistence, sign-out, purge, diagnostics, and lifecycle effects supplied to
those coordinators. The
[native ownership and verification guide](../../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-ownership)
also covers public recovery. This file split changes no payload or lifecycle
contract.

The native workflow checks cancellation before any deletion marker is written,
immediately before and after non-destructive v2 preparation, after the durable
legacy marker, and after both v2 markers. Evidence already written at a later
checkpoint remains available to recovery, while the cancelled task stops before
destructive legacy intake or v2 commit. These client-side checkpoints do not
change the payload, server idempotency, or capability semantics below.

### Request Payload

Legacy intake accepts an absent body or this exact empty object. Existing iOS
requests without a recovery capability send an absent body, which the handler
normalizes to an empty object:

```json
{}
```

When a recovery capability is supplied, the request is exactly:

```json
{
  "recovery_capability": "43-character-base64url-device-proof"
}
```

The capability is the base64url encoding of 32 random device-generated bytes.
Protocol-v2 clients first send a non-destructive preparation with two
independent proofs:

```json
{
  "protocol_version": 2,
  "operation": "prepare",
  "recovery_capability": "43-character-base64url-recovery-proof",
  "acknowledgement_capability": "43-character-base64url-acknowledgement-proof"
}
```

Only after that response is durably recorded locally do they send destructive
commit with the same recovery proof:

```json
{
  "protocol_version": 2,
  "operation": "commit",
  "recovery_capability": "43-character-base64url-recovery-proof"
}
```

The two v2 values must be different. Recovery can inspect/cancel a preparation;
acknowledgement can only retire a committed receipt after verified device
cleanup. Neither selects an account. Unknown keys, padding, malformed lengths,
arrays, and nonobjects return `400 invalid_request`. The endpoint still derives
the deletion target only from the verified JWT identity; the capability
authorizes later recovery and never selects a user, job, provider, or purchase
principal.

### Authentication Enforcement

1. Calls `supabaseAdmin.auth.getUser()` to extract the authenticated user's UUID
   from the `Authorization: Bearer` header.
2. Hashes supplied capabilities with SHA-256. V1 uses the legacy raw-value
   namespace; v2 prefixes recovery and acknowledgement with distinct protocol
   domains before hashing, so neither proof can be replayed through v1 or the
   other v2 operation. Protocol-v2 `prepare` calls
   `prepare_account_deletion_recovery_v2(user.id, recovery_hash,
   acknowledgement_hash)`
   and cannot create a deletion job. After local prepared-state persistence, v2
   `commit` calls
   `request_account_deletion_with_recovery_v2(user.id, recovery_hash)`; the
   database requires the preparation, converts every still-live concurrently
   prepared device proof into a receipt, and tombstones expired hashes as
   committed in the same deletion-intake transaction. Legacy capability clients
   call `request_account_deletion_with_recovery(user.id,
   hash)` and legacy
   `{}` callers use `request_account_deletion(user.id)`. All destructive paths
   record the Apple provider disposition plus legacy manual-fallback boolean.
3. Attempts a target-bound lease through
   `claim_account_deletion_jobs(1, user.id)`. Another live claim produces a
   durable `202` response rather than duplicate work.
4. For every `pending`, `storage_pending`, or `auth_pending` claim,
   `complete_account_deletion_cleanup` atomically writes the idempotent storage
   job, detaches any stable purchase principal from the deleting Auth user,
   freezes further provider-promotion import, invokes `apply_user_tombstone`,
   and verifies no public user or scan still references the UUID. Account-owned
   grants are erased with the account; the installation's non-identifying
   StoreKit principal remains for later signed-out resolution. Retained scans
   become ownerless tombstones and clear compatibility media URLs, structured
   captured-media references, semantic/public location labels, device
   locale/time-zone context, free-form notes, and custom tags. Exact
   coordinates, elevation, time, taxonomy, identification, environmental,
   quality, and provenance facts remain unchanged as mandatory Scientific Data.
   No synthetic `auth.users` or `public.users` identity is created.
5. Relational completion returns `storage_pending` and releases the account
   claim. The storage worker keyset-sweeps the user's free uploads, Pro uploads,
   staging, avatars, and exports prefixes in 50-key pages. After at least 25
   hours it repeats all five prefixes from the beginning. Only an empty delayed
   verification pass transactionally advances the account to `auth_pending`. A
   storage row is claimable only when the matching private job is
   `storage_pending` with completed cleanup and incomplete storage, and no live
   public profile or scan ownership remains. An outbox row by itself never
   authorizes R2 deletion.
6. If `auth_pending` has a stored Apple credential, cleanup returns
   `provider_revocation_pending`. The worker reads the Vault refresh token only
   under the active UUID claim, calls Apple's `/auth/revoke` with the refresh
   token hint, and accepts only HTTP `200`. A transaction then deletes the
   credential mapping, registration receipts, and Vault secret before marking
   provider completion. Any failure preserves both credential and Auth for
   retry. Apple identities without a stored token are explicitly
   `manual_required` and do not claim automatic revocation.
7. Only `auth_pending` with completed storage, resolved provider disposition,
   and no remaining Apple credential may call
   `supabaseAdmin.auth.admin.deleteUser(user.id)`. HTTP `404` and exact Auth
   code `user_not_found` are treated as idempotent success.
8. `finish_account_deletion_attempt` independently rechecks storage and provider
   fences, records terminal completion, or releases the claim with bounded retry
   backoff. Completion clears the private job's direct `user_id`.

All state-machine RPCs are `service_role`-only, call
`internal.require_service_role()`, and have empty `search_path` values. The
caller cannot supply a user ID in the body.

While the job is active, a private database trigger rejects recreation of the
original `public.users` row. Auth metadata synchronization and trusted backend
upserts therefore cannot restore a profile after cleanup but before the external
Auth call. `/generate-upload-urls` also returns
`409 account_deletion_in_progress`, preventing new signed writes during erasure.
Deletion intake locks the Auth user and rejects either side of a bound handoff.
An unbound proof has not authorized a RevenueCat mutation, so deletion may win
without forcing a user who lost the originating device to wait for proof expiry.
The reciprocal bind path locks the same Auth rows and rejects an active deletion
job, so whichever transition wins is visible to the other without a destructive
race.

### Responses

- `200 OK`,
  `{ "success": true, "status": "prepared",
  "protocol_version": 2, "recovery_capability_expires_at": "..." }`:
  only the 24-hour non-destructive preparation is durable. No deletion job,
  cleanup, provider revocation, or Auth mutation has started. If another device
  had already committed deletion, the proof is instead bound to that existing
  job and the subsequent idempotent commit returns its receipt.

  This exact handler shape maps to native `AccountDeletionPreparationReceipt`.
  Its four fields are nonoptional, and
  `AccountDeletionResponseDecoder.decodePreparation` additionally requires HTTP
  200, `success: true`, `status: prepared`, protocol version 2, and a valid
  future expiry. Provider disposition is absent because preparation is
  non-destructive. The handler test and native DTO/decoder tests consume
  `services/supabase/functions/_tests/fixtures/account-deletion-preparation-v2-success.json`
  as one cross-runtime source fixture. See the
  [native preparation contract](../../apps/ios/Merian/Core/Network/README.md#preparation-receipt-contract).
- `200 OK`,
  `{ "success": true, "status": "completed",
  "manual_provider_revocation_required": false,
  "recovery_capability_expires_at": "...", ... }`:
  relational cleanup, delayed empty R2 verification, provider disposition, and
  Auth deletion are confirmed; the terminal account job no longer retains the
  user UUID.
- `202 Accepted`,
  `{ "success": true, "status": "pending",
  "manual_provider_revocation_required": true,
  "recovery_capability_expires_at": "...", ... }`:
  the request is durably recorded. A five-minute scheduled reaper resumes it.
  The boolean is always present; `true` instructs the client to preserve Apple's
  legacy manual removal notice before sign-out. This is a successful deletion
  request, not a prompt to submit another target.
- `400 Bad Request`, `{ "code": "invalid_request", ... }`: malformed or
  unsupported request body. No deletion intake is attempted.
- `405 Method Not Allowed`: any method except `POST`.
- `409 Conflict`, `{ "code": "purchase_continuity_pending", ... }`: this
  identity participates in a bound, unresolved sign-out purchase handoff. No
  deletion job or destructive work began; finish sign-out first.
- `500 Internal Server Error`: no usable intake receipt reached the client. It
  may be a pre-commit failure or a response lost after the idempotent database
  intake committed; the client must retain its pre-request fence and replay the
  same JWT-derived request. It must not infer that destructive work did not
  begin.

`manual_provider_revocation_required` is required on accepted-deletion and
public-recovery receipts, but it is not a backwards-compatible delivery
mechanism for clients that predate it. It is currently absent from the prepare
response as noted above. Older clients ignore the accepted-receipt field and
cannot persist or present the manual Apple-removal notice. Public promotion
therefore requires either an enforceable minimum-supported-build gate with a
clear update path back to in-app deletion, or an independent server-delivered
manual-revocation fallback for older iOS binaries. App Store availability of the
supporting build does not satisfy this compatibility gate.

Supporting iOS clients first persist `capability_preparation_pending`, then
atomically read-after-write verify a protocol-v2 Keychain envelope containing
two independent 256-bit capabilities under `WhenUnlockedThisDeviceOnly`
protection before the first network suspension. The intended path then calls the
non-destructive prepare operation, persists `capability_prepared_pending`, and
persists `capability_intake_pending` before destructive commit. They retain the
exact cached session and permit only an owner-token commit replay until a
receipt arrives. Relaunch from either preparation marker is admitted only to
that same deletion-owned recovery transition. A crash before commit uses public
v2 recovery: `not_committed` retires only the proof and marker and preserves
Auth and SwiftData; pending/completed proves another device or the interrupted
commit created the job and proceeds to cleanup. Outside the installed
mixed-domain compatibility state described below, an unknown v2 proof is also
evidence of no v2 commit because v2 commit cannot run without a server
preparation. Legacy v1 unknown proofs remain ambiguous and fail closed.
Transport, Auth, gateway, `5xx`, cancellation, or decode failure cannot reopen
normal account work or cause a different account to inherit cleanup. The
explicit `409 purchase_continuity_pending` is the only authenticated rejection
that can authorize rejection retirement. V2 first requires public recovery to
establish `not_committed`; legacy rejection may retire directly. iOS persists
`capability_rejection_retirement_pending`, then read-after-delete verifies the
unused proof is gone before clearing the marker. Relaunch in this phase performs
neither local sign-out nor local data erasure.

After a validated pending/completed receipt, iOS advances the marker to
`capability_cleanup_pending`. When the Auth listener observes this accepted-
deletion barrier, it immediately clears the published Auth session,
purchase-principal binding/readiness, and local server-verified entitlement
projection. This is a local fail-closed reset: it does not mutate the server
entitlement ledger, acknowledge deletion, or retire either proof or marker. iOS
then persists any manual Apple disposition, performs verified local Supabase
sign-out, and deletes every active-schema SwiftData row through
`ScanRepository.purgeAllData(modelContext:userDefaults:resetDerivedState:resetRuntimeState:)`.
The required app-owned private-map reset closure empties and epoch-fences
exact-coordinate snapshots, index work, and preview rendering and advances the
active-map presentation reset generation before SwiftData deletion. After the
database save, the asynchronous purge first erases the entire private
`ReanalysisQueue` namespace under its exclusive filesystem lock, including
orphaned preparations. The local receipt worker is suspended and drained first;
Auth transition/recovery barriers remain held. Failure preserves the cleanup
marker and prevents acknowledgement, preference/runtime reset and capability
retirement. The purge then read-back verifies removal of account-derived
`UserDefaults` caches, including field notes, Explore share state, species-name
legacy/tombstone/diagnostic values, account-keyed goal and achievement
envelopes, collection state, Explore state and unread count, legacy
gamification, sync throttles, and account-keyed recovery-dismissal signatures.
Device settings, consent, the deletion marker, and the manual Apple-revocation
notice remain. An injected post-persistence owner then resets observable
settings, gamification, the generation-fenced app badge, and RAM images. It then
acknowledges through the public recovery route using only the independent
acknowledgement capability, records `capability_retirement_pending`, verifies
local Auth absence and repeats the idempotent
SwiftData/private-reanalysis/preferences cleanup on relaunch, verifies Keychain
proof removal, and clears the marker last. Foreground and cold-launch recovery
repeat the exact phase behind a blocking screen. Only a matched committed
capability's `account_deletion_recovery_expired` `410` permits conservative
local cleanup; the subsequent independent acknowledgement remains valid after
expiry and converts the row to a permanent replay receipt before local
retirement. An unknown legacy proof does not. An authenticated duplicate that
arrives after acknowledgement returns the same permanent receipt and cannot
clear acknowledgement or extend its expiry. The app establishes its ordinary
signed-out state only after this sequence. Neither marker nor proof contains an
account, job, provider, or request identifier. Legacy `intake_pending` and
`cleanup_pending` remain supported during the installed-client compatibility
window. A proofless `intake_pending` marker creates and verifies one raw v1
proof before legacy replay; it never stores a v2 envelope for the v1 endpoint,
preserving the same hash domain after an ambiguous response or relaunch. A
proofless `capability_prepared_pending` marker cancels without deletion because
the destructive `capability_intake_pending` phase was never recorded. For
compatibility with an earlier mixed-state bug, a v2 unknown result while an
installed intake/cleanup marker and v2 envelope coexist triggers a read-only v1
recovery lookup with the same proof. Only a positive legacy match advances
cleanup; a legacy unknown remains fail-closed and retains local evidence.

### Public `/recover-account-deletion` continuation

This POST-only route recovers or acknowledges an already accepted deletion after
the cached Auth session is unavailable. It requires the project publishable
`apikey` for gateway routing but deliberately sends no user Bearer token. Its
exact body is:

```json
{
  "operation": "recover",
  "recovery_capability": "43-character-base64url-device-proof"
}
```

Protocol v2 adds `"protocol_version": 2`. Recovery continues to use
`recovery_capability`; acknowledgement instead requires the distinct field
`acknowledgement_capability`. A v2 recovery may return the identity-free
terminal receipt `{ "status": "not_committed", "protocol_version": 2, ... }`.
That status means the server cancelled a non-destructive preparation and no
deletion job exists for the proof. If any device committed first while this
preparation remained live, recovery returns pending/completed. If this proof had
already expired, the commit records its non-reusable tombstone and recovery
returns the distinct non-authorizing preparation-expired state instead.

`operation` is exactly `recover` or `acknowledge`; unknown fields and malformed
proofs return `400 invalid_request`. Edge hashes the proof and calls the
matching service-only v1 or v2 recovery/acknowledgement RPC. A successful `200`
response is exact account-free state:

```json
{
  "success": true,
  "status": "pending",
  "manual_provider_revocation_required": true,
  "recovery_capability_expires_at": "2027-02-09T00:00:00Z",
  "recovery_acknowledged": false
}
```

`acknowledge` must return `recovery_acknowledged: true`. A wrong or unknown v1
proof returns `404 account_deletion_recovery_invalid`; this is not evidence that
the authenticated intake failed, because a prior request may still be
committing. A wrong or unknown proof known to have remained in the v2 domain
cannot have committed because v2 commit requires its prior server preparation,
so supporting clients may retire only that proof and local intent without
signing out or erasing data. Expired 24-hour preparations first move into the
private, identity-free `internal.account_deletion_expired_preparation_proofs`
ledger. If expiration happened before deletion committed, recovery returns
`not_committed`; if another device committed in the transaction that retired
this expired proof, recovery returns the distinct fail-closed
`410 account_deletion_recovery_preparation_expired`. That code is not a deletion
receipt and never authorizes local erasure. Its permanent hash tombstone
prevents an older client from later interpreting the proof as unknown or reusing
it to mint a new capability. A retained proof whose 180-day inspection window
elapsed returns `410 account_deletion_recovery_expired` only after a server-side
hash match. After local cleanup, the same expired proof may be submitted with
`operation: "acknowledge"`; that operation returns the ordinary acknowledged
receipt and removes it from expired-unacknowledged health without deleting the
hash. Dependency failure or malformed database state returns retryable
`503 account_deletion_recovery_unavailable` or
`account_deletion_recovery_invalid_response`. Responses are `private,
no-store`;
no route response or log contains the proof, hash, account, job, or provider
identity.

The native response decoder mirrors this operation boundary rather than relying
on the shared status enum alone. Legacy recovery and acknowledgement admit only
`pending|completed`; v2 recovery may additionally admit only an unacknowledged,
provider-neutral `not_committed`; v2 acknowledgement cannot. Every public
recovery response must carry an explicit Boolean `recovery_acknowledged`. Before
the first cleanup effect, the native workflow independently rechecks that the
receipt is successful and `pending|completed`, so `prepared`, `not_committed`,
and unsuccessful receipts cannot authorize local sign-out or erasure.

### Service-only reaper

`/reconcile-account-deletions` accepts a bounded optional `{ "limit": n }`
object and authenticates one exact platform-managed current or legacy server key
with a timing-safe comparison. Opaque keys use `apikey` only; legacy
service-role JWTs use matching `apikey` and Bearer headers. It never accepts a
target UUID. Each invocation performs a bounded account pass, bounded storage
pages, and, when storage verification completes, one final account pass. It
returns only aggregate `account_claimed`, `account_completed`,
`account_deferred`, `waiting_for_storage`, `storage_claimed`,
`storage_completed`, and `storage_deferred` counts. Claim expiry, persisted
prefix cursors, delayed verification, idempotent Auth-not-found handling, and
database-calculated backoff make crashes and lost responses resumable. It also
prunes a bounded number of expired, non-destructive v2 preparations, records
both proof hashes in the identity-free expired-proof ledger before removing each
row, and returns `recovery_preparations_pruned`. Pruning locks an outer set of
at most the requested number of candidate Auth users in deterministic UUID order
before their preparation rows and skips accounts whose Auth row is already
locked, so concurrent deletion intake wins without making a small cleanup batch
wait or introducing inverse lock order. Committed recovery proofs are permanent
bounded idempotency receipts and the reaper does not delete them. Provider
failures are reported in the existing deferred aggregate and remain inside the
`auth_pending` account phase; no provider credential enters this response.

An authenticated request whose body is exactly `{ "dry_run": true }` returns
only `{ "success": true, "dry_run": true }` with `private, no-store`. Any false,
mistyped, or mixed `dry_run` body returns `400`. The successful path returns
before client construction, database RPCs, job claims, R2 calls, preparation
pruning, or logging. It exists solely for post-deploy verification of the route
and current server-key transport; it is not a health check and does not exercise
deletion work.

The scheduled caller reads its key from Vault and delegates header construction
to `internal.server_api_request_headers(...)`. A modern opaque `sb_secret_...`
key is sent only in `apikey`; a legacy service-role JWT is sent in both
supported headers. The Vault value must be one of the project's active server
keys.

### Service-only deletion health RPC

`POST /rest/v1/rpc/get_account_deletion_health` accepts an empty JSON object and
requires a Supabase server/service-role API credential. Execute is revoked from
`PUBLIC`, `anon`, and `authenticated`; the definer routine also calls
`internal.require_service_role()` before reading private state.

The response is a one-row array of aggregate values:

```json
[
  {
    "generated_at": "2026-07-27T01:00:00Z",
    "active_job_count": 2,
    "pending_cleanup_count": 0,
    "storage_pending_count": 1,
    "auth_pending_count": 1,
    "due_job_count": 1,
    "failed_job_count": 1,
    "active_lease_count": 0,
    "expired_lease_count": 0,
    "oldest_pending_at": "2026-07-25T22:00:00Z",
    "oldest_pending_age_seconds": 97200,
    "oldest_due_at": "2026-07-27T00:45:00Z",
    "oldest_due_age_seconds": 900,
    "storage_backlog_count": 1,
    "storage_due_count": 0,
    "storage_failed_job_count": 0,
    "storage_active_lease_count": 0,
    "storage_expired_lease_count": 0,
    "verification_waiting_count": 1,
    "orphaned_storage_job_count": 0,
    "oldest_storage_pending_at": "2026-07-25T22:00:00Z",
    "oldest_storage_pending_age_seconds": 97200,
    "oldest_storage_due_at": null,
    "oldest_storage_due_age_seconds": null,
    "reaper_cron_active": true,
    "reaper_credentials_configured": true
  }
]
```

`failed_job_count` fields mean active rows carrying their most recent bounded
retry code; the code itself is not exposed. Oldest timestamps and ages are both
null when their corresponding count is zero. The RPC never returns a user UUID,
claim token, cursor, object prefix, or raw error, and it never advances state.
The independent scheduled monitor consumes this contract with a 15-second
deadline and 64 KiB response ceiling.

`reaper_credentials_configured` selects each Vault value first and uses the
legacy app setting only when no Vault row exists, then checks that both
effective values are nonblank. A blank Vault value therefore yields `false` even
if the fallback is populated. The field does not test URL reachability,
credential validity, or a reconciler round trip; the required post-deploy
monitor dispatch validates the independent health-RPC path, while a recent
successful reaper cron request validates the worker path.

### Service-only deletion-recovery health RPC

`POST /rest/v1/rpc/get_account_deletion_recovery_health` accepts `{}` under the
same server/service-role-only authorization and returns one aggregate row:

```json
[
  {
    "generated_at": "2026-08-13T12:00:00Z",
    "active_unacknowledged_count": 2,
    "acknowledged_retained_count": 1,
    "expired_unacknowledged_count": 0,
    "oldest_active_issued_at": "2026-08-13T11:55:00Z",
    "oldest_active_age_seconds": 300,
    "oldest_expired_at": null,
    "oldest_expired_age_seconds": null,
    "maximum_active_capabilities_per_job": 1
  }
]
```

The RPC never returns a proof, hash, account, job, provider, or claim token. An
expired unacknowledged proof is critical because it represents a device that did
not finish cleanup within the normal 180-day recovery window. Eight active
proofs on one job is a warning boundary and more than eight is an invariant
failure. The independent account-deletion monitor fetches and validates both
health rows. Its CLI defaults to `required`, where absence, malformed shape, or
dependency failure is fail-closed. The production schedule derives this mode
with `resolve_deployed_health_monitor_modes.ts`: a successful `main` production
deploy whose ancestor SHA contains both controlling migrations and both hosted
RPC smokes selects `required` immediately. Before that proof and only until the
2026-09-19 UTC deadline, `expand-compatible` accepts an exact `PGRST202` naming
either zero-argument recovery-health RPC. API or Git-history ambiguity fails the
workflow. A sole `completed/skipped` deploy job is conclusive nondeployment
regardless of why it was skipped: the resolver ignores that green run and
continues to older workflow history. A missing or duplicate deploy job, an
incomplete job, or any other conclusion remains fail-closed. The deadline
selects `required` without historical Actions evidence. The summary exposes
`recovery_health_availability` and `recovery_preparation_health_availability` as
`not_deployed` with the corresponding health payload set to `null`; it never
substitutes zero counts. Authorization, timeout, malformed response, and
unrelated catalog errors remain fatal.

---

## Deno `/repair-scan-image` Edge Node

Inspects an active owned scan-image reference and, when the referenced R2 object
is missing, promotes a surviving local image and atomically repairs its cloud
metadata. The same transaction updates matching Scan Library and Explore media
references.

Native inspect/repair requests live in
`Core/Network/Endpoints/MerianNetworkClient+MediaStorage.swift`; their
wire-unchanged, value-only `Sendable` DTOs live in
`Core/Network/MediaStorageAPIModels.swift`. The endpoint forwards raw source/key
values, preserves omitted versus supplied keys, and decodes the required `data`
envelope with explicit wire keys, known statuses, and zero defaults for
absent/null counts. It retains the 30-second deadline, plain decoding errors,
classified refresh, and no ambiguous-failure replay. Core Data Images'
`Services/CloudScanImageRepairActor.swift` owns inspection, local-byte
admission, signing, file PUT, repair, and library-change notification behind
injected dependencies. Native repair admission requires the exact local URL to
be supported by direct filename or registered strong evidence. Timestamp-only
matches remain local display fallbacks and cannot authorize cloud inspection,
upload, or repair. Evidence is rechecked before subsequent network effects after
suspension; its loss permits a later verified retry. This client-side
requirement changes no request or response field and does not replace the
endpoint's owner checks. Before inspection, the recovery boundary canonicalizes
credential-free HTTPS source identity across scheme/host casing, the default
port, query parameters, and fragments. `LocalImageLoader` owns only the
cache/load orchestration that discovers a recovered local file and enqueues the
service. Status decoding alone does not execute that workflow. See the
[native media storage matrix](../../apps/ios/Merian/Core/Network/README.md#media-storage-and-upload-verification).

### Request Payloads

Inspection:

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/old.webp"
}
```

Repair after the client obtains a signed upload URL and uploads the surviving
file:

```json
{
  "source_url": "https://media.merian.app/public_uploads/free/11111111-1111-4111-8111-111111111111/old.webp",
  "restored_object_key": "staging/11111111-1111-4111-8111-111111111111/repair_uuid.webp"
}
```

`source_url` must have the HTTPS protocol, exact `media.merian.app` hostname, no
query or fragment, and a flat
`public_uploads/free|pro/{single-segment}/{single-segment}` path. Its exact
string must also be present in an active owned scan's `image_storage_urls`; path
shape alone is not ownership evidence. `restored_object_key` is optional; when
present it must be one image directly under the authenticated user's exact
staging prefix. The JWT identity—not a body field—selects the owner.

`config.toml` uses `verify_jwt = false` for this app-facing route, so the
function must retain `withEdgeHandler` as its custom live-user authentication
boundary. Disabling the gateway check does not make inspection or repair public.

### Inspection Response

```json
{
  "data": {
    "status": "healthy"
  }
}
```

`status` is:

- `healthy`: an active scan owned by the caller references the URL and the
  source object exists;
- `missing`: the owned reference exists but R2 returns 404; or
- `not_referenced`: no active scan owned by the caller references the URL.

Inspection does not upload, promote, rewrite, or delete media.

### Repair Response

```json
{
  "data": {
    "status": "repaired",
    "replacement_url": "https://media.merian.app/public_uploads/pro/11111111-1111-4111-8111-111111111111/repair_uuid.webp",
    "updated_scan_count": 1,
    "updated_post_media_count": 1
  }
}
```

The repair boundary:

1. rejects the request while account deletion is active;
2. confirms an active owned scan references the exact source URL;
3. `HEAD`s the source and restored staging objects;
4. attempts status-checked removal of the redundant staging upload and returns
   `healthy` without metadata changes if the source has recovered;
5. otherwise promotes the staging image into the caller's current durable
   free/Pro prefix;
6. validates the promoted owner prefix; and
7. invokes service-only `repair_owned_scan_image_reference` to replace the exact
   URL across scan arrays, recursive captured-media JSON, normalized scan
   assets, and owner Explore snapshots in one transaction. Matching Explore
   media health is reset to `healthy` in that transaction, allowing projection
   and owner incident state to restore automatically.

After any unsuccessful or malformed atomic metadata response, the function
rereads exact owner references for both URLs. Source-absent plus
replacement-present evidence proves commit and reconstructs success. It deletes
the newly promoted object only after a returned database rejection when the
source remains referenced and the replacement is provably unreferenced. A lost
response, unavailable owner read, concurrent repair, or any other topology is
outcome-unknown and preserves the object. The old missing URL is not changed
until the atomic metadata transaction succeeds.

### Error Contract

- `400`: invalid source URL or restored staging key.
- `401`: missing/invalid authenticated user.
- `404`: repair requested for a source not referenced by an active owned scan.
- `409 account_deletion_in_progress`: destructive account cleanup is active.
- `409`: the restored staging object does not exist.
- `503`: R2 source or restored-object status could not be verified.
- `503 scan_image_repair_persistence_unknown`: the atomic repair may have
  committed but exact owner references could not confirm it; the promoted
  replacement is preserved and the caller may retry.
- `500`: promotion, atomic persistence, or an unexpected internal boundary
  failed; provider details, keys, and SQL errors are not returned.

This endpoint is a recovery mechanism, not a general media replacement API. See
the
[July 2026 account-scoped R2 image-loss incident report](../incidents/2026-07-account-scoped-r2-image-loss.md).

---

## Deno `/get-explore-media-incidents` Edge Node

Returns only the authenticated owner's active degraded or quarantined Explore
media incidents. The function uses custom JWT authentication and derives the
owner UUID; no target-user field is accepted.

Request:

```json
{}
```

Response:

```json
{
  "data": [
    {
      "post_id": "uuid",
      "scan_id": "uuid",
      "species_common_name": "White-winged Dove",
      "media_health_status": "quarantined",
      "missing_media_count": 2,
      "total_media_count": 2,
      "media_quarantined_at": "2026-07-26T12:10:00.000Z",
      "media_health_updated_at": "2026-07-26T12:10:00.000Z",
      "missing_media_urls": [
        "https://media.merian.app/public_uploads/pro/{owner}/one.webp",
        "https://media.merian.app/public_uploads/pro/{owner}/two.webp"
      ]
    }
  ]
}
```

The canonical handler response is always the wrapped `{"data":[...]}` object
above. During rollout, corrected iOS builds also accept the exact legacy direct
array response (`[...]`) emitted by an older deployed handler; no other
successful-response topology is accepted. Incident entries remain strictly
decoded in either envelope, and a malformed `2xx` response maps to
`invalidResponse` rather than being interpreted as an incident or triggering
scan recovery.

`media_health_status` is `degraded` or `quarantined`. Unpublished, moderated,
tombstoned, and healthy records are excluded. The backing definer RPC verifies
`auth.uid() = self_id` for authenticated direct use, while the Edge boundary
uses service role only with the auth-derived UUID. Its final body dispatches on
identity first: a present user must match `self_id`, while only the no-user path
calls `internal.require_service_role()`. Migration
`20260727183356_restore_identity_first_media_incident_guard.sql` restores this
contract after the later quarantine migration accidentally reintroduced
role-first dispatch.

The iOS `ScansShellViewModel` refreshes this response through its injected live
endpoint adapter on entry, foreground, connection changes, and library repair
events. `LibraryView` consumes only prepared incident/filter presentation
values. Rapid queue-driven refresh triggers are coalesced within five seconds
because this is an independent read-only alert surface. A trigger received
during an in-flight call receives one trailing refresh rather than being
dropped. Canceled drivers cannot admit their response, account replacement keeps
the trailing refresh registered while rejecting the old owner's result, and the
expected authenticated owner is revalidated before private incidents enter view
state. A failed refresh retains the last in-memory incident state instead of
falsely claiming recovery.

---

## Deno `/reconcile-explore-media-health` Edge Node

Scheduled service-role worker for direct R2-origin health verification. The
five-minute cron dispatches unconditionally at fixed ten-minute clock
boundaries, and on alternate ticks only when published, unmoderated,
non-tombstoned media is due without an active lease. That read-only precheck
precedes credentials and HTTP; claims remain inside the existing claim RPC.
Skipped ticks do not call this endpoint. Payload, headers, lease, timeout, and
one audit attempt per actual invocation remain unchanged. The 15-minute
missing-success alert still applies.

Request:

```json
{
  "limit": 200,
  "leaseSeconds": 300
}
```

- Gateway JWT verification is disabled so the endpoint can receive both legacy
  service-role JWTs and current non-JWT project secret keys. The handler accepts
  only an exact server key resolved from `SUPABASE_SERVER_API_KEY`, the
  production-deploy-synchronized `MERIAN_SUPABASE_SERVER_API_KEY`, the hosted
  `SUPABASE_SECRET_KEYS` JSON dictionary, the singular `SUPABASE_SECRET_KEY`
  local/manual fallback, or the legacy `SUPABASE_SERVICE_ROLE_KEY` migration
  fallback. It never uses a database/RLS result as proof. Missing, conflicting,
  and mismatched keys receive `401`; ordinary user and publishable keys are not
  accepted. Worker RPCs use the server environment key rather than the accepted
  request value.
- `limit` is clamped to `1...500`.
- `leaseSeconds` is clamped to `30...600`.
- Primary and distinct-poster `HEAD` requests run in parallel per row within a
  global 24-media-row concurrency cap (at most 48 simultaneous `HEAD` requests);
  a five-minute lease covers the bounded provider-timeout envelope.
- The request cannot specify media IDs, post IDs, object keys, or owner IDs.
- Every primary/poster URL must resolve to a direct durable free/Pro key for the
  owner already attached to the leased database row. Cross-owner,
  temporary-prefix, nested, and arbitrary keys fail closed.
- Each leased primary URL receives a signed S3-origin `HEAD`. A distinct
  thumbnail receives an auxiliary check.
- Primary `404` maps to `missing`; `2xx` maps to `healthy`; timeouts, non-404
  failures, invalid URLs, and provider errors map to `retryable_error`.
- A thumbnail `404` is recorded and omitted but does not mark a healthy primary
  video/audio object as missing.
- Two `missing` outcomes at least five minutes apart are required before
  `health_status = missing`.

Response:

```json
{
  "success": true,
  "claimed": 37,
  "healthy": 34,
  "missingObservations": 2,
  "retryableErrors": 1,
  "errorCount": 0,
  "omittedErrors": 0,
  "errors": []
}
```

Every invocation attempts to write `explore_media_health_reconciliation_runs`.
Per-row result failures are reported as at most 50 private structured samples
with fixed reason codes; complete URLs/provider messages are never persisted or
returned. `errorCount` remains the authoritative total and `omittedErrors`
reports truncated samples. Any failure produces `partial_failure` audit status.
Configuration or lease-claim failures attempt a fixed-code `failed` audit row
before the endpoint returns its generic internal error.

---

## Deno `/ingest-r2-media-events` Edge Node

Accepts trusted Cloudflare Queue batches as reconciliation hints. It never
changes media health directly.

Headers:

```http
X-Merian-R2-Event-Secret: <dedicated random secret, at least 32 characters>
Content-Type: application/json
```

Request:

```json
{
  "object_keys": [
    "public_uploads/pro/{owner}/one.webp"
  ]
}
```

- One to 100 unique direct durable free/Pro object keys are accepted.
- Staging, export, quarantine, avatar, nested, traversal, and arbitrary keys are
  rejected.
- The Cloudflare consumer must not receive or forward the Supabase service-role
  key.
- Create and delete events both make matching health rows due now. The event is
  not treated as existence or deletion proof.
- Queue messages are acknowledged only after a `2xx` response.

Response:

```json
{
  "success": true,
  "accepted_key_count": 1,
  "matched_media_count": 2
}
```

The canonical state, projection, communication, recovery, and operations
contract for all three endpoints is
[Explore Media Health and Quarantine](./12-explore-media-health-and-quarantine.md).

---

## Authenticated Scan Metadata RPCs

Current iOS clients do not PATCH `public.scans` directly:

- `update_owned_scan_custom_tags(p_scan_id, p_custom_tags)` accepts at most 50
  control-free tags of at most 256 UTF-8 bytes each. iOS applies an additional
  64-character display limit, commits the local SwiftData mutation first, and
  serializes immutable RPC snapshots in mutation order. Every snapshot retains
  the authoring account ID and must acquire an exact account-bound Auth lease;
  that identity is not part of the RPC payload. A remote failure is a
  best-effort mirror failure and does not undo the committed local tag or local
  search-index invalidation.
- `update_owned_scan_identification_review(p_scan_id, p_override, p_confirmed,
  p_confirmed_species_id, p_user_review_state)`
  validates one coherent `unreviewed`, `ai_confirmed`, or `user_overridden`
  state and updates all four review fields atomically. The iOS Network mutation
  can be created only through coherent override, confirmation, and reset
  factories; it encodes the same typed `UserReviewState` used for local
  persistence as the exact existing raw enum string and preserves explicit JSON
  nulls for cleared values.

Both SECURITY DEFINER routines have an empty fixed `search_path`, derive the
owner from `auth.uid()`, return the same permission failure for a foreign or
missing scan, and are executable only by `authenticated`. They never accept a
caller-supplied user ID. `anon` and `service_role` cannot execute them. A
temporary column-level UPDATE grant preserves already-installed app versions; it
covers only these five metadata columns and must be retired after the minimum
supported iOS version uses the RPCs.

### Prepared species-confirmation endpoint

`POST /confirm-scan-species` applies only to the reserved explicit-primary
contract. Native explicit-primary reviews use this endpoint; legacy observations
remain on the existing RPC. No current model profile produces the new contract.

The authenticated request contains exactly lowercase UUID `scan_id`, integer
`expected_revision` (0–2,147,483,646), and `action` (`confirm_primary`,
`confirm_name`, `clear`). Only `confirm_name` includes `scientific_name`,
bounded to 160 UTF-16 units. Owner, species IDs, proof and arbitrary fields
cannot be supplied. Primary confirmation takes the saved species-level name;
broader answers cannot use that action. Clear requires no name or external
verification.

Confirmation admits through the existing bounded non-AI dictionary counters,
then obtains fresh accepted SPECIES proof even on a dictionary hit. The
service-only atomic apply RPC rechecks ownership, tombstones, revision and the
exact owner-job backup under the scan-generation lock. It does not invoke an AI
provider. Response `schema_version: 1` contains exact `scan_id` and `review`:
version 1, revision, nullable identity, `user_identification_override`,
`user_confirmed_identification`, `confirmed_species_id`, `user_review_state`.
Identity includes version 1, verified dictionary UUID/scientific name, null
common name and GBIF key. Original AI output/provenance remain immutable.
Verification of the selected taxon is independent of model confidence and
observation truth.

The 8 KiB review envelope preserves existing boolean semantics (`ai_confirmed`
true; `user_overridden`/`unreviewed` false). Initial revision is zero.
Replacement and clear advance it; an exact retry from one revision earlier
returns the same saved state. Other stale/different mutations return
`409 species_review_revision_conflict`; clients must refresh and reconcile,
never silently resubmit with a newer revision. Missing/foreign scans share 404;
unsupported legacy rows return 409; invalid input 400, unverified species 422,
request budget exhaustion 429, and external verification failure 503. Responses
are private/no-store; no provider body or observation text appears in errors.

The scan's identity/revision and job's complete review envelope are
server-owned. Recovery ignores client review authority and restores the exact
backup (including clear); legacy/community edits invalidate stale identity and
FK while retaining review intent. Native acknowledgements and owner history
strictly validate this full envelope and persist it in the existing V53
`confirmedSpeciesIdentityData` bytes. The field contains revision and nullable
identity together, so clearing does not erase ordering evidence. History selects
both authority columns and the four legacy review fields. Omission preserves a
saved authority; partial presence is invalid, older revisions are ignored, and
same-revision conflicts fail. Equal history preserves pending local intent;
newer authoritative state reconciles it. Preparation and acknowledgement never
change original AI output or calibrate its confidence. The shared consumers use
this authority separately from original AI evidence; see
[shared identity semantics](#explicit-identity-in-shared-consumers). Protocol
stays 4. See the
[endpoint contract](../../services/supabase/functions/confirm-scan-species/README.md)
and
[remaining checkpoints](../rfcs/identification-primary-resolution-contract-2026-09-29.md#remaining-consumer-checkpoints).

---

## Prepared observation-history contracts

The
[history contract owner](../../services/supabase/functions/_shared/analysisHistory/README.md)
defines bounded version-1 identity, selection, pagination and chat-context
parsers. These are private preparation contracts, not deployed routes or
generated native DTOs. Explicit history reader protocols 7, 8 and 9 do not
change the current Identify reader capability. Native advertises protocol 9 for
history reads only; V56 admits saved imports with unknown completion dates.
Enrollment still requires state/authority hydration. A separate owner-only
history read RPC is prepared behind a default-false reader gate; no history
selection/deletion RPC is exposed and no chat endpoint persists this context
yet. The
[schema contract](./04-database-schema.md#prepared-observation-analysis-history)
owns prepared storage and transaction behavior; connected API/DTO changes remain
under the
[activation hold](./06-supabase-deployment-runbook.md#observation-analysis-history-activation-hold).
The legacy deletion refusal below remains mandatory.

### Prepared owner analysis history reader

`get_owned_observation_analysis_page(p_request jsonb, p_reader integer)` is
callable only by `authenticated`. It derives the owner from `auth.uid()` and
requires `p_reader` 7, 8 or 9 and
`observation_history_rollout.reader_enabled = true`. Protocol 7 refuses an
entire history containing V2 or V3; protocol 8 accepts mixed V1/V2 snapshots but
rejects any history containing V3. Protocol 9 additionally reads imported saved
identifications, with the unchanged version-1 page envelope. The gate defaults
false; this is not permission to enable it. Ordinary Identify and scan-history
requests still advertise capability 6.

`p_request` has exactly `schema_version: 1`, a lowercase UUID `observation_id`,
nullable positive `before_ordinal`, and `limit` from 1 to 20. There is no
caller-supplied owner. The RPC takes the established owner → generation → scan →
history locks and rejects missing, detached, foreign, unenrolled or deleted
observations. Anonymous and service roles have no execution grant, and no API
role gains direct table access.

The response has exactly `schema_version`, `owner_id`, `observation_id`,
`state_revision`, `items`, and `next_before_ordinal`. Items descend by immutable
ordinal and contain `ordinal` plus a **JSON string** `snapshot`. A page is at
most 4 MiB; a byte-limited prefix can contain fewer than the requested number of
items. Resume only with the returned last accepted ordinal. Null means the
current traversal is complete; later reanalyses are discovered by starting again
at the head. A cursor is never persisted independently of its owner and
observation by this implementation.

Snapshot version 1 contains `schema_version`, `observation_id`, `analysis_id`,
nullable `source_analysis_id`, SHA-256 `request_digest`, positive `ordinal`,
integer UTC `completed_at_ms`, canonical Identify `result` data, and
`evidence_manifest: {schema_version: 1, captured_media: [...]}`. Identify's
`scan_id` binds to the observation; analysis identity is independent. Funding,
review authority and active selection are absent. The media list uses the
existing strict current wire contract, with at least one item and no legacy
local-file references. Added evidence still requires protected-media promotion
before activation; merely decoding a URL does not establish privacy or
recoverability.

The original server result object may also contain projection fields such as
`species_id`, which the canonical Identify validator does not return. Readers
preserve those fields in the original bytes. A future completion producer must
validate the projection-ready object against canonical Identify data and the
species dictionary; it must not persist the normalized parser return as the
server `result_snapshot`.

`internal.observation_analysis_snapshot` produces stable PostgreSQL JSONB text;
the same function enforces the **complete** snapshot's 1 MiB limit on insertion.
The client stores those exact UTF-8 bytes, including ordinal and evidence,
without re-encoding them. Conflicting bytes for an existing analysis ID reject
the whole page before insertion. A future serialization change must preserve
these bytes or introduce a reviewed snapshot-version migration.

Native `ObservationHistorySyncService` accepts one bounded page per call. It
requires an existing acknowledged local owner, initialized selection, selected
analysis UUID and server revision; current login never establishes enrollment.
The account lease surrounds fetch and local commit. A fresh context, pending
deletion check, complete duplicate preflight, parent attachment and save form
one synchronous transaction. A stale lease rolls back even staged children.
Existing selection, correction, rejection, confirmation and community payloads
remain unchanged; the response state revision is not an authority update. There
is no normal sync, completion or UI call site yet. Completion admission,
enrollment, selection/authority hydration and scheduling remain separate
implementation work under the activation hold.

### Prepared private analysis append

`internal.append_observation_analysis(p_user_id uuid, p_request jsonb)` is a
private storage primitive behind default-false `append_enabled`. No API role,
including `service_role`, can execute it directly. No endpoint calls it. Its
caller must eventually be an authenticated, admitted completion orchestrator; a
storage return is not a provider-completion or complimentary-credit receipt.

`analysisHistory/append.ts` owns the canonical builder. The exact request keys
are `schema_version: 1`, `observation_id`, `analysis_id`, nullable
`source_analysis_id`, SHA-256 `request_digest`, `result_snapshot`, and
`evidence_manifest`. These identities are distinct. Full Identify validation
normalizes result data, excludes caller review/funding metadata, and adds only
an independently resolved `species_id`. The database rechecks that link against
its species dictionary and existing primary-identification/projection policy. It
creates fresh unreviewed authority; confirmation of another result cannot
transfer through append.

Evidence is currently limited to 1–64 canonical descriptions with nonempty text
of at most 8,192 characters each. Images, audio, video, local/staging
references, public CDN URLs and signed delivery URLs all fail closed. Current
scan promotion uses public delivery and is not a private history-media contract.
This boundary cannot be enabled for media-backed analyses until protected object
promotion, durable receipts, authorized reads and deletion cleanup are
implemented.

The transaction locks owner → observation generation → owned scan → history.
Ownership, detachment and tombstone checks precede exact replay. A reused
analysis ID must match observation, source, digest, canonical result and
evidence; changed input conflicts. Replay returns the original complete snapshot
text even if new appends are disabled, and changes neither selection nor
authority. New results receive serialized ordinals and a server timestamp. The
aggregate snapshot still has the reader's one-MiB bound.

Initial selection requires an empty revision-zero history and immutable
`initial_selection_permitted`, recorded at history creation and false by
default. A future admission transaction must prove that this is a newly created
observation; clients cannot supply this permission. Subsequent appends,
including concurrent first results, preserve whichever result first initialized
selection. Only initialization writes a projection/reconciliation obligation.
Optional source identity must refer to a result in the same observation.

The prepared child lifecycle below now binds description-only admission and
provider accounting to atomic append/settlement. The raw appender rejects a
funded intent unless that completion transaction owns its fence. Existing
`complete_scan_ingestion_with_entitlement` remains tied to a public scan;
passing a child ID to it is rejected. The separate V2 photo-binding path below
now connects ready private receipts to funded completion. Enrollment and
consumer activation remain prerequisites.

### Prepared funded child-analysis lifecycle

Migration `20261003054717_prepare_funded_observation_analysis.sql` adds private
admission, dispatch, draft, completion and terminal-failure routines. All API
roles, including `service_role`, lack execution and table access. Separate
`admission_enabled` and `dispatch_enabled` gates default false. These are
transaction primitives, not an HTTP endpoint or a running provider/recovery
worker. `analysisHistory/intent.ts` owns the bounded canonical input/draft
builders; existing Identify wire DTOs do not change.

Admission freezes the append identity and description manifest, plus the actual
submitting client's separate `entitlement_protocol: 3`,
`identification_protocol: 6`, `history_protocol: 7`, and
`expected_processor_permission` (`google_gemini` or `openai`). Recovery must
reuse that stored input rather than synthesize capability or reread mutable
notes. Observation and analysis IDs are distinct; an optional source belongs to
that observation. Input and draft are bounded to 1 MiB; the completion receipt
to 2 MiB; provider usage to an allowlisted 2 KiB object. Media-backed input
still rejects in V1. Description admission and protected-media reservation
remain mutually exclusive there; the separately gated V2 admission below binds
ready photo receipts.

The state flow is `admitted → dispatched → draft → complete`, with proven
terminal failure from `admitted` or `dispatched`. Admission reserves using the
analysis ID as the existing complimentary ledger identity and original analysis
ID; it creates neither a public scan nor a legacy ingestion job. Exact admission
retries reuse the intent. Only an expired pre-dispatch reservation may acquire a
new lease/attempt under that same analysis. A changed input or stale lease
conflicts. After dispatch, retry is recovery-only and never requests another
provider execution. No automatic inference retry is prepared.

Dispatch rechecks current processor consent, commits provider quota and records
immutable provenance/attempt accounting once. Its `may_dispatch` is false on
replay. Saving a canonical draft validates the original input, lease and
provenance and records provider usage through the existing idempotent usage
owner. Known refusal/invalid-result/proven-provider-failure records the matching
outcome; a timeout does not prove failure. Existing late usage reconciliation
may preserve an earlier unknown-outcome witness. Drafts are immutable on retry.

Completion locks owner → observation generation → owned scan → history → intent,
checks deletion before replay, then appends the result, settles the
complimentary ledger and stores a receipt in one transaction. It returns exact
saved receipt data after a lost response. The receipt contains the stable
snapshot text, admitted plan, credit consumption and post-settlement
entitlement; it is not yet a client DTO. Reanalysis never changes an existing
selection. Only the separately proven first-selection rule above can initialize
one. Each analysis has at most one credit consumption. Provider executions are
accounted at dispatch; complimentary holds settle at durable completion or
proven terminal failure under the
[funding rules](18-complimentary-pro-scans.md#completion-and-terminal-settlement).

Legacy ingestion, quota, provider-dispatch/reporting and scan-completion paths
cannot bypass an admitted child's owner. Parent deletion and account detachment
erase private inputs/drafts/receipts and release unfinished holds; only an
unused pre-dispatch provider reservation is refunded. Consumed credits remain
consumed. Each erased child leaves a completed ownerless marker in the existing
scan deletion ledger, with no observation link or cleanup lease. Its generation
ID cannot become a legacy scan/job or new quota admission. Owner and
child-generation locks serialize admission/deletion against legacy writers. Raw
result insertion and media reservation are fenced as well.

Before activation, add authenticated orchestration, bounded recovery/delivery,
normal native photo presentation, audio/video evidence binding, analytics
identity discrimination (existing usage `scan_id` means the child analysis
here), verified enrollment, explicit deletion delivery and native sync. This
preparation runs no provider calls and authorizes no deployment.

## Deno `/delete-scan` Edge Node

Deletes a single scan from both Supabase PostgreSQL and Cloudflare R2.

iOS `deleteScan` lives in
`Core/Network/Endpoints/MerianNetworkClient+ScanLifecycle.swift` and retains the
raw camel-case request key below. `ScanLifecycleResponseDecoder` accepts only a
decodable Boolean `success: true` envelope; an empty, malformed, missing-key, or
false-success 2xx response is `MerianError.invalidResponse`. The private
transport retains classified-401 refresh and refuses ambiguous deletion replay.
Core Data retains durable deletion scheduling and does not retire a pending task
without explicit network confirmation. See the
[scan lifecycle verification matrix](../../apps/ios/Merian/Core/Network/README.md#scan-lifecycle-verification).

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
}
```

### Authentication Enforcement

1. Extracts the verified user identity from the GoTrue JWT via the native
   `withEdgeHandler` middleware.
2. Calls the service-only `request_scan_deletion(scanId, userId)` transaction.
   It verifies exact ownership under the per-scan generation lock and persists
   the private deletion tombstone before external work. Foreign ownership
   returns `403`; a genuinely absent or already-completed owner generation
   returns idempotent `200`. An observation enrolled in versioned identification
   history instead returns `409` with code
   `legacy_observation_delete_requires_upgrade`, before any tombstone or
   external erasure. Legacy replacement-deletion intent cannot authorize
   deleting its full history. Native source now stores this exact HTTP/code pair
   as a durable held task without retrying or acknowledging erasure. Other
   failures retain their existing retry behavior. Enrollment stays disabled
   pending reconciliation of ambiguous legacy intent and explicit history
   deletion; new native requests retain account/origin metadata locally, bind
   transport to that account, and keep the same `{scanId}` wire body; the
   rejection is not a success acknowledgement.
3. Reads the fenced canonical scan, normalized media assets, and post-derived
   thumbnails. A database read error is a sanitized `5xx`, never not-found.
4. Deletes only exact
   `https://media.merian.app/public_uploads/{free|pro}/{verified-owner-uuid}/{safe-filename}`
   objects, requiring 2xx or idempotent 404 for every accepted object. Foreign
   owners, nested/dot paths, query strings, fragments, credentials, staging,
   avatars, and malformed URLs are skipped without logging their values.
5. Calls `complete_scan_deletion(scanId, userId)`, which verifies the durable
   owner tombstone, deletes the Postgres row, and records completion. The linked
   Explore post, likes, comments, and media snapshots are permanently removed
   through foreign-key cascades.

The private tombstone survives completion and rejects any delayed inference,
replay, insert/update, or compatibility owner-row recovery for the UUID. A lost
response leaves a retryable deletion rather than permitting an ABA-style scan
resurrection. Completion clears the owner UUID from the private fence.

This explicit owner action is destructive and must be preceded by client copy
that names the linked Explore/engagement deletion. Operational media quarantine
never invokes this endpoint.

---

## Deno `/reconcile-scan-deletions` Edge Node

Service-only recovery worker for interrupted individual-scan erasure. It accepts
no caller-selected scan or user identity. Exact platform server-key
authorization is required before any claim.

PostgreSQL schedules the route every five minutes. One invocation claims
oldest-due rows in 25-job waves with UUID leases, processes at most 100 jobs at
concurrency four, and stops claiming near a 40-second deadline. For each claim
it reloads the canonical fenced source/derived media set, requires every owned
flat canonical R2 deletion to return 2xx or idempotent 404, and calls
`complete_scan_deletion(scan_id, user_id)`. A failure is compare-before-released
with bounded exponential backoff; a stale worker cannot clear a newer lease.

Successful response:

```json
{
  "success": true,
  "claimed": 2,
  "completed": 2,
  "deferred": 0,
  "health_status": "healthy"
}
```

The response and structured logs expose aggregate counters only. Scan IDs, owner
IDs, media URLs, and provider bodies are omitted. The independent Scan Media
Health Monitor calls the service-only `get_scan_deletion_health()` path every 30
minutes and warns at 15 minutes/25 pending jobs; it becomes critical at one
hour/100 pending jobs or any expired lease.

---

## Deno `/block-user` Edge Node

Inserts a moderation block, removing the specified user from the authenticated
user's Discovery Feed via `SocialGuardManager`.

### Request Payload

```json
{
  "blocked_id": "Target UUID to block"
}
```

### Authentication Enforcement

- Extracts the verified user identity from the GoTrue JWT via the native
  `withEdgeHandler` middleware.
- Validates `blocked_id` as a well-formed UUID — a non-UUID string is rejected
  with `HTTP 400` before any database access.
- Upserts the block into `public.user_blocks` using
  `onConflict: "blocker_id,blocked_id"` with `ignoreDuplicates: true`, making
  repeated block requests fully idempotent. A second block by the same user
  returns `200 OK` without inserting a duplicate row or surfacing a constraint
  error.
- Returns `400 Bad Request` if `blocked_id` matches the calling user's UUID to
  explicitly enforce the anti-self-blocking mitigation.

---

## Deno `/flag-issue` Edge Node

Backward-compatible identification-review ingress for an authenticated owner
disputing their own scan inference. Current iOS does not call this endpoint. The
Community Identification detail's **Report post** action is owned by
`Features/Explore/Identify/Services/CommunityIdentificationViewModelDependencies.swift`
and calls `/report-explore-post` with the exact `postId`.

`/flag-issue` derives the reviewer from the verified JWT. Legacy `userId` and
`requestId` properties, when present, are ignored for identity, authorization,
and target selection.

### Request Payload

```json
{
  "scanId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "flagReason": "Incorrect species",
  "userSuggestion": "Optional taxonomy string provided by the user manually"
}
```

`scanId` and `flagReason` are required. `userSuggestion` is optional.

### Authentication Enforcement

- Extracts `user.id` from the `withEdgeHandler` middleware.
- Validates `scanId` as a well-formed UUID — a non-UUID string is rejected with
  `HTTP 400` before any database access.
- Validates `flagReason` against the enum
  `["Incorrect species", "Inappropriate content", "Bad image quality", "Other"]`.
  Values outside this set are rejected with `HTTP 400` before any database
  access.
- Calls the service-only `submit_owned_flag_issue` database transaction. It
  conditionally admits the exact owner, preserves the Admin-compatible
  review-case-before-scan lock order, and revalidates ownership under the scan
  row lock. It atomically inserts `public.flagged_reviews` and sets
  `scans.is_flagged` plus `human_intervention_notes`; a failed mutation rolls
  back both writes.
- Returns `HTTP 404` for unavailable scans and non-owner identification
  disputes, without revealing which ownership check failed.
- Preserves the exact old Community-client **Report post** signature only:
  `flagReason = "Inappropriate content"` and
  `userSuggestion = "Reported from Community request"`. For a non-owner, that
  signature resolves the scan's single possible active Community request,
  requires its canonical detail to be viewer-visible, verifies the exact post
  and scan relation, revalidates the post, and upserts
  `public.explore_post_reports`. Unique `explore_posts.scan_id` and
  `explore_community_requests.post_id` constraints guarantee at most one
  candidate.
- The compatibility path never inserts `flagged_reviews`, sets
  `scans.is_flagged`, or writes `human_intervention_notes`.
- Returns `HTTP 200` on success.
- All current Explore post-content reports use `/report-explore-post` directly.

---

## Deno `/request-export-dwca` Edge Node

This route remains deployed for old-client compatibility, but DwC-A is
authoritatively disabled for the initial launch. A valid permanent-account
request receives `403 feature_unavailable`; the alphabetically first database
BEFORE INSERT trigger independently rejects old Edge bundles and direct
service-role inserts. Release iOS builds hide the control.

When enabled through a reviewed migration, it queues an asynchronous Darwin Core
Archive (DwC-A) export. Because zipping thousands of records exceeds 30-second
HTTP connection limits, this endpoint validates the user and performs a bounded
`export_jobs` insertion transaction. That transaction fixes bounded immutable
phase DTOs plus compact live eligibility metadata under canonical row- and
source-byte budgets; CSV, ZIP, storage, and email work remains asynchronous. The
iOS client awaits the queue response off-main with a 15-second HTTP timeout.

`Core/Network/Endpoints/MerianNetworkClient+Exports.swift` owns that native
request, while Settings Services/ViewModels retain UI gating and error
presentation. It forwards the existing raw scope and Boolean precision flag,
ignores successful HTTP bodies, and adds neither an idempotency key nor
ambiguous mutation replay. This organization does not enable exports or relax
server authorization. `ExportEndpointTests` and the shared transport suite are
in the
[native verification matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification).

### Request Payload

```json
{
  "includePreciseCoordinates": true,
  "exportScope": "personal"
}
```

### Authentication Enforcement

- Extracts user identity from the GoTrue header via
  `supabaseAdmin.auth.getUser(jwt)`.
- Rejects anonymous/ghost sessions with `403 account_required`; export email and
  per-account rate limits require a permanent authenticated identity.
- **`exportScope` authorization**: the public route accepts only `"personal"`.
  The default when omitted is `"personal"`. A `"global"` request receives
  `403 global_export_forbidden`; repository-wide exports require a reviewed
  internal administrative workflow. A non-string scope receives `HTTP 400`.
- **`includePreciseCoordinates` type validation**: `includePreciseCoordinates`
  must be a boolean. A non-boolean value (e.g. a string `"true"`) is rejected
  with `HTTP 400`.
- **Atomic release/rate boundary**: Calls service-only
  `request_dwca_export_job(user_id, scope, precision)`. PostgreSQL first locks
  the private release singleton in shared mode and fails closed if its state is
  absent/off. When enabled, it then takes a transaction advisory lock keyed by
  user, checks the rolling 24-hour successful/nonterminal window, and inserts in
  the same transaction. Reviewed state changes take the conflicting singleton
  row lock, so intake commits before the change or observes its new value.
  `disabled` maps to `403 feature_unavailable`; `rate_limited` and
  `already_pending` map to `429 Too Many Requests`. Failed jobs are excluded
  from the rolling window.
- On `queued`, inserts a row into `export_jobs` with status `pending`. Before
  the `pg_net` webhook can run, an ordered database trigger materializes the
  eligible scan IDs plus immutable bounded occurrence/multimedia JSON DTOs in
  one MVCC statement. Taxonomy follows `confirmed_species_id` when present,
  otherwise the original AI `species_id`. The account advisory lock prevents
  same-user check/insert races. The pending-job partial unique index remains a
  final duplicate fence; only its exact name maps to `already_pending`, while
  any unrelated uniqueness failure is rethrown and fails closed.
- The insertion statement counts only UUIDs through the row lookahead, then
  projects, measures, and inserts one DTO at a time through a parameterized
  lateral cursor. It stops at the first per-row or cumulative source-byte
  violation and removes partial rows, making the aggregate cap a DTO
  memory/temporary-sort work cap as well as a persistence cap.
- `anon` and `authenticated` have no direct `INSERT` privilege on `export_jobs`;
  callers cannot bypass this validation/rate-limit boundary through the Data
  API.

---

## Deno `/export-dwca` Edge Node (Webhook Worker)

For the initial launch, valid service-authenticated calls read the canonical
database release state and return `HTTP 200` with `"disposition":"disabled"`
before queue discovery or provider work. The global continuation cron is
unscheduled and all prior nonterminal jobs are terminal `feature_disabled`.

When enabled, the worker generates the DwC-A ZIP, uploads it to Cloudflare R2,
and emails the user the download link. This endpoint acts purely as a
Server-to-Server webhook triggered by `pg_net` after an `export_jobs` insertion.
It does _not_ accept iOS client connections.

### Request Payload (From Postgres `pg_net` Webhook)

```json
{
  "job_id": "UUID_A"
}
```

Only `job_id` is consumed by the hardened worker. For jobs created inside the
private two-hour migration rollout cohort, PostgreSQL may additionally send
canonical row-derived `user_id`, `export_scope`, and
`include_precise_coordinates` hints for the prior deployed bundle. They are not
authority, they stop appearing automatically after the protocol deadline, and
post-deadline jobs cannot enter processing without a private claim.

The minute-level resume cron sends `{}`. In that form the route repeatedly asks
`get_due_export_job_ids(5)` for oldest-due canonical work until the dispatcher's
soft deadline or step ceiling. An explicit webhook `job_id` is attempted once
without global discovery, bounding fan-out when many jobs are inserted together.
This empty-body contract is also bounded by the shared small JSON reader.

### Security & Enforcement

- Authenticates the Postgres origin by exact comparison with an
  environment-managed current or legacy server key. Current `sb_secret_...` keys
  use `apikey` only; legacy service-role JWTs may use matching Bearer and
  `apikey` transport. The route accepts only `POST`, uses the shared small
  bounded JSON reader, and returns stable request-correlated errors.
- Treats `job_id` only as an opaque wake-up identifier and never reads the
  deprecated user/scope/precision rollout hints. Status, pseudonym version, and
  object-key fields are absent from the webhook contract.
- Calls service-only `claim_export_job_step(job_id, claim_token)`. The RPC locks
  the queue and private work rows, returns immutable canonical state plus the
  current durable phase/cursors/budgets, and creates a private two-minute lease.
  An active, not-due, or terminal job returns no claim and performs no
  source/provider work.
- Calls service-only
  `get_dwca_export_scan_batch(job_id, claim_token, phase, cursor, 100, 262144)`
  for data phases. The database revalidates the claim and canonical cursor,
  keyset-paginates immutable creation-time `(job_id, scan_id)` DTO rows, and
  stops at either 100 scans or 256 KiB of serialized source. Each projection is
  limited to 256 KiB before insertion; total source JSON is limited to four
  times the job archive budget and at most 64 MiB. Global and non-precise
  personal DTOs omit exact GPS keys; an opted-in personal DTO retains them only
  when its snapshot taxonomy does not require protected-species redaction. A
  later scan or ordinary taxonomy/media edit is not part of and cannot alter the
  job. Page reads retain a compact post-cursor eligibility check. A shared
  full-member predicate verifies exact count, snapshot/invalidation state,
  current eligibility, and every stored hash before assembly, staging, email,
  completion, and each download authorization. Relevant scan and
  protected-species changes durably invalidate affected nonterminal jobs. A
  revocation becomes terminal `source_snapshot_changed`, sends no
  not-yet-started email, and removes an uploaded/staged object through the
  durable cleanup outbox. Validated row checks separately cap media-array
  cardinality/URL size, interaction-array cardinality/element size, and selected
  taxonomy text in UTF-8 bytes. Failed jobs purge immutable source DTOs;
  completed DTOs remain only through their live grant and verified cleanup.
- New immutable occurrence DTOs freeze the private `ai_confidence_qualified`
  boolean beside the source score. The worker rejects malformed present flags,
  leaves confidence-derived `identificationVerificationStatus` blank for false,
  and preserves old snapshots whose flag is absent. It adds no public provider
  metadata or new archive columns, and does not reinterpret existing jobs using
  current routing. Deploy the matching worker before alternate results exist.
- Opaque application capability URLs remain in API-inaccessible work state while
  processing. The final full-fence transaction publishes `file_url` and
  `completed` status atomically. The capability points to `download-dwca`, never
  directly to storage.
- Advance, manifest lookup, staging, completion, release, and heartbeat RPCs
  require the same unexpired UUID token; a delayed worker cannot mutate a
  replacement attempt. These definer routines use an empty `search_path`, call
  `internal.require_service_role()`, and are not executable by `PUBLIC`, `anon`,
  or `authenticated`.
- Resolves the email from the claimed canonical `user_id` through
  `supabaseAdmin.auth.admin.getUserById(...)`.
- **DwC-A Global Geoprivacy Leak Prevention**: Enforces strict IUCN Red List and
  ownership gating during ZIP compilation. Evaluates
  `canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id)`.
  For global exports, users receive bounding-box obfuscated coordinates
  (hardcoded 50km `coordinateUncertaintyInMeters`) for scans they do not own.
  Crucially, if a species is flagged as protected (`endangered`, `vulnerable`,
  etc.), the exporter is **always** denied exact coordinates (even for their own
  captures), and public coordinates are aggressively decimate-rounded down to
  ~11km tiles to prevent poachers from extracting precise habitats via standard
  scientific downloads.
- **Versioned pseudonyms**: Global `recordedBy` values use a domain-separated
  HMAC-SHA256 truncated to 128 bits and prefixed with the pinned key version.
  The required Base64 `DWCA_PSEUDONYM_HMAC_KEY_V{n}` is independent of Supabase
  JWT/service keys and has no fallback.
- **Canonical budgets**: Jobs default to at most 5,000 CSV rows and an 8 MiB
  final archive; immutable database constraints cap custom internal jobs at
  20,000 rows and 16 MiB. Budget overflow terminates with `export_too_large`.
- **Resumable generation**: Every claim performs exactly one occurrence page,
  multimedia page, assembly, or delivery phase. An empty-body scheduled route
  invocation processes several claims sequentially, starting no new step after
  the 40-second soft cutoff and attempting at most 40 steps; a targeted insert
  wake-up attempts only its requested job once. Five-job discovery waves remain
  oldest-due ordered, so a successful advance rotates behind older work; failed
  or contended IDs are suppressed for the remainder of that invocation. Data
  phases use row-and-byte-aware `id > last_id` pages over one immutable DTO
  snapshot with page and final full-member privacy-revocation fences. A
  fixed-capacity encoder appends one header/row at a time and fails before
  exceeding 512 KiB; it does not retain a page-wide line array or expanded
  multimedia-row array. Each chunk's CRC-32 is calculated within that bounded
  preparation step and committed to the ordered private manifest together with
  the next cursor and cumulative budgets.
- **Aggregate queue health**: After every drain, the route calls the
  service-only `get_dwca_export_queue_health()` RPC and logs backlog, due,
  active/expired claim, and oldest-due-age values. The five-minute external
  monitor reads the same aggregate only; no job/user identity appears in its
  artifact.
- **Bounded assembly**: Manifest chunks lazily feed a streaming ZIP32 `STORE`
  writer and fixed 8 MiB R2 multipart upload. No complete page history, CSV,
  ZIP, `arrayBuffer()`, or media binary collection is retained in memory. R2
  create/complete XML and Resend replies are streamed through explicit byte
  limits. Completion rejects an S3-compatible `<Error>` body even when R2
  returns HTTP 200. Ordered manifest CRCs are combined algebraically, so
  assembly performs checksum work proportional to chunk count rather than a
  JavaScript loop over every archive byte. Streamed entry sizes must exactly
  match the manifest. Outbound operations have explicit deadlines.
- **Attempt-fenced storage**: Temporary chunk keys contain
  `phase/sequence-claim_token.csv`, and final archives use
  `exports/{user_id}/{job_id}/{claim_token}.zip`. A stale writer can therefore
  neither overwrite the winning chunk/archive nor commit an unexpected key to
  the manifest. After staging, a replacement lease reuses the stored archive key
  and opaque application capability.
- **Idempotent delivery**: Calls Resend directly with
  `Idempotency-Key: dwca-export/{job_id}` and marks the job complete only after
  Resend accepts the request. Re-entry with a staged archive does not regenerate
  it. Because the provider call cannot share a database transaction, completion
  repeats the full-member fence. If privacy changes while Resend is accepting
  the request, the email may exist, but completion fails terminally, revokes the
  capability, and enqueues the attempt-fenced archive for deletion. Permanent
  Resend 4xx rejection is terminal; ambiguous/transient responses remain
  retryable.
- **Revocable downloads**: A capability contains 32 random bytes encoded as an
  exact 43-character base64url token. The database looks it up by SHA-256 hash,
  applies a distributed 60-attempt/IP-hash/five-minute ceiling, and reruns the
  full immutable-membership privacy fence for every click. An authorized request
  receives only a no-store, read-only R2 redirect valid for at most 30 seconds.
  Unknown, revoked, expired, rate-limited, and dependency-error states fail
  closed with stable public codes.
- **Durable archive cleanup**: Expired/revoked grants, privacy races, terminal
  failures, deleted jobs, and legacy direct URLs enter a unique leased outbox.
  `reconcile-dwca-archive-cleanup` drains up to 100 oldest-due rows every five
  minutes with bounded concurrency and durable backoff. Its service-only health
  RPC exposes only backlog, oldest-due age, and expired-lease aggregates.
  Completion compares the leased key with the job's exact current attempt key;
  an old cleanup generation cannot revoke a replacement grant or purge active
  source state. An independent scheduled GitHub monitor calls both export queue
  and cleanup health RPCs, so absent cron/Vault configuration or a stuck
  deletion worker cannot be silent.
- **Stuck-job watchdog**: The watchdog fails pending rows with no phase progress
  for 30 minutes and processing rows with no live claim or durable progress for
  two hours. Public rows store stable failure codes/messages; provider responses
  and internal errors remain only in structured Edge logs. Failed jobs do not
  consume the next 24-hour request window.

### Response

After authentication and bounded parsing, the route synchronously performs a
deadline-bounded drain and returns `HTTP 200`:

```json
{
  "success": true,
  "request_id": "UUID",
  "disposition": "processed",
  "drain": {
    "targeted_wakeup": false,
    "attempted_steps": 8,
    "advanced_steps": 7,
    "completed_jobs": 1,
    "not_claimed_steps": 0,
    "failed_steps": 0,
    "discovery_waves": 3,
    "queue_drained": true,
    "runtime_deadline_reached": false,
    "step_limit_reached": false,
    "elapsed_milliseconds": 1234
  },
  "health": {
    "status": "ok",
    "backlog_count": 0,
    "due_count": 0,
    "active_claim_count": 0,
    "expired_claim_count": 0,
    "oldest_due_at": null,
    "oldest_due_age_seconds": null,
    "generated_at": "2026-07-26T22:00:00.000Z"
  },
  "results": [
    {
      "job_id": "UUID_A",
      "disposition": "advanced",
      "phase": "multimedia"
    }
  ]
}
```

Queue and health fields have deliberately different scopes:

- `backlog_count` includes every nonterminal job, including rows in retry
  backoff or protected by a live claim.
- `due_count`, `oldest_due_at`, and `oldest_due_age_seconds` include only rows
  whose retry deadline has arrived and which have no unexpired claim.
- `active_claim_count` and `expired_claim_count` count claim rows attached to
  outstanding jobs. Any expired claim makes health at least `warning`.
- `queue_drained` means no currently claimable due work remains after the
  invocation. It can be `true` while `backlog_count` is nonzero because another
  worker owns a live lease or work is waiting for bounded backoff.
- `runtime_deadline_reached` and `step_limit_reached` identify why an empty-body
  global drain stopped with due work remaining. Neither is set merely because
  delayed or leased backlog remains.

With no attempted job it returns `"disposition":"idle"` and an empty result
list. A duplicate wake-up can return a result with
`"disposition":"not_claimed"`. A step failure is durably released for retry or
terminal failure, appears only as `"disposition":"failed"` plus a stable
`failure_code`, and does not prevent unrelated due jobs from advancing. Invalid
auth/body values or dispatcher discovery/health failures receive stable
request-correlated HTTP errors; implementation/provider details remain in
structured logs only.

---

## Deno `/download-dwca` Edge Node

Public `GET` capability endpoint:

```text
/functions/v1/download-dwca?token={43-character-base64url-token}
```

For the initial launch, the canonical release state is off and the route returns
no-store `410 download_unavailable` before R2 signing. The launch migration
independently revokes existing capability hashes and queues known archives for
deletion.

The token is the only credential; JWT verification is disabled and
`Authorization` is not accepted as export ownership. Malformed/unknown tokens
return `404`, revoked or expired grants return `410`, the narrow
email-accepted/database-completion race returns retryable `425`, distributed
address-limit exhaustion returns `429`, and database/storage-signing outages
fail closed with `503`. All responses are no-store and request-correlated.

An authorized request transactionally reruns the complete source privacy fence,
then returns `303` to an attachment-only R2 GET signature valid for at most 30
seconds. Privacy triggers also invalidate every affected unpurged snapshot
without relying on a concurrently changing job status. No write credential or
long-lived direct URL is exposed.

---

## Deno `/reconcile-dwca-archive-cleanup` Edge Node

Internal `POST` worker invoked every five minutes. It accepts only one exact
platform-managed server credential, ignores caller-owned work identifiers, and
deadline-drains up to 100 leased deletion jobs in 25-row waves with four
concurrent R2 deletes. A missing object is idempotent success; all other storage
failures release the UUID-fenced claim with durable backoff.

Unlike intake, continuation, delivery, and downloads, this worker remains
scheduled during the initial launch-disabled period so revoked and legacy
objects still converge to physical deletion.

Database completion is also fenced to the exact current `archive_object_key`.
Physical deletion for an older attempt can complete its own outbox row, but it
cannot revoke a replacement grant or purge active source state. Exact-current
terminal cleanup revokes/marks the grant cleaned and then purges retained source
DTOs.

The response contains only claimed/completed/deferred counts and aggregate
health status. Structured health warns at 25 pending or 15 minutes oldest due,
and becomes critical at 100 pending, one hour oldest due, or any expired lease.
Tokens, users, object keys, and provider detail never enter the response or
health event. The independent **DwC-A Export and Archive Health Monitor** reads
this RPC directly on its own schedule as a worker-independent backstop.

---

## Deno `/refresh-species-content` Edge Node (Cron Worker)

Internal service-role worker for stale public species dictionary fields. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{ "limit": 25 }
```

Manual service-role calls may also include:

```json
{
  "limit": 10,
  "dry_run": true,
  "as_of": "2026-05-13T00:00:00Z",
  "content_keys": ["wikipedia_url", "reference_images"]
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires one exact platform-managed current or legacy
  server key and validates it with `timingSafeCompare`; opaque keys use `apikey`
  only.
- Non-POST requests return `405`.

### Refresh Behavior

1. Claims `gbif_wikipedia_reference` rows from `species_enrichment_jobs` with
   the service role. If no jobs are available, falls back to
   `public.get_species_content_refresh_queue(limit, as_of)` for legacy
   provenance-driven refreshes.
2. Groups queued work by `species_id`.
3. Refreshes supported external fields from GBIF/Wikipedia:
   `alternative_common_names`, `taxonomy`, `wikipedia_url`,
   `wikipedia_overview`, `gbif_taxon_key`, and `reference_images`.
4. Updates `species_dictionary` only for fields where fresh external data
   exists.
5. Synchronizes normalized images through
   `public.replace_species_reference_images(...)`, which preserves
   `source = "merian"` rows managed by the Merian reference-image worker. Denied
   external media has already been removed from both the legacy string and
   normalized RPC payload; a database trigger silently rejects the current exact
   outlier if another service-role path attempts to write it.
6. Records new `species_content_provenance` rows for refreshed keys and marks
   claimed enrichment jobs succeeded or failed.

`20260707153931_species_dictionary_enrichment_queue_backfill.sql` is the source
of new queue coverage: it adds a `species_dictionary` insert trigger for future
rows and backfills existing sparse rows into the same `species_enrichment_jobs`
contract. The trigger intentionally runs only on insert so refresh updates do
not continuously reopen completed enrichment jobs.

Per-species refreshes run with a concurrency cap of 4.

Unsupported provenance keys (`common_names`, `habitat_description`,
`lookalikes`, `group_tags`, `iucn_red_list_status`, and `hazard_type`) are
skipped by this worker rather than overwritten. Habitat, lookalikes, and group
tags are handled by `/refresh-species-model-content`; common-name overrides,
IUCN status, and hazard type remain curation-owned.

---

## Deno `/refresh-species-model-content` Edge Node (Cron Worker)

Internal service-role worker for model-heavy species enrichment jobs. It is
invoked hourly by `pg_cron`/`pg_net`, not by iOS clients.

Scheduled call:

```json
{ "limit": 12 }
```

Manual service-role calls may also include `dry_run`, `as_of`, and
`content_groups` with any of `habitat`, `lookalikes`, or `group_tags`.

The worker claims matching `species_enrichment_jobs`, runs the same
species-level biology primitives behind `enrich-scan`, persists results to
`species_dictionary` / `species_lookalikes`, records provenance, and marks each
job succeeded or failed. It does not attach media to species and does not change
scan identity; scan-to-species attachment remains owner publish through
`confirmed_species_id`.

The worker prepares these calls through `_shared/ai/` after the authenticated
claim. Its `service_job` authority contains public-fact purpose, matching task,
claimed job ID and current/max attempts, and fixed `gemini-2.5-flash`; it cannot
authorize identification. Preview returns before preparation. Existing usage
events retain a null user owner and add bounded execution metadata with null
user policy version. Public jobs create no user quota or scan-credit
reservation. The shared boundary does not change the service authentication,
claim RPC, batch/concurrency limits, retry/completion rules, or public payloads.

Lookalike generation is capped at three model candidates per job. Every
candidate must resolve through GBIF as an exact accepted species (or an exact
synonym whose accepted identity is then fetched), match the primary kingdom and
order/family, and pass the same checks again in
`persist_species_model_lookalikes(target_species_id uuid, candidates jsonb, resolution_complete boolean)`.
That service-only RPC returns exactly one row containing `persisted_count`,
`unresolved_count`, and `rejected_count`; the worker rejects malformed or
incomplete accounting. A valid existing relation still counts as persisted even
when its data is unchanged. Candidate taxonomy, eligible unreviewed relation
values, and subject compatibility/attempt values are compared before updating;
unchanged dictionary and relation timestamps remain stable. Successful refreshes
retaining or materializing an unreviewed model relationship still advance
non-curated provenance freshness. Reviewed/curated relations and curated
provenance retain their protection, and no request or response shape changes.
Provider errors, unresolved identities, partial results, and database identity
conflicts fail the job for retry. A verified empty result or candidates proven
incompatible/rejected complete as `no_data` and set the existing attempt flag so
foreground enrichment does not repeat the request.

`claim_species_model_enrichment_jobs(max_rows integer, as_of timestamptz, target_content_groups text[], preview_only boolean)`
is the paired service-only claim RPC. It applies one priority-ordered limit
across the three model groups, keeps preview read-only, and writes a version
marker only as a job is claimed. Legacy empty successes and exhausted failures
without a nonrejected relation receive one fresh attempt; ordinary backoff and
running leases remain unchanged. The migration can therefore precede the new
worker without exposing recovered jobs to an old worker. Candidate
materialization suppresses recursive lookalike jobs and automatic same-genus
fan-out while preserving every other hydration group, reviewed relationships,
curated provenance, and all nonrejected entries in the legacy compatibility
cache.

---

## Deno `/community-taxonomy-status` Edge Node (Internal Status)

Internal service-role endpoint for Community Taxonomy Index and species
enrichment observability. It is read-only and is intended for operational
dashboards, cron health checks, and manual rollout verification after GBIF cache
imports or Community ID publish flows.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires an exact platform-managed service credential:
  `SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
  `MERIAN_SUPABASE_SERVER_API_KEY`, a named `sb_secret_...` value from
  `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
  fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` fallback. Current
  keys use `apikey` only; legacy JWTs use matching `apikey` and Bearer
  transport. Conflicting headers fail closed. Taxonomy table reachability and
  RLS-filtered results are never authorization evidence. Database reads use the
  configured copy of the exact matching environment key, not the raw request
  value or a different preferred overlap key.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "import_run_limit": 10,
  "job_limit": 10,
  "view": "full",
  "target": "birds"
}
```

Both limits must be integers from `1` to `50`. `failure_limit` is accepted as a
backward-compatible alias for `job_limit`. `view = "full"` returns the full
taxonomy/enrichment health snapshot. `view = "coverage"` skips expensive active
taxonomy count queries and returns only bounded import runs plus coverage target
cursor state. `target = "birds"` filters the coverage view to the Birds import
scope.

### Response Payload

```json
{
  "success": true,
  "generated_at": "2026-06-22T00:00:00.000Z",
  "view": "full",
  "active_taxonomy": {
    "id": "taxonomy-version-id",
    "status": "active",
    "source": "merian_dictionary",
    "source_revision": "species_dictionary",
    "node_count": 1000,
    "species_node_count": 600,
    "dictionary_species_count": 240,
    "gbif_only_taxa_count": 360
  },
  "node_counts_by_source": [
    { "key": "gbif", "count": 500 }
  ],
  "node_counts_by_rank": [
    { "key": "species", "count": 600 }
  ],
  "latest_import_runs": [],
  "enrichment_jobs": {
    "counts": [
      { "content_group": "habitat", "status": "queued", "count": 10 }
    ],
    "next_jobs": [],
    "recent_failures": []
  },
  "coverage_targets": [
    {
      "slug": "birds",
      "display_name": "Birds",
      "indexed_species_count": 1000,
      "dictionary_species_count": 600,
      "coverage_ratio": 0.6,
      "last_imported_offset": 950,
      "next_import_offset": 1000,
      "last_successful_import_at": "2026-06-23T00:00:00.000Z",
      "last_import_error": null,
      "gbif_total_count": 14641
    }
  ]
}
```

The endpoint does not refresh coverage, claim jobs, cache GBIF taxa, materialize
Dictionary rows, or attach scan media. It only reports the current database
state available to the service role. Import operators and deploy smoke checks
should use `view = "coverage"` unless they explicitly need source/rank counts or
enrichment queue health.

---

## Deno `/sync-community-taxonomy-index` Edge Node (Internal Import Worker)

Internal service-role worker for bounded GBIF imports into the Community
Taxonomy Index. It is manual-first and resumable; no cron schedule is installed
in v1.

### Authentication Enforcement

- `verify_jwt = false` is configured for service-role calls.
- The function still requires an exact platform-managed service credential:
  `SUPABASE_SERVER_API_KEY`, the production-deploy-synchronized
  `MERIAN_SUPABASE_SERVER_API_KEY`, a named `sb_secret_...` value from
  `SUPABASE_SECRET_KEYS`, the singular `SUPABASE_SECRET_KEY` local/manual
  fallback, or the migration-only `SUPABASE_SERVICE_ROLE_KEY` fallback. Current
  keys use `apikey` only; legacy JWTs use matching `apikey` and Bearer
  transport. Conflicting headers fail closed. Taxonomy table reachability and
  RLS-filtered results are never authorization evidence. Privileged database
  work uses the configured copy of the exact matching environment key, not the
  raw request value or a different preferred overlap key.
- Non-POST requests return `405`.

### Request Payload

All fields are optional:

```json
{
  "target": "birds",
  "offset": 0,
  "limit": 50,
  "page_count": 1,
  "dry_run": false,
  "refresh_coverage": true,
  "retry": false
}
```

Constraints:

- `target`: only `birds` in v1.
- `offset`: non-negative integer.
- `limit`: integer from `1` to `200`.
- `page_count`: integer from `1` to `20`.
- `refresh_coverage`: defaults to `true`; refreshes coverage once after a run
  that imported at least one row.
- `retry`: defaults to `false`; with no explicit `offset`, retries the last
  failed offset when present, otherwise the most recently successful page.

### Response Payload

```json
{
  "success": true,
  "target": "birds",
  "root_gbif_taxon_key": 212,
  "dry_run": false,
  "retry": false,
  "refresh_coverage": true,
  "start_offset": 0,
  "imported_count": 50,
  "fetched_count": 50,
  "normalized_count": 50,
  "end_of_records": false,
  "next_offset": 50,
  "pages": [
    {
      "offset": 0,
      "limit": 50,
      "requested_query": "bounded:birds:root=212:rank=species:status=accepted:offset=0:limit=50",
      "fetched_count": 50,
      "normalized_count": 50,
      "imported_count": 50,
      "dry_run": false,
      "end_of_records": false,
      "next_offset": 50
    }
  ]
}
```

### Import Behavior

1. Fetches GBIF species search pages with `highertaxon_key=212`, `rank=SPECIES`,
   and `status=ACCEPTED`.
2. Normalizes rows into Merian's GBIF community taxon payload.
3. When normalized taxa remain, calls `upsert_gbif_community_taxa(...)`, which
   inserts lineage and species nodes into `taxon_nodes` / `taxon_names` without
   deleting Dictionary-backed rows, and annotates the created import run as
   `scope = "gbif_bounded_birds"`.
4. Checkpoints `next_offset` after every successfully fetched live page,
   including raw nonempty pages whose rows all normalize out and terminal raw
   empty pages. A failure on a later page therefore resumes after every earlier
   checkpoint rather than replaying the batch from its start.
5. Continues until GBIF reports `endOfRecords`, the raw page is empty, or
   `page_count` is reached. An empty normalized page is not a stop condition.
6. Refreshes `taxonomy_coverage_targets` once, and only when the run imported at
   least one row and `refresh_coverage = true`.

`dry_run = true` performs no taxonomy, import-run, cursor, failure, or coverage
writes. Its returned `next_offset` still advances through the simulated pages.

The worker does not create `species_dictionary` rows, enqueue species
enrichment, or attach scan media. Those still happen only through
materialization triggers such as owner-published Community ID consensus.

### Manual Rollout Sequence

After migrations and Edge Functions are deployed:

1. Call `/sync-community-taxonomy-index` with `dry_run = true`, `limit = 50`,
   and `page_count = 1`; omit `offset` to exercise the stored cursor.
2. Repeat the call without `dry_run`, even if the raw page was nonempty but its
   normalized count was zero. That live call must checkpoint the page and move
   to the next raw offset.
3. Call `/community-taxonomy-status` and confirm
   `taxonomy_coverage_targets.next_import_offset` matches the import response.
   If rows were imported, also confirm the latest import run has
   `scope = "gbif_bounded_birds"` and coverage was refreshed. An all-empty run
   correctly creates no import run and performs no coverage refresh.
4. Continue without an explicit offset for ordinary operation. Supply
   `offset = next_offset` only for deliberate manual recovery.

Keep the first rollout to one page per call. Increase `page_count` only after
status checks show expected import rows and coverage counts.

---

## Deno `/refresh-merian-reference-images` Edge Node (Cron Worker)

Internal service-role worker for promoting high-quality published Explore media
into public species dictionary galleries. It is invoked hourly by
`pg_cron`/`pg_net`, not by iOS clients.

### Request Payload

Scheduled call:

```json
{
  "quality_threshold": 80,
  "species_confidence_threshold": 0.95,
  "per_species_limit": 8
}
```

Manual service-role calls may also include:

```json
{
  "quality_threshold": 95,
  "species_confidence_threshold": 0.98,
  "per_species_limit": 4,
  "dry_run": true
}
```

### Authentication Enforcement

- `verify_jwt = false` is configured for `pg_net` compatibility.
- The function still requires one exact platform-managed current or legacy
  server key and validates it with `timingSafeCompare`; opaque keys use `apikey`
  only.
- Non-POST requests return `405`.

### Refresh Behavior

1. Calls `public.refresh_merian_reference_images(...)` with the service role.
2. The SQL helper selects visible Explore posts only: shared, not unshared,
   non-tombstoned, media present, non-private backing scan geoprivacy,
   non-shadowbanned author, and resolved species present. This species-reference
   promotion gate is stricter than ordinary Explore visibility; post-level
   `private` location sharing can keep the post visible while omitting public
   location, but private backing scans are not promoted into Merian reference
   imagery.
3. It unnests all non-empty `scans.image_storage_urls`, requires
   `image_quality_score >= 80` and either `ai_confidence_score >= 0.95` or a
   resolved `confirmed_species_id` by default. Both dry-run and live promotion
   require compatible recorded Gemini metrics or legacy-null provenance.
   Confirmation bypasses the species-confidence threshold, never an unfamiliar
   image-quality scale. The worker dedupes by `(species_id, image_url)`, and
   promotes up to 8 images per species. Public videos are intentionally excluded
   from Dictionary/reference galleries.
4. Public rows use the stable technical `source = "merian"`,
   `license = "Used with permission via Naturebook"`, and
   `attribution = users.public_author_name`. This intentionally preserves the
   public display label rather than switching attribution to the username
   handle.
5. Provenance remains private in `species_reference_image_merian_sources`; no
   public species API exposes source scan, post, user IDs, confidence score, or
   confidence qualification source.
6. Rows are removed on the next refresh when the source Explore post/media is no
   longer publicly visible.

Response:

```json
{
  "success": true,
  "candidate_count": 12,
  "promoted_count": 8,
  "removed_count": 1,
  "species_count": 2,
  "dry_run": false
}
```

---

## Deno `/submit-feedback-survey` Edge Node

Accepts beta feedback survey submissions for the current campaign from the iOS
app. The endpoint is authenticated through `withEdgeHandler`; the server ignores
any client-provided user identity and stores the response under the JWT user id.

Native HTTP submission belongs to
`Core/Network/Endpoints/MerianNetworkClient+ProductFeedback.swift`; the
`FeedbackSurveySubmission` request model and draft/prompt/validation state stay
in Settings Feedback. JSONEncoder, the 30-second deadline, ignored 2xx body, and
ambiguous-replay refusal remain unchanged. `ProductFeedbackEndpointTests` owns
the rehomed endpoint test; `FeedbackSurveyTests` retains only feature policy.
See the
[native matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification).

The
[Settings campaign policy](../../apps/ios/Merian/Features/Profile/Settings/README.md#feedback-campaign-policy)
owns automatic-prompt suppression and the 24-hour submitted-state display for
manual entry. Those client presentation rules are separate from this endpoint's
campaign validation; they are not a server-wide one-submission limit.

### Request Payload

```json
{
  "survey_campaign_id": "beta_feedback_2026_06",
  "satisfaction_rating": 4,
  "recommendation_rating": 9,
  "used_features": ["identify_found_subject", "browse_explore"],
  "most_useful_features": ["camera_identification", "insight_sheet"],
  "confusing_or_disappointing": "Occasionally slow on older devices.",
  "wished_next": "More collection organization tools.",
  "bug_status": "workaround",
  "bug_details": "Retrying fixed one failed scan.",
  "may_follow_up": false,
  "contact": "",
  "app_version": "1.0",
  "build_number": "99",
  "platform": "ios",
  "device_model": "iPhone",
  "os_version": "19.0",
  "locale": "en_US",
  "timezone": "America/Chicago"
}
```

Validation rules:

- `survey_campaign_id` must match the current campaign.
- Satisfaction must be an integer from 1 to 5.
- Recommendation must be an integer from 0 to 10.
- Feature/use values must be from the native survey enum sets.
- Free-text fields are trimmed and capped at 4,000 characters.
- Follow-up fields are retained for API compatibility. The current native survey
  sends `may_follow_up: false` and an empty `contact` value.

### Response Payload

```json
{
  "success": true
}
```

Responses are stored in `public.feedback_survey_responses` with RLS enabled.
Users can insert and read their own rows; product review happens through
Supabase dashboard/service-role tooling rather than public app APIs.

---

## Deno `/submit-community-feedback` Edge Node

Accepts feedback from Explore Identify through the authenticated
`withEdgeHandler` boundary. The handler derives ownership from the verified
user, validates the small JSON body, and awaits insertion into
`community_feedback` before returning `{ "success": true }`. Client-supplied
identity is not used for ownership.

The body contains `feedback` and optional `app_version`, `build_number`,
`platform`, and `os_version` metadata. Feedback must be a nonblank string after
trimming, at most 4,000 characters. Supplied metadata must be strings with at
most 160 characters after trimming; absent/null values are accepted. Blank
version/build/OS values become null, and blank/absent platform defaults to
`ios`. Invalid values return `400` through the shared error boundary.

`Core/Network/Endpoints/MerianNetworkClient+ProductFeedback.swift` owns the
native request. `CommunityFeedbackSubmission` in
`Core/Network/Models/Explore/CommunityFeedbackAPIModels.swift` retains
constructor trimming, metadata, and CodingKeys; Identify Services and its view
model retain validation and submission presentation. The native method keeps its
30-second timeout, ignores successful HTTP bodies, and adds no idempotency key
or ambiguous-failure replay. `ProductFeedbackEndpointTests` and
`EnrichmentExportFeedbackTransportTests` cover this boundary in the
[native matrix](../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification).
This documents the existing route; it introduces no new field or server policy.

---

## Deno `/auto-purge-nonbio` Edge Node

A daily service-only retention endpoint responsible for generation-fencing stale
`.is_biological_subject = false` scans and enqueuing them for the durable
scan-erasure reaper.

### Request Payload

No JSON body is required. The cron trigger issues an empty POST request.

### Authentication Enforcement

- Enforces strict cron authorization via `timingSafeCompare` against one exact
  platform-managed current or legacy server key. Returns `401` if invalid.
- Prevents accidental `GET` evaluations by aggressively validating
  `req.method === "POST"`.

### Deletion Safety

1. Deadline-drains 500-row database batches, with a 40-second runtime budget and
   10,000-generation invocation ceiling.
2. The database selects only rows older than 30 days whose canonical
   `is_biological_subject` value is false, whose `is_tombstoned` value is false,
   whose owner is non-null and non-reserved, and which have no existing
   generation deletion tombstone.
3. Candidate discovery is oldest first, but generation locks are acquired in
   UUID order. Age, classification, scan-tombstone state, owner validity, and
   generation-tombstone absence are rechecked under the generation and scan-row
   locks.
4. The transaction writes the permanent private deletion fence and makes any
   incomplete ingestion ledger terminal. It does no R2 work and leaves the scan
   row available to the reaper.
5. `reconcile-scan-deletions` reloads the fenced row, deletes only exact
   owner-bound scan-media keys, retries interrupted work, and removes the row
   after external erasure succeeds.

Success reports newly requested work rather than completed object deletion:

```json
{
  "success": true,
  "requested_count": 42,
  "runtime_deadline_reached": false
}
```

`requested_count` is intake telemetry, not proof that R2 or relational erasure
has completed. Completion is observable only through the service-only
`get_scan_deletion_health()` summary and the independent health monitor.

| Status | Public contract                                                    |
| -----: | ------------------------------------------------------------------ |
|  `200` | Bounded retention intake completed                                 |
|  `401` | Exact server-key authorization failed                              |
|  `405` | Non-POST method                                                    |
|  `500` | Stable `internal_error` envelope with `X-Request-ID`; no raw error |

## Deno `/report-user`

Authenticated Explore viewers report a visible, non-self author profile. The
function has `verify_jwt = false` because it uses the repository's shared custom
Edge authentication wrapper; it is not an anonymous endpoint.

### Request payload

```json
{
  "reported_user_id": "6a4a8da6-41f5-45de-9569-5f77a60519c1",
  "reason": "Harassment",
  "details": "Optional context, at most 1,000 characters."
}
```

| Field              | Required | Contract                                                                   |
| ------------------ | -------: | -------------------------------------------------------------------------- |
| `reported_user_id` |      Yes | UUID; must differ from authenticated user                                  |
| `reason`           |      Yes | `Spam`, `Harassment`, `Impersonation`, `Inappropriate profile`, or `Other` |
| `details`          |       No | Trimmed text, maximum 1,000 characters; blank becomes `null`               |

Before persisting, the function calls
`get_explore_author_profile(self_id, target_author_user_id, 1)` with the service
client. A syntactically valid but non-visible/arbitrary target returns 404. This
reuses the profile's block, shadowban, post-moderation, and discoverability
rules and does not enumerate account IDs. Because automatic Backyard Safari
enrollment is profile-visible, a known account ID normally remains reportable
until the unfinished starter is stopped or reset.

Success returns HTTP 200:

```json
{
  "success": true,
  "reported_user_id": "6a4a8da6-41f5-45de-9569-5f77a60519c1",
  "message": "Report submitted for moderation."
}
```

Validation/self-report errors return 400, missing/invalid authentication returns
401, and a non-visible profile returns 404.

The service-role upsert key is `(reporter_user_id, reported_user_id)`. The write
updates reason/details/time but deliberately omits `status`, so repeat evidence
from the same reporter does not reset `DISMISSED` or `ACTIONED`. A database
insert trigger attaches a new intake source to the private grouped user case.
The reporting action never blocks the target or modifies abuse state.

`get-explore-author-profile` includes `viewer_can_report`; it is true only when
the current viewer can use this endpoint for the non-self target.

## Internal admin RPCs

All RPCs use the normal authenticated Supabase client. The admin deployment has
no service-role key and does not read tables directly.

`admin_get_access_state` is the restricted pre-MFA routing check. It returns:

```json
{
  "is_authenticated": true,
  "is_member": true,
  "role": "moderator",
  "aal": "aal1",
  "session_active": false
}
```

It does not return raw application data. At `aal2`, `admin_begin_session`
creates/refreshes the internal session for the JWT `session_id` and returns the
role plus absolute expiry.

Every remaining RPC calls `internal.require_admin`, which verifies:

- immutable `auth.uid()` and valid JWT `session_id`;
- registered, active Google user and private membership;
- `aal2`;
- matching live `auth.sessions` row;
- internal session not revoked, not over eight hours, and active within 30
  minutes;
- minimum role.

### Aggregate RPCs

| RPC                      | Parameters                                                                    | Minimum role | Response                                                                                      |
| ------------------------ | ----------------------------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------- |
| `admin_get_overview`     | `p_days`, `p_timezone`, `p_refresh`                                           | Analyst      | Range, account/plan counts, open reviews, new feedback, AI totals, prior period, daily rows   |
| `admin_ai_usage_summary` | `p_days`, optional operation/model/plan/modality, `p_scan_scope`, `p_refresh` | Analyst      | Token categories, cache rate, scan avg/p50/p95, modality totals, daily rows, coverage cutover |

`p_days` is clamped from 0 (all time) through 36,500. Overview daily rows use
the requested IANA timezone; AI summary daily rows currently use database time.
`p_scan_scope` is `primary` or `all_scan_related`. Authorized results are cached
for five minutes by the full filter key; `p_refresh = true` bypasses the cache.

Both RPCs add `priced_events` and `unpriced_events` beside `events` and
`estimated_cost_microusd` in each AI total and daily row; Overview includes the
same fields in `previous_period`. The numeric sum includes only known prices.
Consumers must distinguish zero events, zero priced events, and a partial sum;
missing coverage fields must not imply full coverage. AI Usage adds
`provider_usage`, at most 50 aggregate objects containing `provider`, `model`,
`attribution`, `events`, `total_tokens`, both coverage counts and the cost sum.
`provider_groups_truncated` signals omitted groups, which still count in totals.
Attribution is `saved_result`, `legacy_tier`, `execution_metadata`,
`legacy_model`, or `unknown`. Provider identity is a bounded configuration
label, never an owner identifier. No raw ledger row or observation content is
returned. New versioned cache keys retain the five-minute TTL and
authorization-before-cache behavior. AI Usage encodes the complete filter tuple
structurally, preserving delimiters and distinguishing null from a literal `*`.

### Review RPCs

| RPC                            | Important parameters                                                       | Minimum role |
| ------------------------------ | -------------------------------------------------------------------------- | -----------: |
| `admin_list_review_cases`      | Optional status/type/priority/assignee/reason/from/to, tuple cursor, limit |    Moderator |
| `admin_get_review_case`        | `p_case_id`                                                                |    Moderator |
| `admin_update_review_case`     | Case ID, optional status/priority/assignee change/resolution/note          |    Moderator |
| `admin_set_content_visibility` | Case ID, hidden boolean, required reason                                   |    Moderator |

Review list responses use:

```json
{
  "items": [],
  "limit": 100,
  "next_cursor": {
    "updated_at": "2026-07-19T12:00:00Z",
    "id": "00000000-0000-0000-0000-000000000000"
  }
}
```

Case detail returns `case`, `subject`, `sources`, `notes`, and a nullable
`scan`. The scan object, available only for identification review, may include
exact coordinates; the read is audited. Assignments accept only active moderator
or owner UUIDs. Note storage permits 4,000 characters, but the current
transition RPC mirrors the note into the audit `reason` field and therefore has
an effective 1,000-character limit. Hide/restore is valid only for post/comment
cases, requires a reason of at least three characters, and never changes case
status.

### Feedback and user RPCs

| RPC                     | Parameters                                                     | Minimum role |
| ----------------------- | -------------------------------------------------------------- | -----------: |
| `admin_list_feedback`   | Optional source/status/rating/app-version, tuple cursor, limit |    Moderator |
| `admin_update_feedback` | Source type/ID, state, assignee, tags, optional note           |    Moderator |
| `admin_list_users`      | Search, `(created_at,id)` cursor, limit                        |    Moderator |
| `admin_get_user_detail` | User UUID                                                      |    Moderator |

Feedback states are `new`, `reviewed`, `planned`, and `closed`; original
submissions are never changed. User search matches partial/exact email, Auth
UUID, and public handle. Search input is sent through a server action rather
than a URL query. Both search and detail access are audited.

### Owner RPCs

| RPC                    | Parameters                                 | Purpose                                         |
| ---------------------- | ------------------------------------------ | ----------------------------------------------- |
| `admin_list_members`   | None                                       | Membership inventory                            |
| `admin_upsert_member`  | Exact email, role, active state            | Add/update an existing verified Google user     |
| `admin_list_sessions`  | None                                       | Supabase/internal admin sessions                |
| `admin_revoke_session` | Session UUID, reason                       | Revoke internal session and delete Auth session |
| `admin_list_audit`     | Optional exact action, tuple cursor, limit | Immutable audit history                         |

The member RPC accepts roles `analyst`, `moderator`, and `owner`, and prevents
disabling/demoting the final active owner. Revocation reasons must contain at
least three characters.

All list limits are clamped to 1–100. Callers must pass back the complete
`next_cursor`; there is no offset pagination. Sensitive list/detail access and
mutations write an audit row. Browser server actions additionally enforce an
exact same-host `Origin` check before mutation.

See [`10-internal-admin.md`](./10-internal-admin.md) for the data/security model
and [`11-internal-admin-operations.md`](./11-internal-admin-operations.md) for
setup, deployment, and recovery.

## Deno `/revenuecat-webhook` Edge Node

Receives signed POST events from RevenueCat and reconciles the latest
authoritative subscriber state into Supabase. The route is a server-to-server
boundary; the iOS SDK and client-reported entitlements never authorize the
database write.

### Request Payload

The body is a RevenueCat Webhook envelope with an `.event`. The handler requires
bounded, non-control-character values for `event.id` and `event.type`, plus a
non-negative safe-integer `event.event_timestamp_ms`. Optional `app_user_id`,
`original_app_user_id`, `aliases`, `product_id`, `transaction_id`, and
`original_transaction_id` are validated before use. `TRANSFER` instead requires
non-empty, bounded `transferred_from` and `transferred_to` arrays. An event
timestamp more than five minutes ahead of the signed delivery timestamp is
rejected before database access. The request body is capped at 256 KiB.

### Authentication Enforcement

- Requires `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>` and compares it
  in constant time.
- Requires
  `X-RevenueCat-Webhook-Signature:
  t=<unix-seconds>,v1=<hmac-sha256-hex>`.
  `REVENUECAT_WEBHOOK_SIGNING_SECRET` signs the ASCII timestamp/dot prefix plus
  the exact raw request bytes. Verification happens before UTF-8 decoding or
  JSON parsing, permits more than one `v1` digest for protocol compatibility,
  and rejects timestamps more than five minutes in the past or future.
- Missing any of the Authorization, signing, or server API secrets returns `401`
  or `503`; there is no static-secret-only compatibility path.
- **Customer identity contract**: iOS configures RevenueCat only after a
  Supabase session exists, using the uppercase RFC 4122 Auth UUID, and writes
  subscriber attributes (`supabase_user_id`, `auth_email`, `public_username`,
  `public_author_name`, `public_identity_source`, `account_kind`) before
  entitlement checks. Account changes use direct `logIn`; the client never
  configures without an ID and never calls SDK logout. Manual dashboard
  adjustments should use the uppercase UUID/App User ID first, with subscriber
  attributes as the human-readable cross-reference. This applies to both
  RevenueCat Test Store and production keys.
- UUID candidates are ordered from `app_user_id`, `original_app_user_id`, then
  `aliases` and deduplicated. A RevenueCat `TRANSFER` creates independent source
  and destination subjects from its two identity arrays; it does not have an
  `app_user_id`. Each subject must resolve transactionally to exactly one live
  `public.users` row. A purely anonymous customer receives a durable
  `200 ignored` event receipt without a provider call; a later alias event has a
  different event ID and can carry the linked UUID. A UUID with no public
  profile returns retryable `503`, while a group that maps to multiple live
  profiles returns `409`. The one exception is an already-deleted transfer
  source: no Merian access remains to revoke, so that subject is omitted without
  blocking the destination. Billing never creates a user.

### Authoritative state and transaction

- The server calls, for every mapped customer,
  `GET https://api.revenuecat.com/v1/subscribers/{app_user_id}` with
  `Authorization: Bearer <REVENUECAT_SECRET_API_KEY>` after each new accepted
  webhook. Before that call, `get_revenuecat_webhook_event_result(...)` checks
  the private ledger; a committed duplicate with the same event timestamp, type,
  and payload SHA-256 returns immediately so normal retries and in-window
  replays do not amplify provider traffic. The response is capped at 2 MiB and
  must contain a safe-integer `request_date_ms` and subscriber object; an
  implausibly future snapshot is rejected. Network/provider errors return
  `502`/`503` without a database mutation. For `TRANSFER`, source and
  destination lookups run concurrently and both must succeed before the database
  call.
- An active standard entitlement whose identifier is `pro` or `Naturalist Tier`
  projects `subscription_tier = pro` and persists the later of recurring
  expiration and grace-period expiration. `NULL` is reserved for an entitlement
  whose provider expiration is explicitly null (lifetime).
- An unexpired authoritative `pro_week` transaction projects a timed Pro expiry
  at `purchase_date + 7 days`. A matching pass refund/revocation is excluded; an
  unmatchable revocation fails closed for transactions at or before the event
  time while preserving a provably later purchase.
- No active paid state projects `subscription_tier = free` and a null expiry.
- `public.apply_revenuecat_identity_state(...)` records `event.id` under a
  primary key, records zero to two identity subject rows, and locks all selected
  users in sorted UUID order. Authoritative `request_date_ms` is the primary
  monotonic version; provider event timestamp and event ID break only exact
  snapshot ties. Duplicate IDs and older snapshots cannot update a user; a
  conflicting reuse of the same ID with a different event timestamp, type, or
  payload digest is rejected. Transfer source/destination transitions commit or
  roll back together. During rollout, the immediately previous bundle may still
  call the exact `public.apply_revenuecat_customer_state(...)` and
  `public.schedule_revenuecat_reconciliation(...)` signatures. Those
  compatibility adapters validate the old payload and delegate legacy UUID
  subjects into the separated identity ledger and scheduler. Both share a
  cutover advisory lock with stable completion before taking principal/user row
  locks, then recheck after acquiring them; SQLSTATE `55000` wins if stable
  activation commits before either legacy mutation.
- The RPCs and private ledger tables are not client APIs. Only `service_role`
  may execute the duplicate lookup and mutation definer routines; both perform
  their own caller check and use an empty search path.
- Existing scan media stays in place on tier changes. Both
  `public_uploads/free/` and `public_uploads/pro/` are durable scan-media
  prefixes.

### Response contract

- `200 {"success":true,"outcome":"applied","subject_count":N,
  "applied_count":N,"stale_count":0}`:
  all mapped authoritative transitions were accepted.
- `200 ... "duplicate"`: the exact event ID/timestamp/type/payload was already
  committed; the three counts describe its original result.
- `200 ... "stale"`: all mapped subjects were recorded but their ordering tuples
  were older.
- `200 ... "mixed"`: a multi-subject transfer applied for one user while the
  other already had a newer watermark.
- `200 {"success":true,"outcome":"ignored","subject_count":0,
  "applied_count":0,"stale_count":0}`:
  no Supabase UUID existed in the RevenueCat identity set; the event ID was
  still persisted.
- `400`: malformed event data.
- `401`: Authorization or HMAC verification failed, including replay-window
  rejection.
- `409`: the same event ID was reused with conflicting immutable fields, or a
  RevenueCat identity group mapped to multiple live Merian profiles.
- `413`: the raw webhook body exceeds 256 KiB.
- `405`: any method other than `POST`.
- `502`/`503`: authoritative subscriber lookup, configuration, public-profile,
  or database availability failed. RevenueCat should retry these non-2xx
  responses.

### Service-only authoritative reconciliation

`/reconcile-revenuecat-subscribers` is not a client API. The 15-minute `pg_cron`
call sends `POST {}` with one exact platform-managed current or legacy server
key. The route also requires a configured `sk_` RevenueCat server key and
accepts no user ID, lookup ID, tier, or limit from HTTP. Its `pg_net` response
timeout is 120 seconds.

The private queue leases six due linked customers per short
`FOR UPDATE SKIP LOCKED` wave for two minutes. The worker repeats waves until
empty or until its 60-second monotonic start-work cutoff; the remaining 30
seconds are reserved for the final bounded wave, writes, and health read.
CustomerInfo lookups run with concurrency three and reuse the same 10-second, 2
MiB provider boundary as webhook processing. A claim-token-fenced
`apply_revenuecat_reconciliation(...)` updates access only when
`request_date_ms` is newer than the transactional customer watermark. Pro users
are next due in six hours and free users in 24 hours; transient failures use
durable database backoff.

RevenueCat App User IDs are case-sensitive and subscriber GET is get-or-create.
Database-generated queue identities therefore use
`internal.canonical_revenuecat_app_user_id(...)`, which returns the uppercase
Supabase UUID used by iOS. Exact webhook aliases remain valid lookup IDs and are
not case-normalized by the scheduling RPC.

Background reconciliation does not newly grant a historical `pro_week`
transaction after a free/revoked watermark, preventing refunded pass history
from restoring access. Its response is aggregate only:

```json
{
  "success": true,
  "claimed": 3,
  "reconciled": 3,
  "applied": 1,
  "stale": 2,
  "failed": 0,
  "claimBatches": 2,
  "queueDrained": true,
  "runtimeDeadlineReached": false,
  "healthStatus": "ok",
  "health": {
    "generatedAt": "2026-07-26T03:30:00.000Z",
    "dueCount": 0,
    "expiredClaimCount": 0,
    "oldestDueAt": null,
    "oldestDueAgeSeconds": null,
    "signoutPreparedCount": 0,
    "signoutBoundCount": 0,
    "oldestSignoutPendingAt": null,
    "oldestSignoutPendingAgeSeconds": null
  }
}
```

`get_revenuecat_reconciliation_health()` is a separate service-role-only Data
API RPC. It returns one aggregate row and no customer identity. In addition to
queue health, its snake-case Data API row counts unexpired `prepared` legacy
sign-out proofs and all `bound` proofs and exposes one combined oldest pending
age. A prepared proof has not moved a StoreKit receipt and deliberately remains
recoverable by the originating device for 30 days, so prepared-only age does not
change worker or GitHub monitor severity. Legacy prepared-proof volume warns at
100 and becomes critical at 500 regardless of whether a bound proof also exists.
Once any bound proof exists, the combined oldest age is used conservatively: 30
minutes warns and 60 minutes is critical. Expired queue claims also warn.

The stable-principal migration adds the separate service-role-only
`get_purchase_principal_health()` aggregate. The monitor JSON records its
contract as `purchase_principal_health_availability: available` plus the bounded
aggregate row. This established aggregate is unconditionally required: the CLI
exposes no compatibility switch for it, and a missing RPC, authorization or
transport error, or malformed response is fatal.

Protocol 3 adds `get_purchase_principal_signout_rotation_health()` under the
same service-only monitor boundary. Its one aggregate row contains
`generated_at`, `prepared_count`, `expired_prepared_count`,
`oldest_prepared_at`, `oldest_prepared_age_seconds`, `completed_last_24h`, and
`cancelled_last_24h`; it contains no Auth identity, capability, principal ID, or
proof. The RPC first atomically terminalizes every preparation whose expiry has
passed. `expired_prepared_count` is the number newly transitioned by that health
invocation, not the retained lifetime total, while `prepared_count` contains
only still-live rows. Any newly expired preparation is at least a warning.
Oldest prepared age shares the configured 30/60-minute warning/critical
thresholds; prepared volume warns at 100 and becomes critical at 500 by default.
The schedule derives the rotation mode with
`resolve_deployed_health_monitor_modes.ts`. A successful `main` production
deploy whose ancestor SHA contains the controlling migration and hosted
rotation-health smoke selects `required` immediately. Before that proof and only
until the 2026-09-19 UTC deadline, `expand-compatible` allows an exact
`PGRST202` naming this zero-argument RPC to yield
`purchase_principal_signout_rotation_health_availability: not_deployed` and a
null payload. This rotation-only flag is independent from the already-deployed
principal aggregate, which has no compatibility mode and always remains
required. Malformed shape, authorization, transport, and every unrelated catalog
failure remain fatal. A sole `completed/skipped` deploy job is conclusive
nondeployment regardless of why it was skipped: the resolver ignores that green
run and continues to older workflow history. A missing or duplicate deploy job,
an incomplete job, or any other conclusion remains fail-closed. API or
Git-history ambiguity fails the workflow, and the deadline selects `required`
without retained Actions evidence.

## Explore emoji reactions (2026-09-18)

`set-explore-post-reaction` accepts `post_id`, `emoji`, and boolean `selected`;
`set-explore-comment-reaction` accepts `comment_id`, `emoji`, and `selected`.
Both return `success`, `target_id`, and `reaction` containing `emoji`, `count`,
`viewer_has_reacted`, and catalog `order`. Setting the same state twice is
idempotent. The authenticated viewer is derived server-side; hidden, moderated,
blocked, or unavailable targets are denied. Mutations serialize on the post.
Each request sets one emoji independently. A viewer may select multiple distinct
emojis on the same target; selecting or removing one does not replace the
others.

Post ❤️ maps to the existing like and additionally returns `like_count` and
`viewer_has_liked`. Other emoji do not affect the Liked feed or trending score.
The legacy comment-toggle route remains available through the same guarded
transactional boundary, but is not retry-idempotent and should not be used by
new clients.

`get-explore-reactions` accepts `target_kind` (`post` or `comment`),
`target_id`, and optional `after_order` (default -1). It returns up to 32
catalog-ordered `reactions` plus nullable `reactions_next_cursor`. Native
post/detail and comment catalog endpoints include 12 initial groups and the same
continuation cursor, using a batch enrichment RPC without changing existing SQL
projection signatures. Map markers stay lightweight; an interactive preview
hydrates through the single-post endpoint. Clients merge pages by canonical
emoji identity.

The pinned Unicode 17.0 catalog and CLDR 48 English search annotations are
reviewed source data under `resources/emoji`. Run
`python3 scripts/generate-explore-emoji-catalog.py` to update both bundled
copies; `--check` verifies them. Qualification aliases normalize to their fully
qualified form; skin tones, flags, and joined sequences retain separate
identities. Arbitrary text, multiple emoji, bare modifiers, and oversized inputs
are denied. Existing recognized comment aliases are coalesced per viewer when
read and removed together. Historical noncatalog TEXT values remain stored, but
are not rendered as selectable Unicode reactions; this migration does not delete
them.

Notification list/count/mark-read requests and push registration accept optional
boolean `supports_post_reactions`, default false. Capable clients receive the
new `post_reaction` type, aggregated per post/emoji and routed to post detail.
Legacy clients neither list/count nor mark those rows read. Both legacy and
capable list/count/mark-read RPCs are service-only; callers use the
authenticated Edge endpoints. Pushes require both Explore opt-in and capability
registration; badges are calculated for that device's capability. Self-reactions
and removals are silent. Blocked and shadowbanned actors are excluded from
current counts and display names.

### Reaction request and response details

All three reaction routes use the existing authenticated JSON POST boundary and
its small request-body limit. IDs must be UUIDs. Setters require a boolean
`selected` (including false), and an exact supported emoji string. Edge
validation accepts at most 128 UTF-16 code units, normalizes NFC, then looks up
a recognized catalog alias; it does not accept surrounding text or multiple
emoji. The SQL boundary also caps emoji input at 256 UTF-8 bytes and revalidates
the catalog. Missing/invalid fields return 400; unavailable/unauthorized
reaction targets return 403, with authentication handled by the shared Edge
boundary.

| Route                          | Request                                                                  | Response                                                                                           |
| ------------------------------ | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `set-explore-post-reaction`    | `post_id`, `emoji`, `selected`                                           | `success`, `target_id`, `reaction`; post ❤️ additionally includes `like_count`, `viewer_has_liked` |
| `set-explore-comment-reaction` | `comment_id`, `emoji`, `selected`                                        | `success`, `target_id`, `reaction`                                                                 |
| `get-explore-reactions`        | `target_kind` (`post` or `comment`), `target_id`, optional `after_order` | `reactions`, `reactions_next_cursor`                                                               |

A reaction group is `{emoji, count, viewer_has_reacted, order}`. Counts are
nonnegative; a setter can return zero after removal, at which point the client
removes the chip. Order is the canonical catalog ordinal, not a popularity rank.
The continuation request accepts an integer `after_order` from -1 through 10000,
defaulting to -1; null also uses that default. Pass the returned non-null cursor
unchanged. `reactions_next_cursor: null` ends pagination. Preview enrichment
accepts at most 100 targets per call and returns 12 groups per target;
continuation responses contain up to 32 groups. Pages are merged by canonical
emoji identity, including locally revealed out-of-page selections.

Post setters return absolute desired state and serialize under the post-row
lock, including notification recomputation. Current native post ❤️ selections
reuse the existing set-like client path; the reaction endpoint also supports
atomic ❤️ mapping for compatible callers. Other heart emoji remain distinct.
Comments, including replies, treat ❤️ as a normal emoji reaction. New native
setters do not automatically replay ambiguous transport failures; that is a
conservative client retry policy, not a server toggle semantic.

### Reaction rollout order

1. Prepare/apply `20260918142009_add_explore_post_reaction_type.sql` before
   `20260918142010_add_explore_emoji_reactions.sql`. The separate enum migration
   ensures the value is committed before dependent schema/functions use it.
2. Release the three new reaction routes plus updated post/comment projection,
   legacy-toggle, notification list/count/read, push-registration, and
   push-worker bundles against that schema. Shared-helper dependency discovery
   determines all affected bundles; do not hand-maintain a smaller deployment
   list.
3. Verify both capability paths before distributing the native app. Older apps
   continue using legacy notification types and comment toggles. Current native
   callers declare support explicitly, including on device registration.

Existing likes, legacy comment values, and old notification signatures remain
compatible. Do not remove the additive enum/table/capability when reverting an
app update; backend changes require the normal reviewed forward-repair/rollback
procedure. Generation updates only the iOS and Edge catalog files; a future
Unicode upgrade also requires a new forward database-catalog migration and the
database parity test. See the
[catalog maintenance guide](../../resources/emoji/README.md),
[deployment runbook](./06-supabase-deployment-runbook.md), and
[reaction verification matrix](../development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).
These are release prerequisites, not deployment authorization or evidence of a
hosted rollout.

If a native reaction appears briefly and then disappears, inspect the mutation
result before changing selection limits. A gateway `404 NOT_FOUND` classified as
an unavailable Function route means the reaction handler was not reached. The
client retries with its bounded route-recovery policy, then rolls back the
optimistic selection and displays an error. The existing ❤️ path can still
succeed through `set-explore-post-like`, making the mismatch look like a
one-reaction limit. Confirm the app's configured backend target and the deployed
reaction routes, then verify migration and projection readiness through the
authorized release workflow. Local source or passing tests do not establish
hosted availability; retaining failed optimistic chips would misrepresent saved
state.

### Reaction Realtime compatibility

Capability filtering applies to notification list/count/read RPCs and push
fanout. The existing authenticated Realtime subscription still observes own-row
changes in `explore_post_notifications`; it is not capability-filtered. Native
clients consume these as opaque `AnyAction` refresh signals and obtain display
rows/counts through the filtered endpoints. Do not treat a raw Realtime change
as a notification DTO or display it directly.

### Post reaction people

`POST /get-explore-post-reactors` accepts authenticated JSON
`{"post_id":"uuid","after_user_id":"uuid"}`. The cursor is optional/null for the
first page. Both non-null fields must be UUIDs; the shared small-body limit
applies. The server derives the viewer from authentication, never from JSON.

```json
{
  "total_count": 6,
  "preview_names": ["Observer A", "Observer B"],
  "reactors": [
    {
      "user_id": "00000000-0000-4000-8000-000000000001",
      "display_name": "Observer A",
      "username": "observer_a",
      "avatar_url": null,
      "emojis": ["😂", "❤️"]
    }
  ],
  "next_cursor": null
}
```

The example abbreviates the reactor array. Real pages contain up to 32 unique
people in UUID ascending order; `next_cursor` is the final returned UUID only
when more people exist. Pass it as `after_user_id`; null ends pagination. A
person's added emoji never changes their sort position. Membership can change
between requests: merge by `user_id` and refresh for newly inserted earlier
actors or removed people. This is not snapshot pagination.

`total_count` and up to two `preview_names` describe the whole visible set,
independent of cursor. A person contributes once across likes (mapped to ❤️) and
ordinary post reactions. Rows include the viewer and post owner; reaction
notification self-suppression is unchanged. Each row carries all its canonical
emoji in catalog order, bounded by the catalog. Public names/avatars come only
from `users.public_author_name` and `public_avatar_url`; blank names fall back
to “Nature lover.” No private Auth metadata is returned.

Each reactor also carries `username`, the bare public handle from
`users.public_username`. The native Reactions sheet and detail aggregate render
it as `@username`. The aggregate takes usernames from the first two loaded
reactors, retains those actors across pagination, and uses count-only copy when
an expected username is absent; it does not render `preview_names`. Display
names and preview names remain unchanged on the wire. The additive field
requires `20260919203823_add_explore_post_reactor_usernames.sql`; the existing
Edge route passes it through without a handler change. Native clients decode it
optionally for older-server compatibility. Until that migration is applied,
sheet rows show "Username unavailable" and the aggregate shows only the count;
neither renders a first/last-name fallback.

The service-only RPC applies the existing post visibility guard, then filters
both directions of viewer/actor blocks and shadowbanned actors before totals,
previews, and pages. Invalid input returns 400; unavailable/unauthorized targets
return 403. Current native use is the detail-only summary and Reactions sheet,
through injected dependencies and a refresh/account-fenced state owner. Apply
`20260918163435_add_explore_post_reactors.sql` and deploy the new route before
that app update. Existing post/comment DTOs and reaction endpoints are
unchanged.

## Species discovery search

`POST /species-discovery-search` is an authenticated, no-store, version-1 search
operation. `request_id` and `result_kind` are echoed and strictly validated by
iOS. A question plus prior structured context performs refinement; context-only
requests paginate or switch tabs without invoking AI. Results contain real
catalog items with source excerpts, or viewer-filtered public Explore cards with
no map coordinates. `results`, `clarification`, and `unsupported` have distinct
response semantics. Questions never become retained Field Chat messages.

The
[owning executable contract and limits](../../services/supabase/functions/species-discovery-search/README.md)
cover request/context/cursor shapes, result bounds, consent, quota, retry, and
privacy. iOS hand-written DTOs live in `SpeciesDiscoverySearchAPIModels.swift`;
`SpeciesSearchResponseValidator` validates the version, request identity, result
type, context, record identities, and cursor before publishing a page. Existing
Identify generated DTOs and web/admin consumers are unaffected.

## Authenticated Naturebook dictionary projection

`POST /functions/v1/species-dictionary-for-viewer` accepts the same detail,
catalog and overview requests as `/species-dictionary` and returns the same
schema-version-1 envelopes. Authentication is required (`401` without it); the
trusted handler identity selects the viewer, never a request body field.
Responses use `Cache-Control: private, no-store` and `Vary: Authorization`.
Reference images exclude media belonging to that viewer's reported posts;
missing eligible media produces the existing empty/null image representation
without dropping the species. Native callers use this route. The anonymous
endpoint and its public contract are preserved.

## Explicit identity in shared consumers

The dormant explicit-primary contract is evaluated from the authorized saved
row, never from client-supplied recovery fields. The full primary/provenance and
revisioned species review must validate. Pending typed review or a bare
confirmed ID cannot confer species authority. Valid genus, family and unresolved
biological observations remain shareable and eligible for biological Field Chat.
Legacy reads retain their prior behavior.

Explore card RPCs add nullable `identification` with exactly `version: 1`,
`rank`, `label_source`, `original_rank`, `original_scientific_name` and
`original_common_name`. Rank is species, genus, family or unresolved_biological;
source is ai_primary, verified_selection or community. Original fields are
required nullable values. Legacy cards omit/null this object unless a community
label applies. A present malformed object fails decoding. No confidence,
provider settings or review envelope is public. Cards/detail/map/web keep
existing privacy predicates and original `ai_reasoning`; presentation names its
original rank separately when a selection or community label is displayed.
Broader or community display alone supplies no verified species reference or
preferred species-name substitution.

Insight Field Chat separates original AI evidence, verified taxonomy selection
and pending review; it never transfers original confidence to a replacement.
Field Trip receipts track the primary/review revisions and recompute or withdraw
regular/Event credit, including completed trips, when the selected species
changes. Reference promotion requires the original species association and
qualified original metrics for explicit results.

New DwC-A source snapshots add nullable `identification` containing `rank`,
`scientific_name` and `verified_selection`. Invalid authority gives no effective
species and a null identification projection. Existing immutable snapshot rows
and resumable archive format stay unchanged. The 20-column CSV uses the existing
scientificName, genus/family and identificationVerificationStatus fields to
preserve the explicit interpretation; a new taxonRank column requires a future
versioned archive format. No producer, export gate or client protocol changes.

## Owner rejection of an identification

`POST /review-scan-identification` is the owner-authenticated, revisioned
boundary for **Mark as incorrect**, Undo, verified acceptance, and replacement
handoff. Its executable request/receipt contract and error behavior are
documented in
[the owning route](../../services/supabase/functions/review-scan-identification/README.md).
It applies to legacy and explicit-primary observations. Rejecting an AI answer
requires no alternative name or external taxonomy lookup. The scan remains saved
and unresolved, with no effective species or species-level Field Trip credit.
Undo restores the AI suggestion as unreviewed; reanalysis proposals need
explicit acceptance or authoritative community resolution. A non-biological
reanalysis result is saved separately and does not retire the rejected original.

Review authority is separate from original AI evidence and verified owner
selection. Community authority comes from the consensus transaction, carries its
request lineage, and is revoked when that consensus is withdrawn or reversed.
Genus-level community resolutions remain free of species credit. Neither
rejection nor consensus changes model confidence or rewrites AI prose.

The raw `ai_identification_review` envelope is owner-private. Public scan column
grants exclude it; owner history uses `get_owned_scan_ai_reviews(p_scan_ids)`
with a maximum of 100 IDs and current review fields in the same snapshot.
Protocol 6 readers understand rejected, proposed, and community-resolved
identifications. Older readers receive `client_update_required` for affected
rows. Admission recognizes 4, 5, and 6 without raising provider binding minima.
Ship this backend contract before the corresponding native reader. No release or
deployment is implied by repository implementation.

## Prepared protected evidence lifecycle

Upload and erasure remain internal preparation. The protocol-8 photo read
adapter below now has a narrow service-only wrapper and authenticated Edge
source; there is still no scheduled erasure worker or deployed photo route.
Existing V1 history snapshots remain unchanged, and
`append_observation_analysis` continues accepting descriptions only. Enrollment,
append, media issuance and media reads remain closed.

`internal.reserve_observation_evidence(owner,observation,analysis,media,type,bytes,sha256)`
returns an immutable database-generated object identity and five-minute
deadline. The future caller must derive owner from a verified session and
validate an admitted child-analysis intent; possession of these internal
arguments is not authorization. Identical reservation replay preserves its
key/deadline; changed payload conflicts. Current description-only result
insertion and reservation share an analysis lock, so both cannot claim the same
analysis identity.

The shared storage owner owns a buffered copy, hashes it, performs a conditional
PUT with `If-None-Match: *`, and HEAD-verifies exact length, content type and
trusted writer hash metadata. Only afterward may
`internal.complete_observation_evidence(owner,observation,analysis,media,object)`
mark readiness, with the same current-owner and deletion fence as reserve. Lost
PUT responses can recover through a matching existing object; a deletion marker
never verifies as evidence. This is not provider completion, quota settlement,
media moderation or client-declared upload proof.

`internal.read_owned_observation_evidence` requires matching current owner,
observation, analysis and media IDs and a ready receipt. The protocol-8 Edge
adapter additionally requires a completed V2 reference and uses that receipt to
sign a GET with a separate read credential and fixed 30-second lifetime. The URL
is a bearer capability, is not persisted, and carries no-store cache controls. A
previously issued capability remains usable until expiry or marker replacement;
the database cannot revoke a signature already issued. All new reads fail after
the deletion fence.

Erasure is asynchronous and durable. Receipt removal—including scan tombstone,
parent cascade and account detachment—queues an opaque object UUID independently
of the parent. `claim_observation_evidence_erasure` leases one obligation for
one minute; `finish_observation_evidence_erasure` rejects stale/expired tokens.
The bounded worker seam overwrites the exact key with a zero-byte marker,
HEAD-verifies it, and only then acknowledges success. Failure remains retryable.
No DELETE is issued, because deleting the marker would allow delayed writes to
restore content. The
[storage owner README](../../services/supabase/functions/_shared/analysisHistory/README.md#prepared-protected-evidence-storage)
details the boundaries and tests.

The V2 photo contract below now prepares receipt binding, admitted intents and
cancellation/expiry cleanup. Activation still requires normal native
presentation, authenticated inference orchestration, explicit history deletion
delivery, worker routing/scheduling, audio/video evidence contracts, account
scientific allowlisting, and a private-bucket/credential audit with real R2 race
evidence. No public-CDN URL, staging URL, signed URL or caller-nominated key can
stand in for a durable protected-media receipt.

## Prepared protected photo analyses

`20261003063309_bind_protected_analysis_evidence.sql` connects private ready
photo receipts to funded analysis completion behind a new default-false
`protected_analysis_enabled` gate. `admit_protected_observation_analysis` and
`append_protected_observation_analysis` have no API execution grants. V1
admission/append remain description-only. All earlier gates stay closed. The
protocol-8 reader and private-photo read endpoint are now prepared below. No
provider materializer or recovery schedule is introduced.

`protectedManifest.ts` owns the strict V2 contract. Input and draft identities
use `schema_version: 2`; evidence is `{schema_version: 2, items: [...]}`.
Ordered items are either `{kind: "description", text}` or
`{kind: "image", media_id, content_type, byte_count, sha256}`. There must be at
least one image, no repeated media UUID, at most 64 total items, descriptions of
1–8,192 Unicode characters, and at most 32 MiB of referenced image bytes in
aggregate. JPEG, PNG and HEIC are accepted; audio/video and all unknown fields
reject. Object UUIDs/keys, staging references, public URLs and signed URLs never
enter the manifest. A content reference is not proof of upload: the SQL owner
joins it to the exact current owner/observation/analysis receipt and verifies
readiness and every content field under locks.

The future orchestrator first reserves and verifies private uploads, then admits
all ready receipts atomically. Initial admission requires each receipt's
five-minute deadline still to be live; it rejects extra unreferenced receipts
for that analysis. Admission freezes the entire ordered manifest and actual
client claims: entitlement 3, identification 6, history 8 and expected
processor. The existing `multimodal_photo_v1` binding determines provider/model
and consent; no provider policy, credit rule or inference fallback changes. The
new source must use canonical Identify/taxonomy validation shared with V1.

An admitted intent pins its ready evidence beyond the upload deadline, including
ambiguous provider work and saved drafts. New receipts cannot be added after
admission. Independent receipt deletion/expiry cannot remove evidence needed by
an intent or retained result. Completion rechecks the same receipt set, appends
through the funded draft fence, and settles the existing complimentary ledger in
the same transaction. Exact completion retries return the same saved receipt.
Existing selection and review authority remain unchanged.

Terminal failure/cancellation queues unused photo erasure before its transaction
returns. Deleting an intent also retires its unused receipts; parent deletion
and account detachment supersede every pin and queue retained photos for
erasure. `expire_unbound_observation_evidence` can retire ready or unready
uploads after their deadline only when no intent or result owns them. It
rechecks the exact object generation under owner/observation/analysis locks. No
cleanup scheduler is activated. Failed cleanup remains in the existing durable
opaque-key outbox.

The snapshot serializer emits version 2 only for V2 evidence, preserving all V1
serialization bytes. The protocol-7 page RPC rejects an entire history
containing V2 with `analysis_history_reader_upgrade_required`, even when a
cursor would skip those rows, and only after owner/deletion checks. No partial
mixed page is returned. The Deno default parser remains strict V1; explicit
reader 8 and the native decoder accept both versions with exact version-matched
manifests. `LocalAnalysisRecord` admits version values 1 and 2 without changing
its V55 stored shape. The coordinated protocol-8 implementation below must be
validated before any V2 enrollment or production use. Public
Identify/captured-media DTOs, Explore and Field Chat remain unchanged.

This slice proves database binding and cleanup transactions with synthetic
receipts; it does not prove live R2 policy, photo moderation, media budgets for
a provider request, image decoding or end-to-end reanalysis. Those remain
orchestration/activation requirements.

## Prepared protocol-8 reads and private photo resolution

`20261003070545_prepare_protocol8_history_reads.sql` extends the existing owner
page RPC without changing request/page schema 1, limits, ordinal cursors or V1
snapshot bytes. Protocol 8 admits mixed V1/V2 results; protocol 7 still refuses
whole V2 histories after ownership/deletion checks. Unknown readers fail closed.
Native admission stores the decoded snapshot version and compares it alongside
all immutable bytes on replay. It leaves selection and review authority alone.

`POST resolve-history-photo` authenticates through `withEdgeHandler`. Its exact
body is `{observation_id, analysis_id, media_id, reader_protocol: 8}` with
lowercase UUIDs and no supplied owner. `db.ts` calls the service-only
`resolve_owned_observation_photo` RPC with the verified owner. The routine
checks service authorization, current owner and deletion fencing, both
`reader_enabled` and `media_reader_enabled`, completed V2 result membership,
readiness and the exact MIME/byte-count/SHA-256 tuple. A ready but uncommitted
upload is insufficient. Anonymous/authenticated roles cannot call this routine
or read internal receipts directly.

Success has exactly `schema_version: 1`, `owner_id`, `observation_id`,
`analysis_id`, `media_id`, `content_type`, `byte_count`, `sha256`, `url` and
integer `expires_at_ms`. The URL is a temporary 30-second signed GET. No
separate receipt object UUID field, upload deadline or storage configuration is
returned. The signed URL necessarily contains its opaque storage path and must
remain transient. The adapter rechecks the database fence after signing and
returns `Cache-Control: private, no-store`. Fixed safe errors are 400
`invalid_analysis_history`, 404 `analysis_history_not_found`, or 503
`analysis_history_unavailable`; raw database and storage diagnostics are never
returned or logged. A deletion after the final check can still leave an issued
capability usable until expiry or erasure-marker replacement; no new capability
is authorized after the fence.

Native `ObservationHistoryPhotoLoader` reopens the saved child under its
enrolled owner, uses an account work lease, validates ticket
identity/content/expiry and the HTTPS R2 account host, and fetches through an
isolated ephemeral URLSession. It rejects redirects, cookies, disk caching,
unexpected MIME/length and excess stream bytes, then verifies SHA-256 away from
MainActor. Account, child and pending-deletion checks surround suspensions. Only
transient verified `Data` is returned; neither URLs nor photo bytes enter
SwiftData or public-media caches. Failures require a fresh caller invocation and
a newly authorized ticket; there is no automatic stale-URL retry.
Rendering/image decompression and visible-view invalidation remain the future
presentation owner's responsibility.

All read/enrollment/write gates remain false. This source is not deployed and
has no normal UI/sync caller. Bucket provisioning, real R2 policy/expiry
evidence, provider orchestration, explicit deletion/erasure delivery and the
other activation requirements remain open. Public Identify/captured-media DTOs,
Explore and Field Chat are unchanged.

## Prepared child-analysis orchestration and recovery

The prepared authenticated RPC `get_owned_observation_reanalysis_preflight`
accepts one exact `p_request` object: `schema_version:1`, distinct canonical
`observation_id`, `analysis_id`, `source_analysis_id`, and independent protocols
`entitlement_protocol:3`, `identification_protocol:6`, `history_protocol:8`. It
targets photo reanalysis only, without content, caller-supplied owner, provider
choice or fallback permission. Owner/history/deletion and source membership are
checked under the same owner-first locks as admission. A historical source need
not be selected or confirmed. Existing orchestration, admission and protected
analysis gates must be open; this migration changes none of them.

The response is exactly
`{schema_version:1, observation_id, analysis_id,
source_analysis_id, decision, processor_permission,
minimum_entitlement_protocol, minimum_identification_protocol}`.
Fresh children reuse the current read-only recipient policy with fixed photo
shape and no free fallback. Decisions are `ready`, `permission_required`,
`client_update_required` or `recovery_only`. An existing intent with the same
owner, observation and source returns only `recovery_only`, with null recipient
and minima, for every lifecycle state. Legacy or unrelated identity collisions
fail before recipient resolution; they cannot become new analyses. Owned
pre-admission private evidence is permitted but this read does not certify its
readiness or extend its expiry.

Preflight does not reserve quota, claim complimentary funding, admit an intent,
select a result or authorize dispatch. In particular, native callers must not
preclaim a legacy complimentary hold for the child: protected admission rejects
existing unrelated funding identities and owns its own atomic hold. Persist the
qualified child and exact request locally, then let `analyze-observation` admit
or recover that same operation. Admission and dispatch still recheck current
consent and recipient expectations. Native decoding has a separate bounded
4-KiB, exact-key/identity contract and supports capability 6; it does not pass
this request through the legacy native preflight format. The same account lease,
consent and queue-currentness checks apply before the read and after suspension;
there is no hidden transport retry or 401-refresh recursion.

Migration `20261003074429_prepare_observation_analysis_recovery.sql` adds the
false-by-default `orchestration_enabled` gate. `analyze-observation` validates
the existing strict V1/V2 admission contract, derives owner from verified auth
and IP HMAC from the trusted request boundary, and returns only
`{schema_version:1, observation_id, analysis_id, state}`. Terminal states
`complete`/`failed_terminal` return 200; admitted/dispatched/draft return 202.
All responses are private/no-store. Transport failure requires the same analysis
ID/input on retry. An immutable identity conflict from admission returns HTTP
409 with `analysis_history_operation_conflict`; it does not invite endless retry
of the conflicting input. Later worker-claim conflicts remain sanitized 503
failures so retry can recover saved work. New analyses use fresh IDs. Completion
never changes selection. V2 input is additionally limited to five photos and 5
MiB combined before quota; storage's 32 MiB receipt allowance does not expand
provider admission.

The prepared native `analyzeObservation` transport preserves the complete saved
request bytes, initiating account and 130-second timeout. It disables automatic
transport retries and 401 session refresh so the durable owner controls
ambiguous recovery. Dispatch authorization must match the saved processor and
still pass current local consent checks. In particular, `recovery_only`
preflight means an intent exists, not that it has dispatched: an admitted replay
can still invoke the provider. That authorization cannot be used to submit this
endpoint. Exact result reads remain separate, and execution receipts never carry
selection or result authority. This transport alone does not connect ordinary UI
or queue execution, reserve native funding or open any activation gate.

The service-only `begin_owned_observation_analysis`,
`advance_owned_observation_analysis`, `claim_observation_analysis_recovery`, and
`list_observation_analysis_recovery` RPCs are inaccessible to
anon/authenticated. They do not grant API access to internal tables/routines.
New admission/dispatch requires the applicable admission, dispatch, append and
protected-media gates. A 120-second work token fences materialization, taxonomy,
draft, completion and release; it is independent of quota and invocation
identities. An existing active claim returns only busy state to the
orchestrator.

The foreground worker prepares the qualified provider adapter and result policy
before committing dispatch. Private photo GETs verify exact receipt bytes,
content type, hash and absence of erasure markers, without public promotion or
provider-visible URLs. Dispatch rechecks parent ownership/deletion, consent and
ready evidence. SQL dispatch is the external-processing authorization point; its
provider call follows immediately. A later deletion may not retract
already-authorized external processing, but it prevents outcome persistence,
completion, replay and delivery. No lock spans the provider network call.

Received output is normalized and saved as a bounded immutable canonical
checkpoint before taxonomy I/O. The checkpoint binds invocation provenance and
allowlisted provider usage. Its exact retry is idempotent, including a late
response after work-lease expiry when the original dispatch quota token still
matches. The final draft's result must equal that checkpoint except for its
verified dictionary `species_id`. Taxonomy creates only a missing
scientific-name identity under the deletion fence; it does not overwrite curated
facts, publish private result prose, or confer identification authority.

A proven refusal/invalid result releases the complimentary hold under the shared
terminal settlement rules. A still-live worker may cancel with its original
claim after a dispatch-RPC failure only before entering provider `invoke()`.
Quota accounting already committed at SQL dispatch remains committed. Expired
claims, crashes, unknown executions and timeouts provide no terminal proof and
retain their holds. There is no qualified provider retrieval/idempotency
contract for these ambiguous outcomes; no automatic redispatch or age-based
refund is allowed. This remains an explicit activation limitation.

The service-authenticated `recover-observation-analyses` source discovers at
most ten due saved outcomes/drafts, stops starting work after 40 seconds, and
retries failed completion after 60 seconds. RPCs have bounded deadlines; a
started item can finish after the admission deadline. Recovery never admits or
invokes AI. It reads immutable saved context only. The default-off gate, absence
of a cron schedule, and remaining enrollment/native/public/chat/erasure
prerequisites mean this prepared source is not a production-enabled feature.

## Private library detail RPCs

[Guest library transitions](./21-guest-library-transitions.md#private-detail-api)
defines `set_owned_scan_library_details` and `get_owned_scan_library_details`,
including explicit nullable notes, owner verification, 100-ID read pages, stable
operation receipts and tombstone refusal. Replay of an accepted operation UUID
is a no-op, including after a newer operation; reusing that UUID with a
different payload conflicts. Distinct operations follow server arrival order,
not a cross-device revision or client-time last-edit-wins protocol.
Notes/Favorites stay private in scan-linked internal tables; tags keep their
existing public projection. Merge can return `pending_library_work` or
`library_transfer_needs_attention` (409) without retiring the source identity.
These additive RPCs must precede a client that requires their restoration
response.

### Prepared saved-identification enrollment and protocol 9

Migration `20261003152940_prepare_saved_identification_enrollment.sql` adds
`enroll_owned_observation_history(p_observation uuid, p_reader integer)`. Only
`authenticated` can execute it; `auth.uid()` supplies ownership and `p_reader`
must be 9. There is no client-supplied result, review, owner, import timestamp
or analysis identity. Under owner → observation generation → owned live scan →
history locks, new enrollment requires `reader_enabled`, `enrollment_enabled`
and the new `saved_import_enabled`, all still false in source defaults.

The server copies the surviving identification into one immutable child, copies
all seven current review fields exactly into its separate authority, and selects
that baseline at observation revision 1. `review_revision = 0` is the new
history counter; copied confirmed-species and AI-review revisions retain their
own values. `initial_selection_permitted` stays false. Enrollment changes no
public scan fields, existing eligibility, funding or reconciliation credits.
Existing primary/provenance semantics must pass the current projection policy;
enrollment never invents missing provenance to make a primary answer valid.

The acknowledgement has exactly `schema_version: 1`, `owner_id`,
`observation_id`, and `baseline_analysis_id`. An exact retry returns the
original baseline UUID after ownership/deletion checks, even when new import
admission is closed. It does not restore a later-changed selection, revision or
review. The reader gate remains required. This acknowledgement is not an
authority snapshot; native enrollment must await separately acknowledged current
selection/review state, with its account and deletion fences.

Snapshot V3 uses the existing nine outer keys but has `schema_version: 3`,
`ordinal: 1`, and explicit null `source_analysis_id`, `request_digest` and
`completed_at_ms`. Its evidence manifest is exactly:

```json
{
  "schema_version": 3,
  "origin": "saved_identification",
  "imported_at_ms": 1750000000000,
  "availability": "unavailable"
}
```

The timestamp records import, never original inference completion. The result
has exactly `scan_id`, `primary_identification`, `identification_provenance`,
`species_id`, `is_biological_subject`, `candidates`, `pet_identification`,
`ai_confidence_score`, `ai_reasoning`, and `inference_tier`, copied from the
locked row. Older candidate/pet JSON is retained as opaque bounded saved data;
it must not be decoded or dispatched as a current Identify provider response.
Review, private notes, location, account fields and public media URLs are not
merged into this immutable identification. In particular, legacy public images
are not converted into private evidence receipts. “Saved identification” is the
appropriate presentation label; this import does not establish “Original.”

V1/V2 retain their non-null execution metadata and exact serializer bytes. V3
alone permits missing execution metadata; its exact manifest, ordinal and
nullability are enforced together. Unknown versions fail closed. The aggregate
one-MiB snapshot and four-MiB page caps still apply. Readers 7/8 refuse the
entire history containing an import, including requests whose cursor would skip
it. Protocol 9 is explicit to this owner history read; it does not alter
Identify, funded-input or photo-resolution protocols. Imported IDs cannot enter
legacy scan ingestion, quota or settlement; deletion retains an ownerless
child-ID fence without retaining the private snapshot.

`savedIdentification.ts` owns the executable imported-result and enrollment
acknowledgement validation; `result.ts`/`page.ts` own version negotiation and
byte-preserving delivery. Native V56 advertises reader 9 and validates/stores V3
with nil completion; import time stays separate and private photo resolution
remains V2-only. State hydration, owner and community review synchronization,
public/chat projections, explicit deletion, and the other RFC activation gates
remain required. No enrollment backfill or live app call site is enabled by this
slice.

### Prepared owner observation state read

`20261003162801_prepare_owner_observation_state_read.sql` adds
authenticated-only
`get_owned_observation_analysis_state(p_request jsonb, p_reader integer)`. Both
`reader_enabled` and the new `state_reader_enabled` must be true; all source
rollout defaults remain false. Reader 9 is required. The exact request is
`{schema_version:1, observation_id:<lowercase UUID>, analysis_id:null|<lowercase UUID>}`.
An analysis cannot equal its observation. The owner is always derived from auth.

A null target resolves the selected result under owner → observation advisory →
owned live scan → history locks. An explicit target previews that child without
selecting it. The response contains exactly `schema_version`, `owner_id`,
`observation_id`, `state_revision`, `selection_initialized:true`,
`selected_analysis_id`, and `analysis`. The latter contains exactly `snapshot`,
`review_revision`, and `review_snapshot`. Snapshot is the same immutable
V1/V2/V3 text as the result-page reader, bounded to one MiB; the entire response
is bounded to four MiB. Review is the separate seven-field saved authority,
bounded to 32 KiB. Neither active projection nor arbitrary scan columns are
returned.

The prepared native reanalysis recovery endpoint uses this same fixed RPC for an
explicit saved child. It requires the expected owner and current durable claim,
disables automatic transport and response-driven 401 recovery, and validates the
complete state envelope plus exact saved request provenance. It returns only
immutable snapshot bytes for later atomic completion; it does not apply
selected-state or preview projections. This read precedes current inference
consent and file/upload access, permitting recovery after consent withdrawal or
temporary evidence expiry. Only the bounded PostgREST `P0002` /
`analysis_history_not_found` pair means target absence. Other errors or HTTP
status alone cannot authorize execution; local and server deletion fences remain
required after absence. No wire shape, rollout gate or provider authority
changes.

`analysisHistory/state.ts` validates this contract, retaining legacy review
fields without manufacturing a verified identity. Explicit identity and AI
review envelopes use their existing validators; nested AI review is capped at
eight KiB and its label limits use UTF-16 units on both clients. Native
`ObservationHistoryState` and `ObservationHistoryAuthority` share
`state-v1.json`, preserve result bytes, and keep mutable review separate. The
cloud adapter and `ObservationHistoryStateSyncService` are prepared. Native
admission can atomically cache the exact result, refresh review and advance the
observation revision. A changed server-selected ID requires a strictly newer
revision, retained prior evidence/display and matching acknowledged authority, a
complete target display, and representable target review. Nested review
revisions are compared within each analysis, never across selections. It
rechecks account/deletion and pending review, rejects stale/equal-conflicting
state, and applies display, own authority, selection and revision atomically.
Missing V3 display and ambiguous legacy intent still defer. Normal sync and
enrollment remain disconnected. Selection transport and a separately injected
history sheet are prepared behind closed gates; normal UI access is nil. The
listing consumer retains the existing page revision and ordered analysis IDs
without changing protocol 9 or its wire shape. V57 additionally caches exact
per-analysis authority and review/observation revisions, separately from
immutable result bytes, in the same transaction. Complete V1/V2 results produce
immutable allowlisted display bytes. An eligible already-selected V3 can capture
a versioned, provenance-labelled device-local display baseline; this does not
change server snapshot bytes or protocol 9. Explicit native preview requires
exactly the acknowledged observation revision and selected ID, never mutates
parent selection/review, and returns display origin separately. A missing V3
baseline remains unavailable on that device. Existing selected-review
representability and pending-intent guards still apply. The
[native boundary](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md)
owns the local admission rules.

Missing/non-owned/deleted observations or children return
`analysis_history_not_found`; closed gates or incomplete internal state return
`analysis_history_unavailable`; malformed requests and unsupported reader values
return `invalid_analysis_history`. Reads create no receipts, credit obligations,
enrollment or selection changes. Review updates serialize against the state
read, and changes on an inactive result still advance the observation revision.
The client must recheck account/deletion, reject stale state and preserve
pending local review intent at eventual admission. A preview response is never
permission to replace selection; restore/Undo must use the explicit revisioned
mutation.

### Prepared native saved-identification enrollment admission

The native `ObservationHistoryEnrollmentService` now implements the two-response
admission contract above without an app caller. Its bounded exact-key
`ObservationHistoryEnrollment` decoder shares `enrollment-v1.json` with Deno.
The authenticated account lease must survive both the enrollment RPC and current
state read. Only a still-selected V3 baseline whose surviving evidence and exact
review match the unchanged local scan can establish local ownership/selection.
The result, authority, saved-local display and enrollment fields commit
together; existing display, review and private details are preserved. Divergence
requires reconciliation, never silent server preference. Lost responses leave no
local acknowledgment and permit idempotent server retry.

Before dispatch, native admission now commits a bounded owner-bound enrollment
intent in the existing job store. Lost responses and failed local admission
retain the same receipt; successful admission removes it atomically. A fresh
transaction fence blocks legacy replacement deletion for either pending or
acknowledged history. Expiry and hydration honor that protection. Explicit user
erasure retains an identity-only terminal local fence, so late history reads
cannot recreate the observation after cloud deletion cleanup. No autonomous
retry or ordinary enrollment caller is connected. The
[native admission boundary](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#prepared-native-enrollment)
owns the exact local eligibility, tombstone and rollback rules. No server
payload, reader protocol or rollout gate changed.

### Prepared native selection requests and Undo receipts

Native `ObservationHistorySelectionRequest` matches the existing six-field
private selection transaction: `schema_version`, `observation_id`,
`analysis_id`, `operation_id`, `expected_observation_revision`,
`expected_review_revision`. Native preparation requires a positive initialized
revision below exhaustion, a distinct target with retained evidence/display, and
current target authority. `ObservationHistorySelectionReceipt` checks the seven
existing fields, including exact operation, observation, previous and selected
IDs, the next observation revision, and the expected target review revision.
`selection-v1.json` is shared by native tests and the Deno transition producer.
The protocol-9 owner RPC below wraps the existing success shape and adds a
separate strict revision-conflict outcome.

The prepared native owner persists the request before dispatch and reuses it
across ambiguous retries. It reads current state after receipt validation, then
commits projection/authority and the completed receipt atomically. A newer state
supersedes an older receipt; replay does not reinstall old selection. Undo is a
new conditional request bound to the latest receipt's still-current revision and
selection. Local selection remains pending until acknowledgment and awards no
credit. The
[native selection boundary](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#prepared-selection-and-undo)
owns persistence, preview freshness, account/deletion checks and rollback.
Protocol-9 mutation transport and definitive-conflict recovery are prepared;
workers and UI remain disconnected and all gates remain closed.

`select_owned_observation_analysis(p_request JSONB, p_reader INTEGER)` accepts
exact reader 9 and the six-key request, bounded to 2,048 database JSON-text
bytes. Only `authenticated` has execute permission. The server derives ownership
from `auth.uid()`; no owner parameter is accepted. The private implementation
remains ungranted to API roles. Outer owner-row, observation advisory and
owned-live-scan locks protect deletion and every outcome. Under those locks an
exact existing outcome replays before any rollout gate; changed input with the
same operation returns `analysis_history_operation_conflict`. Fresh operations
require `selection_api_enabled`, `reader_enabled`, `state_reader_enabled` and
`selection_enabled`, all default false. Closing gates stops new choices while
preserving outcome recovery; state-read gates still apply to the subsequent
native read, so a closed reader keeps the native intent pending.

Only the explicit `analysis_history_revision_conflict` from the private CAS is
converted into a durable rejection. The wrapper's outer locks survive the nested
transaction rollback; insertion into `observation_selection_receipts` commits
before response. The exact seven fields are the original six request fields plus
`outcome: "revision_conflict"`. This is proof that the operation cannot later
apply, not current authority. It changes neither selection nor revision and
emits no reconciliation obligation. Other failures, including infrastructure
serialization failures, missing/foreign/deleted targets and closed gates, remain
errors without a terminal proof. Deletion wins over both insertion and replay.

Native success and rejection decoding reject extra, mismatched or wrongly typed
fields. After either outcome, current selected state must pass the existing
account, deletion, baseline, authority and revision checks. One save commits
state plus either the success receipt or version-2 cancelled rejection intent.
Failed reads/saves leave the original request pending. A rejected operation
cannot enable Undo; a fresh preview is required before a new choice. No
complimentary credit, provider dispatch or public publication is triggered by
this selection boundary.

### Prepared analysis-bound Reject and Undo

Native foreground review admission is prepared behind the disabled UI boundary.
An immutable preview ticket freezes the owner, observation, analysis, selected
child, both revisions and result/authority digests. The synchronous tap creates
one exact operation request; new staging revalidates the complete ticket, idle
selection and settled legacy review in one local transaction. Exact
saved-request replay precedes fresh-action validation. Local status
distinguishes pending, receipt reconciliation, attention and historical
completion without asserting current authority. Undo requires a reconciled
applied same-target Reject receipt and the current ticket's exact rejection
association/review revision. No idle Auth lease, implicit enrollment, optimistic
review or selection change is added.

`public.review_owned_observation_analysis(p_request JSONB, p_reader INTEGER)` is
an authenticated owner RPC with a separate, default-false
`rejection_api_enabled` hold. Reader and state-reader gates must also be open;
`p_reader` must equal 9. It has no ordinary native caller yet. The executable
request and receipt contract lives in
`functions/_shared/analysisHistory/review.ts`; Identify DTO generation, web and
admin payloads are unchanged.

The exact eight-field request contains `schema_version: 1`, `observation_id`,
`analysis_id`, `operation_id`, `expected_observation_revision`,
`expected_review_revision`, `action`, and `undo_operation_id`. IDs are lowercase
UUIDs and revisions are integers from zero through 2,147,483,646. `action` is
`reject` or `undo`; `undo_operation_id` is null for Reject and the acknowledged
rejection operation UUID for Undo. Request bytes are bounded to 2 KiB.
Confirmation, carry, and community actions are deliberately unsupported.

The RPC locks owner, observation generation, owned live scan, history, and
target authority in that order. Ownership and the deletion fence are checked
before replay. The operation UUID is unique within the observation; changing any
intent field on a retry returns `analysis_history_operation_conflict`. Exact
retries return their immutable original outcome even after later changes or gate
closure.

An applied receipt repeats all eight request fields and adds `outcome: applied`,
`observation_revision`, and `review_revision`, each revision exactly one greater
than requested. A stale expectation returns the exact request plus
`outcome: revision_conflict` and is durably recorded without any state change.
Missing/foreign/deleted targets return `analysis_history_not_found`; malformed
requests return `invalid_analysis_history`; closed gates or exhausted revisions
return `analysis_history_unavailable`. Invalid transitions return
`invalid_identification_review`. These errors are not terminal operation
receipts. Receipts are bounded to 4 KiB and never replace a fresh protocol-9
state read.

Reject accepts a biological, unrejected result whose authority is neither a
manual correction nor community-resolved. It clears that result's confirmation
and sets its AI review to rejected. Undo requires both current revisions and the
same result's accepted rejection receipt; it clears rejection to unreviewed and
never reinstates confirmation. It cannot undo an imported rejection without a
bound receipt. Neither action changes selection or immutable evidence. Every
successful review advances the observation revision and enqueues reconciliation;
only a selected result's review changes the active projection. Downstream credit
and publication reconciliation remains held.

Legacy `review-scan-identification` and `confirm-scan-species` target lookups
now call service-only `require_legacy_scan_review` before quota admission or
taxonomy verification. An enrolled observation returns HTTP 409
`analysis_bound_review_required`; direct legacy commit RPCs repeat the check
under the generation locks, including both ends of carry. This closes enrollment
races without copying scan-row authority into a selected child. The community
Edge request also runs this preflight before media restoration, taxonomy
synchronization, or moderation. Legacy community request creation, authority
updates, and both sides of reparenting are also fenced, as are scan-row
authority mutations; analysis-bound community authority and its revocation
behavior remain activation requirements. Privacy/deletion cleanup retains its
existing path.

### Prepared analysis-bound confirmation

`confirm-observation-analysis` prepares authenticated, private confirmation for
protocol-9 history. Its `confirmation_api_enabled` gate defaults false; reader
and state-reader gates must also be enabled. No ordinary native caller or
rollout is enabled. `_shared/analysisHistory/confirmation.ts` owns the strict
request, preparation envelope and terminal receipt parsers. Identify DTOs,
web/admin payloads and native schemas are unchanged.

POST accepts exactly eight fields: `schema_version: 1`, `observation_id`,
`analysis_id`, `operation_id`, `expected_observation_revision`,
`expected_review_revision`, `action`, and `scientific_name`. IDs are lowercase
UUIDs, revisions are integers 0–2,147,483,646, and the stored request is bounded
to 2 KiB. `confirm_primary` requires a null name and derives the verification
query from that child's immutable species-level primary identification.
`confirm_name` requires a trimmed, control-free name of 1–160 characters and
explicitly accepts a verified species, including from a broader primary answer.
The request cannot supply owner identity, species UUID, taxonomy proof or review
authority. Both actions require biological evidence with an explicit stored
primary; imported legacy results without one remain viewable/restorable but
cannot use this confirmation endpoint. Community authority remains held.

The service-only `prepare_observation_analysis_confirmation` RPC acquires owner
→ observation generation → owned live scan → history → target authority locks.
Ownership and deletion are checked before immutable receipt recovery. An
unfinished operation saves its exact request and verification query in
`internal.observation_confirmation_intents` before network execution. The
operation UUID cannot be rebound to another result, action, query or revisions,
including through Reject/Undo. Preparation returns either
`{schema_version:1,status:verify,request,scientific_name}` or
`{schema_version:1,status:complete,receipt}`; these internal envelopes are not
the HTTP response.

Only an unfinished, eligible intent proceeds to the existing dictionary lookup
rate limiter and GBIF verifier. Each attempted lookup is rate-limited; retries
of completed outcomes skip both admission and lookup. Verification uses the
frozen query and accepts the verifier's canonical accepted species, which can
differ from a synonym query. The separate service-only
`complete_observation_analysis_confirmation` RPC requires a prior intent,
rechecks ownership/deletion, gates and both revisions, and binds the verified
query to that intent. No network call runs while database locks are held.
Provider executions and complimentary scan credits are untouched: this is
dictionary verification, not another AI analysis.

HTTP 200 returns the exact eight request fields plus one terminal outcome:

- `applied`, with `observation_revision` and `review_revision`, each exactly one
  greater than requested;
- `revision_conflict`, with no extra state fields, if either expectation became
  stale before admission or completion;
- `not_verified`, with no extra state fields, for a definitive negative lookup.

All three outcomes share the immutable review ledger and replay before rollout
gates, without reapplying state. A negative outcome cannot later become a
confirmation under the same operation UUID. Interrupted/unavailable lookups
leave their intent recoverable and consume no confirmation outcome. A changed
intent returns HTTP 409 `analysis_history_operation_conflict`; malformed input
returns 400 `invalid_analysis_history`; missing/foreign/deleted history returns
404 `analysis_history_not_found`; missing primary returns 409
`species_review_requires_primary`; unsupported authority returns 422
`species_not_verified`; closed holds or persistence unavailability return 503
`analysis_history_unavailable`. Lookup unavailability returns 503
`species_resolution_unavailable`, and dictionary rate refusal returns 429
`rate_limited`. Responses use `Cache-Control: private, no-store`; diagnostics
and stored/private payloads are not exposed.

An applied confirmation updates only the named child's seven-field authority.
Primary confirmation sets `ai_confirmed`; named confirmation sets
`user_overridden`, records the query as the override, and does not mark the AI
answer confirmed. Both store the verified canonical species identity and
explicitly clear that child's AI rejection/awaiting-acceptance state. Selecting
a result alone never clears rejection. Community authority cannot be displaced
through this endpoint. Selection and immutable evidence remain unchanged. The
authority trigger advances the observation revision and adds reconciliation;
only a selected child's confirmation updates the active projection. A receipt is
an operation outcome, not current authority: consumers must reread current state
before display or credit decisions. Native confirmation admission, community
transitions, downstream reconciliation and activation remain separate work.

### Prepared native analysis-bound review wire

Native `ObservationAnalysisReviewRequest` and `ObservationAnalysisReviewReceipt`
mirror the rejection and confirmation contracts without enabling an ordinary
caller. One immutable request retains the caller-supplied observation, analysis,
operation and both expected revisions. Reject/Undo encode exactly
`undo_operation_id`; confirmation encodes exactly `scientific_name`, including
required nulls. Names use the backend's UTF-16 limit and ECMAScript trim set;
canonically equivalent but byte-distinct names remain different operation
intent. Saved requests are bounded to 2 KiB, receipts to 4 KiB. Receipt decoding
binds every field to the original request and admits only outcome-specific keys.

The review overload of `ObservationHistoryMutationTransport` owns only the fixed
owner RPC (reader 9) and confirmation Edge route, selected by the typed
decision. It composes the existing private authenticated dispatcher and disables
transient transport replay and classified-401 recovery. A required
durable-attempt validator runs after Auth preparation and before actual
dispatch. The read-only admission RPC capability and wire payloads are
unchanged. Transport never mints an operation ID, changes selection, projects
review status, or falls back to legacy review. Prepared native persistence now
retains the exact request, local fingerprint and terminal receipt across
restart, with claim/account/deletion fences and a saved applied Reject
association for Undo. Only one unfinished review is admitted per observation,
through projection reconciliation. Storage does not treat receipt acceptance as
current authority. The delivery owner must retain an account lease and reconcile
current protocol-9 state separately. A nonselected target response cannot
advance the parent revision while leaving a stale selected projection. The
prepared native reconciler now reads the exact pair under one account lease and
applies the selected state before the distinct target cache in one locked
transaction with receipt completion. Applied receipts bound only their own
target authority; selected-result review authority remains independent. Failed
validation or save rolls back the entire projection. The prepared one-operation
delivery service retains an account lease, replays the exact saved request
before current-state preflight and acquires a new receipt claim after
acknowledgement. Received receipts only reconcile; they never dispatch again.
Exact permanent errors hold work without inventing receipt outcomes; network
uncertainty and state revision races retain bounded retry. The dedicated native
scheduler now retains a bounded, account-fenced pass over saved work, restores
strict owner-qualified deadlines and awaits task cancellation before Auth drain.
Database uncertainty has a bounded owner/container recovery wake; malformed or
held jobs cannot be automatically reclaimed. Ordinary review UI remains separate
implementation work. See the
[native persistence contract](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#prepared-analysis-bound-review-persistence).
All activation gates remain false.

### Private analysis-bound community authority preparation

The community-authority foundation has **no public RPC, Edge endpoint, native
caller or scheduled worker**. `internal.bind_observation_community_request` and
`internal.reconcile_observation_community_authority` have no API-role execution
grants, including service role. The new `community_authority_enabled` flag
defaults false and controls new bindings. Existing bindings can still reconcile
and revoke authority after this admission hold closes.

The future atomic publisher must supply an explicit owner, observation,
analysis, community request, and expected observation/review revisions.
Registration locks owner → observation generation → live scan → history → named
authority, verifies biological/unreviewed evidence, and requires a fresh
`needs_id` request belonging to that owner/scan/post/taxonomy generation. A
private AFTER INSERT fence proves that the request was inserted in the same
transaction; reopening or updating a committed legacy request cannot manufacture
that proof. Exact binding retries recover without changing authority; changed
identities/revisions conflict. Registration atomically marks the named result as
awaiting acceptance through initial reconciliation. Selection is unchanged.
There is no automatic migration or binding of existing community requests.

Request identity is immutable after binding: request, observation, analysis,
owner, post, taxonomy version and request timestamp cannot be reassigned. Bound
consensus updates bypass the legacy scan-review writer and only increment a
private durable source revision. Status/taxon/withdrawal changes and request
deletion enqueue work in the same transaction as the public request mutation.
Unbound requests keep the existing history fence. Ordinary enrolled request
creation remains blocked; a future publisher must add its approved public
snapshot and atomic admission path before this preparation can be activated.

The private reconciler takes the history lock order and attempts the queue row
with `FOR UPDATE NOWAIT`. A busy consensus transaction yields `pending`; callers
must end the transaction and retry later. This prevents a cycle with consensus
notifications that can wait on the owner while holding request/queue locks. The
worker never locks the request row. Its queue lock serializes the read of
current committed request state: a request mutation cannot commit without
advancing that same queue row. Delayed invocations recompute current state,
never replay an old resolve/withdraw payload.

A species resolution supplies separate community species authority; a genus
resolution remains visible without species credit. Loss, withdrawal or deletion
of the request produces awaiting-acceptance authority with no effective species
or inherited confirmation. Only the bound child's seven-field authority changes;
the existing authority trigger advances parent revision and reconciliation,
updating active projection only when that child is selected. A newer owner
review permanently supersedes the old community binding, so later consensus
cannot undo explicit acceptance. Outcomes are internal `applied`, `current`,
`pending` or `superseded` signals, not public operation receipts or
current-state payloads.

Binding and queue records survive request deletion long enough to revoke its
authority, but cascade with the observation/analysis. Deletion and owner checks
precede reconciliation and binding replay. The future dispatcher must retain and
retry pending work, and public/credit consumers must enforce current source and
authority revisions before counting or displaying verified identity. The
subsequent
[publication preparation](#prepared-analysis-publication-snapshots-and-public-reads)
adds frozen public snapshots, immediate invalidation and otherwise-visible
post/discussion preservation. The subsequent
[private admission transaction](#prepared-atomic-community-request-admission)
adds fresh-request receipts and frozen evidence. Its moderated caller, explicit
shared updates, worker scheduling and native integration remain activation
requirements. The community foundation alone enables none of them.

### Prepared analysis publication snapshots and public reads

`publication_snapshot_enabled` defaults false. Private
`internal.register_observation_publication` has no API-role execution grant,
including service role. It is a preparation for the future moderated atomic
publisher, not a new sharing endpoint. Only a resolved, published request
already explicitly bound to a named result can register. Registration checks
owner/deletion fences, both current revisions and current reconciliation, locks
its request/post/media without waiting, and requires an exact match between the
caller-approved bounded manifest and persisted public media. Exact retries
recover the immutable registration without restoring old authority. Initial
registration creates version 1; explicit update/version advancement and its
native caller remain outstanding. No legacy request is silently bound.

The private publication records the named result, admission revisions, original
public labels and approved media cohort. The separate
`public.explore_analysis_public_projection` contains only a post ID, publication
version, public names, species ID and the existing allowlisted identification
object. It contains no analysis/owner/request ID, private evidence or review
payload. Direct reads follow existing owner post RLS; public app/web reads use
the existing service-mediated RPCs and their privacy/moderation/block guards. No
new privileged public reader or private-history grant is introduced.

Community source changes invalidate public names and species eligibility in the
same transaction, before a worker runs. Named review changes also invalidate
immediately. Reconciliation can republish only matching current source and
review revisions, never a superseded owner decision. Private selection does not
change the published result. Missing private history retains an unresolved
public marker, preventing fallback to the legacy scan. Otherwise-visible posts
and discussion remain, while privacy, moderation, media quarantine and deletion
still hide them. Cards, detail, species filters/search, public web, community
detail and both notification readers follow this projection. Community detail
uses approved media, suppresses private suggestions and model metadata, and
clears current/initial taxon labels when unresolved. Discussion timeline entries
remain historical contributions.

Approved media identity/order/content cannot be changed by legacy refresh or
composer writes. Health metadata remains mutable; unsharing and parent deletion
can erase media. Versioned replacement needs the future explicit publisher.
Registration retires derived Merian reference entries attributed to that post,
including matching dictionary fallback URLs, and marks provenance disqualified.
A transaction advisory lock serializes this with reference refresh; registration
uses try-lock and retries on contention. Refresh excludes bound posts. A shared
URL may be reconsidered under another eligible post's attribution on a later
refresh; no private evidence is deleted by this cache invalidation.

Owner/history writers use NOWAIT for public projection rows and return
`analysis_history_unavailable` on contention. Account tombstoning prelocks bound
request and projection rows without waiting before detachment, avoiding cycles
with request-first consensus. A failed operation rolls back completely and must
retry. New admission gates never suppress revocation. The moderated publisher,
explicit shared-identification update, durable worker, native integration and
remaining activation checks are still required.

### Prepared atomic community-request admission

`internal.admit_observation_community_request` now prepares the fresh-request
transaction behind default-false `community_admission_enabled` and the existing
community-authority gate. It has no API-role execution grant, including service
role, no Edge caller and no native caller. The future publisher must
authenticate the owner, moderate and copy the named analysis's evidence to
approved public media, and freeze that intent before invoking this private
boundary. The routine accepts only a bounded public cohort, never private signed
tickets. Its URL shape checks are not moderation or proof of evidence ownership.

Admission locks owner, observation generation, live scan, history and the named
authority. Both expected revisions must match; the named result must be
biological and unreviewed, without existing community authority. The active
taxonomy and optional non-Human initial taxon are checked explicitly. V1 hides
location and accepts at most six approved media items and a 1,000-character
public note. Existing posts or requests cause a conflict: this operation never
reopens, replaces or silently binds an older discussion.

A private same-transaction insertion fence authorizes only the exact freshly
generated request/post/owner/observation tuple. The normal enrolled-scan guard
continues to reject every unfenced insertion. Admission creates post, approved
media, sanitized marker, fresh `needs_id` request, immutable analysis binding
and retry receipt in one transaction; initial reconciliation advances authority
without changing selection. The transient insertion fence is consumed before
commit. A failure leaves none of those writes behind.

The operation UUID identifies an immutable intent and receipt. Deletion and
ownership checks precede replay. An exact retry returns the same original
`admitted` receipt, even after admission closes or the request is deleted; it
never recreates a request or reapplies authority. This is historical evidence of
admission, not a current request-state response. Changed identities, revisions,
note, taxonomy or media conflict. Observation/account erasure removes the
private operation through the history cascade.

`public.explore_analysis_community_posts` stores only the post ID. It survives
private-history removal until post deletion and prevents fallback to mutable
scan evidence. Community detail uses the frozen post cohort and suppresses AI
suggestions, confidence qualification and inference metadata. The current feed
and Edge media enrichment already read that same cohort. Media identity/order
and initial request note/taxon cannot drift; health metadata remains mutable,
and unsharing/deletion can erase media. Legacy refresh leaves it alone. A new
request has no resolved Explore sidecar and stays out of Explore even if its
request later disappears. Explicit resolved publication registration remains a
separate transaction boundary.

The authenticated moderated publisher, saved native operation, authority-worker
dispatcher and explicit updates for existing discussions remain activation
requirements. This preparation changes no client payload and opens no rollout
gate.

### Prepared protected-photo publication intent

`internal.prepare_observation_publication_intent(owner, request)` persists a
private operation before moderation or copying. It has no API execution grant
and requires default-false `publication_intent_enabled` plus history/photo
reader gates. The exact V1 request contains `observation_id`, `analysis_id`,
`operation_id`, both expected revisions, active `taxonomy_version_id`, nullable
`initial_taxon_id`, nullable `note`, and ordered unique `media_ids`, alongside
`schema_version`. It permits one to six photos, a 1,000-character note and a 4
KiB JSONB request. The first version is a fresh community-request preparation:
it requires an unreviewed biological result without community authority and
refuses any existing post or discussion. It never changes selection or
authority.

Only completed V2 image references are eligible. Every media ID resolves through
`resolve_owned_observation_photo` against the named result's immutable manifest
and owned ready receipt. The frozen private source tuple contains media ID,
opaque object ID, content type, byte count and SHA-256; aggregate photos are
bounded at 32 MiB. Caller URLs, mutable scan photos and imported V1/V3
presentation evidence cannot substitute for that proof. The preparation envelope
is `{schema_version: 1, request, sources}` and must never be returned to public
readers or used as public media metadata. No client DTO changes in this slice.

An exact retry returns historical preparation even if a gate or authority later
changes, but ownership/deletion checks always run first. Changed request fields
conflict. Historical preparation is not permission to execute. The separate
`internal.revalidate_observation_publication_intent(owner, observation, operation)`
rechecks current gates, revisions, taxonomy, absence of an existing publication,
and ready source facts against the frozen tuple. Neither routine authorizes
provider dispatch, public copying, final admission or billing settlement.

Completed identification, provider response safety and settled funding contain
no persisted approval to publish these photos. An immutable moderation receipt
bound to each exact source tuple and policy version, funded dispatch rules,
public-copy reservations, deletion-safe cleanup and final revalidation remain
required before an authenticated publisher can be exposed. Private verified-byte
reads must precede moderation; public visibility must follow approval. Existing
private evidence cleanup does not cover future public copies.

### Prepared photo-moderation attempt lifecycle

The next private SQL boundary records one source-bound photo moderation job per
publication intent/media ID and explicit provider attempts beneath it. It has no
API grant or production caller. `publication_moderation_enabled` and every
`observation_photo_publication_moderation` quota policy default disabled. The
prepared binding is Gemini / `gemini-2.5-flash` / `google_gemini`, with policy
identifier `photo_publication_v1`; the prepared classifier below provides
versioned prompt/response validation. The private execution binding below
connects proof, dispatch and output; live repository and endpoint integration
remain required before activation. No existing scan result or audio attestation
authorizes a photo decision.

`admit_publication_photo_moderation` revalidates the frozen parent intent and
exact source tuple. A private stable quota request ID belongs to that photo job;
each attempt records its quota attempt number, reservation, lease hash and
active token. Original analysis IDs are not passed into generic quota admission:
those IDs remain fenced for identification. Private job fields provide
observation/analysis correlation instead. The new operation receives ordinary
provider quota under each plan, including complimentary entitlement, and never
creates or settles a complimentary scan-credit hold. Current named-processor
consent is required for each new attempt and immediately before dispatch.

The first admission uses a null predecessor. Recovery of that admission returns
the same attempt. Only an explicit cancelled or `unknown_execution` predecessor
can admit a successor; repeating the predecessor recovers that same successor.
Approval and rejection are terminal. Dispatch atomically commits provider quota
and grants one `dispatch_allowed` permit; retries never grant another. The
trusted adapter must verify the private bytes and its exact policy/response
binding before invoking the completion routine with `approved` or `rejected`.
Completion rechecks source/revisions, quota attempt/token and the two-minute
dispatch deadline. A late or superseded response cannot become approval.
Terminal records erase the active token and preserve only its hash and bounded
quota metadata, source and policy identities. These are private historical
decisions, not current public-copy authorization.

Retirement before dispatch refunds once. After dispatch, retirement requires
expiry and records `unknown_execution`, retaining charged provider quota. A
process crash therefore cannot silently redispatch or refund an uncertain call.
The generic expired-reservation sweep may refund a still-reserved quota lease;
dispatch then fails, retirement records cancellation idempotently, and a new
explicit predecessor is required to retry. Generic quota pruning may remove an
old reservation before its private history. Retirement then records the existing
private state without refunding anything; a successor may acquire a new
reservation whose attempt count restarts. Identity includes reservation ID,
attempt count and token, never the counter alone. Deletion erases private
jobs/attempts under the observation fence and refunds only still-reserved
attempts. Already dispatched calls retain their provider charge. Deletion wins
every late replay.

No provider call, public copy, endpoint or native operation is enabled by this
lifecycle. The prepared adapter below provides bounded byte verification, strict
classifier policy/response validation and provider-usage decoding; the private
execution owner below binds its proof and saves those outcomes atomically.
Public-copy reservations/cleanup and final admission still need fresh authority,
policy and source checks over the complete approved ordered cohort.

### Prepared source-bound photo classifier adapter

`analysisHistory/photoClassifier.ts` now prepares a concrete Gemini request from
an authorized private photo tuple. It reads with private storage credentials,
checks exact size and SHA-256 plus a JPEG/PNG/HEIC container signature, and
freezes the serialized inline request before invocation. A container signature
is not a complete image decoder or safety approval. This prepared policy limits
each source to 12 MiB and the serialized request to less than 20,000,000 bytes;
larger photos fail before dispatch. It never resizes or silently substitutes
content. Only photo bytes and fixed policy text enter the provider request;
private IDs, object keys, notes and storage URLs are excluded.

The immutable proof includes the source tuple, provider/model/processor, policy
version and SHA-256, and a request digest binding POST, the exact endpoint/API
version and body digest. The policy digest includes generation settings,
transport bounds and response-contract version. Future policy, parser or
transport changes must version that binding. The key is captured before dispatch
and carried only in the provider header. The one-shot invocation closure sends
one HTTP request with redirects disabled and a 90-second request/body deadline;
429, 5xx, disconnects and malformed responses never retry.

Response parsing is bounded to 32 KiB, strict UTF-8 and JSON. Approval requires
the exact returned model, one STOP candidate with one plain JSON text part, no
provider safety block, an exact decision/confidence/category object, allow with
confidence at least 0.95 and no adverse categories, and bounded consistent
input/output/total usage. Review or low confidence returns rejection. Unexpected
output, missing usage or any post-dispatch error returns only a generic unknown
execution error without provider payloads or transport causes. Valid results
contain bounded category codes and usage, never generated descriptions.

The prepared execution owner below now persists this exact proof before
consuming the private SQL dispatch permit and atomically saves bounded
output/usage. Its local one-shot closure alone is not authorization. The
prepared `moderate-publication-photos` endpoint now connects the scoped
repository and execution owner behind closed gates. Public-copy approval,
authenticated publication and native delivery remain disabled and unimplemented.
No live provider call qualifies this policy; synthetic adapter tests prove
contract behavior only.

### Prepared durable photo execution binding

`prepare_publication_photo_execution` stores an immutable attempt proof before
dispatch, validating the exact private source and pinned classifier policy
digest. The request digest binds the adapter's concrete transport/body; SQL
validates its shape but cannot recompute private image bytes or provider input.
The trusted execution owner must save the proof from the same prepared adapter
closure that it later invokes. Dispatch now refuses any reserved attempt without
that proof. No API role can read or execute these private objects.

`complete_publication_photo_execution` validates bounded classifier facts and
usage, then stores them and completes the decision in one transaction. It uses
the existing owner/deletion/attempt lock order. SQL independently enforces
approval iff allow, confidence at least 0.95 and no adverse categories, with
exact enums, unique category codes and consistent positive input/output token
counts. Both proof and the entire result must match on replay. Bare decision
completion requires the matching stored result, closing that bypass. Changed
authority, expired dispatch, stale quota or deletion rolls back the result
write. Proofs and results cascade with the attempt, including account deletion.

`photoExecution.ts` is the prepared execution owner. It freezes verified
owner/observation/attempt/original-lease scope before suspension and passes that
explicit scope to every repository callback. It saves the adapter proof before
requesting one dispatch permit, invokes that same frozen closure, and retries
only the identical atomic completion write once after an error. Pre-dispatch
preparation failures use authoritative retirement, which cannot refund a
competing dispatch. A lost dispatch acknowledgement or uncertain provider result
never invokes again, refunds, or admits a successor.

Recovery of dispatched work calls the authoritative retirement boundary: before
expiry it remains pending; after expiry it can become `unknown_execution`,
retaining its charge. Expiry alone does not transition state. The prepared
moderation worker and scoped repository below consume recovery; no deployment or
scheduler is authorized. If a valid provider result never commits before expiry,
it is intentionally treated as an uncertain execution. An already-committed
terminal result remains replayable after expiry and generic quota pruning.
Neither result nor historical receipt authorizes public copying.

## Prepared public-photo storage boundary

`analysisHistory/publicPhotoStorage.ts` supplies bounded transport, not
publication authority. The prepared erasure worker uses its permanent-marker
operation; the prepared copy worker below connects the scoped execution
repository to durable authenticated publication operations behind closed gates.
Private SQL now reserves a never-reused opaque object UUID and durable cleanup
obligation before I/O and revalidates current source, moderation policy,
authority and the complete ordered cohort before atomic publication binding.
Historical approval alone is insufficient. Bound ownership coordinates unshare,
moderation and deletion revocation independently of private selection;
reversible health quarantine does not erase the cohort. The contracts below
define the staged, bound and revoked lifetimes.

The writer uses `publication_media/v1/<object UUID>` in the public bucket,
separate from legacy scan upload ownership. It requires exact private bytes,
size, MIME and SHA-256 and uses conditional PUT with `If-None-Match: *`. Both
dedicated read and write configurations are captured and checked before I/O. A
successful write or duplicate conflict requires matching HEAD facts, including
`Cache-Control: no-store, max-age=0` and absence of an erasure marker. Public
metadata contains only the content digest, never private source identities.
Erasure overwrites the same key with a permanent empty marker; it never deletes
the key. This defeats both orderings of a delayed conditional upload racing
origin erasure. The durable operation owner must queue cleanup and attempt
immediate erasure after uncertain writes or final admission denial, while
fencing against another worker's valid committed publication. This helper
supplies no such ledger, claim, cleanup scheduling or publication transaction.

`publicPhotoContainer.ts` rejects known out-of-band metadata containers through
a bounded JPEG/PNG allowlist before writing. JPEG permits baseline/progressive
coding markers and only the exact minimal JFIF 1.1 header; EXIF, XMP, ICC, IPTC,
comments and other application segments are rejected. PNG permits bounded image,
transparency and color-description chunks with valid CRCs; text, EXIF, ICC,
unknown ancillary and animation chunks are rejected. Trailing bytes are
rejected. This is structural filtering, not a pixel decoder or a claim that
image content cannot encode private information. HEIC and metadata-bearing
inputs are held. Future admission must perform this preflight on verified bytes
before reserving provider quota. A sanitized derivative requires a separately
immutable source and its own moderation; transcoding cannot inherit the original
approval.

Origin no-store headers and markers do not prove CDN revocation. Activation
requires a verified cache bypass for this namespace, permanent-marker lifecycle
protection and authorized nonproduction edge tests showing no stale body after
erasure. No hosted storage policy, credential or cache setting changed here.

## Prepared public-photo staging lifecycle

The private SQL owner reserves one copy per moderation attempt only after fresh
owner/deletion, intent/revision, exact-source and stored proof/result approval
checks. It requires the current pinned policy and JPEG/PNG source. A permanent
opaque object registry and leased private receipt commit before external I/O.
Retries recover the same key and lease; abandoned or expired copies cannot
allocate a successor through the same attempt. No client URL, storage key,
classification or metadata-filter assertion is accepted. The trusted future
writer must still preflight verified bytes and perform conditional PUT plus HEAD
verification before calling completion; SQL cannot inspect storage bytes.

Completion repeats current authorization and checks the exact object/lease,
registry state and fixed ten-minute deadline. It marks staging ready once;
`ready_at` does not extend availability or confer public publication authority.
Both reserved and ready unbound copies become eligible for cleanup at that
original deadline. The cleanup claim locks only the permanent registry, uses
SKIP LOCKED, and issues an expiring token. Stale tokens cannot acknowledge a
newer claim. Success means externally verified permanent empty marker; failure
retains the obligation for retry. Expiry alone does not execute storage I/O.

Abandonment ignores rollout/review changes after verifying owner and original
lease, advances cleanup immediately and prevents later completion or allocation.
Parent observation/account deletion cascades the private receipt and advances
the detached registry through its deletion trigger. The existing moderation
observation-tombstone fence supplies the cascade. Cleanup remains callable when
rollout gates are closed. Copy routines remain private; the prepared erasure
worker below has narrowly scoped service-only claim/acknowledgement wrappers. No
authenticated publisher or public-copy writer calls the copy routines.

The private atomic binder below supplies bound-publication state. The prepared
copy executor now abandons and attempts targeted erasure after failed writes or
completion; operation-wide final binding failure must apply the same cleanup to
every staged copy. Abandonment rejects already-bound objects. The authenticated
operation owner and live repository remain required before activation. No
original-analysis safety result or historical approval can replace these checks.
No provider or complimentary-credit charge occurs in this copy lifecycle.

## Prepared atomic public-photo binding

`internal.bind_approved_publication_photo_cohort(owner, observation, operation)`
accepts identities only. It resolves the immutable intent, revalidates current
owner/deletion/revision/source/policy authority, and requires every ordered
photo to have a stored approved moderation result and ready unexpired copy. It
locks the complete registry cohort in object-ID order and rejects any expired,
claimed, erased, revoked or already-bound object. URLs derive exclusively from
`https://media.merian.app/publication_media/v1/<opaque-object-UUID>`; activation
must verify that this configured public origin serves the reviewed bucket with
namespace cache bypass.

One transaction creates the fresh needs-ID post/request through the existing
admission owner, binds all photos, and saves an immutable ordered-object
receipt. There is no partial cohort, client URL, legacy scan-media update or
resolved publication registration. Existing discussions require a separate
explicit update contract. Replay requires the same owner/observation, saved
admission and entire ordered binding. It returns historical admission without
revalidating revisions advanced by admission, or changing a removed post.
Missing bindings conflict; deletion fences run before replay.

`bound_at` establishes a separate lifetime without extending staging deadlines.
Cleanup claims skip bound objects until `revoked_at` is set. Unshare,
moderation, post deletion and private-receipt deletion queue irreversible object
erasure; registry obligations survive parent deletion. A removed bound post
cannot clear both unshare/moderation flags to expose erased URLs: a new approved
publication is required. Location privacy, private selection, identification
withdrawal and reversible media-health quarantine do not erase this cohort.
Quarantine recovery retains existing approved bytes; identification revocation
retains the discussion with unresolved labels under the existing authority
projection.

Fresh binding locks owner/observation before registry and creates a new post;
replay never locks the registry or rewrites an existing post. Removal triggers
lock post then registry, never owner/history. The registry-only cleanup worker
cannot claim the cohort across a successful binding transaction. Late copy
abandonment rejects bound objects, protecting another worker's committed post.

`publication_binding_enabled` defaults false. All routines/tables remain private
with revoked API privileges. No authenticated publisher, public-copy writer or
scheduler is activated by this migration. The later erasure worker is separately
prepared below. The prepared transaction does not establish CDN erasure or
production readiness.

## Prepared public-photo erasure worker

`erase-publication-photos` is a prepared service-authenticated POST endpoint. It
derives no authority from a user JWT, request body, owner account or private
history row. Public service-only RPCs claim one due registry obligation and
acknowledge its exact two-minute token. A targeted claim supports immediate
failed-copy cleanup after abandonment or deletion; an unknown, unexpired staged,
already-erased or valid bound target cannot fall back to erasing another object.
The HTTP worker itself accepts no target. Internal copy recovery must obtain the
SQL claim before storage I/O, even when its original completion failed.

A single invocation writes a permanent empty marker and verifies HEAD through
the dedicated public-photo storage adapter. It then reports success or failure
with the original object and claim identities, frozen before I/O. Failure
releases the claim for retry without marking the object erased; crashes/lost
replies leave durable claim-expiry recovery. A stale token cannot acknowledge
another worker's claim. No key is deleted or reused, and no provider or scan
credit is involved.

The response contains only zero-or-one `claimed`, `marked` and `acknowledged`
counts. `marked` confirms the origin marker; acknowledgement can also accept a
failed-write report, so consumers must not equate it with successful erasure.
Unknown errors receive a fixed 503 envelope without database/storage
diagnostics. The endpoint uses the shared exact service-key authorization and
bounded client transport. RPCs have twelve-second client and ten-second SQL
deadlines. There is no unbounded discovery pass or internal storage retry loop.

`publication_erasure_enabled` defaults false and rejects new external claims
until cleanup credentials/cache behavior are qualified. Finishing existing
claims is not gated. Once qualified, keep this separate cleanup gate enabled
during a publication rollback; it does not depend on admission flags. No
deployment, scheduler, public-copy execution owner or native operation is
enabled here. Dedicated credentials, scheduled draining, monitoring and verified
managed-cache bypass remain activation requirements; origin marker completion is
not proof of CDN erasure. Adding the route to `config.toml` participates in the
normal main-branch deployment plan (a config change selects the function fleet);
the default-off runtime gate is not a deployment hold. Merge/deployment still
require explicit release authorization.

## Prepared public-photo copy execution

`analysisHistory/photoCopyExecution.ts` executes one already-approved source. It
freezes the verified owner, observation, attempt and exact five-field source
before suspension. Reservation must freshly authorize that source in SQL and
commit the permanent cleanup registry before any storage I/O. A strict returned
receipt must match the full scope and source; malformed or lost reservation
replies cause no write or cleanup using untrusted object identities.

A ready staging receipt replays without another write. Otherwise the executor
reads verified private bytes, checks digest/size and the JPEG/PNG metadata
allowlist, then calls the conditional writer and requires its HEAD verification.
A single abort deadline, capped at sixty seconds and the remaining fixed
reservation lifetime, covers the source read, destination PUT/HEAD and both
completion calls. Per-request storage and RPC limits remain shorter bounds.
Expired work starts no new I/O; cleanup uses its own independent budget because
abort cannot prove that a remote PUT was not already accepted. It retries only
the identical completion at most once, preserving object, lease and fixed
expiry. It does not publish a post, renew a reservation, admit another
moderation attempt or spend provider/complimentary quota. Admission must still
preflight all approved sources before reserving moderation quota.

After a failed source read, write, verification or completion, it attempts
abandonment and then a targeted registry-only cleanup claim even when
abandonment fails because deletion already removed the private receipt. The
shared `photoErasure.ts` owner writes a permanent marker only after SQL grants
that claim. Valid bound publications cannot be claimed; errors alone never
authorize erasure. Cleanup failure leaves the durable registry obligation.

The internal result is `ready` or `reconcile`, with no private receipt returned.
`ready` means staging only; final ordered-cohort binding must revalidate current
authority and deletion. `reconcile` requires the operation owner to read durable
publication/copy state before choosing a terminal result or explicit new intent:
a lost completion may already have been bound by another worker. It is not an
automatic retry or successor permit. Expired or abandoned copies never allocate
another key through the same attempt. The live copy repository, authenticated
operation admission and recovery owner remain unconnected; all gates stay off.

## Prepared authenticated publication operation intake

`request-observation-publication` is an owner-authenticated POST endpoint using
`withEdgeHandler`. It accepts the exact protected-publication-intent request:
`schema_version:1`, operation/observation/analysis UUIDs, both expected
revisions, taxonomy version, nullable initial taxon, nullable note and one to
six unique ordered `media_ids`. Consent covers that exact order only. No owner,
public URL, source tuple, moderation decision or provider/copy identity is
accepted. The body is limited to 4KiB and canonical request JSON to 3,800 UTF-8
bytes; notes allow at most 1,000 Unicode code points within that byte limit.

The service-only `admit_owned_observation_publication` RPC derives its owner
argument exclusively from the verified Edge user. It locks ownership/deletion
before reading any saved operation, validates the entire request through the
private intent owner, and atomically persists immutable intent plus intake
record. Previously prepared intents require fresh revision/taxonomy/source/gate
revalidation before first intake. The original server HMAC IP hash is retained
privately for later quota admission; changed networks never change a retry's
saved hash. It is not a raw address and is never included in responses or logs.

Success is always HTTP 202 with an immutable six-field receipt:
`{schema_version:1, operation_id, observation_id, analysis_id,
status:"accepted", admitted_at}`.
Accepted means durable intake, not completed moderation, public availability or
a scheduled worker. No provider quota, scan credit, storage write or post
creation occurs here. A later execution/status owner must supply the terminal
result. Prepared native delivery exists, while ordinary UI remains disabled.

New operation admission is also observation-wide: after exact UUID replay, any
existing intake for that observation rejects a different UUID with
`analysis_history_operation_conflict`. Pending, held, unknown and terminal
`needs_action` all retain the original identity. A different historical analysis
is not another publication target. Terminal remediation does not authorize an
automatic replacement; explicit supersession requires a separate contract. This
guard is confined to intake, preserving original moderation/copy recovery.

The prepared service-only database lookup
`read_owned_observation_publication_target(owner, observation)` uses the same
owner/deletion lock. It always returns an exact non-null
`{schema_version:1,operation}` envelope: no intake has `operation:null` only for
an existing owned observation; one intake has the existing five-field status;
multiple legacy intakes conflict without choosing a latest row. It exposes no
consent or private evidence. Exact-ID replay remains available for each original
legacy operation. The separate prepared HTTP target reader is documented below.
The native reader currently resolves only local occupancy; preflight is not
proof that no other operation exists.

At most eight new operations per owner are accepted in a rolling 24-hour window.
This is intake protection, separate from provider and complimentary-credit
accounting. Exact matching replay returns the original receipt even after this
bound or the rollout gate closes and even after authority changes; replay grants
no permission to execute. Changed request fields conflict. Owner loss or
deletion wins over replay. Observation tombstones immediately erase queued
intake facts; parent result/account deletion cascades them as private history,
outside the scientific-retention allowlist. Capacity checks and insertion
serialize under the existing owner-first lock order.

`publication_operation_enabled` defaults false. Public/client database roles
cannot call the service RPC or read its table. Safe request errors return 400,
missing/deleted observations 404, operation/revision conflicts 409, and other
failures 503; responses are private/no-store. Invalid database receipts fail
closed as server errors. Calls have a twelve-second client deadline and
ten-second SQL limit, with no automatic mutation retry. The route participates
in normal main deployment planning; runtime-off is not a deployment exclusion.
Database worker claims and sanitized status are prepared below. The worker
endpoint, source-container preflight before quota, moderated execution/copy,
final cohort binding and cleanup, durable retirement and native delivery remain
held.

## Prepared publication operation worker ownership

`20261004125428_prepare_publication_operation_worker.sql` adds private mutable
work state beneath immutable accepted operations. Intake seeds it atomically;
existing unbound operations are backfilled without changing their acceptance,
selection or review. Durable cohort binding removes work in its transaction.
Observation/account deletion cascades it immediately. All new RPCs are
service-only, with no direct table grants or authenticated caller nomination. No
worker endpoint or scheduler is connected by this slice.

`list_observation_publication_work()` returns at most ten due scope hints
(`owner_id`, `observation_id`, `operation_id`). It takes no child locks.
`claim_observation_publication_work(owner, observation, operation)` locks the
owner and observation before work, rechecks deletion and exact ownership, then
issues a new 120-second token only when due and unclaimed or expired. A busy,
backed-off or already-bound operation returns `{claimed:false}`. A successful
claim returns private frozen request/sources and the **original** intake IP hash
alongside the scope, token and expiry. Never serialize this context to a client
or log it. The default-false `publication_execution_enabled` gate controls both
list and claim independently of intake.

`release_observation_publication_work(owner, observation, operation, token)`
requires the exact live token, clears it and applies a 60-second recovery delay.
Gate closure does not prevent release. Expired or replaced tokens cannot mutate
a successor. A lost claim response waits for lease expiry; a repeated claim
never returns another worker's token. Reclaiming orchestration does not renew a
provider lease, authorize dispatch or copy, retry an uncertain execution, or
settle any funding. Future execution wrappers must verify current work and
freshly revalidate their separate source, revision, consent and attempt rules.
Recovery must inspect durable outcomes before deciding on external work.

`read_owned_observation_publication_status(owner, observation, operation)` is
prepared for a future authenticated owner endpoint and returns exactly
`{schema_version:1, operation_id, observation_id, analysis_id, status}`. Status
is `admitted` only if the durable cohort receipt exists; otherwise a settled
photo phase reports `photos_approved` or `needs_action`, then `processing` while
an orchestration lease is live and `accepted` while awaiting recovery. Photo
outcomes are historical provider decisions only (see below); lease expiry does
not imply provider failure or permission to retry. `admitted` is historical and
does not assert current public visibility, identification authority or species
eligibility. Separate public projections enforce revocation. Reads work after
intake/execution gate closure but fail after ownership loss or deletion. The
original POST always returns its unchanged acceptance receipt.

Activation also requires bounded verified container preflight **before**
provider quota, scoped moderation/copy repositories, cohort-wide failure
cleanup, expired-attempt recovery and native operation delivery. Optional public
notes currently have length validation only: photo approval cannot approve text.
Before live binding, require durable exact-note moderation (including an
explicit no-note case) or restrict the activated subset to no notes. No gate is
enabled by this migration.

## Prepared scoped publication moderation repository

`20261004132016_scope_publication_moderation_operations.sql` exposes three
service-only RPCs under an accepted operation.
`read_publication_moderation_work` requires the exact live
owner/observation/operation/work token and returns each consented media ID in
order with its latest private attempt, or null before admission. Recovery
includes the original provider lease and dispatch deadline; never send it to a
user or log it.

`admit_publication_moderation_work` accepts only that work scope and one member
media ID. It uses the original intake IP hash for provider quota, not a new
worker address. Any existing attempt, including cancelled or unknown execution,
is returned for recovery. No predecessor parameter or automatic successor is
available. Fresh admission requires the execution gate, moderation gate and
current intent/consent/quota checks. Recovery does not imply permission to
invoke.

`advance_publication_moderation_work` binds every action to the accepted
operation, exact attempt and original provider token. Prepare/dispatch require a
live work token and enabled execution gate; private routines retain their proof,
source, consent and moderation gates. Reserved cancellation also requires live
work so an expired worker cannot cancel a replacement worker's reservation.
Completion of an already-dispatched request uses the original provider lease,
proof and exact result even after orchestration expires or its gate closes;
provider expiry, deletion and authority/source checks still apply. Dispatched
retirement requires expiry and retains the charge. Terminal replay is immutable.
The facade cannot grant public copying or approve a note.

`publicationModerationRepository.ts` freezes the complete scope and source
cohort, validates ordered/scoped receipts, drops unused quota details, supplies
12-second RPC deadlines, sanitizes errors and never retries transport calls.
`isActivePhotoWork` separates reserved/dispatched execution capabilities from
terminal outcomes, which have no provider token and are consumed directly. Every
execution callback checks the original owner, observation, attempt and provider
token. Only the execution helper may repeat the identical final write.

`photoCohortPreflight.ts` prepares the **entire** exact ordered source cohort
before the future worker may call admission. It rejects duplicate media/object
IDs, more than six photos, more than 32 MiB total, or unsupported MIME/size
facts before I/O. Sequential private reads share a 60-second deadline and caller
cancellation; copied bytes must match immutable digest/length and the bounded
JPEG/PNG container policy. HEIC and metadata-bearing containers remain held. The
successful handle retains at most 32 MiB of verified raw bytes. It permits
preparing one selected photo per pass, releasing all unselected buffers before
building one provider request; it never retains a full cohort of base64 request
bodies. That classifier freezes the same bytes without a second storage read
after quota, and its invocation remains one-shot. CPU-bound hash/container/JSON
phases check cancellation at boundaries, without claiming preemptive
interruption. No partial cohort is returned when a later photo fails. This
preflight is not provider approval, ownership authorization or an image decoder;
current database checks still govern every external step.

`moderate-publication-photos` now consumes recovery first, completes full-cohort
preflight before any new quota, and passes its prepared closure into the
execution owner. No scheduler is connected. SQL does not itself inspect object
bytes; the trusted worker supplies this boundary. Optional-note moderation, copy
integration and cohort failure cleanup, durable retirement scheduling, native
delivery and cache-bypass qualification remain required. All activation gates
stay false.

## Prepared durable photo moderation outcomes

`20261004135533_settle_publication_photo_moderation.sql` adds private immutable
`observation_publication_moderation_outcomes` beneath accepted operations.
`finalize_publication_photo_moderation(owner, observation, operation, work)` is
service-only. It takes no caller decision or attempt list. Owner/deletion and
operation scope are checked before replay. Fresh settlement requires live work,
serializes with completion/deletion, and rejects an already-bound operation.
Existing outcomes replay after work expiry or gate closure.

The finalizer returns `{finalized:false}` without a write while any attempt,
including a predecessor, remains reserved or dispatched. It never cancels an
attempt, settles quota, dispatches a provider, or creates a successor. Once no
attempt is active, it records causal-leaf attempt IDs in the frozen source
order: missing attempts are null. Latest approved/rejected decisions require
their exact source-bound stored proof and validated result. Rejection, unknown
execution, then cancellation take precedence and produce
`{finalized:true,status:"needs_action",reason:<photo_rejected|unknown_execution|cancelled>}`.
A failure can close a partly unattempted cohort; remaining photos need not incur
provider spend. Old terminal predecessors do not override newer explicit
results. Without failure, every source must have an approved decision or work
stays pending. Success is
`{finalized:true,status:"photos_approved",reason:null}`.

Outcome insertion and moderation-work removal are atomic, preventing endless
reclaim. Attempt insertion is fenced against settled operations, including
private explicit-successor calls. Neither the original HTTP 202 receipt nor
existing provider charges change. Owner status keeps its five-field shape and
adds the two phase states; no attempt IDs, provider diagnostics, evidence or
worker tokens are exposed. No endpoint or native decoder yet consumes this
prepared status boundary. Observation/account erasure cascades the outcomes;
deletion wins over historical replay.

`photos_approved` means historical provider approval only. It does not attest
strict container preflight, approve notes, grant public-copy permission, or
assert current authority/visibility. Copy recovery ownership is prepared below;
the future executor must re-read exact immutable bytes and repeat strict
metadata/container validation, current source/review/consent checks and final
ordered binding. The held private copy authorizer/binder still select approved
attempts directly; the live integration must require `photos_approved` plus its
exact ordered causal-leaf attempt IDs. Test denial for a mismatched leaf or a
`needs_action` outcome before activation. Unsupported formats, transient storage
failures, stale authority, exact-note moderation and recovery of expired active
attempts remain execution-owner responsibilities; this slice does not silently
classify them as permanent refusals. All gates remain false.

## Prepared photo moderation execution worker

`moderate-publication-photos` is a service-authenticated POST endpoint with no
caller-selected operation or media. It returns only private/no-store
`{claimed:0|1,settled:0|1}`. Counts describe orchestration, never public
availability or a provider charge. The SQL execution/moderation gates and
provider quota policy remain default-off; no scheduler is added.

The worker takes at most ten discovery hints and claims only the first. It
validates owner/observation/operation, ordered frozen source IDs and saved
intake shape before dropping notes and IP context. Scoped SQL admission
retrieves the original IP hash. Recovery and durable finalization precede
preflight. Existing dispatched attempts can only recover/retire under their
original provider lease; no permit is reconstructed and no successor is created.
Refused cohorts cancel one remaining proven undispatched reservation per pass,
then finalize when no active attempt remains.

Fresh or reserved execution must verify the entire source cohort and prepare the
selected classifier before admission/dispatch. Only one provider invocation is
possible per pass. Unsupported formats, metadata-bearing containers and
transient read failures currently release/back off with no new admission; an
explicit permanent remediation policy remains required before activation.

A shared 135-second request deadline bounds awaited RPC, preflight, fetch and
body reads. The provider/new-work cutoff is 105 seconds. After preflight and
preparation, admission requires at least 60 seconds before that cutoff; dispatch
requires 27 (12 for the dispatch RPC plus at least 15 for invocation). Each RPC
is also capped at 12 seconds. Provider invocation combines its policy's
90-second maximum with the earlier worker signal. The remaining 30 seconds
permit two exact completion writes; finalizer/release are best-effort within the
remaining global budget and may require later durable recovery. No phase may
extend the overall deadline. A timeout never proves rollback: unknown dispatch
stays charged and lost mutation replies recover from SQL.

These limits fit beneath the documented 150-second request idle timeout, which
applies even where paid worker wall time is longer. They do not imply that every
phase can consume its individual maximum in one successful request. CPU/memory
qualification remains an activation gate. Platform limits were checked against
[Supabase's official limits](https://supabase.com/docs/guides/functions/limits)
on October 4, 2026.

Historical photo approval does not approve notes or publication. Future copy and
binding must require the settled exact causal-leaf cohort and repeat byte,
container, revision, consent and deletion checks. No complimentary scan credit
is charged by moderation. No merge, deployment, scheduling, activation or
TestFlight authorization is supplied by this prepared endpoint.

## Prepared publication copy recovery ownership

`20261004145323_prepare_publication_copy_work.sql` seeds a separate durable copy
work row atomically when an accepted operation settles `photos_approved`.
Existing approved unbound outcomes are backfilled; refused outcomes never seed
this stage. Moderation work stays retired. A durable publication receipt removes
copy work atomically, and observation/account deletion cascades it.

The service-only RPCs `list_publication_copy_work`,
`claim_publication_copy_work`, `read_publication_copy_work` and
`release_publication_copy_work` expose only private orchestration. Discovery is
bounded to ten hints. Claim requires the independent default-false
`publication_copy_execution_enabled` gate and returns a 120-second token plus
owner/observation/operation and a `cohort` array. Each array entry contains only
`attempt_id` and its immutable `source`. The cohort must match the settled
outcome's exact order, every current causal leaf, accepted owner and analysis,
and original approved source facts. Workers cannot nominate substitute attempts.
No note, quota receipt, provider token, address hash or public URL is returned.

Duplicate claims disclose no token. Read and release require the exact live copy
token; a moderation token is insufficient. They remain available after gate
closure. Release enforces a 60-second backoff; expired or replaced tokens cannot
release a newer claim. Claim, read and release take the existing owner/deletion
fence before child locks. Discovery returns bounded untrusted hints without
locks; claim rechecks them. Deletion invalidates both live recovery and
historical claims.

This is recovery ownership only. It deliberately does not require current
publication authority, so later execution can recover and clean up an operation
whose authority changed. It creates no storage object, renews no staging TTL,
spends no provider quota or complimentary credit, and approves no public note.
There is no Edge consumer or scheduler yet; client DTOs are unchanged. The
separate copy executor must still recover any durable binding first, revalidate
current authority and verified containers, consume the prepared atomic cohort
reservation below, propagate its fixed deadline, and obtain registry claims
before cleanup. The held private per-photo copy/binder routines remain
ungranted. Live binding must also require immutable exact-note approval or an
explicitly restricted no-note path. All activation gates remain false.

## Prepared atomic publication copy reservation

`20261004152009_reserve_publication_copy_cohort.sql` adds a separate
default-false `publication_copy_reservation_enabled` gate. Enabling recovery
alone cannot activate these allocation/completion APIs.
`reserve_publication_copy_cohort` requires a live copy-work token, the exact
settled ordered causal-leaf cohort, current intent/source/review/consent
authorization and the existing copy gates. This prepared path explicitly accepts
only a null public note. Photo approval cannot authorize arbitrary public text;
nonnull notes need separate immutable moderation before that restriction may
change.

Reservation creates every member's opaque object, copy lease and registry
cleanup obligation in one transaction, along with a private immutable operation
receipt. All members share one ten-minute deadline assigned at first
reservation. A failure on any member rolls back all allocations. Exact retries
return the original objects, leases and deadline; existing legacy partial
allocations are rejected rather than adopted or renewed. Readiness never extends
expiry.

The service-only `complete_publication_copy_cohort_photo` verifies live work,
exact member/object/lease, all registry states and the unchanged common
deadline, then repeats current authority checks before marking that member
ready. It does not attest storage bytes: the pending execution adapter must
verify exact private bytes, strict container policy and the conditional public
write/HEAD receipt, with one shared request signal reaching the completion RPC.

`read_publication_copy_cohort` returns private
`{reservation:{expires_at,copies}|null,publication:<historical receipt>|null}`.
It checks owner/deletion and immutable cohort identities, but deliberately does
not require live work, an open gate, unexpired staging or current publication
authority. Binding retires work; its lost response must remain recoverable
before any cleanup decision. A historical receipt does not assert current
visibility.

`abandon_publication_copy_cohort` checks for a committed publication first and
returns `{abandoned:false}` when one exists. Otherwise it requires live exact
copy work and queues every unbound member for erasure under stable registry lock
ordering, even after authority/gate changes. Success returns
`{abandoned:true,object_ids:[...]}`; this is eligibility, not permission to
erase. The external cleanup owner still needs a targeted registry claim per
object. Expired/stale workers cannot abandon a newer claim; fixed TTL cleanup
remains. Deletion removes private receipts and makes surviving registry objects
due; the independent erasure worker can claim them without private owner
records.

All four RPCs are service-only, allowlisted and ungranted to clients; private
helpers/tables remain ungranted. They never create provider attempts or charge
complimentary credits. No Edge repository/worker or live binder is connected by
this migration. The next execution slice must enforce whole-cohort cleanup after
final denial and consume historical publication recovery before cleanup. Every
activation gate stays false.

## Prepared scoped publication copy repository

`publicationCopyRepository.ts` freezes the accepted owner/observation/operation,
copy-work token and exact ordered approved attempt/source tuples. It accepts one
to six distinct JPEG/PNG sources, each at most 12 MiB and at most 32 MiB total.
Recovery strictly decodes the entire reservation and historical publication;
copy receipts must match the frozen order, source facts, identities and common
expiry. Duplicate or private-source destination keys are rejected.

`forPhoto` supplies frozen scope/source, reserve/complete callbacks and exact
cleanup targets. `executePublicationCopyMember` in `publicationCopyExecution.ts`
adapts these to the existing single-photo executor. Reserve refreshes current
authorization for the whole cohort before each member's I/O; completion requires
the exact lease obtained through reserve. Historical read alone cannot authorize
completion. Completion checks the same object, lease and expiry in the response
and requires readiness. The existing executor and repository reuse the same
receipt/source validators.

Every RPC has a 12-second cap combined with the operation deadline, and
completion also honors the executor's shared signal. Abort regains control even
if transport cancellation stalls. There is no automatic transport retry,
successor allocation, provider call or billing action. Errors expose only fixed
contract codes.

Abandonment first recovers historical publication; an admitted operation skips
cleanup. SQL repeats that check atomically. A cleanup response must identify all
and only the recovered cohort's object IDs. The dedicated coordinator requests a
targeted registry claim for each validated sibling; the generic single-photo
executor can target only its own reserved object. If private deletion or a lost
response prevents recovery, the adapter returns only its previously pinned
original IDs as cleanup hints; it never uses an unvalidated response. A
committed publication returns an empty target set. No object may be erased
without its registry claim. The future worker must bound all cleanup
dependencies with its overall deadline. This adapter does not approve bytes,
read storage, write public objects or bind a post. The operation controller
below connects preflight, transport and binding; service-worker admission and
durable phase outcomes remain unconnected. All activation gates stay false.

## Prepared exact reserved-cohort binding

`bind_publication_copy_cohort(owner, observation, operation, work)` is a
service-only facade; callers cannot submit public URLs, alternate attempts,
object keys or notes. Its separate `publication_copy_binding_enabled` gate
starts false and supplements all existing copy, binding and community admission
gates. New binding requires live copy work, the exact settled ordered causal
leaves, the immutable reservation, every member ready, the original unexpired
staging deadline and current source, review and consent authority. Only the
explicit no-note subset is supported.

The existing atomic writer creates the community request and its public post.
Before committing, the facade requires exact equality between the reservation's
ordered object keys, the publication's ordered keys, actual post bindings and
community/publication receipts. A discrepancy rolls back the entire admission,
post, binding, registry and work-retirement transaction. The private writer
remains ungranted; the service facade is allowlisted.

A durable publication is recovered through the writer's existing owner and
receipt validation before checking live work or current gates/authority. Replay
also verifies the immutable reserved cohort, but does not require its deadline
to remain current. Historical success does not assert current visibility or
republish a hidden post. Observation deletion still wins over recovery. A failed
binding creates no erasure authorization: execution must recover durable success
before requesting targeted cleanup of unbound siblings.

This slice supplies no public storage transport or Edge execution route, does
not dispatch providers or charge credits, and leaves all activation gates false.

## Prepared bounded copy operation controller

`executePublicationCopyOperation` consumes one already-claimed operation and its
original work expiry. It constructs the scoped repository, recovers a historical
publication first, and reserves the complete exact approved cohort before
private or public storage I/O. The repository now exposes strict `bind` receipt
decoding and operation-level cleanup hints restricted to its validated original
keys.

A single 110-second overall deadline includes recovery and cleanup. Fresh work
ends at the earlier of 80 seconds or 30 seconds before the original work expiry;
binding ends at the earlier of 92 seconds or that expiry. No phase or photo
renews the claim or staging deadline. Every RPC is additionally capped at 12
seconds. Cancellation reaches storage and registry transports; bounded waits
regain control even when transport cancellation is not acknowledged. CPU-bound
container and digest work checks cancellation at phase boundaries and still
requires runtime CPU/memory qualification.

The controller verifies every ordered private source's exact length, digest and
strict JPEG/PNG container before any public write. At most 32 MiB of verified
raw cohort bytes are retained, with bounded per-photo read/copy buffers; no
provider bodies are created. This is a retained-input limit, not a process-heap
limit: defensive transport copies of the current photo increase peak memory. It
executes photos sequentially under the shared fresh-work signal, releases each
retained buffer after use, and skips already ready writes while still verifying
current private evidence and authority. Binding runs once only after every
member reports readiness. A stalled or failed member stops further writes.

A lost or invalid binding response triggers durable publication recovery before
cleanup. If recovery cannot establish success, only the original reserved keys
are offered for targeted registry claims. Bound objects remain protected by the
registry, including when a late binding commits after the response is lost.
Cleanup uses the remaining overall deadline and leaves unfinished work to the
permanent registry. No transport failure is asserted to be durable terminal
failure; the result is only `published` or `reconcile`.

The prepared HTTP copy worker below connects this controller and settles durable
needs-action outcomes before new copy execution. Unsupported source and verified
container outcomes are handled by the moderation boundaries below; ambiguous
network/storage results remain recoverable. No scheduler is connected.
Owner-status delivery, native operations and runtime qualification remain. All
gates stay false.

## Prepared durable copy needs-action outcomes

`finalize_publication_copy_work(owner, observation, operation, work)` is a
service-only, independently gated finalizer. Callers cannot choose a terminal
reason or supply cleanup keys. Scope and deletion are checked first. A valid
existing publication wins and returns admitted with no cleanup targets; this
uses the private writer's historical owner, intent, admission and binding
validation, including legacy publications without a cohort reservation. It
confers no fresh reserved-cohort binding authority. A previously stored copy
outcome replays before live work or gate checks because settlement removes work.

New settlement requires a live exact copy token and the default-false
`publication_copy_settlement_enabled` gate. SQL derives only these facts:

- `note_requires_text_moderation`: the immutable intent has a nonnull note, with
  no atomic reservation or legacy per-photo copy. Photo approval cannot approve
  arbitrary public text.
- `staging_expired`: the exact immutable reservation's original expiry has
  passed. Every unbound registry object is locked in UUID order and made due for
  erasure. Existing claim ownership is preserved, and deadlines are never
  extended. The receipt retains the source-ordered original object IDs.

The private immutable copy outcome and removal of copy work commit together.
Provider moderation remains an unchanged historical fact. A new claim cannot
reopen the operation. Settlement does not charge, release or refund quota, and
it never dispatches providers or writes storage. Returned object IDs are only
private cleanup hints; targeted registry claims still authorize erasure. The
permanent registry survives private history deletion.

Fresh ineligible work returns `{finalized:false}`. Historical success returns
`{finalized:true,status:"admitted",reason:null,object_ids:[]}`; needs-action
returns the same envelope with `status:"needs_action"`, the derived reason and
original cleanup IDs. The existing owner-status wire shape remains unchanged:
admitted takes precedence, then copy needs-action, then the moderation state.
Reasons, storage keys and work tokens stay private. Deletion defeats all replay.

Gate closure, a changed review/privacy/consent revision, expired worker token,
and transport uncertainty are not terminal content facts. They remain
recoverable under existing authority and cleanup rules. A note with a legacy
copy also remains pending rather than being silently discarded. The prepared
copy HTTP owner below calls this finalizer before execution. Unsupported sources
and verified container rejections are handled by the separate moderation
boundaries below. All activation gates remain false.

## Prepared unsupported publication source settlement

With the independent default-false `publication_source_settlement_enabled` gate,
`finalize_publication_photo_moderation` derives `unsupported_source_type` from
immutable intent source metadata when any source is outside JPEG/PNG. HEIC is
accepted as private evidence but is not supported by public-copy container
validation. This result requires exact live moderation work, owner/deletion
checks, an accepted operation, no publication and **no existing provider
attempts of any state**. Existing provider attempts keep their original
completion/retirement lifecycle. No provider or complimentary quota is changed.

The immutable moderation outcome records `needs_action`, the private reason, and
an empty attempt array; removing moderation work commits atomically with it. It
never seeds copy work. Historical outcomes replay before token and gate checks;
deletion wins. The service repository accepts the exact finalizer receipt, and
the existing worker consumes it before preflight or new provider admission.
Owner status remains the same five-field envelope and exposes only needs-action,
not private source facts or reasons. Stored publication retains precedence in
owner status; finalization cannot replace a publication.

Attempt-backed outcomes retain their existing constraints: complete approval has
one to six nonnull ordered attempt IDs, while terminal provider failures can
retain null slots for unattempted siblings. Only the source-type reason allows
zero attempt slots. This is metadata-derived remediation, not proof that a
JPEG/PNG container is invalid. Container rejection still requires a verified
source-bound attestation; read failures, digest uncertainty, network, storage,
timeouts and authority changes never become this outcome. All gates remain
false.

## Prepared verified-container rejection attestation

The service-only
`finalize_publication_container_rejection(owner, observation,
operation, work, attestation)`
persists a conservative public-publication remediation decision. It does not
declare private evidence invalid. The bounded attestation contains exactly
`{schema_version:1,
policy_version:"public_photo_container_v1",source:{media_id,object_id,
content_type,byte_count,sha256}}`.
SQL requires one exact original JPEG/PNG intent member; it cannot inspect image
bytes itself. The private table has no direct API-role privileges and deletes
with the accepted operation.

The trusted preflight verifies exact length and SHA-256 before running the
container validator. Only the validator's deliberate typed policy rejection,
with the shared signal still live, can create this frozen evidence. Transport
lookalikes, unexpected parser exceptions, read errors, digest mismatch and
cancellation remain unavailable/recoverable. The worker catches only that typed
result around preflight, retains a bounded completion window, and submits it
through the operation-scoped repository without provider admission or dispatch.

Owner/deletion and accepted scope precede replay. A valid committed publication
returns `{finalized:true,status:"admitted",reason:null}` without an attestation.
Exact saved attestation replay precedes live work and gates; changing the source
or policy cannot rewrite it. New settlement requires exact live work, the
independent default-false `publication_container_settlement_enabled` gate, no
provider attempt of any state and no copy cohort. It atomically inserts the
immutable attestation and zero-attempt `needs_action/public_container_rejected`
outcome and removes moderation work. No copy work is seeded; provider and
complimentary quota are unchanged. Existing attempts retain recovery ownership.

The service receipt is exactly
`{finalized:true,status:"needs_action",
reason:"public_container_rejected"}`.
Owner status keeps its existing five-field shape without sources, private
reasons or work tokens. This decision applies to the immutable operation's
approved evidence; remediation requires a separately consented operation, never
silently transformed or replaced bytes. Policy changes must version the
validator and its accepted attestation contract together. All activation gates
stay false; native remediation delivery and runtime/CDN qualification remain
pending.

## Prepared service publication copy worker

`POST /functions/v1/copy-publication-photos` uses explicit service
authorization; it accepts no caller-controlled work parameters. Strict bounded
database hints lead to one original copy claim, whose ordered
`{attempt_id,source}` cohort, owner/operation scope, token and `work_expires_at`
are frozen before execution. Claim receipts reject extra fields, aliases,
unsupported media, expired leases, more than six photos or 32 MiB combined
input. Database authority and byte checks remain necessary; claim decoding
grants no permission to write.

`finalize_publication_copy_work` runs first. Historical admitted state skips
copying and cleanup. Note-required outcomes do no I/O; expired staging allows
only targeted registry claims for the original SQL-returned objects. Pending
eligible work enters the existing exact-cohort controller, with full preflight,
original reserved keys and deadlines, scoped binding, durable publication
recovery before cleanup, and permanent erasure authority. Unknown failures
release/reconcile; no terminal state is inferred from transport or gate failure.

The aggregate response is exactly `{claimed,published,needs_action}`; published
includes recovered historical admission, not current visibility. All responses
are no-store. Private sources, object keys, notes, reasons and work tokens never
leave the service boundary.

The total request deadline is 135 seconds. Work/cleanup ends at 123 seconds to
reserve a 12-second release window. The 110-second controller starts only when
at least 122 seconds remain; three worst-case setup RPCs cannot be added to its
budget. Slow setup releases the original claim for later recovery. Each RPC also
has a 12-second cap and marker PUT/HEAD honors parent cancellation. Original
120-second claim expiry remains authoritative and is never recreated locally.

**Activation remains blocked** until separately authorized recurring registry
erasure invocation, due-backlog/oldest-age monitoring and CDN cache bypass are
verified. Expiry settlement deletes copy work before best-effort immediate
cleanup, so failed cleanup depends on the permanent registry and independent
`erase-publication-photos` worker; no copy claim will recover it. All gates
remain false. CPU/process-memory qualification and owner/native delivery remain
pending. This prepared endpoint does not authorize scheduling or deployment.

## Owner publication target recovery

Prepared `POST get-observation-publication-target` accepts only
`{schema_version:1,observation_id}` within a 1 KiB body. `withEdgeHandler`
authenticates the owner, and the fixed service repository invokes
`read_owned_observation_publication_target` with a twelve-second deadline and no
retry. Success is literal JSON null for an existing owned vacant observation, or
the unchanged five-field status shape described below. It validates exact keys,
lowercase identities, schema and closed status values before returning. No
client-supplied owner, operation, analysis, URL or consent is accepted.

Missing, foreign and deleted observations share opaque 404; duplicate targets
return 409. Unknown errors and malformed responses return sanitized 503, never
vacancy. Method/body/auth errors and successful responses all use private
no-store. The historical analysis may differ from the displayed one; the result
is neither current authority nor public visibility. No operation or worker is
created. Existing exact-ID status and its native decoder remain unchanged.

Remote absence is advisory and final admission closes cross-device races. A
remote status lacks the immutable request fingerprint, so it cannot become a
synthetic native intent. A locally held losing request after 409 retains its
original UUID and consent. Explicit remote recovery may display a different
operation separately, without rebinding, acknowledging or reopening the local
request. Null or failure after uncertainty never authorizes a successor. The
prepared native target transport uses a separate exact two-field request and 4
KiB null-or-status decoder. Empty successful responses cannot mean absence; the
discovered operation and historical analysis are preserved without becoming
local consent. Its fixed owner-bound route disables transient, 401 and
missing-route replay with a thirty-second timeout. The injected queue-retained
`ObservationPublicationRecoveryOwner` coalesces at most four owner, observation,
session, generation and container scopes. Its read-only service checks strict
local target state before and after remote I/O and releases its account lease
before removing retained work. Auth transitions cancel and await these reads; an
individual presentation cannot poison another waiter. Prepared History access
returns local held status and remote historical status separately, without
saving, acknowledging or waking delivery. Prepared History consent now uses this
boundary before preflight; ordinary access and all activation gates stay false.

## Owner publication operation status

Prepared `POST get-observation-publication-status` uses `withEdgeHandler` to
validate the authenticated owner and calls the service-only
`read_owned_observation_publication_status` routine with that identity. The
request is exactly `{schema_version:1,observation_id,operation_id}`, bounded to
1 KiB and lowercase UUIDs. Lookup uses the immutable operation ID from durable
intake; no latest-scan lookup or legacy sharing fallback is allowed.

The five-field response is exactly
`{schema_version:1,operation_id,observation_id,analysis_id,status}`. The closed
status set is `accepted`, `processing`, `photos_approved`, `needs_action`,
`admitted`. `admitted` means historical admission and does not assert current
public visibility or identification authority. No post ID, media, note, private
reason, provider attempt, work token or cleanup key is exposed. Unknown fields,
wrong identities or invalid status from SQL fail closed with 503.

Owner and observation deletion checks remain authoritative. Foreign, missing and
deleted records all return opaque `analysis_history_not_found` (404). Invalid
caller input returns 400; known operation/revision conflicts return 409; other
failures are sanitized 503. Every route response, including auth, preflight,
method and body failures, uses `Cache-Control: private, no-store`. The RPC is
bounded to twelve seconds, with no automatic retry and no mutation. Native
durable delivery now uses this reader for status-first recovery; ordinary UI
admission remains separate. The route is prepared but not activated; all
publication activation gates remain false.

## Native publication wire boundary

Prepared native admission and status calls now use the existing pinned raw-JSON
transport with a required expected account at dispatch. Classified-401 recovery
is deferred to the durable owner, preventing recursive Auth-drain waits. No new
retry policy, legacy sharing fallback or operation-ID generator is added. The
immutable native request validates the same revisions, lowercase UUIDs, explicit
nulls, ordered 1–6 unique media IDs, 1,000-code-point note bound and 3,800-byte
encoded request cap as the HTTP boundary. Its strict restoration path rejects
missing/extra fields and Boolean revisions before network dispatch.

Admission responses require exact fields, accepted status, valid timestamp and
matching operation/observation/analysis IDs. Status responses require only the
five documented fields and closed status enum, again matching all three IDs.
Responses are bounded to 4 KiB before parsing. Native `admitted` is historical
operation evidence, never current public eligibility or a post ID. Dedicated
wire/transport tests exercise immutable consent, malformed/private fields,
missing-account dispatch prevention, and ambiguous admission without automatic
replay. Prepared local persistence now saves exact consent, then strips raw
consent after acknowledgement while retaining a versioned local fingerprint and
minimal terminal status. The fingerprint is not a backend digest or authority.
Native delivery now holds an expected-owner lease, claims durable work before
I/O and rechecks fresh account/deletion/claim state after suspension. It reads
status before admission: only HTTP 404 plus `analysis_history_not_found` permits
the exact original request while that request is retained. Once acknowledged,
the operation polls status only. Monotonic local claim attempts reject stale
completion and retry writes; interrupted claims recover after a fixed deadline.
Permanent local conflicts require attention without synthesizing a server
receipt. Network uncertainty retains the same operation under bounded backoff;
Auth cancellation is awaited before replacing the session. Ordinary UI delivery
remains separate; all activation gates remain false. See
[the storage contract](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#prepared-publication-persistence).

## Owner publication consent preflight

Prepared `POST prepare-observation-publication-consent` authenticates the owner
with `withEdgeHandler`. Its exact request is
`{schema_version:1,observation_id,analysis_id}` (lowercase UUIDs, 1 KiB body).
The exact response is
`{schema_version:1,observation_id,analysis_id,
expected_observation_revision,expected_review_revision,taxonomy_version_id,
initial_taxon_id:null,media:[{media_id,content_type,byte_count,sha256}]}`.
The taxonomy UUID is the active version; no name matching invents an initial
version-bound taxon. No operation, post, URL, storage key, description, note or
visibility claim is returned. General history and operation-status shapes are
unchanged. The native consent producer is connected to prepared History UI.
Ordinary app access remains disabled. Final explicit photo acceptance persists
one exact operation before delivery; existing or uncertain target occupancy
blocks new consent.

The service-only `prepare_owned_observation_publication_consent` RPC and the
existing intent resolver share `internal.lock_publication_consent_eligibility`.
Owner/generation/deletion locks precede the existing closed publication-intent,
reader and media-reader gates. Authority is locked before reading current
revisions. Eligibility remains biological, unreviewed, without community
authority or human identity, and without an existing Explore post or community
request. Here unreviewed means `user_review_state=unreviewed`: an AI rejection
remains eligible for community help while preserving its separate rejection
authority and returning the advanced review revision. An explicit historical
analysis can qualify independently of private selection. This boundary prepares
initial community intake, not later resolved Explore publication. The existing
resolver still rejects stale revisions before evidence, review or taxonomy
failures and validates selected ready receipts.

Photo candidates preserve immutable V2 manifest order and metadata (up to 64
items and 32 MiB total image bytes), omitting descriptions. They do **not**
prove ready media or reserve publication authority. V1/imported V3 evidence is
unavailable. The later explicit consent must select exactly 1–6 photos; clients
must not silently truncate candidates. Admission rechecks current authority,
revisions, taxonomy, deletion and the exact selected ready receipts. This read
creates no intent, provider attempt, quota debit or public copy.

Every response includes `Cache-Control: private, no-store`, including auth and
parser errors. Invalid requests receive 400. Missing, foreign and deleted
analyses share opaque 404; changed/ineligible review or existing-publication
conflicts receive 409. Closed gates, unavailable evidence, transport failures
and malformed server projections return sanitized 503. The RPC transport has a
12-second deadline without internal retries. All activation gates stay false.

### Native consent preflight transport

`ObservationPublicationConsentRequest` encodes only schema version and the exact
observation/analysis IDs. `ObservationPublicationConsentSnapshot` correlates
both IDs and validates the closed eight-field response with a separate 32 KiB
cap. Existing request/status limits stay at 4 KiB. Initial taxon must be present
and null; revisions remain bounded integers. Candidate objects preserve server
order and enforce unique IDs, allowed MIME types, positive integral byte counts,
32 MiB aggregate content and exactly 64 lowercase SHA-256 characters. Private
keys/URLs, operation IDs, post IDs and extra fields fail closed.

`prepareObservationPublicationConsent` uses the existing account-bound raw JSON
bridge with an expected owner and classified-401 recovery disabled. It never
creates consent, mints an operation UUID, chooses the first six candidates or
falls back to legacy sharing. The prepared consent service below owns explicit
final intent; ordinary UI and its foreground session guard remain the next
integration boundary. The history rollout gate remains closed. Candidate
metadata is descriptive and does not authorize ready-photo transport or
publication.

### Native explicit consent persistence

`ObservationPublicationConsentService` requires the immutable displayed review
ticket, including owner, observation, historical target, selected context, both
revisions and result/authority digests. It validates that exact ticket before
and after preflight and requires the server snapshot's revisions to match. It
never adopts newer authority on behalf of a stale presentation. This native
admission contract changes no HTTP payload.

New preparation and consent require both settled legacy review and completed
native analysis-bound review work across the observation. Pending, running,
waiting, received-but-unreconciled, needs-attention, corrupt or misbound jobs
cannot authorize new consent. The check runs under the existing persistence
transaction, alongside selection, enrollment, deletion and foreground-session
fences; it does not broaden the shared legacy settlement predicate used by
receipt reconciliation. Final explicit acceptance validates 1–6 distinct
candidate IDs in user order, fixes initial taxon and public note to null, and
creates a retained immutable operation. Private notes are not used by this
photo-only consent flow.

New-intent validation runs inside `ObservationPublicationPersistence.stage`
after exact-operation replay, before insertion/save, and retains the original
displayed ticket through final acceptance. An exact saved operation, including a
terminal receipt, remains recoverable despite subsequent authority changes or
new pending review. Recovery cannot authorize a different operation UUID. A
failed save never wakes delivery; success wakes the existing durable scheduler
without starting feature-owned network work. Ordinary UI wiring and activation
remain separate.

### Private reanalysis photo upload

Prepared `POST upload-observation-evidence` is owner-authenticated and held by
`media_enabled = false`. Its bounded binary frame avoids base64 duplication:
four-byte unsigned big-endian metadata length, 1–4096 UTF-8 JSON metadata bytes,
then concatenated raw photos in declared order. Exact metadata is
`{schema_version: 1, observation_id, analysis_id, photos}`; each photo is
exactly `{media_id, content_type, byte_count}`. IDs are lowercase UUIDs, media
IDs are unique and distinct from the observation/analysis; the analysis differs
from the observation. Only 1–5 JPEG/PNG photos and 5 MiB combined raw bytes are
supported. Unsupported media, incomplete/trailing bytes, extra keys and identity
aliases fail before writes. The server computes SHA-256 from its owned bytes.

One service-only transaction freezes the ordered descriptor cohort and original
five-minute deadline before any storage I/O. Changed bytes/order conflict under
the same analysis ID. Exact retry recovers original objects, never renews
expiry, and rechecks ownership/deletion. The private immutable cohort survives
individual receipt cleanup; missing receipts cannot be reallocated by replay.
After expiry, a new attempt requires an explicitly new child analysis identity.
No quota is admitted by uploading. Existing `analyze-observation`
exact-ready-set admission and durable completion remain separate.

The complete response is
`{schema_version: 1, observation_id, analysis_id, items}`; ordered items contain
only `{kind: "image", media_id, content_type, byte_count,
sha256}`. No private
object ID, storage path, signed URL or public availability is returned.
Responses are private/no-store. A shared 120-second deadline bounds body
reading, all RPCs (each also capped at 12 seconds) and conditional storage
writes/verification. Lost responses retry the identical immutable frame. Partial
uploads cannot start inference; expiry and permanent erasure-marker cleanup
remain required. This source addition does not enable a native production
caller, bucket, worker schedule or rollout gate.

The prepared native `uploadObservationEvidence` caller emits this exact binary
frame through the existing account-bound authenticated transport. It validates
IDs and media bounds before dispatch, hashes/prepares off the main actor, and
requires the schema-1 receipt to match every submitted reference in order and
content. Its decoder caps receipt admission at 4 KiB. The fixed bridge uses a
130-second client timeout and disables hidden transport/401 replay; the durable
caller must retain exact request identity and decide recovery. This transport
connection does not yet connect ordinary capture/queue reanalysis or activate
history.

The prepared native `ObservationReanalysisRequest` value represents photo-based
protocol-8 admission without starting it. It requires a distinct nonnull source
analysis, preserves ordered descriptions and exact V2 image references, and
requires the existing recipient preflight's explicit processor expectation. Its
native fingerprint convention hashes sorted-key UTF-8 JSON of the entire input
except `request_digest`, with lowercase UUIDs and unescaped slashes. Restoration
validates the digest and strict executable limits, retaining the original saved
bytes rather than rebuilding an attempt from current scan content. Server
identity still compares the complete admitted input; this fingerprint is not
evidence or provider authority. The strict native execution receipt contains
only parent ID, child ID and execution state with schema 1; completion requires
a separate authoritative history read. These value types do not connect capture,
queue delivery or selection, and do not activate any gate.

The prepared native `ObservationReanalysisExecutionStore` persists local attempt
claims independently of provider execution identities. Fresh row/job
compare-and-save rejects stale workers; retry and interrupted recovery retain
the same immutable request. Evidence/consent/reconciliation holds and proven
terminal failures remain held for explicit remediation. Local execution never
claims or settles funding. Exact validated completion appends the child, retires
only its transport work and records temporary-file erasure authority in one
save, preserving current selection and review authority. Committed replay still
requires the same owner, exact retained result and a parent without pending
deletion. This is a prepared persistence boundary, not network dispatch or an
activated scheduler. Its
[local ownership contract](../../apps/ios/Merian/Core/Data/AnalysisHistory/README.md#durable-execution-claims-and-local-completion)
owns native claim and recovery details.

For an already-bound native request, current consent authorization preserves the
saved processor and synchronizes required cloud consent without rerunning
recipient discovery. Expected owner and durable claim checks surround this work
and remain in the final dispatch authorization. Required consent and optional
OpenAI permission can still deny the original request. Recovery-only cannot be
used as execution permission or to reconstruct an unbound request.

### Prepared immutable Insight admission protocol

The private, service-only database boundary
`reserve_insight_chat_send_with_context(uuid,uuid,uuid,text,uuid,jsonb,integer)`
returns the existing admission fields (`conversation_id`, `message`,
`is_replay`, `sends_today`) plus `context_snapshot`. This is prepared storage,
not an enabled HTTP contract. Existing `insight-chat` request/response DTOs and
native callers are unchanged in this slice.

Protocol/context version is exactly 1. `p_displayed_ticket` is JSON null for
unenrolled observations; enrolled sends supply exactly `analysis_id`,
`state_revision` and `review_revision` for the displayed selected
identification. A new request cannot silently adopt newer selection or
authority. Same-key replay requires original normalized text and ticket, and
recovers original context even if the gate or authority later changes. Ownership
and deletion still win. An old admitted question lacking a context row returns
`field_chat_context_missing`; there is no snapshot backfill or permission to
redispatch it from current data.

The context contains version, source kind (`legacy_scan_v1` or
`analysis_history_v1`), original ticket, bounded `scan_context` and an ordered
`conversation_prefix` of at most 12 `{role,text}` entries, capped at 900
characters per entry. Source projection excludes media, exact coordinates, raw
library notes and unrelated payload keys, including nested keys. Historical
imports with missing encounter data remain unavailable. Internal IDs are
recovery metadata and must not enter model prompts.

Database denials distinguish invalid input (`22023 field_chat_invalid_request`),
changed ticket (`40001 field_chat_context_conflict`), changed same-ID intent
(`23505 field_chat_idempotency_conflict`), missing legacy context
(`55000
field_chat_context_missing`), closed/malformed context
(`55000
field_chat_context_unavailable`) and absent/deleted ownership
(`P0002
field_chat_subject_not_found`). Existing admission errors remain
authoritative. HTTP status mapping, execution from immutable context and native
displayed-ticket transport must land before activation. This boundary neither
retries providers nor changes quota settlement.

### Prepared read-only Insight context resolution

Service-only `get_insight_chat_turn_context(uuid,uuid,uuid,text,jsonb,integer)`
takes owner, observation, client-message UUID, original normalized question,
displayed ticket and context version 1. It returns exactly
`{context_version:1,found:false}` for an absent user turn, or
`{context_version:1,found:true,message,context_snapshot}` for a stored turn.
`message` contains exactly `id`, `conversation_id`, `scan_id`, `user_id`,
`role`, `client_message_id` and `message_text`; role is `user`. The ticket, text
and joined current ownership must match. A JSON-null legacy ticket (SQL NULL
through PostgREST) is normalized to stored JSON null. History tickets remain
exact, closed three-field objects. Total recovery response is capped at 136 KiB;
the snapshot remains capped at 128 KiB.

The resolver does not admit, consume daily/conversation capacity, inspect
current history or gates, or authorize provider execution. Owner/deletion checks
precede saved context. An uncontexted existing user turn holds with
`55000 field_chat_context_missing`; it is never treated as absent. The internal
TypeScript adapter maps only exact code/message pairs to missing-subject 404,
missing-context 409 or idempotency-conflict 409. Unknown errors, malformed data
and missing RPC routes become unavailable 503, never fresh-send permission. It
issues one request bounded to five seconds and respects parent cancellation.
These are prepared internal errors, not a newly activated HTTP endpoint.

After genuine absence, future handler integration must run read-only immutable
eligibility and existing Pro/quota checks before atomic context admission; no
recovery probe may consume a slot. Live HTTP/native DTOs remain unchanged.

### Prepared fresh Insight context preflight

Service-only `prepare_insight_chat_send_context(uuid,uuid,jsonb,integer)` takes
owner, observation, displayed ticket and context version 1. Its closed result is
`{context_version:1,source_kind,displayed_ticket,scan_context}`, bounded to 128
KiB. It has no message/conversation identifier or prefix. Explicit legacy null
supports PostgREST SQL NULL; an enrolled observation requires its exact selected
analysis/global/review ticket. Missing imported fields remain missing, and
damaged history cannot use mutable scan data.

The private derivation helper is shared with final atomic admission, which
revalidates authority after preflight. Preflight consumes no daily/conversation
capacity or provider quota and grants no execution, eligibility or entitlement.
Only final admission reads and stores the prior-message prefix; final snapshot
overflow produces `55000 field_chat_context_unavailable` and rolls back the
question and admission count. Exact existing-message replay still precedes fresh
gate/authority checks.

The prepared TypeScript adapter performs one five-second request with
cancellation and retries disabled. Exact `P0002 field_chat_subject_not_found`
maps internally to 404, and `40001 field_chat_context_conflict` to 409. Other
errors, missing routes and malformed results become unavailable 503. This is not
an activated HTTP/native contract. Future integration recovers stored turns
first, then checks fresh immutable eligibility and existing Pro/quota rules
before admission. Transport-ambiguous admission outcomes retain their original
identity and unresolved reservation; they do not authorize unconditional refunds
or successors.

### Prepared immutable Insight semantic adapter

The private version-1 `scan_context` producer now preserves null alternatives
and each alternative's `taxon_rank`. It rejects malformed candidate containers
rather than silently discarding evidence. Optional `metrics_qualified` is a
Boolean computed against original provenance before its allowlist projection:
missing provenance is false, explicit legacy null retains compatibility, and
unknown provider/configuration additions cannot become qualified by sanitation.
Older stored snapshots lack this field and remain unqualified without backfill.

The pure prompt/eligibility adapter accepts decoded prepared or stored context,
uses existing effective-identification and human/biological rules, and keeps
missing V3 encounter values unavailable. Its prompt data excludes operational
IDs, review records and provider configuration. Qualified scores require the
saved true marker, with no later qualification-policy recomputation; descriptive
alternatives remain available when scores are omitted. Stored conversation roles
and text retain their exact order. Preflight has no prefix and cannot fabricate
an admitted turn. Live HTTP/native wiring remains pending and default-off.

### Prepared immutable Insight admission adapter

The internal admission adapter sends one fixed RPC with a five-second deadline
and retries disabled. It validates the original six-field owner/scan/message/
conversation/ticket request, a bounded single-row result, exact message linkage
and the saved context. An existing returned conversation may differ from the
proposed UUID. It retains only message identity/text from the database row;
provider metadata and future table columns do not become prompt context.

Exact SQL error pairs distinguish a rejected transaction from an unknown
outcome. A rejection is not a statement about previous attempts or authorization
to refund quota. Lost replies, malformed success and post-dispatch cancellation
remain unknown. The recovery coordinator may issue one exact read, returning a
separate recovered-context result on success. It never repeats admission or
synthesizes missing daily-count/admission receipt fields. An absent read after
timeout does not prove non-commit; unknown outcomes retain the original identity
and hold. These prepared adapters do not change HTTP/native contracts or enable
provider execution.

Protected execution additionally requires a dedicated quota admission fence:
legacy same-ID quota reopening and stale-chat recovery can authorize another
metered provider attempt, so they are not safe dispatch authority for uncertain
immutable turns. The fence must survive ordinary quota-row pruning and preserve
account merge/deletion semantics. HTTP wiring remains blocked on this execution
contract; existing legacy funding behavior is unchanged.

### Prepared protected Insight quota and context admission

The default-off, service-only
`reserve_protected_insight_chat_quota(uuid,uuid,uuid,text,jsonb,integer,text)`
accepts owner, observation, client-message UUID, normalized question, displayed
ticket, context version 1 and the original IP hash. It rechecks ownership,
deletion, immutable context and current AI consent before first quota admission.
Entitlement and provider quota remain owned by the existing quota core; this
operation consumes no complimentary scan credit. First success returns
`{status: "reserved", reservation_id, lease_token, lease_expires_at, model}`.
Every exact retained replay returns only `{status: "held"}` and cannot authorize
dispatch. `field_chat_execution_unavailable` (55000) is the closed fresh gate;
`field_chat_execution_held` (55000) preserves retired/unknown work and
`field_chat_idempotency_conflict` (23505) rejects altered content or same-owner
request reuse across observations. No public HTTP or native caller is connected.

`reserve_protected_insight_chat_send_with_context` accepts the seven arguments
of `reserve_insight_chat_send_with_context` followed by original reservation
UUID and lease token. It returns the same five-column immutable admission row.
Fresh admission and first message binding commit together under owner/scan locks
and quota-before-fence row locking. Exact receipt recovery precedes gate and
lease checks; erased bindings never reopen. Recovery through the existing
read-only context resolver remains separate and does not expose execution
authority.

The unconnected `contextAdmission.ts` still calls the earlier context-only RPC.
The future protected HTTP owner must use these new funding-bound boundaries and
the dedicated one-time dispatch boundary; it must not treat generic idempotent
quota commit or a recovered context as permission to call the provider again.
Lost replies retain their original identity and hold. No automatic
successor/refund is added.

### Prepared one-time Insight provider dispatch

`grant_protected_insight_chat_dispatch(uuid,uuid,uuid,uuid,uuid)` is
service-only and takes exact owner, observation, client-message, reservation and
lease UUIDs. Fresh permission atomically consumes a permanent marker and commits
original provider quota, returning exactly
`{status: "dispatch_granted", model}`. It requires the original bound immutable
message/context, active execution gate, live original lease and current consent.
It does not revalidate against a newer selected identification. Owner and
deletion checks always apply. A consumed marker returns only `{status: "held"}`
even after quota pruning or gate closure; no stored grant is replayable. Generic
finalizer success is not dispatch authority.

The prepared `protectedExecution.ts` adapter uses fixed five-second RPCs with
transparent retries disabled and caller cancellation before/after each await.
Quota responses expose only the five-field receipt above; raw quota-core rows,
additive fields, unknown models and malformed dates/UUIDs are rejected. Dispatch
responses contain no reusable lease capability. Transport, cancellation, server
error or decoding uncertainty holds the request and never authorizes a provider
call, successor or refund. The adapter is not connected to the HTTP handler yet;
all gates stay false and no public/native wire changes in this slice.

### Protected Insight routing and funded context binding

`get_insight_chat_send_route(owner, scan)` is service-only and returns exactly
`{requires_context: boolean}`. The handler reads it for sends before mutable
scan, entitlement or quota work; client ticket omission cannot select legacy
behavior. Unknown/malformed routing holds with `field_chat_context_unavailable`.
Until the bounded immutable execution owner is connected, required-context sends
return 503 `field_chat_context_required`. No protected provider execution is
enabled. Ordinary unenrolled legacy sends remain available when execution
rollout is off.

The existing public `reserve_field_chat_send` also enforces this boundary in
Postgres, covering old deployed handlers and races after route lookup. Generic
Insight quota commit is fenced again after admission; stale rescue cannot reopen
protected work. `enroll_owned_observation_history` can return 55000
`analysis_history_chat_in_progress` for a committed legacy attempt without its
exact assistant receipt. Retrying enrollment cannot fabricate that receipt or
release provider quota. Existing enrollment replay remains historical.

`protectedContextAdmission.ts` calls only the funding-bound nine-argument
`reserve_protected_insight_chat_send_with_context` RPC. It freezes the full
original request and reservation/lease pair, parses the existing closed
five-column response, and labels replay separately from fresh admission. Unknown
writes allow at most one exact context read: recovered or absent context grants
no dispatch permission, new write or refund. Caller cancellation bounds each
five-second request, with automatic retry disabled. Unfunded context admission
is a building block for the atomic deterministic refusal routine below; invoking
it alone neither completes a refusal nor authorizes provider execution. An
unknown or partially saved refusal must never become a provider call.

### Prepared exact chat completion and deterministic refusal

`get_insight_chat_turn_completion` takes the original recovery arguments plus
expected user-message UUID and conversation UUID. Its fixed result is
`{context_version:1,completed:false}` or
`{context_version:1,completed:true,message}`. The ten message fields match the
existing public projection: `id`, `conversation_id`, `scan_id`, `role`, `text`,
`client_message_id`, `model`, `is_refusal`, `refusal_reason`, `created_at`. Role
is assistant; the exposed client-message ID is the original request ID, not a
new operation. Response is bounded to 32 KiB, text to 4,000 characters, model to
200 and reason to 100. No safety metadata, stored prompt or quota receipt
escapes. Incomplete grants no permission. Missing or incompatible original
evidence holds.

`admit_insight_chat_local_refusal` accepts the seven unfunded context-admission
arguments plus one closed reason: `foraging_or_ingestion`,
`medical_or_veterinary`, `dangerous_handling`, or `legal_or_collection`. SQL
owns the fixed answer, null model/usage and exact refusal/request metadata. It
returns the same completed receipt, never partial success. Normal chat capacity
is consumed once; provider quota is untouched. Existing incomplete/provider
turns remain held, and changed text/ticket conflicts. Exact static replay
precedes fresh gates. Cross-scan request reuse or an existing provider attempt
cannot become a fresh refusal.

`exactCompletion.ts` uses fixed five-second RPCs, caller cancellation and
`retry(false)`. It strictly checks deterministic UUID and receipt linkage; the
refusal decoder also verifies the closed answer/reason/model. A known rejection
describes only that transaction. Lost, malformed or canceled write replies stay
unknown and are never automatically retried or refunded. Recovery orchestration
will read original context and its exact completion; neither absence nor
incompleteness may authorize a replacement. These adapters remain prepared;
protected HTTP still holds before mutable reads.

### Prepared original-grant chat reply persistence

Service-only `complete_protected_insight_chat_reply` and
`get_protected_insight_chat_reply` take the original eight exact-completion
arguments plus `p_reservation_id`, `p_lease_token` and `p_reply`. The reply is a
closed object: `answer` (1–4,000 characters), fixed `gemini-2.5-flash` model,
`is_refusal`, nullable bounded `refusal_reason`, and nullable `usage`.
Non-refusal reasons must be null. Usage contains exactly five nullable
nonnegative int32 counts (`prompt_tokens`, `candidate_tokens`,
`thinking_tokens`, `total_tokens`, `cached_tokens`) and `modality_breakdown`.
Its four maps (`prompt`, `cached`, `candidates`, `tool`) contain only
text/image/audio/video/document/unspecified nonnegative int32 counts. Arbitrary
provider metadata is rejected.

The fixed public completion receipt excludes accounting and private metadata,
but SQL verifies their full equality on recovery. The prepared
`protectedReply.ts` adapter freezes all original arguments, disables retries and
uses a five-second call bound within the parent signal. An unknown write permits
one exact full-payload read only; absent, changed or uncertain recovery stays
unknown. It never writes again, dispatches, refunds or creates a successor. The
protected HTTP execution owner now uses this module.

### Protected Field Chat send HTTP protocol, version one

For server-required immutable sends, `insight-chat` accepts exactly `action`
(`send`), `context_version` (`1`), lowercase UUID `scan_id`, `conversation_id`
and `client_message_id`, normalized 1–600-character `message_text`, and an
explicit `displayed_ticket` (null for a legacy immutable snapshot, otherwise
exact `analysis_id`, `state_revision`, `review_revision`). No new UUID or ticket
is inferred after uncertainty. Server routing precedes mutable scan/thread
reads; client omission cannot choose legacy, and explicit protected fields on a
legacy route fail closed instead of starting a legacy request.

Success is the closed `{data:{context_version:1,completed:true,message}}`
receipt, not the legacy conversation envelope. `message` has exactly `id`,
`conversation_id`, `scan_id`, `role`, `text`, `client_message_id`, `model`,
`is_refusal`, `refusal_reason`, `created_at`. Its deterministic assistant UUID
binds returned conversation and original request. The proposed conversation may
resolve to an existing owned conversation at atomic admission. No context,
usage, current-selection projection, thread messages or quota estimates are
returned. Native `decodeProtectedCompletion` validates this separate 32 KiB
contract, including the fixed provider model and valid local-refusal
combinations; existing conversation decoding and ordinary access stay unchanged.
Native persisted send-ticket delivery is still required before coordinated
activation.

Existing turns recover before fresh eligibility or Pro. Fresh sends preserve
immutable eligibility → Pro → local safety → protected quota → context admission
→ one-time grant ordering. All prompts use the final saved context and prefix.
Unknown admission, provider or completion never authorizes automatic redispatch,
refund or a replacement request. Incomplete exact recovery returns held (503);
stale immutable context and request conflicts remain explicit errors. Every
protected success/error is no-store. The request budget is measured from entry;
provider dispatch requires five-second grant, 90-second provider and 15-second
persistence/recovery headroom plus a two-second margin. A confirmed grant
invokes once within the remaining provider window, preserving completion time.
Provider HTTP uses actual cancellation, no retries, no redirects and a 32 KiB
response limit. All activation gates remain false.

The prepared native enrolled subset requires a nonnull selected ticket. It
bounds revisions to 2,147,483,646, review revision to the displayed global
revision, and text to 600 UTF-16 code units with exact ECMAScript trim
semantics. It preserves Unicode bytes and canonical sorted-key JSON in a
version-one owner-private intent. The canonical SHA is a local drift check only.
Terminal receipts are validated against the original observation/client-message
and retained without substituting their resolved conversation for the original
proposal in a retry.

Native staging is atomic and inert: exact message-ID replay first, then fresh
selected-result proof/authority, pending-selection/review and unfinished-chat
checks. Message IDs cannot move between observations. Namespace erasure is part
of direct, bulk and owner-qualified cloud deletion. No schema shape changes or
automatic scheduler eligibility are introduced. Native claims and atomic receipt
acknowledgement are prepared; dedicated transport and lifecycle are connected
below, while UI remains required before activation. Initial claims accept
pristine work only. Unknown outcomes hold without a wake deadline; explicit
replay must match the previous local attempt while preserving the exact original
request. Claim expiry denies new dispatch but permits an unchanged late receipt.
Replaced attempts cannot acknowledge, and terminal receipts never reopen. These
local attempts do not authorize provider successors. No gate is enabled.

The prepared native protected chat transport now sends one exact saved request
through a closed typed mutation boundary. It bypasses the legacy 45-second
retrying executor. A scoped pinned session permits 145 seconds and bounds actual
received bytes to 32 KiB; the ordinary session retains its 90-second resource
ceiling. Redirects, automatic 401 refresh, transient retry and route retry are
forbidden. Owner and claim validation follows Auth before dispatch, and a
separate response fence validates the unchanged attempt. Dispatch requires the
full 145-second wire budget, 15-second local receipt reserve and two-second
margin inside the original claim. Late exact replies can still reach atomic
acknowledgement; the transport does not extend expiry or mint identities.
Retained delivery and Auth teardown now use this transport through explicit
injected admission; actual send UI remains unconnected. All activation gates
remain false.

Native `ProtectedInsightChatReply` retains the validated completion alongside
original bounded receipt bytes for atomic persistence, preserving required null
fields. Both session and task authentication challenges share the existing
certificate-pin validator. Successful JSON MIME validation precedes body
acceptance, and a final synchronous budget check precedes task start. The scoped
session has no credential store; ordinary transport policies remain unchanged.

Native `ProtectedInsightChatDeliveryService` reads only terminal local receipts
before claiming. Initial admission cannot reopen held/running work; explicit
replay requires the prior exact attempt and unchanged request. The retained
owner distinguishes cancelled dispatch from valid same-account settlement of a
known reply. Account/container/claim changes still reject receipt persistence.
Both Auth quiescence paths await actual lease release. Unknown outcomes have no
retry deadline, and ordinary scheduler recovery never starts them. Save
uncertainty checks for a committed exact local receipt before holding the
original claim. No mutable conversation or observation selection is projected. A
failed HTTP status never proves no admission or authorizes replacement intent;
only the exact stale-ticket no-admission receipt described below can retire that
request. Other uncertain outcomes remain held.

Native restart discovery is local and read-only. It validates all scoped saved
requests in bounded fetch batches and returns at most 20 immutable completion
receipts in canonical client-message UUID order, independently of the unique
unfinished operation. Off-page corruption or multiple unfinished operations
fails closed; a partial page never grants new-message admission. Historical
requests keep their original tickets after selection/review changes. Prepared
selected-chat access validates the actual displayed baseline before constructing
a new ticket, with a second context check around the exact child read. It is
installed only in the inert History bundle; ordinary access stays nil and no
remote read-before-claim path is introduced.

The prepared native composer now stages synchronously before queue handoff and
retains the original candidate on save uncertainty. Explicit pending delivery
uses the saved intent without another UUID; held or expired-running recovery
uses an exact claim. A newly supplied ticket that differs from the session's
frozen displayed ticket can only read an already saved exact request. Closing
presentation does not cancel durable delivery. Local pages contain original
questions and immutable receipts, never a reconstructed mutable thread. These UI
connections remain behind the disabled complete History installation gate;
explicit refreshed-authority presentation and runtime qualification remain open.

### Prepared exact chat no-admission proof

The service-only `seal_unadmitted_insight_chat_request` RPC is a separate
prepared recovery boundary. It accepts the exact original request tuple and
returns either `{status:"held"}` or the closed six-field receipt with
`status:"not_admitted"`, `context_version:1`, `scan_id`, `conversation_id`,
`client_message_id` and `reason:"displayed_identification_changed"`. The server
independently proves the stale displayed ticket under admission locks and
permanently prohibits that request from entering any context or quota writer.
Existing attempt evidence never becomes this receipt. Lost replies use the
service-only five-second, retry-free `get_insight_chat_no_admission` read with
the same exact tuple. It returns `not_admitted`, `held`, or `fresh_candidate`;
the last only permits subsequent fresh preflight, never admission or dispatch. A
generic error, absent context, timeout or cancellation is not proof. Proposed
conversation is immutable request correlation only.

The proof neither refunds provider usage nor authorizes another execution. A
future native consumer may retire only its matching saved request; a new
question requires a separate explicit tap and current displayed ticket. The
prepared protected HTTP owner recovers stored completion first and existing
seals second, before fresh gates/eligibility/Pro. Only a typed stale-ticket
preflight denial calls the seal writer; a held or unknown write cannot settle.
The distinct terminal HTTP 200 shape is:

```json
{
  "data": {
    "context_version": 1,
    "outcome": "not_admitted",
    "scan_id": "<original observation UUID>",
    "conversation_id": "<original proposed UUID>",
    "client_message_id": "<original message UUID>",
    "reason": "displayed_identification_changed"
  }
}
```

The existing completed-assistant receipt is unchanged. No assistant, thread,
quota or refund is synthesized. Native now strictly decodes this outcome
separately and persists it in a version-two intent with an explicit terminal
kind. Version-one assistant intents remain readable without rewriting. Exact
same-running-claim acknowledgement atomically saves proof and completes the
operation; unknown errors remain held. Every nonterminal HTTP call still needs a
claim. Fresh admission rejects a new UUID with a selection tuple already proved
stale, across restart and all status pages. Only actual updated authority and a
new explicit tap can permit a new question; the dedicated refresh action remains
to be connected. All activation gates remain closed.
