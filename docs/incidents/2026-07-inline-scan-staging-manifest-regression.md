# Inline Scan Staging-Manifest Regression

**Date:** 2026-07-28\
**Severity:** Release-blocking\
**Affected flow:** Capture → Identify → Insight → Field Chat / Explore sharing /
Field trips / owner sync\
**Repository status:** Remediated\
**Production status:** Open until ordered deployment and retained customer-flow
evidence satisfy the closure gates below

## User Impact

Users could submit a live still and incur a successful provider analysis, but
the app received `503 scan_persistence_failed` instead of the Insight. Retrying
could remain in restoration/backoff because the quota reservation was already
committed while the ingestion job could never satisfy its media manifest.
Offline image retries could use an object-key owner from before lazy
authentication, and audio/video/Describe submission could wait on optional
environment context before making the capture durable. Together these defects
also removed or blocked the scan prerequisite consumed by Field Chat and manual
Explore publication.

Production Edge logs supplied during remediation confirmed an independently
sufficient failure at the same durability boundary: after 21.7 seconds of
successful request work, `upsertGhostUserIfMissing` attempted to insert only
`id` and `subscription_tier` for an Auth identity with no public profile.
`users.public_author_name` has no direct-insert default and is `NOT NULL`, so
the request logged `scan_inserted:false` and returned the same 503 before scan
insertion. The request had already crossed provider inference. This profile
prerequisite affected image, audio, video, and Describe routes.

The joined audit found a third durability race. An anonymous source identity
could be merged into an existing account while its provider request was in
flight. The generic merge correctly reparented ledgers and deleted the source
profile, but the old invocation still attempted its final owner-scoped insert as
the retired source. The provider reservation was already committed, while
neither identity had a completed scan that Field Chat or Explore could use.

## Root Cause

The regression was an invalid boundary between two supported image transports:

1. `InferenceEngine` encoded a foreground still in `imageBase64s`.
2. It also constructed `staging/{session-or-device}/{random}.webp` and sent that
   nonexistent key in `r2ObjectKeys` as a destination filename hint.
3. Media resolution correctly preferred the inline bytes, and moderation used
   the key only to choose the public filename. No staging PUT or
   `scan_media_assets(source = 'capture_upload')` row existed for it.
4. The ingestion job and intent nevertheless persisted the raw key as a staged
   source. After the owned scan row was inserted, strict complete-last
   finalization required a matching promoted capture asset.
5. `complete_scan_ingestion_finalization` correctly failed with
   `scan_media_promotion_incomplete`. The route converted the durability failure
   to HTTP 503 and marked the job retryable.
6. The primary provider quota was already committed. A duplicate could wait for
   completion, but this generation had no valid way to complete, so retry work
   became stranded.

The strict finalizer exposed the bad transport representation; weakening that
finalizer would have hidden real lost-upload errors and was not an acceptable
fix. Only genuine R2 source keys may participate in promotion ownership,
upload-session lookup, asset failure marking, or finalization.

## Contributing Regressions

- Upload preparation predicted an owner before `/generate-upload-urls` performed
  lazy authentication. The server correctly ignored body `user_id` and returned
  its authenticated owner, but iOS compared that key with the pre-auth
  prediction and could tombstone a valid queued capture.
- Legacy background upload task descriptions did not retain the exact
  server-issued key. Completion reconstructed keys from whichever auth identity
  was current later.
- Safe R2 promotion consumes staging objects before the scan insert. On a
  pre-insert persistence failure, the queue returned to `.staged` and retried
  keys that rollback had made nonexistent.
- Non-visual submission crossed an asynchronous WeatherKit/geocoding boundary
  before enqueue. Offline audio/video/Describe durability therefore depended on
  optional context and shared singleton scheduling state.
- Completed-response lookup selected a newly additive response column even for
  active jobs, making a migration/schema-cache rollout mismatch capable of
  failing every first request.
- Upload signing inserted a new staged ledger row each time it signed the same
  deterministic owner/client-scan/filename key. A lost signing response or
  concurrent retry could therefore create multiple active rows; the strict
  finalizer updated all of them and correctly rejected the unexpected row count.
- Signing retry logic initially treated any existing media subset as the scan’s
  immutable complete manifest. That rejected legitimate foreground-inline to
  queued-recovery handoff and made live-video signing race with the queue’s
  frame/audio/video subset for the same stable scan ID.
- The staged row’s `order_index` used the file’s flat position across a
  multi-scan signing batch. Retrying that same scan alone changed the index and
  made an otherwise identical upload generation appear incompatible.
- Shared Identify and the separate audio route tried to repair a missing
  `public.users` row with a partial table upsert. Explore has required
  `public_author_name`, `public_identity_source`, and `public_username` since
  April/May. Auth signup derives them, but replay/profile drift bypassed that
  trigger; the partial repair could never satisfy the current schema.
- `identify-describe` and `audio-spec` still returned their validated provider
  response after registering scan persistence as optional background work. They
  could therefore report success while the required scan row or canonical media
  finalization failed later.
- Compatibility routes performed a cache enrichment read after provider dispatch
  but outside their persistence failure boundary. A transient cache read could
  leave committed provider usage with no retryable ingestion transition and no
  scan row.
- A failed file in a multi-file background upload did not fence the generation
  before sibling completion callbacks ran. A sibling could therefore advance an
  incomplete manifest after the queue had already decided to retry the batch.
  Task-list inspection alone also could not prove success: a failed completed
  sibling could disappear from `URLSession.allTasks` before its asynchronous
  failure callback fenced the generation.
- After process relaunch, modern background tasks retained their task-level
  generation but the global process-local sync generation was empty. The final
  callback rejected latch completion and skipped the only immediate orphan
  recovery trigger, so partial callback state could remain `.uploading` until a
  later foreground or connectivity transition.
- A thrown/lost PostgREST response after scan insertion was treated like a
  definite rejection. The scan transaction could have committed while the
  invocation still failed quota and deleted promoted media, leaving a durable
  row whose URLs now returned 404. Explore restoration made the same unsafe
  assumption for returned update failures instead of reconciling the owner row.
  Owned scan-image repair also deleted its replacement after any atomic RPC
  exception, including a response lost after commit.
- Malformed paid-provider output returned HTTP 422 even though each route had
  already marked its ingestion generation retryable. iOS intentionally treats
  most 4xx responses as user attention, so queued scans could not execute that
  server-supported retry.

## Why Earlier Attempts Missed It

The preceding fixes correctly addressed owner-row durability, service-key
authorization, idempotent response replay, retry scheduling, and complete-last
media validation independently. Existing Edge tests mocked job/database
boundaries or inspected source invariants; they did not submit an inline image
with a destination hint through the real strict catalog finalizer. iOS tests
also treated a synthetic key as harmless because the inline resolver never
fetched it. The failure existed only at the joined transport → ledger →
catalog-finalization seam.

A review of the last 100 integrated commits found a linear/squash history rather
than merge commits. The relevant sequence was the combination of latency work,
generation fencing, server quota/idempotency changes, owner-row durability
repair, and the strict 2026-07-28 media-finalization migrations. No single
downstream Field Chat or Explore handler caused all four symptoms.

The same history review identified four independent state-boundary regressions
that amplified the backend outage:

- `212f9ce91` reset scan-level retry accounting after each successful upload
  member instead of after the complete required manifest;
- `db23a1cf1` introduced structured server-status recovery but treated
  server-`found` plus failed local hydration as unresolved, which could return a
  known server-owned scan to provider-dispatch eligibility;
- the Explore-chat extension at `655e89091` retained source-agnostic permanent
  handling for HTTP 404, so an owned scan that was merely still syncing could
  hide Field Chat; and
- `23da15f33` dismissed the Explore composer when the in-flight flag returned to
  false rather than when publication returned validated success.

Explore post, media, hashtag, and resolved-community writes also remained
separate PostgREST transactions after the media-snapshot changes in
`6def1242f`. A late failure could therefore report failure after exposing or
erasing only part of a post. These regressions explain why earlier
owner-persistence fixes improved individual layers without restoring the joined
submission → analysis → chat → publication experience.

## Resolution

- Foreground inline stills now send `r2ObjectKeys: []`.
- Shared Edge code derives `stagedImageKeys`: empty whenever inline image bytes
  are present, otherwise the validated R2 source keys. Both current and
  compatibility Identify paths use that derived set for every durable manifest
  and finalization operation. Ignored legacy inline keys cannot influence the
  public object name or extension.
- A service-only `recover_inline_scan_ingestion_completion(scan_id, user_id)`
  routine repairs already-stranded post-insert generations. It takes the
  canonical per-scan transaction lock and fails closed unless owner/job/intent
  rows, redacted counts, resumability, canonical owner URLs, filenames, and
  upload sessions all agree. Inline bytes prove that historical image keys were
  hints and must have no capture row; zero inline-image bytes prove that queued
  image keys are real staged sources and each must have one exact active owner
  row. Historical multi-image and video-frame requests may have one hint for
  many inline images. Real image/audio/video keys and audio promotion/deletion
  dispositions are rebuilt from canonical scan URLs and sanitized descriptors.
  Only migration-marked superseded signing rows may coexist. The repair
  atomically recomputes both ledger checksums and invokes the canonical
  finalizer.
- Upload signing now reuses an exactly compatible staged row and its original
  upload session. Retryable failed rows are reactivated rather than duplicated;
  a failed row attached to a terminal, completed, or active generation fails
  closed, as do promoted, deleted, or media-incompatible rows. A partial unique
  index serializes concurrent active registration, duplicate filenames are
  rejected before signing, and historical extras remain as explicit
  `superseded_staging_registration` audit rows. New rows use a stable per-scan
  media slot; exact legacy rows remain reusable despite their historical flat
  batch index. Exact requested subsets compose with unrequested rows for the
  same scan, while the union of non-superseded capture keys remains bounded at
  six. A database trigger takes an owner-scoped transaction advisory lock and
  enforces that cap across concurrent disjoint-key registrations.
- Upload dispatch validates the entire signed response before starting any PUT
  and embeds the exact server key in each generation-fenced task. Legacy tasks
  parse and validate it from the signed URL path. Completion derives the owner
  from that confirmed key, never from current auth state. Local preparation and
  pre-V33 key recovery prefer the persisted Auth-session owner over delayed
  in-memory user hydration, with device identity retained only as a
  non-authoritative pre-auth fallback.
- Retryable pre-insert persistence failure transitions the committed quota
  attempt to `failed`, allowing the stable UUID to reserve a fenced metered
  retry. Terminal moderation failures remain committed. iOS clears consumed
  staged keys, returns the row to `.pending`, and uploads its retained local
  media again. Post-insert failure keeps the committed reservation and uses
  owner-row reconstruction.
- Non-visual capture commits immediate telemetry synchronously. Optional context
  gets a bounded post-enqueue grace and late-merges locally/server-side without
  another inference request.
- Additive response storage and response-aware finalization tolerate only their
  exact missing-routine/column rollout cases; validation and promotion errors
  remain visible and fail closed.
- Every scan route now uses `ensure_scan_user_profile(owner_id)`, a service-only
  profile prerequisite. It locks against ghost merge/cleanup, requires the exact
  `auth.users` row, refuses merged or deletion-pending identities, derives
  mandatory identity and avatar fields through the canonical database helpers,
  retries only a proven public-username uniqueness race, and is idempotent for
  an existing profile.
- Identity merge now fences unfinished source scan generations before generic
  ownership reparenting. It retires ambiguous source staging, refunds only an
  unused reservation, preserves committed provider usage, and records an exact
  retryable `identity_merge_interrupted` outcome. A service-only recovery
  routine can rebuild only the exact target-owned scan proven by the
  source/target handoff, job, quota, lease, tombstone, and owner-row topology.
  Active work, deletion, ambiguity, and any existing scan win over recovery.
- All four scan-producing routes now await owner-row insertion and run
  complete-last finalization in the required task rather than registering scan
  insertion as background work. Fresh provider-owning multimodal delivery
  requires that finalizer; a later same-UUID request can return a marked
  reconstructed replay from the exact owner row while finalization remains
  retryable, with no second provider call. A compatibility route whose exact
  owner row was already committed may also deliver immediately from that
  canonical row while leaving failed finalization retryable for
  reconstruction/reconciliation; it can no longer succeed with no scan.
  Describe, audio, and compatibility image paths move only analytics, group
  tags, and candidate enrichment to optional background work. Post-provider
  cache misses or transient cache reads degrade to uncached enrichment rather
  than escaping the durability state machine.
- Legacy audio treats inline bytes as the authoritative source when both
  `audio_base64` and a destination-key hint are present. The ignored hint is
  never fetched, ledgered, finalized, or deleted. Real staged or inline audio is
  promoted into `audio_storage_urls` and normalized audio assets so Field Chat,
  Explore, replay, and owner recovery share one durable representation.
- A failed background upload atomically fences the whole generation and cancels
  every sibling before any callback may mark an incomplete manifest staged.
  Every successful callback records its exact canonical server key in a
  generation-scoped accumulator; final staging requires the complete expected
  key set, independent of task-list removal or callback ordering. Outcome
  classification and success recording occur before the handler’s first
  suspension. When all tasks settle, orphan recovery runs independently of the
  process-local global latch, and any proven orphan reset immediately restarts
  signing. This safely converts accumulator loss across process termination into
  a fresh upload rather than a stuck or partial manifest.
- Explore restoration validates every supplied key as a traversal-safe staging
  key for the authenticated owner. Image, audio, and video metadata updates
  reconcile through an exact-owner reread. Newly promoted objects are deleted
  only after a returned database rejection and a readable owner row prove the
  expected URLs absent; ambiguous responses preserve media and return retryable
  503.
- Every scan-row adapter uses one shared persistence settler. It performs short
  bounded exact-owner polls after every write, accepts a row committed despite a
  lost/error response, and emits a typed ambiguous outcome when commit status
  cannot be proved. Ambiguity keeps committed quota, staged lifecycle state, and
  promoted media intact until same-UUID recovery.
- Malformed or structurally invalid provider output returns HTTP 503 from all
  four scan producers so offline delivery retains and backs off the job.
- Owned scan-image repair reconciles source-absent/replacement-present owner
  evidence as a committed atomic repair. It deletes a replacement only after a
  returned rejection plus source-present/replacement-absent evidence; every
  ambiguous or unreadable topology preserves the object.
- Upload retry accounting now resets only when the generation-scoped exact-key
  accumulator contains the complete manifest and the reset itself saves.
- An exact-owner server `found` response is persisted as a dedicated local-result
  recovery fence before hydration. Failed hydration, relaunch, a later status
  outage, and explicit manual retry keep the scan `.inferencing` and consume only
  bounded owner-result recovery; they never return it to provider dispatch.
- Field Chat permanent unavailability is code-specific. Owned readiness and
  action-target 404s remain retryable; Explore hides chat only for
  `post_not_available`, not feedback’s `message_not_found` or an unmarked
  platform-route 404.
- Explore create returns validated Boolean publication success to the composer.
  Failure or malformed HTTP success retains the draft and does not cache a post
  ID.
- Final Explore publication is one service-role-only invoker transaction for
  post, media, hashtags, and resolved-community state. It locks community request
  before scan, rechecks `needs_id`, resolves omitted privacy from the locked scan,
  and rolls the previous complete snapshot back on every late failure.
- Ask the Community now resolves taxonomy and moderation before one
  service-role-only invoker transaction commits post, media, and hidden
  `needs_id` state. It no longer imports the removed legacy Explore upsert,
  cannot leak a normal post on a late request failure, resets stale consensus
  generations on reopen, and rejects an explicit share that loses the
  concurrent Community-request race at the actual post write.

## Security Properties Preserved

- The repair routine is executable only by `service_role`, performs its own
  service-role check, uses an empty search path, and is migration-allowlisted.
- Every scan and ledger lookup is constrained by both scan UUID and owner UUID.
- A deletion tombstone always wins before repair.
- Missing scan-user profile repair cannot resurrect a merged ghost or race
  account deletion/empty-ghost cleanup; existing public identity is not
  overwritten.
- Genuine capture-upload image/audio/video keys and sessions are never
  normalized away. Every real key requires one exact active owner row and
  canonical filename mapping; only extras marked by the migration as
  `superseded_staging_registration` are ignored. Cross-owner/noncanonical URLs,
  malformed JSON, unrecognized duplicates, and ambiguous dispositions make
  repair inapplicable.
- Strict promotion completeness and complete-last canonical media validation
  remain unchanged for ordinary staged captures.
- Raw media, private paths, coordinates, and user-authored context are not added
  to logs or replay ledgers.
- Identity recovery never reopens or decrements committed provider usage. It
  cannot resurrect the retired source identity, cross a merge handoff, outrun an
  active lease, or overwrite an existing owner scan.
- Destructive quota/media resolution requires positive absence evidence. A
  timeout, unreadable owner row, reported-success/no-row anomaly, or identity
  reparent race is never converted into permission to delete referenced media.

## Regression Coverage

- Inline source-manifest derivation tests cover legacy hint exclusion and true
  staged source preservation.
- Completed-response tests cover exact stranded recovery, migration-first
  rollout, owner reconstruction, and unexpected-error visibility.
- Migration source contracts enforce ordering, type-before-operation safety,
  ACLs, owner checks, narrow signature checks, and canonical finalization.
- pgTAP fixtures exercise multi-image recovery with one historical hint, mixed
  video recovery with a retained upload session, real queued-image recovery with
  a marked signing duplicate, and refusal when an inline hint collides with a
  genuine capture-upload image asset.
- iOS tests cover canonical server-key handoff, signed-path recovery, task
  persistence, path traversal, whole-manifest validation, synchronous offline
  audio durability, whole-generation sibling failure fencing, exact
  all-members-success accumulation (including generation-less compatibility),
  relaunch orphan recovery, and fresh-upload retry after consumed staging keys.
- Signing tests cover lost-response reuse, concurrent convergence, terminal
  refusal, inline-to-recovery subset composition, video/recovery subset
  composition, and union-cap refusal. Migration contracts pin the unique index,
  owner-scoped advisory lock, trigger cap, and deny-by-default routine ACL.
- Field Chat, Explore sharing/media, scan status, workflow route, and quota
  contract suites remain part of the connected-flow verification. Source-aware
  Field Chat tests distinguish `post_not_available` from action-level and
  platform 404s; Explore tests cover draft retention, strict response integrity,
  transaction rollback, lock ordering, and locked privacy defaulting.
- Profile-prerequisite source and pgTAP contracts cover exact Auth backing,
  mandatory identity validity, idempotence, ACLs, and all retirement fences.
- Identity-merge source contracts and pgTAP fixtures cover pre-reparent fencing,
  exact endpoint/operation preservation for all four producers, committed-usage
  accounting, target-only recovery, active/deletion refusal, ACLs, and stable
  restaging outcomes.
- Shared persistence tests cover returned rejection, lost write response,
  delayed owner visibility, unreadable verification, exact owner scoping, and
  cleanup classification. Explore tests cover direct and reread-confirmed
  commits, definite rejection, ambiguous update, and rollback refusal unless
  absence is proven.

## Deployment Follow-up: Workflow Run 1549

Attempt 1 of `Deploy Merian to Supabase` for commit
`fab31d92a5985c7c02669c33cadfcc2b1091e3a8` stopped while the disposable local
database applied `20260728230000_recover_inline_scan_ingestion_completions.sql`.
PostgreSQL returned `SQLSTATE 42601`, `syntax error at end of input`, at
statement 0; the reported caret was inside the recovery routine's monolithic
ledger predicate. The committed and checked-out migration blobs were both
complete and had the same SHA-256, ruling out a partial checkout.

The failed object was one 43 KiB PL/pgSQL definition. The remediation preserves
the fail-closed checks but separates them into three bounded private
`SECURITY INVOKER` validators for ledger shape, durable scan media, and staged
assets. Their execution privileges are revoked from every API role, including
`service_role`; only the unchanged service-only public wrapper can call them
while holding its owner, ledger, and transaction locks. Expected media counts
are computed before endpoint predicates, removing the nested `CASE` expression
at the reported parser seam. Source contracts keep all four routine definitions
below a conservative 16 KiB repository review budget, and pgTAP adds explicit
helper-bypass denials. That budget is a regression guard, not a claimed
PostgreSQL function-size limit. The structural contract is itself exercised
against adversarial unmatched-parenthesis, orphaned/unterminated control-flow,
invalid `ELSIF` / repeated-`ELSE`, and unterminated-literal fixtures so the
scanner cannot silently accept the malformed shapes it is intended to prevent.

Because the failure occurred in the disposable `db start` gate, that attempt did
not run production `db push`, deploy an Edge Function, synchronize a secret, or
execute production smoke tests. The repository remediation is not deployment
evidence: the exact reviewed SHA must pass fresh-catalog replay and the
remaining closure gates before this incident can be marked deployed.

## Deployment Follow-up: Workflow Run 1550

Attempt 1 of `Deploy Merian to Supabase` for commit
`16397c0cdf79b622dd0072b2fd2432a53ea20b5f` advanced past the bounded inline
completion recovery migration, then stopped while the disposable database
applied `20260728233000_recover_identity_merge_interrupted_scans.sql`. The
reported caret was the `FROM` in
`pg_catalog.SUBSTRING(media_keys.storage_key FROM pattern)` inside the
`owner_texts` CTE. The equivalent public-media-URL extraction had the same
syntax.

This combined two incompatible PostgreSQL forms. Keyword-separated
`SUBSTRING(value FROM pattern)`, `SUBSTRING(value FOR count)`, and
`SUBSTRING(value SIMILAR pattern ...)` are unqualified SQL expressions. Once
the function is schema-qualified, PostgreSQL expects ordinary comma-separated
arguments. Both recovery calls now use
`pg_catalog.SUBSTRING(value, pattern)`. This changes no owner, merge, ledger,
quota, tombstone, media, or execution-grant rule.

The migration execution contract now performs a depth-aware scan of every SQL
migration and rejects a schema-qualified `SUBSTRING` whose first top-level
separator is `FROM`, `FOR`, or `SIMILAR`. Detector fixtures cover nested
expressions, all three invalid forms, unqualified valid syntax, and qualified
comma invocation. The deployment runbook's executable index-command query also
used qualified `FOR` forms; those examples now use ordinary
`pg_catalog.SUBSTRING(value, start, count)` calls.

Run 1550 failed in disposable `supabase db start`, before production connection
preparation, `db push`, secret synchronization, Edge deployment, or smoke
testing. It therefore made no production mutation. The source correction and
164 passing migration contracts remain repository evidence only; a new exact-SHA
fresh-catalog replay is still required.

## Deployment Follow-up: Workflow Run 1551

Attempt 1 of `Deploy Merian to Supabase` for commit
`f841a436a87bfafa296f4c0fb89e1d8264192f91` successfully rebuilt the
disposable PostgreSQL catalog and applied the complete migration history,
including both incident recovery migrations that had blocked runs 1549 and
1550. This is the first hosted evidence that the corrected migration fleet
parses and applies from an empty catalog.

The next gate discovered 24 pgTAP files and completed 22. Two files aborted
during fixture setup before their plans:

- `identity_merge_scan_recovery_security.sql` proposed 26-character public
  usernames even though the production CHECK permits at most 24. The same
  fixture also performed a plain profile insert after its `auth.users` inserts
  had synchronously fired `on_auth_user_created`.
- `inline_scan_manifest_recovery_security.sql` likewise inserted
  `public.users` after the Auth trigger had already created the same primary-key
  row.

The identity fixture now uses 20-character, policy-valid usernames. Both
fixtures use `ON CONFLICT (id) DO UPDATE` to customize the trigger-created
profile without bypassing the Auth foreign key, username policy, identity
source checks, or transaction rollback. Focused source contracts pin the valid
fixture identities and the trigger-aware upsert. The later `Bad plan` messages
were consequences of setup exceptions aborting the pgTAP blocks, not additional
test failures.

Run 1551 stopped before production connection preparation, `db push`, secret
synchronization, Edge deployment, or smoke testing, so it made no production
mutation. A new exact-SHA run must repeat fresh-catalog replay, execute all 26
current fixtures—including the subsequently added atomic Explore and Community
rollback fixtures—and continue through deployment and production smokes.

## Deployment Follow-up: Workflow Run 1552

Attempt 1 for commit
`7e54a1ade9806f40654c937fe9eaf6f7d93439e9` repeated complete disposable
catalog replay. The fixture corrections did not close the gate: 22 of 24 files
completed.

The inline fixture now executed assertions 1–15 successfully. That proves its
ACL checks, adversarial topology checks, profile setup, first inline-image
repair, normalized ledger state, and ready canonical image path. The next
statement is mixed-video recovery for scan `...f112`; it raised before
assertion 16.

The video scan retains sampled inference frames in
`image_storage_urls`, while canonical refresh correctly creates one playback
video and no standalone rows for those frames. The strict finalizer introduced
on July 28 nevertheless required every compatibility image URL as a ready image
row and raised `canonical_scan_media_incomplete`. Forward migration
`20260729012153_fix_video_scan_canonical_finalization.sql` now validates the
same structured or legacy canonical projection as refresh and still requires
exact owner/kind/URL ready rows. See the dedicated
[video finalization incident](./2026-07-video-scan-canonical-finalization-regression.md).

The identity-merge fixture separately remained at `planned 1, ran 0`. It now
catches its outer exception, emits phase/SQLSTATE/message/detail/hint as a
bounded deterministic warning, and returns one TAP result so another hosted run
cannot hide the root PostgreSQL error.

Run 1552 again stopped at the disposable catalog gate before any production
connection preparation, `db push`, secret synchronization, Edge deployment, or
smoke test. It made no production mutation. Only a new exact-remediated-SHA run
with every fixture passing can replace this failed evidence.

## Deployment Follow-up: Exact-SHA Catalog Rerun

The next hosted catalog run exercised commit
`50d905f85ac536052abefa63d36c9b45e5e4ec74`. The complete 30-assertion inline
recovery fixture passed, including historical mixed-video repair and the direct
six-object production-shape case. This is fresh disposable-PostgreSQL evidence
that the forward video projection accepts sampled inference frames without
turning them into standalone display images.

The diagnostic-hardened identity fixture emitted one precise failure before it
reached the production merge routine:

```text
phase=ingestion-intent setup
sqlstate=42702
column reference "scan_id" is ambiguous
```

Its anonymous block declared a synthetic variable named `scan_id`, then used
that name beside `jobs.scan_id` in an `INSERT ... SELECT`. PL/pgSQL could not
choose between the variable and the table column. The fixture now calls the
synthetic identity `fixture_scan_id` everywhere while retaining real
`scan_id` column names. The source contract forbids the ambiguous declaration
and pins the qualified comparison.

This was a fixture defect; the run never invoked
`internal.perform_ghost_profile_merge` or
`public.recover_stranded_scan_ingestion_attempt`. It stopped with 23 of 24
catalog files complete, before production connection preparation, `db push`,
secret synchronization, Edge deployment, or smoke testing, and made no
production mutation. A further exact-SHA run must execute the now-reachable
identity merge and recovery assertions and pass all 26 current files.

## Deployment Follow-up: Atomic Explore Graph Regression

The backend workflow for
`1a75179dd88f20163cb5c01bffd60478b9545009` stopped during isolated Edge
Function graph validation, before disposable database startup, production
connection preparation, migration push, secret synchronization, Function
deployment, or smoke testing. Deno reported that
`request-community-identification/db.ts` imported `upsertExplorePost`, although
the same commit intentionally removed that export while replacing separate
Explore writes with `publish_scan_to_explore_atomically(...)`.

Restoring the deleted helper would make the graph compile while reintroducing
the partial-publication boundary. Instead, Ask the Community now resolves
taxonomy and prepares moderated media before one owner-checked
`request_community_identification_atomically(...)` transaction commits the post
snapshot and hidden request. The route is the tenth member of the ordered
critical rollout. Local isolated validation now checks all 89 entrypoints with
their function-specific deploy configs, but only a final exact-SHA hosted run
can replace the failed workflow evidence.

## Release Follow-up: iOS Workflow Run 73

Attempt 1 of `iOS Build and Test` for the same commit compiled and completed its
unsigned Release archive, but correctly failed production readiness because the
complete unit target reported 1 failure after 1,167 passes. The sole failed test
was
`OfflineQueueManagerTests.testMediaStagingContractBuildsSanitizedMixedMediaKeys()`.

The commit added a security check requiring every server-issued
`staging/{owner}/{file}` owner to be a canonical lowercase UUID. The mixed-media
fixture still constructed its supposedly valid manifest with synthetic owner
`USER/ABC`, which key construction sanitized to `user_abc`; the validator
correctly rejected it. The remediation changes the fixture to an uppercase Auth
UUID and asserts its lowercase canonical key. Existing tests continue to reject
non-UUID, cross-owner, traversal, mixed-origin, insecure, duplicate, and
filename-mismatched manifests. Production validation was not weakened to make
the gate green.

The original job summary obscured this result by grepping every raw log line
containing `error:`. That selected a deliberately injected
`ExploreReplyLoadingStateTests` failure and metadata reads against intentionally
unreadable temporary Core Data stores from passing negative-path tests. Neither
was causal. Failure reporting now reads Xcode's structured result-summary
failures first, then failed test-tree nodes, and consults the build log only as a
fallback. The release archive success remains valid evidence for that SHA, but
it cannot substitute for a passing full unit target; both jobs must pass again
on one exact remediated SHA.

## Production Closure Gates

Repository remediation, merge to `main`, backend deployment, iOS release, and
production verification are separate states. Close this incident only after
retaining all of the following:

1. the exact reviewed repository SHA, four migration versions, nine deployed
   Edge Function versions, and matching iOS version/build;
2. successful disposable-catalog migration and pgTAP evidence for inline
   completion repair, profile prerequisite security, and identity-merge
   recovery;
3. staging smoke evidence for current foreground image, queued image, audio,
   video, and Describe scans, including ambiguous response and partial-upload
   fault injection;
4. immediate exact-owner `found` status after every producer `200`;
5. Field Chat opening and Explore publication with eligible saved public media
   for the same newly completed scan;
6. guarded recovery of eligible historical drift without provider redispatch,
   quota decrement, direct client scan writes, or destructive ambiguous-state
   cleanup; and
7. a clean production observation window with no new false-success, phantom
   manifest, owner-profile prerequisite, or post-commit cleanup failures.

The canonical joined contract is
[Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).
Execute and retain the exact release procedure in
[Scan Owner-Row Durability and Recovery Rollout](../backend-and-data/06-supabase-deployment-runbook.md#scan-owner-row-durability-and-recovery-rollout).
