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

The daily allowance is an admission-history contract, not a content-retention
contract. Deleting a conversation may erase its private messages, but must not
restore sends already admitted that UTC day. The current candidate still derives
daily usage from live user-message rows, whose conversation cascade can erase
that evidence. This is a release blocker until admission uses durable,
delete-resistant accounting and a delete-then-send test proves the allowance
cannot be reset.

## Storage and rollout

Migration `20260821030027_add_species_dictionary_field_chat.sql` adds the three
Edge-only tables, validated composite subject/conversation/viewer bindings, RLS
defense in depth, least-privilege service grants, account-merge handling, the
`species_dictionary_chat_reply` quota matrix, and the three-family atomic
admission and stale-recovery definitions. Same-key retries replay one saved
pair; different text with the same UUID conflicts; another unanswered request is
fenced; and a ten-minute-stale committed provider claim can recover only after
exact user-row and absent-assistant proof.

Because the current `insight-chat` and `explore-post-chat` bundles also import
the three-family daily-usage helper, apply this migration before deploying any
updated `insight-chat`, `explore-post-chat`, or `species-dictionary-chat`
Function from this candidate. Deployment and production mutation require
separate release authorization; implementing or validating this route does not
authorize either operation.

## Candidate Release Blockers

This source implementation is not release-ready until all of the following are
fixed and proven:

- daily admission survives deletion of any Insight, Explore, or Species
  Dictionary conversation;
- iOS includes `species-dictionary-chat` in its audited idempotent ambiguous
  transport/`5xx` replay allowlist. The request already sends `Idempotency-Key`,
  and manual retry preserves the UUID, but automatic replay does not currently
  run for this route;
- authenticated executable handler tests cover every action, Pro enforcement,
  invalid and unavailable species, response echoes, replay/conflict/in-flight
  recovery, and ownership. The current route-contract test inspects source text
  and is not included in the deploy workflow's focused Function test list; and
- dictionary refusal copy is fully source-specific and the iOS deterministic
  fallback sanitizes and bounds the display label exactly like the server
  fallback. No scan/observation wording or untrusted overlong label may reach a
  Dictionary thread.

The canonical release checklist and manual Great Egret matrix live in
[`docs/backend-and-data/06-supabase-deployment-runbook.md`](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md)
and
[`docs/features-and-hardware/16-species-dictionary.md`](../../../../docs/features-and-hardware/16-species-dictionary.md).

## Verification

```bash
deno check --frozen \
  --config services/supabase/functions/species-dictionary-chat/deno.json \
  services/supabase/functions/species-dictionary-chat/index.ts

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=. \
  services/supabase/functions/species-dictionary-chat/eligibility_test.ts \
  services/supabase/functions/species-dictionary-chat/prompt_test.ts \
  services/supabase/functions/species-dictionary-chat/promptSuggestions_test.ts \
  services/supabase/functions/_tests/speciesDictionaryChatRouteContract.test.ts \
  services/supabase/functions/_tests/speciesDictionaryChatMigrationContract.test.ts \
  services/supabase/functions/_shared/fieldChatReservation_test.ts
```
