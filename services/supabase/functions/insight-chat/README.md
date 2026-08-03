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
must be a completed supported biological observation; a local iOS record, an
ingestion job without its scan, another owner's UUID, or a media-only staging
generation is not chat context.

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
service-availability failure; it is not evidence that the scan is missing.

## Privacy

Chat context is assembled server-side from stored text evidence only: species
names, taxonomy, hazard type, confidence, candidates/lookalikes, habitat,
Wikipedia overview, invasive flag, review/provenance state, observed traits,
ecological annotations, species group tags, `ai_reasoning`, field notes, capture
date/month, location label, weather, elevation, and image/capture-quality
metadata.

Do not add raw image bytes, R2 object keys, cloud image URLs, Explore comments,
public post metadata, or Darwin Core export payloads to the prompt.

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
- Requires durable effective Pro entitlement. Model replies, prompt suggestions,
  and field-note summaries reserve separate database quota operations before
  provider dispatch. Complimentary access uses the `pro_complimentary` policy
  and retains the original scan linkage without acquiring another scan credit;
  `pro_trial` remains historical only after entitlement cutover.
- `client_message_id` is the durable request identity for sends. The function
  canonicalizes it to lowercase, records it privately on both sides of the saved
  user/assistant pair, and projects it as `client_message_id` on both response
  messages. Reusing a UUID with different normalized message text returns
  `409 field_chat_idempotency_conflict`; this binding is rechecked when a
  duplicate insert races the initial read and again before a waited replay is
  returned. New user rows go through the atomic reservation RPC, which locks the
  user before the conversation and owns exact replay/conflict, the combined
  Insight/Explore daily count, unanswered-request fencing, capacity, and insert
  in one transaction. A duplicate, quota-layer replay, automatic transport
  retry, or user retry first coalesces into that exact saved pair. Assistant
  rows use a deterministic UUIDv8 derived from conversation and request
  identity, so concurrent local refusals and ambiguous inserts cannot persist a
  second answer. An in-flight replay waits for the original answer within a
  bounded window and otherwise returns retryable
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
  user per day limit across Insight and Explore.
- Quick prompt suggestions are generated asynchronously from saved text context
  and recent chat history, then regenerated after successful chat turns. Prompt
  generation does not consume the user send limit and falls back to local iOS
  suggestions if unavailable. Generated prompt text should stay short enough for
  chips and must avoid edible certainty, medical/veterinary treatment, illegal
  collection, pesticide/poison instructions, exact-location requests, and
  human-subject identification.

## Safety

The system prompt states the assistant has no raw image access and answers only
from saved scan evidence. Local deterministic guards refuse or redirect
edible/foraging certainty, medical or veterinary treatment, dangerous handling,
illegal collection, pesticide/poison instructions, and human-subject
identification.

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
  services/supabase/functions/_shared/fieldChatReservation_test.ts \
  services/supabase/functions/_shared/fieldChatResponse_test.ts \
  services/supabase/functions/insight-chat/guards_test.ts \
  services/supabase/functions/insight-chat/prompt_test.ts \
  services/supabase/functions/insight-chat/promptSuggestions_test.ts

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/fieldChatReservationMigrationContract.test.ts

deno check --frozen --config services/supabase/functions/deno.json \
  services/supabase/functions/insight-chat/index.ts
```

The upstream owner-row, retry, recovery, and deployment guarantees are
documented in
[`docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md`](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#field-chat-readiness).
