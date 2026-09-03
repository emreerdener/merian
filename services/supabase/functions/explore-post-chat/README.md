# explore-post-chat

Private Pro Field Chat for any active Explore post visible to the viewer,
including their own. Conversations are per viewer and post. Observation evidence
comes from the same privacy-filtered public post projections returned by
`get_explore_post` and `get_explore_post_detail`, plus explicit observations
reported by the viewer in chat. Shared `_shared/fieldChatSpeciesKnowledge.ts`
rules also allow well-established general species knowledge when a detail is
absent from the projection. Typical species traits must not be presented as
observed in this individual, and the assistant cannot claim live retrieval or
unsupported current/local facts. Only the requesting viewer can load, send,
delete, or rate messages in that conversation; it is not visible to other
viewers.

The answer rules follow the public context projection, so an `Unavailable`
projection field limits only claims about the post. Casual pronouns in a typical
trait question refer to the identified species unless the user explicitly asks
about the individual in the post.

Access requires the same durable server-side Pro projection as Insight Field
Chat. An active store subscription, receipt-backed free trial, or explicitly
approved finite RevenueCat beta promotion qualifies only after it reaches
`public.users.subscription_tier = 'pro'`; the RevenueCat developer project plan,
and client-only state do not. The independent, exactly verified
`pro_complimentary` functional tier also qualifies while a credit or active hold
remains, without creating RevenueCat Pro or a paid badge. Beta promotion apply
remains
[release-held](../../../../docs/incidents/2026-08-revenuecat-customer-identity-drift.md)
until the documented identity and cohort controls pass.

The function supports `load`, `send`, `delete`, `feedback`, and
`suggest_prompts` actions with `post_id`; `send` also requires a UUID
`client_message_id`. It deliberately excludes owner scan rows, media bytes or
URLs, exact coordinates, comments, and owner chat history.

Explore, Insight, and Species Dictionary chat share the 20-send daily allowance.
Unpublishing a post deletes its Explore chat conversations.

Every success response echoes the exact requested post UUID as
`data.subject_id`. Thread messages retain the shared iOS compatibility shape
where `scan_id` is that same post UUID, never the owner's private scan UUID. iOS
requires the top-level echo even for an empty/deleted thread and requires both
echoes for every populated thread before replacing local state. Feedback and
prompt suggestions also require the subject echo before showing success or using
generated chips.

Each saved assistant answer is tagged privately with the originating
`client_message_id` and projects that canonical lowercase UUID on its response
message. Reusing the UUID with different normalized text returns
`409 field_chat_idempotency_conflict`, including when contradictory requests
race before either initial read sees the saved user row. The duplicate-insert
and waited-replay boundaries both revalidate the UUID/text binding. Duplicate,
in-flight, and quota-layer replays coalesce into the exact saved user/assistant
pair before reporting success; failed attempts recover under the same UUID
without inserting a second question. Assistant rows use deterministic UUIDv8
identities, preventing a concurrent local refusal or ambiguous insert from
saving a second answer. New sends reserve two of the 30 persisted-message slots
together through the atomic database reservation RPC. Per-user admission is
serialized before conversation admission, so simultaneous
Insight/Explore/Dictionary requests cannot race the shared 20/day count and
different UUIDs in this conversation cannot both become unanswered. An
incomplete retry must still fit its missing assistant inside that cap. A bounded
in-flight wait that cannot yet find the answer returns retryable
`503 field_chat_send_in_progress`. Assistant text is capped at 4,000 Unicode
code points before persistence. The hardened iOS client requires the exact
two-message pair, bounded message text, and a response body no larger than 1 MiB
before clearing its pending send; manual retry reuses the original UUID. A
quota-committed request missing its assistant stays in progress for ten minutes;
afterward, exact-row-bound service recovery may fail only that reservation and
the next provider attempt is newly metered.

Deterministic prompt labels normalize the public common name and use
`this species` when it is empty or longer than 64 characters. This keeps all
three server prompts within the client's 120-character chip contract without
truncating a species name into a misleading label.

Apply `20260729163616_reserve_field_chat_sends_atomically.sql`, then deploy this
additive response expansion and request-pair projection together with
`insight-chat`. Apply the compatible
`20260730180000_bind_field_chat_rows_to_subjects.sql` before release acceptance;
it cleans impossible historical cross-bound private rows, binds retained Insight
conversations to their exact scan owners, enforces exact
conversation/post/viewer and copied-feedback identity with deferred composite
foreign keys, independently binds conversation-optional Insight feature feedback
to its scan owner, and keeps feedback on the Edge-only API boundary. Old clients
safely ignore `subject_id` and the additive assistant request projection; the
corrected client intentionally fails closed when an old function response omits
the subject or cannot confirm its current send pair.

Migration `20260821030027_add_species_dictionary_field_chat.sql` subsequently
extends the same atomic count and stale recovery to Dictionary chat without
changing this route's request or response fields. Apply it before deploying this
updated `explore-post-chat`, not only before the new Dictionary route, because
the shared bundle understands all three subject families. Apply
`20260824210544_preserve_field_chat_daily_usage.sql` next; its content-free
user/day aggregate and service-only read RPC replace live-message counting.
Conversation deletion continues to erase private content without restoring
same-day allowance, and any unverifiable aggregate read fails closed. The
migration registers and asserts its Ghost handler, short-locks all three
conversation/message families to remove historical message-less threads, moves
conversation creation into atomic admission, and blocks novel sends through the
next database-observed UTC boundary while permanently reserving conversation
insertion for the atomic RPC. After the boundary it reports `ready` but remains
closed; only the service-only one-way activation, called after all three
corrected bundles deploy successfully and each live route returns
`X-Merian-Field-Chat-Contract: atomic-admission-v1` plus its candidate-derived
`X-Merian-Field-Chat-Bundle-SHA256`, records the candidate SHA, migration
digest, and all three route digests, then transitions to `active`. Database
`ready` force-selects the entire Field Chat fleet even after the migration is
the deployment baseline. Keep the release hold active until non-skipped
three-family, full-merge, cutover, live-provenance, and no-orphan evidence is
retained.

## Verification

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/fieldChatReservation_test.ts \
  services/supabase/functions/_shared/fieldChatResponse_test.ts \
  services/supabase/functions/explore-post-chat/eligibility_test.ts \
  services/supabase/functions/explore-post-chat/prompt_test.ts \
  services/supabase/functions/explore-post-chat/promptSuggestions_test.ts

deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/migrations \
  services/supabase/functions/_tests/fieldChatReservationMigrationContract.test.ts

deno check --frozen --config services/supabase/functions/deno.json \
  services/supabase/functions/explore-post-chat/index.ts
```
