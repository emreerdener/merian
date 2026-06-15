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
```

The migrations add:

- `comment_mention` to `public.explore_notification_type`
- `public.explore_comment_mentions(comment_id, mentioned_user_id,
  mention_username, created_at)`
- `public.get_explore_mention_suggestions(...)`
- `public.comment_mention_projection(comment_id)`
- `public.insert_explore_comment_mentions_from_body(comment_id, actor_user_id)`
- `public.insert_explore_comment_mention_notifications(comment_id)`

`explore_comment_mentions` has a primary key on
`(comment_id, mentioned_user_id)` so duplicate tokens cannot create duplicate
rows. Mention notifications use a partial unique index on
`(user_id, comment_id, type)` for `comment_mention` rows.

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

## iOS Touchpoints

- DTOs and client method: `apps/ios/Merian/Core/Network/ExploreAPIModels.swift`
  and `apps/ios/Merian/Core/Network/MerianNetworkClient.swift`
- Shared comment composer:
  `apps/ios/Merian/Features/Explore/Components/ExploreCommentComposer.swift`
- Mention parsing, replacement, and attributed links:
  `apps/ios/Merian/Features/Explore/Models/ExploreCommentMentionText.swift`
- Tappable rendered body:
  `apps/ios/Merian/Features/Explore/Components/ExploreCommentBodyText.swift`
- Comment surfaces:
  `apps/ios/Merian/Features/Explore/Components/ExploreCommentsSheet.swift` and
  `apps/ios/Merian/Features/Explore/Components/ExplorePostDetailCommentsSection.swift`
- Profile routing:
  `apps/ios/Merian/Features/Explore/Views/ExploreAuthorProfileSheet.swift`
- Notification rendering:
  `apps/ios/Merian/Features/Explore/Models/ExploreNotification.swift` and
  `apps/ios/Merian/Features/Explore/Components/NotificationRowView.swift`
- Regression tests:
  `apps/ios/MerianTests/Features/Explore/ExploreCommentMentionTextTests.swift`

The composer watches the trailing token. Selecting a suggestion replaces the
active `@query` token with `@username` followed by a space and leaves the
comment as plain text. Rendered comments link only the resolved mention spans
that came back in the `mentions` array. Unresolved `@text` remains normal text.

## Verification

Recommended checks:

```sh
deno check services/supabase/functions/create-explore-comment/index.ts services/supabase/functions/get-explore-mention-suggestions/index.ts services/supabase/functions/get-explore-comments/index.ts services/supabase/functions/get-explore-comment-replies/index.ts services/supabase/functions/get-explore-notifications/index.ts services/supabase/functions/send-push-notification/index.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreMentionsDb.test.ts
deno test --allow-env --allow-net services/supabase/functions/_tests/exploreCommentsDb.test.ts services/supabase/functions/_tests/exploreNotificationsDb.test.ts services/supabase/functions/_tests/userFollowsDb.test.ts
xcodebuild -scheme Merian -project merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -scheme Merian -project merian.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:merianTests/ExploreCommentMentionTextTests
```

The DB-backed Deno tests require a local Supabase Postgres schema at
`127.0.0.1:54322`.
