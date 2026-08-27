# Explore Comment Mentions

Explore comment mentions let a viewer type `@username` inside a comment or reply
to notify an eligible user. Mentions are a notification and profile-linking
layer only; they do not replace the existing Reply button and they do not create
a thread relationship.

## Product Contract

- Comment text remains plain text and stores the user-entered `@username` tokens
  exactly as part of the comment body.
- Resolved mention identity is stored separately in
  `public.explore_comment_mentions`.
- A saved comment can mention at most five unique eligible users.
- Self-mentions are ignored.
- Duplicate mentions of the same user in one comment collapse into one stored
  mention.
- Blocked users, shadowbanned users, and users whose public profile is not
  visible to the viewer are excluded.
- V1 does not support global public-user tagging. The backend resolves only:
  post author, visible participants in the relevant thread, and users the
  commenter follows.
- In replies, visible thread participants are scoped to that reply thread rather
  than every participant on the post.
- Followed-user suggestions require a typed query so the endpoint cannot be used
  as a follower-list browser.

## Database Model

Migrations:

```text
services/supabase/migrations/20260615090000_add_explore_comment_mention_notification_type.sql
services/supabase/migrations/20260615100000_add_explore_comment_mentions.sql
services/supabase/migrations/20260615120000_add_explore_comment_mention_push_preference.sql
services/supabase/migrations/20260808144244_expand_reserved_public_username_policy.sql
```

The migrations add:

- `comment_mention` to `public.explore_notification_type`
- `public.explore_comment_mentions(comment_id, mentioned_user_id,
  mention_username, created_at)`
- `public.get_explore_mention_suggestions(...)`
- `public.comment_mention_projection(comment_id)`
- `public.insert_explore_comment_mentions_from_body(comment_id, actor_user_id)`
- `public.insert_explore_comment_mention_notifications(comment_id)`
- `public.user_push_devices.comment_mentions_enabled`

`explore_comment_mentions` has a primary key on
`(comment_id, mentioned_user_id)` so duplicate tokens cannot create duplicate
rows. `mention_username` is a historical rendering snapshot: it remains the
lowercase, structurally valid token stored in the plain-text comment body even
if the mentioned user later changes handles or that old handle becomes reserved.
The durable `mentioned_user_id` continues to route profile taps and
notifications. Mention notifications use a partial unique index on
`(user_id, comment_id, type)` for `comment_mention` rows.

The snapshot CHECK intentionally enforces only username shape: lowercase ASCII,
3 to 24 characters, a leading letter, a trailing alphanumeric character, and no
repeated underscore. It does not call the current reserved-name policy. Applying
new reservation rules retroactively to this column would either invalidate old
rows or require changing immutable comment text, breaking rendered-link lookup.

This historical exception does not permit a new user to claim or be mentioned
through a newly reserved handle. New mention rows are created only after the
resolver matches a token to a current `public.users.public_username`; current
profile rows remain protected by the policy-aware username CHECK. The stored
snapshot is therefore the handle that was valid when the comment was created,
while `mentioned_user_id` is the durable identity.

Comment and reply read RPCs return a `mentions` JSON array. The array is
additive and may be empty:

```json
[
  {
    "user_id": "uuid",
    "username": "nick_h",
    "display_name": "Nick H.",
    "avatar_url": "https://..."
  }
]
```

`username` is the historical token used to locate the matching span in `body`.
`user_id` remains stable, while `display_name` and `avatar_url` are read from
the current public profile. Clients must key link rendering by the snapshot
`username` and route the tap by `user_id`; substituting the user's current
handle would make an old token stop matching its plain-text body.

## Suggestion Endpoint

`get-explore-mention-suggestions` is an authenticated app-facing Edge Function.
Its Supabase gateway entry uses `verify_jwt = false`; identity is resolved by
`withEdgeHandler`, matching the other Explore app endpoints.

Request:

```json
{
  "post_id": "uuid",
  "parent_comment_id": "uuid",
  "query": "ni",
  "limit": 8
}
```

- `post_id` is required.
- `parent_comment_id` is optional and must be a visible top-level comment on the
  same post when provided.
- `query` is optional. Empty or one-character queries can return the post author
  and visible thread participants, but not followed-user results.
- `limit` is optional and capped server-side.

Response:

```json
{
  "data": [
    {
      "user_id": "uuid",
      "username": "nick_h",
      "display_name": "Nick H.",
      "avatar_url": "https://...",
      "source": "thread"
    }
  ]
}
```

`source` is one of:

- `post_author`
- `thread`
- `following`

The endpoint enforces the same Explore post visibility rules as comment
creation, then applies mention-specific eligibility. It never returns arbitrary
public users who are outside the post, thread, or current viewer's followed
accounts.

## Comment Creation

`create-explore-comment` saves the plain-text body first, then calls
`public.insert_explore_comment_mentions_from_body(...)` for the inserted
comment. The resolver parses syntactically valid username tokens, resolves them
through `public.users.public_username`, filters through mention eligibility,
caps to the first five eligible unique users, stores mention rows, and creates
deduped notifications.

Mention notifications are suppressed when the same recipient already receives a
`comment` or `comment_reply` notification for that exact comment. This keeps a
reply to a post owner or parent commenter from producing two activity rows when
the body also mentions them.

Soft-deleting or moderating a comment removes `comment_mention` notifications
for that comment. Restoring a comment recreates the eligible mention
notifications.

## Push Preferences

Mention notifications can be delivered through APNs when the recipient enables
the independent `Comment mentions` push toggle in Notifications settings.
Explore activity pushes and comment mention pushes both default on for new app
installs. Effective mention delivery requires:

- iOS notification authorization
- the `Comment mentions` push setting
- an active `public.user_push_devices` row for the APNs token

The Edge registration contract accepts `comment_mentions_enabled` in addition to
`explore_enabled`. The field is optional for older clients; when omitted, the
server treats the mention preference like the submitted `explore_enabled` value
for compatibility. `send-push-notification` requires `explore_enabled = true`
for regular Explore activity pushes and requires
`comment_mentions_enabled = true` for `comment_mention` payloads.

This setting controls only remote push delivery. The in-app Explore
notifications feed remains complete and continues to include mention rows.

## iOS Touchpoints

- DTOs and client method: `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
  and `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- Shared comment composer:
  `apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentComposer.swift`
- Mention parsing, replacement, and attributed links:
  `apps/ios/Merian/Features/Explore/Feed/Models/ExploreCommentMentionText.swift`
- Tappable rendered body:
  `apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentBodyText.swift`
- Comment surfaces:
  `apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentsSheet.swift`
  and
  `apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostDetailCommentsSection.swift`
- Typed profile route:
  `apps/ios/Merian/Features/Explore/AuthorProfile/Models/ExploreAuthorProfileRoute.swift`
- Profile destinations:
  `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileContent.swift`
  for parent-owned navigation stacks and
  `apps/ios/Merian/Features/Explore/AuthorProfile/Views/ExploreAuthorProfileSheet.swift`
  for the standalone modal host
- Notification rendering:
  `apps/ios/Merian/Features/Explore/Notifications/Models/ExploreNotification.swift`
  and
  `apps/ios/Merian/Features/Explore/Notifications/Components/NotificationRowView.swift`
- Push preference:
  `apps/ios/Merian/Features/Profile/Settings/Notifications/Views/NotificationSettingsView.swift`
  and `apps/ios/Merian/Core/Hardware/PushNotificationManager.swift`
- Regression tests:
  `apps/ios/MerianTests/Features/Explore/ExploreCommentMentionTextTests.swift`

The composer watches the trailing token. Selecting a suggestion replaces the
active `@query` token with `@username` followed by a space and leaves the
comment as plain text. Rendered comments link only the resolved mention spans
that came back in the `mentions` array. Unresolved `@text` remains normal text.

## Verification

Recommended checks:

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/create-explore-comment/index.ts services/supabase/functions/get-explore-mention-suggestions/index.ts services/supabase/functions/get-explore-comments/index.ts services/supabase/functions/get-explore-comment-replies/index.ts services/supabase/functions/get-explore-notifications/index.ts services/supabase/functions/send-push-notification/index.ts
deno test --config services/supabase/functions/deno.json --allow-read=services/supabase,apps/ios services/supabase/functions/_tests/publicUsernamePolicyMigrationContract.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreMentionsDb.test.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/exploreIdentityDb.test.ts services/supabase/functions/_tests/exploreCommentsDb.test.ts services/supabase/functions/_tests/exploreNotificationsDb.test.ts services/supabase/functions/_tests/userFollowsDb.test.ts
make test-supabase-privileged-routines
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -scheme Merian -project Merian.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:merianTests/ExploreCommentMentionTextTests
```

The DB-backed Deno tests require a local Supabase Postgres schema at
`127.0.0.1:54322`. The catalog gate includes
`services/supabase/tests/public_username_policy_security.sql`, which verifies
that current profile handles use the reservation-aware constraint while mention
snapshots retain a separately validated structural constraint.
