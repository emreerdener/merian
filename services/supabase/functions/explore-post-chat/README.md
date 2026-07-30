# explore-post-chat

Private Pro Field Chat for any active Explore post visible to the viewer,
including their own. Conversations are per viewer and post, and are grounded
only in the same privacy-filtered public post projections returned by
`get_explore_post` and `get_explore_post_detail`. Only the requesting viewer can
load, send, delete, or rate messages in that conversation; it is not visible to
other viewers.

The function supports `load`, `send`, `delete`, `feedback`, and
`suggest_prompts` actions with `post_id`; `send` also requires a UUID
`client_message_id`. It deliberately excludes owner scan rows, media bytes or
URLs, exact coordinates, comments, and owner chat history.

Explore and Insight chat share the 20-send daily allowance. Unpublishing a post
deletes its Explore chat conversations.

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
serialized before conversation admission, so simultaneous Insight/Explore
requests cannot race the shared 20/day count and different UUIDs in this
conversation cannot both become unanswered. An incomplete retry must still fit
its missing assistant inside that cap. A bounded in-flight wait that cannot yet
find the answer returns retryable `503 field_chat_send_in_progress`. Assistant
text is capped at 4,000 Unicode code points before persistence. The hardened iOS
client requires the exact two-message pair, bounded message text, and a response
body no larger than 1 MiB before clearing its pending send; manual retry reuses
the original UUID. A quota-committed request missing its assistant stays in
progress for ten minutes; afterward, exact-row-bound service recovery may fail
only that reservation and the next provider attempt is newly metered.

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
