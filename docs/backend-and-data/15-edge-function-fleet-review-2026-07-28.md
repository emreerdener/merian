# Edge Function Fleet Review — 2026-07-28

**Status:** Repository review complete. Exact-SHA application CI, production
route, and authenticated customer smoke evidence remain release-blocking.

## Scope

This review covers all 89 deployable Supabase Edge Function entrypoints, their
`config.toml` records, isolated deployment graphs, shared authentication/error/
request-size/outbound/quota boundaries, database migration contracts, and static
production callers across every application target, workflows, Edge workers,
operator scripts, and migrations.

PostgreSQL routines are not counted as Edge Functions. Their effective grants,
caller binding, RLS, cron transport, and migration compatibility are covered by
the privileged-routine catalog audit and migration/security contract suites.

## Findings Corrected

1. Production rollout previously proved route execution for only five
   customer-critical functions. It now derives the full graph inventory and
   requires every route to return fixed `X-Merian-Handler: 1` execution
   evidence. Preflight uses a validated legacy anon JWT only to cross the two
   intentional gateway `verify_jwt = true` boundaries and fails closed rather
   than placing a publishable key in Bearer authorization. The five scan/Explore
   routes retain their stricter marked fail-closed `401` probes.
2. `identify-multimodal` multiplexed user and internal replay authentication
   around raw `Deno.serve`, leaving preflight and internal replay responses
   outside the universal marker/error boundary. The entire multiplexer now
   registers through `serveEdge`, and the fleet contract rejects any future
   branched raw entrypoint.
3. No contract linked app/worker route literals to current entrypoints. The
   tooling gate now scans every application target and rejects any static
   production caller for a missing or unconfigured function. The historical
   `auto-purge-domesticated` literal is accepted only while the exact later cron
   unschedule remains present.
4. iOS retried every transient transport error and returned `5xx`, including
   insert and toggle operations whose first attempt might already have
   committed. Ambiguous replay is now limited to audited reads and exact
   idempotency-aware endpoint contracts. Signed upload-session/URL generation is
   explicitly excluded because a lost response may have committed a fresh
   staging generation.
5. The public species website treated every Edge `404` as a missing species.
   Only marked handler-owned `404` responses now become not-found pages;
   unmarked platform/router failures remain transient server failures.
6. The two customer-visible raw `localizedDescription` assignments encountered
   on the affected Community Feedback and observation-statistics screens now use
   customer-facing copy.
7. The isolated deployment-graph check caught stale ownership during the
   ingestion-module refactor. The atomic scan-ingestion initializer now has one
   canonical home in `scanIngestionJobs.ts`, all callers import it there, and
   strict response validation covers the current RPC shape, including stage and
   already-complete state. Malformed database envelopes fail closed.

## Boundary Review

- **63 user or hybrid routes:** `withEdgeHandler` authenticates the Supabase
  user before route logic. `identify-multimodal` additionally permits the exact
  service-key replay boundary before entering the same owner-scoped handler.
- **21 internal workers:** exact environment-backed server-key comparison runs
  before body parsing and privileged client construction. Current opaque keys
  use `apikey`; only validated legacy service-role JWTs also use Bearer.
- **5 deliberate custom routes:** `download-dwca` uses an opaque hashed
  capability with click-time privacy checks; `ingest-r2-media-events` verifies
  its dedicated secret before parsing; `revenuecat-webhook` verifies bearer and
  raw-body HMAC before provider/database work; `species-dictionary` exposes only
  the public projection except for its authenticated `my_scans` tree; and
  `species-observation-stats` applies distributed IP/user limits and
  dictionary-bound authorization.

Every entrypoint uses a bounded request reader where a body exists, the shared
public response boundary, frozen function-local dependencies, deadline-bound
outbound transport, and a matching explicit configuration record.

## Application Caller Review

All normal iOS Function requests use `MerianNetworkClient`, including Share,
composer media, Ask the Community, Insight/Field Chat, Explore, Dictionary, and
feedback routes. Its platform-router `404` recovery is separate from
handler-owned `404`, and ambiguous transport/`5xx` replay fails closed unless
the route is an audited read or carries a server-supported idempotency key.

The only direct iOS SDK callers were reviewed separately:

- collection sync sends a stable set-state payload, preserves local tombstones
  until a confirmed response, and retries on the next sync cycle;
- ghost-profile merge prepare can leave only an expiring unused handoff after a
  lost response; received handoffs stay in Keychain, completion is
  server-idempotent, and unresolved state remains available for retry; and
- no admin or companion application target currently invokes an Edge Function
  directly.

The public species website is the only direct web SDK caller. It now accepts
not-found only with exact Merian handler evidence. The static caller contract
scans the complete `apps/` tree so future application targets cannot silently
reference a missing or unconfigured route.

## Validation Evidence

- complete Edge Function suite: `1238 passed`, `0 failed`;
- migration contracts: `144 passed`, `0 failed`;
- discovery-based Supabase tooling: `100 passed`, `0 failed`, plus `16` DTO and
  `10` Identify wire-contract tests;
- workflow security and documentation contracts: `11 passed` and `8 passed`;
- all `89` function-local deployment graphs checked in isolation;
- Deno format across `656` files and lint across `501` files;
- all `56` public-web source tests passed; the complete frozen
  install/audit/type-check/build gate remains exact-SHA CI evidence because
  registry access is unavailable locally;
- changed Swift sources parsed, and iOS project resource validation passed; and
- `git diff --check`.

Database-backed cases in the complete Edge task reported skips because this
workspace cannot reach the disposable PostgreSQL service; production CI sets an
explicit test URL so the same condition fails closed there. Full Xcode
compilation also remains limited by the local SwiftPM/CoreSimulator environment.
Neither limitation, nor hosted route/authenticated customer smokes, is counted
as passing evidence.

## Reviewed Entrypoints

```text
audio-spec
auto-purge-nonbio
backfill-explore-audio-spectrograms
block-user
check-public-username
check-scan-status
community-taxonomy-status
create-explore-comment
delete-explore-comment
delete-scan
download-dwca
enrich-scan
expire-subscription-passes
explore-post-chat
export-dwca
field-trips
flag-issue
generate-upload-urls
get-community-identification-detail
get-community-identification-feed
get-explore-author-posts
get-explore-author-profile
get-explore-comment-replies
get-explore-comments
get-explore-composer-media
get-explore-feed
get-explore-hashtag-posts
get-explore-map-points
get-explore-media-incidents
get-explore-mention-suggestions
get-explore-notifications
get-explore-post
get-explore-post-detail
get-explore-species-posts
get-explore-unread-notification-count
get-filtered-discovery-feed
get-scan-explore-share-state
identify
identify-describe
identify-multimodal
ingest-r2-media-events
insight-chat
mark-explore-notifications-read
merge-ghost-profile
process-community-consensus-jobs
reconcile-account-deletions
reconcile-dwca-archive-cleanup
reconcile-explore-media-health
reconcile-ghost-profile-merges
reconcile-revenuecat-subscribers
reconcile-scan-deletions
reconcile-scan-media-assets
refresh-merian-reference-images
refresh-species-content
refresh-species-model-content
refresh-taxonomy-nodes
register-push-device
repair-scan-image
replay-scan-ingestion
report-explore-comment
report-explore-post
report-user
request-community-identification
request-export-dwca
restore-community-identification
revenuecat-webhook
safe-delete
scan-media-health
search-community-taxa
send-push-notification
set-explore-post-like
set-user-follow
share-scan-to-explore
species-dictionary
species-observation-stats
submit-community-feedback
submit-community-identification
submit-feedback-survey
sync-collections
sync-community-taxonomy-index
toggle-explore-comment-reaction
unshare-explore-post
update-community-identification-request
update-explore-field-notes
update-public-avatar
update-public-display-name
update-public-username
update-scan-context
withdraw-community-identification
```

## Release Evidence Required

Repository checks cannot prove hosted regional routing or an authenticated
customer journey. Before closing the incident:

1. run the production Supabase workflow from the reviewed release SHA and
   require all 89 graph-derived route probes plus the five stricter auth probes;
2. require the stable hosted `iOS Build and Test / Production readiness` result
   for the same SHA, including the complete unit-test target and independent
   unsigned Release archive;
3. require the frozen public-web install, audit, test, type-check, and
   production build gate for the same SHA;
4. perform one authenticated new-scan smoke covering owner status, Field Chat,
   composer media, and Explore publication;
5. perform the same Share and Field Chat smoke on an eligible older local scan;
6. retain the scan and queue item under a synthetic/observed platform
   `NOT_FOUND`; and
7. escalate any later zero-execution route recurrence to Supabase with only the
   affected UTC window, function names, and project reference.

See [Supabase deployment runbook](./06-supabase-deployment-runbook.md) and
[July 2026 Edge route incident](../incidents/2026-07-supabase-edge-route-not-found.md).
