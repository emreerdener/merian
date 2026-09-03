# species-dictionary-chat

Authenticated private Pro Field Chat for an in-app Species Dictionary subject.
Each viewer has at most one saved conversation per canonical species UUID. This
route is separate from the anonymous, cacheable `/species-dictionary` read API;
public web species pages do not call it and remain unchanged.

## Contract

`POST /species-dictionary-chat` accepts `load`, `send`, `delete`, `feedback`,
and `suggest_prompts` with `species_id`. `send` additionally requires a trimmed
`message_text` of at most 600 characters and a UUID `client_message_id` used as
the request body and `Idempotency-Key` identity. Feedback requires an owned
assistant `message_id`, an allowlisted `feedback_rating`, and an optional note
of at most 500 characters.

Every success reuses the strict shared Field Chat envelope. Top-level
`subject_id` is the exact requested species UUID. For iOS compatibility, every
thread message's `scan_id` is also that species UUID. A send succeeds only with
the exact persisted user/assistant pair bound to the request UUID. Feedback and
deterministic prompt responses echo the same subject before iOS applies them.

The route authenticates through `withEdgeHandler` and resolves functional Pro
access server-side. Store-paid Pro, an active receipt-backed trial, an approved
projected promotion, and the exactly verified complimentary functional tier can
qualify. Client-only RevenueCat state and database edits do not authorize the
route. A missing or malformed `species_id` fails request validation with
`400 invalid_request`. A syntactically valid UUID that does not resolve to an
available canonical biological dictionary row returns HTTP `404` with stable
code `species_not_available`; a non-Pro viewer receives `402 pro_required`.

## Grounding and privacy

Every action reloads the canonical `species_dictionary` row. Every send
therefore uses the latest bounded names, taxonomy, Wikipedia overview text,
habitat description, hazard type, conservation status, group tags, and up to six
nonrejected lookalikes with their names, rationale, and visual traits. Source
values are fenced as untrusted reference data and cannot supply instructions to
the model.

Shared `_shared/fieldChatSpeciesKnowledge.ts` rules also allow well-established
general species knowledge, such as typical fragrance or diet, when reference
prose does not cover the question. Answers distinguish typical traits and
individual variation, acknowledge uncertain knowledge, and never imply that
general facts were observed in a particular specimen. This adds no live search
or source retrieval and does not authorize unsupported current/local facts or
invented citations.

The answer rules follow the canonical data block. An `Unavailable` reference
field therefore does not become the final instruction or block a direct
species-level answer. Casual pronouns in typical-trait questions refer to the
dictionary species; questions about a particular individual still require
observation evidence that this route does not receive.

The prompt and database projection exclude Community sightings, observation
charts or counts, scans, field notes, users, locations, media, reference URLs,
licenses, and attribution identities. The route never receives raw image, video,
or audio bytes. Product telemetry omits species names and UUIDs; the private AI
usage ledger retains only the operational conversation/message linkage and the
`species_dictionary` source type, not a species source ID.

Model sends use database-selected `gemini-2.5-flash`, 700 output tokens, JSON
output, no search grounding, and thinking disabled. Local safety refusals and
deterministic prompt suggestions make no provider call. Conversations retain a
30-row cap, and new user sends share one 20-send UTC-day limit with Insight and
Explore Field Chat.

Deterministic prompt labels execute
`docs/contracts/species-dictionary-prompt-label-policy.json` in both Deno and
Swift. The contract counts Unicode scalars, caps the normalized label at 64,
enumerates whitespace and punctuation, accepts U+2013 EN DASH and U+0085 NEXT
LINE, rejects U+FEFF BYTE ORDER MARK, and falls back to `this species` for every
unsupported scalar or boundary violation.

The daily allowance is an admission-history contract, not a content-retention
contract. Deleting a conversation may erase its private messages, but must not
restore sends already admitted that UTC day. Migration
`20260824210544_preserve_field_chat_daily_usage.sql` makes the content-free
`internal.field_chat_daily_admissions` aggregate the intended authority.
Admission increments that user/day row in the same transaction that converges
the subject-bound conversation and inserts the user message; deleting an
Insight, Explore, or Dictionary conversation does not touch it. The service-only
`get_field_chat_daily_usage(...)` RPC shapes responses and fails closed if the
durable count cannot be verified. Ghost coalescing sums both principals under
the shared ordered user locks, and the effective policy allowlist is
source-guarded before the migration re-runs the complete coverage assertion.

## Storage and rollout

Migration `20260821030027_add_species_dictionary_field_chat.sql` adds the three
Edge-only tables, validated composite subject/conversation/viewer bindings, RLS
defense in depth, least-privilege service grants, account-merge handling, the
`species_dictionary_chat_reply` quota matrix, and the three-family atomic
admission and stale-recovery definitions. Same-key retries replay one saved
pair; different text with the same UUID conflicts; another unanswered request is
fenced; and a ten-minute-stale committed provider claim can recover only after
exact user-row and absent-assistant proof.

Migration `20260824210544_preserve_field_chat_daily_usage.sql` then locks all
three conversation/message families for the short cutover, removes historical
message-less threads, lower-bound backfills the current UTC day from retained
user rows, and replaces live-row counting with the durable aggregate for all
future admissions. It adds no retained chat content: private conversation
deletion continues to cascade through messages and feedback. Already-deleted
current-day rows cannot be reconstructed, so production uses the migration's
database-owned cutover. It records the next PostgreSQL UTC-day boundary, rejects
every novel admission before and after that boundary with
`field_chat_admission_cutover_pending`, and permanently revokes direct
conversation insertion from API roles. Exact persisted replays return before
that gate; load, delete, and feedback remain available. The service-only bounded
status RPC exposes only migration/time/state evidence.

The cutover has three fail-closed states. It is `pending` before the recorded
UTC boundary, `ready` after that boundary while novel admissions remain closed,
and `active` only after the workflow successfully deploys all three selected
Field Chat bundles, observes both
`X-Merian-Field-Chat-Contract: atomic-admission-v1` and the exact
candidate-derived `X-Merian-Field-Chat-Bundle-SHA256` on every live route, and
calls the service-only one-way activation RPC. Activation records candidate,
migration, all three route digests, and database timestamp. Database `ready`
force-selects the complete Field Chat fleet even after the migration becomes the
successful baseline. If deployment fails, an old/different bundle is still
serving, or rollover occurs during rollout, the database remains closed; time
alone can never reactivate an older create-before-admission bundle.

Because the current `insight-chat` and `explore-post-chat` bundles also import
the three-family daily-usage helper, apply this migration before deploying any
updated `insight-chat`, `explore-post-chat`, or `species-dictionary-chat`
Function from this candidate. Deployment and production mutation require
separate release authorization; implementing or validating this route does not
authorize either operation.

## Production Release Hold

The candidate includes durable admission, automatic same-key iOS replay after
ambiguous transport/`5xx` failures, post-authenticated handler-core tests, and
Dictionary-specific refusal copy. The source now also includes:

- a source-guarded effective Ghost handler allowlist plus coverage assertion;
- a current-UTC-day concurrency case using the public reservation RPC and full
  merge orchestrator;
- real reserve-delete-fresh-reserve PostgreSQL cases for all three families;
- database-atomic conversation creation, quota admission, and user-message
  insertion, so quota denial leaves no empty conversation;
- a PostgreSQL-clock pending/ready cutover guard plus one-way post-bundle
  activation that records candidate, migration, and all three content-addressed
  bundle digests after live verification;
- one shared executable prompt-label fixture for Swift and Deno, including
  U+2013 EN DASH, U+0085 normalization, U+FEFF rejection, combining marks, and
  exact 64-scalar boundaries; and
- a source hold gate plus protected-Production clearance that downloads each
  reviewed GitHub artifact, recomputes archive and embedded evidence digests,
  validates exact-SHA successful runs, and checks live branch/environment
  protections before mutation.

Production nevertheless remains blocked by the checked-in
`species_dictionary_chat_production_hold` in
`services/supabase/release-holds.json`. Source implementation is not retained
release evidence. The complete disposable-database suite did not execute in the
current review environment because no reachable disposable PostgreSQL service
was available; its database-backed cases explicitly self-skipped and therefore
are not passing evidence. The handler suite now executes the real
`withEdgeHandler` boundary with deterministic accepted and refused
authenticators, but it does not validate a hosted JWT. The real-token HTTP
boundary still needs explicit exact-SHA execution evidence.

Candidate Validation remains available and must run on the reviewed immutable
SHA. The separate pre-production source gate reports a successful `held` status
and `deploy_allowed=false` for a valid active hold, so the conditional
Production job is skipped before its environment, database push, secret
synchronization, Function deployment, or smoke probes can begin. Missing,
malformed, duplicate, and required-ID-absent manifests still fail. The gate
requires this hold ID and a clean exact checkout. A green held workflow does not
mean the backend deployed. If a reviewed manifest later marks the hold inactive,
the sole Production job independently pins and clean-checks the same SHA, then
requires the protected `MERIAN_PRODUCTION_RELEASE_CLEARANCE_JSON` environment
secret before reading ordinary production credentials or mutating Supabase. That
clearance must match the candidate SHA, exact manifest SHA-256, every stable
criterion ID and evidence type, positive artifact IDs, nonzero evidence digests,
and a current approval window. A read-only GitHub audit token verifies two
author-independent current reviews, protected branches without bypass,
self-review-resistant `Release Evidence`/`Production` environments, artifact
bytes, supporting runs, and structured evidence payloads. Statements, embedded
observations, and supporting-run `updated_at` values must be no more than 30
days old, and artifact IDs cannot be reused across criteria. Evidence dispatch
must start from current `main`; manual values enter Bash only through step
environment variables. Keep the hold active until the non-skipped database
suite, wrapper-auth and iOS retry evidence, genuine released-binary V49→V50
physical install-over, both hosted gates on one SHA, live external controls, and
external approvals are complete and retained.

The canonical release checklist and manual Great Egret matrix live in
[`docs/backend-and-data/06-supabase-deployment-runbook.md`](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md)
and
[`docs/features-and-hardware/16-species-dictionary.md`](../../../../docs/features-and-hardware/16-species-dictionary.md).
Evidence authors must also follow the
[`docs/release-evidence` operations guide](../../../../docs/release-evidence/README.md).

## Verification

```bash
deno check --frozen \
  --config services/supabase/functions/species-dictionary-chat/deno.json \
  services/supabase/functions/species-dictionary-chat/index.ts

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-env --allow-read=. \
  services/supabase/functions/species-dictionary-chat/handler_test.ts \
  services/supabase/functions/species-dictionary-chat/eligibility_test.ts \
  services/supabase/functions/species-dictionary-chat/prompt_test.ts \
  services/supabase/functions/species-dictionary-chat/promptSuggestions_test.ts \
  services/supabase/functions/species-dictionary-chat/refusal_test.ts \
  services/supabase/functions/_tests/speciesDictionaryChatRouteContract.test.ts \
  services/supabase/functions/_tests/speciesDictionaryChatMigrationContract.test.ts \
  services/supabase/functions/_tests/fieldChatDurableDailyUsageMigrationContract.test.ts \
  services/supabase/functions/_shared/fieldChatDailyUsage_test.ts \
  services/supabase/functions/_shared/fieldChatReservation_test.ts
```

`handler_test.ts` executes both the handler core and `withEdgeHandler` using
deterministic accepted/refused authenticators. It proves the wrapper
authenticates before binding the user and never enters the route after refusal;
it does not validate a hosted JWT. Database-backed cases are evidence only when
they run against a disposable fully migrated catalog. A connection-refused skip,
source-contract pass, direct counter update, or test-created V49 store does not
satisfy the production hold.
