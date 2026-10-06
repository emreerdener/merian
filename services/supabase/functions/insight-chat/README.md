# insight-chat

Private Pro follow-up chat for completed biological Insight sheets.

## Contract

The function accepts authenticated POST requests with:

- `action: "load" | "send" | "delete"`
- `action: "feedback" | "feature_feedback" | "summarize_notes" |
  "suggest_prompts"`
  for answer feedback, sheet-level feature feedback, field-note drafts, and
  AI-generated quick prompts
- `scan_id`: owned `public.scans.id`
- `message_text`: required for `send`, capped at 600 characters
- `client_message_id`: required UUID for idempotent sends

Every success response returns `data.subject_id` with the exact requested scan
UUID. Thread responses also return `data.conversation_id`, ordered
`data.messages`, and `data.limits`. Each scan has at most one saved chat
conversation per user. `suggest_prompts` returns `data.prompts`, three
non-persisted prompt chip suggestions with allowlisted telemetry categories.
Prompt generation is best-effort and independent from `load` / `send`; iOS falls
back to local deterministic chips if this action fails.

## Durable Scan Prerequisite

Every action reloads the scan by both `scan_id` and authenticated owner. The row
must be a completed non-Human biological observation; a local iOS record, an
ingestion job without its scan, another owner's UUID, or a media-only staging
generation is not chat context. Legacy rows check the confirmed species relation
before the original relation and reject unresolved placeholders such as “Unknown
Subject,” “Taxonomy Unavailable,” “Unidentified Wildlife,” and “No Wildlife
Detected.” Explicit primary rows use the validated effective identity and
support broader or unresolved biological subjects. Both paths reject
`is_biological_subject=false` and Human aliases in selected taxonomy or the user
override. Neither infers eligibility from `ai_reasoning` or trusts the client
toolbar state.

Current scan-producer `200` guarantees this row already exists. Before opening
an older local Insight, iOS preflights `/check-scan-status`. Eligible historical
drift may use that route's bounded non-media owner recovery, while
processing/retryable ingestion, policy rejection, deletion, and ambiguous state
remain closed. `/insight-chat` itself does not create a scan, restore media, or
accept `recovery_scan`.

A handler-owned missing/not-ready scan returns `404 scan_not_ready`. The client
shows a retryable still-syncing message and keeps the Field Chat affordance
available. A Supabase platform `404 NOT_FOUND` without `X-Merian-Handler: 1`
means this route did not execute and must remain a temporary
service-availability failure; it is not evidence that the scan is missing. An
owned but unsupported Human, unresolved, or non-biological row returns
`400 unsupported_scan`; reloading or direct endpoint access cannot bypass that
classification guard for legacy rows. Valid explicit genus/family/unresolved
biological snapshots remain eligible after primary/provenance/review validation.
Their prompt states the original rank and labels, separates an independently
verified selected taxon from pending review, and keeps original reasoning and
confidence attached to the original answer. Species relations are used only when
they match the validated effective species ID.

## Privacy

Chat context is assembled server-side from stored text evidence only: species
names, taxonomy, hazard type, confidence, candidates/lookalikes, habitat,
Wikipedia overview, invasive flag, review/provenance state, observed traits,
ecological annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata.

Answers, prompt suggestions, and field-note drafts also receive saved
`extracted_visual_traits` under `AI-extracted observation traits`. Entries are
trimmed, non-string/empty values are discarded, and output is limited to ten
traits, 500 characters per trait, and 2,000 characters including quoting and
separators. Missing or empty traits are `Unavailable`. Traits are quoted data,
not instructions: they remain fallible original AI observations even after a
user correction and cannot establish measurements without supporting scale
evidence. This uses existing scan records without reanalysis or raw-image
access.

Do not add raw image bytes, R2 object keys, cloud image URLs, Explore comments,
public post metadata, or Darwin Core export payloads to the prompt.

Saved inference tier and execution provenance are read only to qualify metric
interpretation. Legacy SQL-null and exact known Gemini configurations at policy
version 1 retain their existing scores. Missing or unknown metadata omits
primary, candidate, sex/invasive confidence and model image-quality values from
answers, suggestions and field-note context. Bounded candidate names/features
and other saved evidence remain usable; confirmation does not qualify a model
score. Full provider configuration never enters the prompt. Local blur and zoom
values remain capture measurements. The shared predicate is tested against the
SQL compatibility policy.

## Rollout and Limits

- Apply `20260729163616_reserve_field_chat_sends_atomically.sql` before
  deploying either chat function. The additive `subject_id` response expansion
  and assistant request-pair projection must then ship to both `insight-chat`
  and `explore-post-chat` before the hardened iOS validator. Existing clients
  ignore the extra response fields; corrected clients reject an old response
  without its subject or current send pair. Verify empty `load`, every action,
  same-UUID ambiguous replay, same-conversation different-key concurrency, cap
  boundaries, and stale recovery before lifting the iOS release hold.
- Apply the compatible follow-up
  `20260730180000_bind_field_chat_rows_to_subjects.sql` before release
  acceptance. It removes only impossible historical cross-bound private rows,
  binds every retained Insight conversation to its exact scan owner, then
  enforces exact conversation/scan-or-post/user and copied-feedback identity
  with validated deferred composite foreign keys. Conversation-optional feature
  feedback is independently bound to its exact scan owner. The migration also
  revokes the legacy authenticated Data API surface from Insight answer and
  feature feedback; all current writes remain through these authenticated Edge
  routes.
- The current three-family bundle also requires
  `20260821030027_add_species_dictionary_field_chat.sql` before deploying this
  updated `insight-chat`, even if `species-dictionary-chat` remains held. Apply
  `20260824210544_preserve_field_chat_daily_usage.sql` next. It makes the
  content-free user/day aggregate authoritative for response shaping and atomic
  admission, so cascading conversation deletion cannot restore allowance. The
  shared helper fails closed through the service-only aggregate RPC and never
  falls back to live message rows. The migration registers and asserts its Ghost
  handler, short-locks all three conversation/message families to remove
  historical message-less threads, moves conversation creation into atomic
  admission, and blocks novel sends through the next database-observed UTC
  boundary while permanently reserving conversation insertion for the atomic
  RPC. Crossing the boundary yields a closed `ready` state; a one-way
  service-only transition records the exact clean candidate and migration digest
  plus all three candidate-derived bundle digests only after every route returns
  both `X-Merian-Field-Chat-Contract: atomic-admission-v1` and its exact
  `X-Merian-Field-Chat-Bundle-SHA256`. A database `ready` state force-selects
  the entire Field Chat fleet even when the migration is already the deployment
  baseline. Keep the release hold active until non-skipped three-family,
  full-merge, cutover, live-provenance, and no-orphan evidence is retained.
- Requires durable effective Pro entitlement. Active store subscriptions,
  receipt-backed free trials, and explicitly approved finite RevenueCat beta
  promotions unlock Field Chat only after the provider entitlement is projected
  to `public.users.subscription_tier = 'pro'`. RevenueCat's developer project
  plan and client-only state grant no access. The beta operation is
  [release-held](../../../../docs/incidents/2026-08-revenuecat-customer-identity-drift.md)
  until its identity and cohort controls pass. Model replies, prompt
  suggestions, and field-note summaries reserve separate database quota
  operations before provider dispatch. The independent, exactly verified
  `pro_complimentary` functional tier also satisfies the chat gate while an
  available credit or active hold remains. It retains the original scan linkage
  without acquiring another scan credit and does not create RevenueCat Pro or a
  paid badge. `pro_trial` remains historical only after entitlement cutover.
- `client_message_id` is the durable request identity for sends. The function
  canonicalizes it to lowercase, records it privately on both sides of the saved
  user/assistant pair, and projects it as `client_message_id` on both response
  messages. Reusing a UUID with different normalized message text returns
  `409 field_chat_idempotency_conflict`; this binding is rechecked when a
  duplicate insert races the initial read and again before a waited replay is
  returned. New user rows go through the atomic reservation RPC, which locks the
  user before the conversation and owns exact replay/conflict, the combined
  Insight/Explore/Species Dictionary daily count, unanswered-request fencing,
  capacity, and insert in one transaction. A duplicate, quota-layer replay,
  automatic transport retry, or user retry first coalesces into that exact saved
  pair. Assistant rows use a deterministic UUIDv8 derived from conversation and
  request identity, so concurrent local refusals and ambiguous inserts cannot
  persist a second answer. An in-flight replay waits for the original answer
  within a bounded window and otherwise returns retryable
  `503 field_chat_send_in_progress`; a failed provider or assistant-persistence
  attempt can resume under the same UUID without inserting a second user
  question. If quota is committed but the assistant remains absent for ten
  minutes, narrow exact-row-bound recovery can fail only that reservation before
  a newly metered retry. Suggestions and summaries accept the `Idempotency-Key`
  header. Local safety refusals do not invoke the provider and therefore do not
  consume AI quota, but a newly admitted refusal still counts toward the Field
  Chat send limit.
- Uses `gemini-2.5-flash`, `maxOutputTokens: 700`, no streaming, no Google
  Search grounding, and thinking disabled. Every persisted assistant answer is
  nonempty and capped at 4,000 Unicode code points before it reaches either chat
  table.
- Each scan has one saved conversation per user, capped at 30 persisted rows. A
  new send reserves room for its user and assistant rows together; a retry that
  already owns the user row adds only the missing assistant and must still have
  that one slot available. All Insight chat sends share the 20 sends per Pro
  user per day limit across Insight, Explore, and Species Dictionary. Migration
  `20260821030027_add_species_dictionary_field_chat.sql` extends the existing
  atomic admission and stale-recovery RPCs to that third family without changing
  this route's request or response fields.
- Quick prompt suggestions are generated asynchronously from saved text context
  and recent chat history, then regenerated after successful chat turns. Prompt
  generation does not consume the user send limit and falls back to local iOS
  suggestions if unavailable. Generated prompt text should stay short enough for
  chips and must avoid edible certainty, medical/veterinary treatment, illegal
  collection, pesticide/poison instructions, exact-location requests, and
  human-subject identification.

## Safety

The system prompt states the assistant has no raw image access. Shared
`_shared/fieldChat/speciesKnowledge.ts` rules allow well-established species
knowledge to answer general questions, such as typical flower fragrance, even
when the saved scan or dictionary does not contain that detail. Answers preserve
identification uncertainty and relevant individual or cultivar variation; claims
about this observation require recorded evidence or an explicit user
observation. General knowledge does not authorize current/local claims, invented
citations, or claims of live source retrieval.

The answer rules follow the complete saved-context block. They explicitly treat
casual pronouns in questions such as `Do they smell good?` as species-level when
the user did not ask about the current individual, define `Unavailable` as a
record limitation rather than a knowledge limitation, and require the direct
species fact before any qualification. Few-shot examples demonstrate the
difference between a general fragrance question and the unobservable scent of a
particular flower. Field-note summaries and generated prompt chips use a
separate support instruction without chat-answer examples or response schema.

Local deterministic guards refuse or redirect edible/foraging certainty, medical
or veterinary treatment, dangerous handling, illegal collection,
pesticide/poison instructions, and human-subject identification.

`buildFieldNotesSummaryPrompt` limits drafts to recorded scan evidence and
explicit observations reported by the user. General species facts from the
dictionary or assistant answers, unanswered questions, hypotheticals, and
suggested checks must not become recorded observations.

Field-note summaries remove canonical internal UUIDs across all UUID versions,
including the UUIDv7 identifiers used by current scan and chat flows. iOS
independently rejects a summary that still contains one, so a sanitizer
regression cannot become a successful note draft. If privacy scrubbing removes
the entire model draft, the server returns a bounded non-sensitive fallback
instead of an empty successful payload.

Send-time and generated-prompt filtering match direct unsafe action intent
rather than isolated terms. Requests to harvest or handle an observation remain
excluded, while educational questions about poison ivy habitat, tea plants,
animal foraging, bee stings, or why handling is discouraged remain available for
an ordinary grounded answer.

iOS treats each HTTP `200` as candidate evidence. It requires `subject_id` to
match the requested scan before an empty or populated thread can replace local
state, feedback can show as saved, a summary can become a note draft, or prompt
chips can be used. A successful send additionally requires exactly one saved
user message and one saved assistant message carrying its original
`client_message_id`; trimmed/nonempty message text is capped at 4,000
characters, and JSON decoding is refused above 1 MiB. Manual retry preserves the
failed request UUID. This prevents a valid response from another in-flight
scan—or an incomplete replay—from becoming a false local success.

## Verification

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/fieldChat/reservation_test.ts \
  services/supabase/functions/_shared/fieldChat/response_test.ts \
  services/supabase/functions/_shared/fieldChat/reply_test.ts \
  services/supabase/functions/insight-chat/eligibility_test.ts \
  services/supabase/functions/insight-chat/guards_test.ts \
  services/supabase/functions/insight-chat/prompt_test.ts \
  services/supabase/functions/insight-chat/promptSuggestions_test.ts

deno test --frozen --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_field_chat_answers_test.ts

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/fieldChatReservationMigrationContract.test.ts

deno check --frozen --config services/supabase/functions/deno.json \
services/supabase/functions/insight-chat/index.ts
```

After local checks pass, run the optional provider behavior check with the
approved paid Gemini test key configured outside chat:

```bash
deno run --frozen --config services/supabase/functions/deno.json \
  --allow-env=GEMINI_PAID_API_KEY,GOOGLE_SDK_NODE_LOGGING,GOOGLE_GENAI_USE_VERTEXAI,GOOGLE_GENAI_USE_ENTERPRISE,GOOGLE_API_KEY,GEMINI_API_KEY,GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_LOCATION,GOOGLE_VERTEX_BASE_URL,GOOGLE_GEMINI_BASE_URL,WS_NO_BUFFER_UTIL,WS_NO_UTF_8_VALIDATE \
  --allow-net=generativelanguage.googleapis.com \
  services/supabase/scripts/evaluate_field_chat_answers.ts --live
```

The check makes nine paid calls using synthetic Desert Rose context: a general
fragrance question, the same question after a prior context-only deflection, and
an individual-scent question across all three routes. It reports only case IDs
and stable failure codes; it never prints or stores provider answers. A missing
key exits before the SDK is imported or any call is made. This smoke check
detects the reported response pattern but does not replace factual review or the
hosted authenticated-wrapper release evidence.

The upstream owner-row, retry, recovery, and deployment guarantees are
documented in
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#field-chat-readiness).

## Prepared immutable turn admission

The default-off database RPC `reserve_insight_chat_send_with_context` atomically
stores the admitted question and its bounded immutable context. It preserves the
existing daily/conversation caps and exact message identity. Context follows the
message through account merge and cascades with deletion. History admission uses
the displayed selected analysis and global/review revisions; imported missing
encounter fields stay unavailable instead of borrowing mutable parent metadata.
Snapshot replay precedes fresh authority checks, while owner/deletion checks
still apply. Old messages without a snapshot are held, never reconstructed.

This storage slice does **not** change the live handler or provider recovery.
Before activation, connect the handler to the new admission result, build every
recovered answer from its saved snapshot/prefix, add strict HTTP/native ticket
contracts, and prevent the old mutable execution path for enrolled sends. No
provider successor, refund or new quota authority is introduced here.

Database/static/concurrency contracts live in `insight_chat_turn_context.sql`,
`insightChatContextMigrationContract.test.ts` and
`insightChatContextConcurrencyDb.test.ts`. The canonical
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-immutable-insight-admission-protocol)
and
[schema](../../../../docs/backend-and-data/04-database-schema.md#prepared-immutable-insight-field-chat-turn-context)
describe bounds and denial behavior. Raw library `field_notes` are not part of
this snapshot; the existing captured `user_observation_context` has its own
explicit text allowlist.

### Prepared read-only recovery

`get_insight_chat_turn_context` resolves an exact owner, observation,
client-message UUID, normalized question, original displayed ticket and version.
A missing message returns `{context_version:1,found:false}` without creating a
conversation or consuming a send. An existing message returns its original
context before any current authority or rollout checks. Uncontexted old messages
remain held. Ownership and deletion are checked first; surviving merged messages
resolve under their current owner. Explicit JSON-null legacy tickets cross
PostgREST as SQL NULL and are normalized by this resolver.

`storedContextContract.ts` and `storedContext.ts` decode a bounded, closed
storage shape, validate message/ticket association and return detached frozen
data. Missing V3 fields remain absent. `storedContextRepository.ts` performs one
fixed RPC with a five-second deadline and caller cancellation; malformed
success, unknown errors and missing routes never become `found:false`. Only
exact SQL code/message pairs classify missing subjects, uncontexted turns or
idempotency conflicts. This is a prepared internal adapter, with no live handler
import.

Future send integration must recover before the global mutable scan fetch and
before stale-quota recovery. A genuinely absent turn needs read-only immutable
eligibility preflight, existing Pro/provider-quota checks and then atomic
admission with final ticket revalidation. Admission is never a recovery probe.
Prompt construction must use only the saved snapshot/prefix and apply existing
semantic authority and metric qualification; structural decoding alone grants no
execution authority. Native retry must retain the displayed ticket verbatim,
with an explicit restart-durability design before claiming restart recovery.

`insight_chat_context_recovery.sql`,
`insightChatRecoveryMigrationContract.test.ts`,
`insightChatRecoveryConcurrencyDb.test.ts` and
`insightChatStoredContext.test.ts` cover no-slot probes, original-context
recovery, merge/deletion, concurrent admission/deletion, strict decoding and
transport cancellation. All activation gates remain closed.

### Prepared fresh-context preflight

`prepare_insight_chat_send_context` is a service-only, default-off read that
returns version, source kind, exact displayed ticket and sanitized
scan/dictionary context. It accepts only owner, observation, ticket and version:
no conversation, message UUID or question. It does not read a conversation
prefix, reserve a send, check entitlement, reserve provider quota or grant later
execution permission. The private `prepare_current_insight_chat_context` helper
performs the same locked authority derivation for preflight and final atomic
admission.

Final admission preserves exact replay first, then reruns that helper. Only it
freezes the prior-message prefix. It checks the final 128 KiB bound explicitly
before inserting context; an overflow rolls back the question and daily slot
with `field_chat_context_unavailable`. PostgREST SQL-null legacy tickets are now
normalized consistently in preflight, final admission and recovery.

`preparedContext.ts` validates a closed response against the original ticket,
keeps missing historical fields unavailable and never fabricates a prefix or an
admitted message. Its fixed RPC has a five-second deadline, caller cancellation
and no retries. It maps only exact subject-not-found and context-conflict pairs;
unknown errors and malformed output remain unavailable. HTTP/native integration
is still pending. New sends must recover first, then apply pure immutable
eligibility and existing Pro/quota checks before final admission. Lost admission
replies cannot trigger an unconditional refund or a new provider identity.

The SQL catalog `insight_chat_context_preflight.sql` and the
`insightChatPreflight*`/`insightChatPreparedContext` tests verify no-slot
preflight, exact replay, missing historical data, final size rollback and real
preflight/authority/admission/deletion races.
