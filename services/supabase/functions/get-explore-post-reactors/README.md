# get-explore-post-reactors

Authenticated, detail-only reactor identities. The shared handler supplies the
viewer; `types.ts` validates a UUID `post_id` and optional UUID `after_user_id`
(null/omitted means the first page). `db.ts` calls the guarded, service-only
`get_explore_post_reactors` RPC. Hidden/unavailable posts return 403; invalid
request fields return 400.

The response contains `total_count` (unique visible people), `preview_names`
(first two public names), `reactors`, and nullable `next_cursor`. Each reactor
has `user_id`, `display_name`, nullable `avatar_url`, and all their canonical
`emojis`. Likes contribute ❤️. A person who liked and used several emoji occurs
once, including the viewer and post owner. Notifications retain their separate
self-suppression rules.

Pages contain at most 32 people ordered by UUID ascending, with one lookahead
row. Pass `next_cursor` as `after_user_id`. Immutable actor IDs avoid moving a
person when they add another emoji; this is not a snapshot of concurrent
membership changes. Refresh to see newly added earlier actors or removals. Emoji
arrays follow the bundled catalog order and are bounded by that catalog. Totals
and previews use the same shadowban/block filters as rows and remain independent
of the current page. Only public profile identity is projected.

See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#post-reaction-people)
and
[native verification](../../../../docs/development-guides/08-testing-strategy.md#post-reaction-people-verification).
Focused coverage lives in `types.test.ts`, `db.test.ts`,
`_tests/exploreReactionsDb.test.ts`,
`_tests/explorePostReactorsMigration.test.ts`, and
`tests/explore_post_reactors_security.sql`. Run the complete candidate gate
before release. Apply the forward migration and deploy this route before the
native client; local validation does not authorize deployment.
