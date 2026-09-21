# Species discovery search

Authenticated, session-only dictionary discovery for iOS. `index.ts` owns
bounded HTTP orchestration; `contract.ts` validates requests and model
interpretations; `provider.ts` interprets English questions; `db.ts` retrieves
real records. This route does not create Field Chat conversations or store
search text.

## Contract

POST with a user JWT. Gateway `verify_jwt = false` delegates authentication to
`withEdgeHandler` / `requireAuth`, which validates the Bearer token with
`Auth.getUser` before parsing or database/provider work. The route is not
public. Every response uses `Cache-Control: private, no-store`. The route is
covered by the deployment workflow's critical user-route unauthenticated POST
denial smoke. The request contains `request_id` (UUID), `question` (optional, at
most 600 UTF-16 units), `context`, `result_kind` (`species` or `sightings`), and
`cursor`. The native first-query UX supplies a question; the endpoint also
accepts valid context-only reads without a prior server-side session, including
a group-only context. Requests require at least a question or context.
Follow-ups send the previous context. Tab changes, filter edits and pagination
send context without a question and never invoke a model. A question and cursor
cannot be combined.

Context contains `query` (at most 240 UTF-16 units), `group` (nullable catalog
group), `media` (nullable image/video/audio), and `mode` (name/description).
Media applies only to Sightings; the client explicitly labels this scope.
Species pagination uses descending rank/UUID; sightings use descending share
time/UUID. Cursors are specific to the unchanged context and result tab.

Responses echo `request_id` and `result_kind`, set `schema_version: 1`, and
contain `status` (results/clarification/unsupported), `message`, `context`,
`species`, `sightings`, and nullable `next_cursor`. Species matches contain an
existing catalog `item` and a bounded dictionary `excerpt`, selected from
matching overview or habitat passages for descriptive searches. Each page
contains at most 20 entries. Clarification carries unresolved search context;
unsupported requests retain the prior context. Neither returns result rows.

## Retrieval and privacy

`public.search_species_discovery` is a service-only security-invoker RPC. The
Edge derives its viewer from the authenticated user. Its shared eligibility
helper searches only public biological dictionary records. A generated English
text-search document and partial GIN index cover canonical English/scientific
names, taxonomy, overview, and habitat. Common, scientific, and alternative-name
substrings are supported. Exact scientific and canonical English common-name
matches receive the first-rank bonus; alternative names support substring lookup
without that exact-match bonus. An initial question without prior context and at
most 240 UTF-16 units first attempts a name lookup. If it finds a match, it
bypasses the provider and AI allowance; a longer or unmatched initial question
and any question with prior context use interpretation. Descriptive retrieval is
lexical search assisted by AI query interpretation, not an embedding index.

Sightings join the complete matching species set through
`explore_projected_post_cards(viewer)` before pagination. Effective community
species resolution, blocks, publication state, tombstones, and media quarantine
remain authoritative. The response explicitly selects the existing species-post
card fields and omits map coordinates. Edge enrichment preserves the RPC's
health-filtered media array instead of reloading unfiltered source media. Public
captions, user identities, media, and observations are never included in model
input. Only the bounded question and previous search context reach Gemini; both
are untrusted data.

Geography, dates, private-observation search, and factual comparison answers are
unsupported in v1. The model must explain unsupported requests rather than
silently dropping their constraints. It cannot supply result identities.

## Provider accounting

`species_discovery_search` uses the existing server consent and quota lease.
Commit precedes provider dispatch; failure is accounted for without persisting
the question. The dedicated daily bucket permits 20 calls for free and 120 for
Pro plans, with existing aggregate account/IP rate buckets. Successful initial
name lookups and context-only tab reads, filter edits, and pagination do not
spend AI allowance. A manual retry creates a fresh request UUID because this
operation has no durable answer cache; a dispatched attempt may already have
consumed allowance. No automatic replay is added to the iOS transport.

Model interpretations require a nonempty explanation. Malformed output fails at
the provider boundary with the retryable search-unavailable response rather than
returning an unusable clarification to the client.

## Verification

Run the local contract/handler tests, the AI quota dispatch inventory, the
migration contract, and `tests/species_discovery_search.sql` on a freshly
replayed disposable database. iOS owns strict identity/context/cursor decoding
and latest-request-wins session-state tests. `db_test.ts` locks preservation of
the RPC's filtered media during enrichment. See the
[verification matrix](../../../../docs/development-guides/08-testing-strategy.md#species-discovery-search-verification)
for exact suite ownership and manual acceptance. The canonical product contract
is
[Species Dictionary](../../../../docs/features-and-hardware/16-species-dictionary.md).
Source implementation and local validation do not deploy this route or
migration.
