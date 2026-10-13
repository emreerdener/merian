# Initial media handoff lock and erasure closure

Status: independent and IC-1 source-specific design concurrence recorded October
13, 2026. The exact reviewed candidate is
`.artifacts/initial-media-handoff-v2/runtime-lock-closure-v3.md`, SHA-256
`3fb5bc3f35318def79d77dde79eeb7c904694d1504747935a28a3378b4d73fd9`. Acceptance
is recorded in `runtime-closure-acceptance-v3.json`. This closes the
source-specific pre-DDL design prerequisite for the inactive handoff family and
the explicitly assigned narrow Ghost target-funding guard. It does not implement
or qualify runtime behavior, grant access, enable activation, or authorize an
external operation. The following candidate body is retained as reviewed;
implementation must verify the actual effective graph and complete its stated
acceptance before runtime qualification.

Baseline: `d68f272d4`, October 13, 2026. This is the source-specific companion
to `runtime-contract-v2.md` and `runtime-mechanics-v3.md`, for independent and
IC-1 review before runtime DDL. It is not implementation or concurrency
acceptance.

## Exact catalog and limits

`runtime-inventory/effective-inventory-receipt.json` binds the complete replay
of 486 migration files to all 1,133 source-defined public/internal functions and
261 public/internal base tables. It includes effective routine definitions,
security mode, search path, ACL, columns, constraints, incoming foreign keys and
all trigger definitions, including internal RI triggers. All 467 earlier
retained function records match exactly. The new migration since that earlier
inventory adds only the accepted pure SQL proof validators. No actual data or
credentials are in the extract. The owned database was disposed after verifying
activation false and zero invocations, admitted receipts and preparation
intents.

`runtime-inventory/edge-index.json` is a lexical review aid, not an asserted
execution graph. It retains literal-qualified references, possible unqualified
source-function names, ordered lock/dynamic-SQL excerpts and exact trigger/FK
edges. Comments, SQL strings and overloads can overapproximate references; the
review must resolve executing branches rather than interpreting every lexical
match as a call. Source routines below mean the exact effective definitions in
that extract, not merely their first CREATE statements in old migrations.

## Fixed entrypoints and closed selectors

The six proposed private handoff owners remain begin-copy, record-object,
complete-copy, claim, verify and transfer. Each resolves only the original
admitted owner/scan pair and the original admission digest. No operation accepts
a relation name, backend replacement, clock value or arbitrary execution
callback. They do not reuse `lock_initial_media_scope`, which rejects admitted
v3 and is a v1 provider/media boundary.

The existing admitted-recovery callers are
`public.get_initial_preparation_status`, `public.finalize_initial_preparation`,
`internal.create_initial_media_preparation` and
`internal.initial_preparation_execution_action`. Their existing early
`recover_initial_admitted_media` branch must keep precedence over legacy expiry
and action. The recovery owner gains reads/locks of original handoff state and
transfer-first classification, never mutation or new I/O authority. V1
`initial_media_verification_action` and preparation execution grants remain
separate and closed to admitted v3.

The fixed dynamic catalogs and trigger arrays are independently covered:

| Selector                                                                           | Consumers and required change                                                                                                                                                                                                                           |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `initial_cancellation_private_catalog`                                             | Add the four durable receipt children, root `submission`, limit one each. `capture_initial_cancellation_private_images`, generated BEFORE/AFTER private-member guards, and exact C1 erasure witnesses consume this same list. Fifteen becomes nineteen. |
| `initial_cancellation_seal_catalog`                                                | Add all four durable and both transient handoff relations. The catalog drives statement trigger installation and seal validation.                                                                                                                       |
| Admission statement-seal literal array, atomic-admission migration lines 2202–2246 | Add those six relations to denial only. Do not add them to admission's exact funding/member image array or materialization ledger.                                                                                                                      |
| `initial_cancellation_cleanup_catalog` and terminal catalogs                       | Keep transient C1 consumption separate. Do not classify handoff durable rows as cleanup witnesses. Cross-owner absence checks include both handoff transient relations.                                                                                 |
| New handoff domain catalog                                                         | Four durable tables, source fence and registry, seven intent-root private relations. All names are fixed SQL literals. Action/row expectations and statement frames are derived from protected original prestate, not a caller relation selector.       |
| New handoff seal catalog                                                           | Fixed union of existing admission/C1 affected relations, all six new relations, and their bookkeeping exclusions. Seal permits only its exact parent-present consumption; no provider or accounting exception.                                          |
| Existing preparation provider/execution trigger arrays                             | Preserve the legacy barrier and exact admission exception. Do not attach pre-admission execution authority to new handoff tables or add a transfer exception to provider creation.                                                                      |

Catalog-driven `EXECUTE format` must interpolate only validated closed catalog
members. Migration-time `pg_get_functiondef` replacements must assert one exact
known source match and review resulting definitions; no open runtime routine
executor is introduced. The expanded catalog is retained so previously omitted
nested trigger and cascade routines remain reviewable.

## Ordered acquisition and branch distinctions

This is an order of resources when acquired, not a mandate that erasure depend
on intact proof or currently eligible catalog rows. Reentrant validation can
read already held rows; it must not newly acquire an earlier resource after a
later one. All new identity/receipt FKs reference already locked parents. New
durable rows have only the admitted receipt composite FK, with existing unique
`(scan_id, owner_id)`; no direct user FK or additional peer cascade is added.

All ordinary scoped data-row locks below are `FOR UPDATE` in READ COMMITTED,
including read-only recovery, to preserve the established owner serialization.
No conversion to weaker SHARE/KEY SHARE is implied. The exceptions are named
explicitly. An absent row is serialized by the existing locked owner and scan
advisory scope, not by claiming SELECT locked a nonexistent tuple.

| Order | Resource, mode and exact key ordering                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | `public.users WHERE id=p_owner FOR UPDATE`. Canonical live owners acquire this first. Raw scan/tombstone entry uses `FOR UPDATE NOWAIT`; raw owner deletion already owns its deleting tuple. Multi-owner exceptions are specified below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 2     | Exact per-scan advisory expression and scan/history acquisition are specified immediately below this table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| 3     | By `scan_id=p_scan`, each `FOR UPDATE` in this exact family order: lifecycle fence, preparation intent, submission, cancellation, admission. Validate original owner after locks; no identity change.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| 4     | Fresh action eligibility only: rollout `singleton=TRUE`; preparation profile eligibility `profile_digest=original assignment preparation.profile_digest`; source backend eligibility `generation=original assignment preparation.backend_generation`; handoff eligibility `installation_digest=original assignment handoff.installation_digest`. Each is `FOR SHARE NOWAIT`, in that sequence, matching `lock_initial_preparation_eligibility`. Values are from the immutable admitted receipt, not a new selector. Immutable catalog definitions use ordinary snapshot reads with complete digest correlation; their immutability guards remain in force. Recovery, positive C1 and raw erasure add no new current-eligibility requirement. |
| 5     | Original quota reservation by relational admission `funding_binding_id`, `FOR UPDATE`; provider attempt by `(reservation_id,attempt_count=1)`, `FOR UPDATE`; reservation-counter links for that reservation `FOR UPDATE ORDER BY CASE scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END, scope_key, bucket, window_start`; immediately for each link, its exact `(scope_type,scope_key,bucket,window_start)` counter `FOR UPDATE`; then complimentary usage `(user_id=p_owner,client_scan_id=p_scan) FOR UPDATE`. This preserves `release_ai_quota_reservation_counters`/C1 ordering, not lexical scope ordering. No new reservation or funding resolution.                                       |
| 6     | Source fence `scan_id=p_scan FOR UPDATE`; every actual source registry row for that scan `ORDER BY object_id FOR UPDATE`; source mapping `ORDER BY ordinal FOR UPDATE`; admitted receipt `scan_id=p_scan FOR UPDATE`. Registry membership comes from actual scan rows even when private proof is damaged.                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 7     | Each `FOR UPDATE`, `scan_id=p_scan`: source verification, execution grant, output manifest; output mapping `ORDER BY ordinal FOR UPDATE`; outcome; transfer receipt. This preserves C1's existing source-proof suborder and inserts transfer before M1.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 8     | Each `FOR UPDATE`, `scan_id=p_scan`: M1 allocation fence, M1 cohort, v1 M2 preparation, v1 M2 verification, copy progress, v2 claim, v2 verification. V1 M2 siblings must be absent for valid admitted-v3 proof.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| 9     | Every actual destination registry row for this scan `ORDER BY object_id FOR UPDATE`. No subsequent new outer/catalog/funding locks.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 10    | Handoff stage and ordinal-ordered ledger, after complete domain scope. Stage updates/consumption use its already-owned row; child FK key-share is against that already-owned parent. Final IMHF seal uses exclusive transaction `pg_try_advisory_xact_lock(1229801542,hashtext(scan_id::TEXT))`. Failure rejects; it is denial only.                                                                                                                                                                                                                                                                                                                                                                                                         |

Rank 2 uses the exact exclusive transaction call
`pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || p_scan::TEXT, 0::BIGINT))`.
Trigger entry uses `pg_try_advisory_xact_lock` with that same hash/key and
raises `initial_analysis_erasure_busy` / `55P03` if unavailable. After the
advisory scope, acquire `public.scans WHERE id=p_scan FOR UPDATE`, then
`internal.observation_histories WHERE observation_id=p_scan FOR UPDATE`. The
scan/tombstone entry's already-held tuple and owner NOWAIT exceptions remain as
stated below. This expression is outside the table so Markdown pipe parsing
cannot truncate the concatenation.

Required caller changes are explicit, rather than relying on the table alone:

- All six new handoff owners acquire this order before mutation, then the stage
  guards revalidate already-held scope without I/O. Stage registration cannot
  admit a second logical owner, admission or C1 action in that transaction.
- `recover_initial_admitted_media` changes its executing admitted-v3 branch to
  lock intent/submission/cancellation/admission in order 3 before
  receipt/transfer and other handoff rows. It does not retain the existing
  admission-first pair. It skips fresh eligibility and funding mutation; loading
  optional original funding for integrity obeys order 5. Transfer precedence is
  classification precedence after ordered locks, not permission to lock transfer
  before parents.
- `cancel_initial_analysis_explicit` adds the admitted-v3 intent prelock before
  its current submission/cancellation locks; its C1 capture then reenters those
  rows and continues orders 5–9, with no new eligibility gate. The preserved
  legacy fallback is still under the original owner/advisory scope. Its terminal
  replay does not require erased evidence or reconstruct a handoff stage.
- `capture_initial_admitted_cancellation_prestate` retains its existing exact
  funding and source-proof orders and adds the transfer/new rows at the
  specified slots. No call to an old intent-required verifier on transferred
  state.
- The four recovery wrappers retain their initial owner/advisory/scan/history/
  lifecycle acquisition through `lock_initial_preparation_scope`; they must
  enter normalized v3 recovery before acquiring any lower v3 private rows. Their
  unadmitted/v1 paths remain unchanged and cannot reach v3 mutation.
- Generic cancellation's admitted erasure branch keeps its existing terminal and
  no-refund classification, then prelocks the actual applicable private and
  registry rows before source-first erasure. Raw scan/account callbacks skip
  proof/catalog/funding prerequisites; they acquire only applicable erasure rows
  in the same relative order, using their already-held/fail-fast outer scope.

Caller-held exceptions are not silently normalized by acquiring a late lock. Raw
scan UPDATE/DELETE already holds the scan tuple before its BEFORE trigger;
existing owner NOWAIT and advisory try-lock avoid waiting backwards. Tombstone
entry similarly uses the existing fail-fast guard before callback fanout. Owner
DELETE already holds its user row; it processes existing pre-row identities in
ascending scan UUID order and does not update that deleting user tuple. The
supported account procedure cancels conservatively before detachment/deletion.
All of these preserve their original no-new-owner-acquisition rule inside nested
private cascades. Shared quota counter rows retain the exact CASE order above.
Registry cleanup workers acquire only an already-retired object and never any
resource earlier in this table.

The common original user lock already serializes current canonical same-owner
recovery and C1 operations. Their existing pair-order differences are not a
reproduced deadlock finding. Normalization is a requirement for the new
executing v3 graph, with no weakening of that outer serialization. Add
both-winner recovery-versus-transfer and recovery-versus-C1 schedules to verify
it.

The first transfer validates all live original proof, including exact source and
destination membership. Transferred recovery and positive C1 use the
self-contained admitted/transfer proof, exact empty intent-root images and
already-retired source registry. The old `assert_initial_admission_live_receipt`
requires a present intent and allocated sources; it cannot be called unchanged
on transferred state. Retain its pre-transfer checks and implement an explicit
transferred verifier, not a broad exemption based on transfer row existence.
Both require retained receipt digest and original funding correlation; raw
erasure uses neither as an authorization prerequisite.

## Existing nested mutations and planned changes

`retire_initial_preparation_source_objects` locks source registry UUIDs after
updating the source fence; `retire_initial_media_objects` does the corresponding
M1 fence/destination registry work. Their C1 retirement witness calls remain
separate from handoff's exact statement ledger. A transfer executes the
registered source transitions directly under its own protected expectations, not
through a generic helper that could issue duplicate zero-row updates.

Submission BEFORE DELETE invokes `retire_initial_media_on_erasure`, hence any
root submission DELETE can acquire destination locks before its FK children.
Intent BEFORE DELETE invokes `retire_initial_sources_before_erasure`. In a
handoff transfer, that trigger must validate the exact already-retired original
union and matching transfer-stage DELETE event, without repeating retirement. C1
uses its own actual captured retirement delta, including empty already-retired
source transitions. Ordinary raw erasure retains conservative terminal/tombstone
predicates and irreversible retirement.

The currently effective generic cancellation, tombstone callback, scan-change
fence and owner-delete fence delete submission before calling source retirement.
For admitted v3 their canonical roots must prelock the complete applicable scope
and retire sources before destinations/private-root cascades. Do not let a new
child AFTER trigger repair that order by acquiring outer locks too late.

| Root                                                                                  | Required closure                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `internal.cancel_initial_analysis`                                                    | Preserve conservative admitted/unknown and dispatched classification. Complete applicable ordered lock scope before source retirement and submission erasure. No new refund path. Legacy-only behavior remains separate.                         |
| `internal.cancel_initial_analysis_explicit`                                           | Normalize admitted-v3 prelocks, extend protected C1 capture/witness/terminal state to all four rows, and preserve once-only positive-unused original accounting.                                                                                 |
| `guard_initial_analysis_tombstone_scope` → `erase_initial_analysis_for_scan_fence`    | Preserve owner NOWAIT and advisory try-lock before callback. Callback fences lifecycle, locks actual unions, retires source then destination, erases private roots and cancellation evidence. Do not require valid private JSON.                 |
| `guard_initial_analysis_scan_erasure_scope` → `fence_initial_analysis_on_scan_change` | Preserve fail-fast outer acquisition before existing history/accounting fanout. Tombstone creation can already invoke the erasure callback; subsequent handling must be an idempotent empty-state branch, not a second handoff ledger operation. |
| `fence_initial_analysis_before_owner_delete`                                          | Keep rejection until existing scan detachment is complete. For sorted pre-row identities, preserve tombstones and source-first ordered retirement before root cascades. Never mutate the deleting user tuple or invoke positive C1 implicitly.   |
| `public.apply_user_tombstone`                                                         | Preserve conservative generic cancellation while owner is live, followed by existing detachment/deletion. Account fanout remains existing behavior, not a new handoff or Field Trip policy.                                                      |
| Existing expiry callers                                                               | Exact transfer is checked before legacy preparation/M1 expiry. Transfer preserves live destinations until explicit C1/raw erasure; no v1 retirement route is opened to v3.                                                                       |
| Source and destination claim/finish-erasure RPCs                                      | Lock only one already-retired registry object, with SKIP LOCKED claim or token-checked finish. No later outer/catalog/funding row acquisition. Still participate in denial seals and competing-stage absence checks.                             |

Damaged or absent admitted/private proof must not prevent authorized
scan/account erasure from retiring the actual surviving registry union.
Source/destination fences and registry identities outlive private rows and are
the cleanup authority. Strict transfer/C1 proof is required only to advance or
positively refund, not to erase. New private DELETE guards recognize the
existing authenticated terminal root flow and registry retirement; parent
absence alone is never permission.

## Outer scan/account fanout boundary

The expanded definitions also include `public.request_scan_deletion`,
`public.claim_scan_deletion_jobs` and `public.complete_scan_deletion`. Request
locks owner then scan advisory/scan and inserts the tombstone; completion locks
owner, advisory and tombstone before deleting the public scan. A pre-row
admitted identity returns not-found from the existing request route; do not
reinterpret that as cancellation or expose a new route. For existing scans these
owners reach the same guarded raw scan/tombstone erasure path above.

Other user/scan cascade families (purchase, consent, publication, chat, history,
Field Trip) remain visible in the full extract and retain their existing owners.
The new receipt children do not add a direct user/scan FK. Their triggers must
never call back into those unrelated families, acquire a late owner lock, or
settle funding from raw erasure. Existing account/scan fanout is not qualified
by this design review; changed handoff edges must be tested with that fanout in
the full affected gate without absorbing unrelated implementation work.

## Ghost and multi-owner ingress

`public.issue_ghost_profile_merge_handoff(text,text,text)` and
`public.consume_ghost_profile_merge_handoff(uuid,text)` are authenticated-only
security-definer ingress. Issue takes the existing `ghost-profile-merge:<ghost>`
exclusive transaction advisory lock and writes only prepared handoff metadata;
it does not reparent or settle initial evidence. Consume takes that same ghost
advisory lock, its exact handoff row `FOR UPDATE`, purchase-principal rows via
`lock_purchase_principals_for_auth_users` ordered by principal UUID
`FOR UPDATE OF principal`, both `auth.users` rows ordered by UUID `FOR UPDATE`,
then calls `perform_ghost_profile_merge`. The latter takes both `public.users`
rows ordered by UUID `FOR UPDATE` before all merge mutations. New handoff/C1
owners never acquire ghost, auth or purchase-principal resources after their
public-user lock. Existing merge ordering is not changed.

Source exclusion already exists. The submission, preparation-intent and
cancellation owner FKs have `preserve` policies (orders 900, 902 and 901).
`assert_ghost_profile_merge_reference_preconditions(source)` checks every
preserve policy before reparenting; any matching source row raises
`ghost_merge_preserved_reference_present`. Its identifiers come from the guarded
reference-policy catalog with coverage validation, not caller SQL. New durable
rows have receipt-only lineage, so a source-owned receipt necessarily retains a
preserved submission. No new direct user FK or merge policy is required. Source
preconditions remain unchanged.

Target ownership is different. The existing precondition only examines source.
`merge_ghost_complimentary_scan_usage` locks both identities' usage ordered by
`(user_id,client_scan_id)`, merges duplicates, reassigns source usage, then
ranks **all** target holds by `(held_at,client_scan_id)`, releases excess with
`ghost_merge_grant_cap`, and increments target complimentary epoch. This can
change a target's admitted original funding after user locks are released.
Serialization alone is not a durable funding exclusion. The downstream
`prepare_scan_ingestions_for_identity_merge` collision branch can also update a
target reservation when a source job/request is committed; the exclusion covers
paid as well as complimentary admitted funding. The ordinary admission and C1
member guards are transaction-stage scoped; their absence does not reject this
later merge. The downstream `prepare_scan_ingestions_for_identity_merge` and
generic FK reparenting occur after these funding mutations and therefore cannot
serve as the early exclusion.

IC-1 has explicitly assigned History primary sole ownership of the narrowly
required target guard in the existing merge owner and its forward
migration/tests. This is an original-funding consistency prerequisite, not
broader merge or Field Trip work. Place the private guard immediately after both
ordered public-user locks and before the first merge side effect. Keep it inside
the transaction; rejection rolls back the entire consume operation. No repair,
repointing, cancellation, release/refund or invocation is performed by that
guard.

The target footprint predicate is conservative but owner-bound:

1. Enumerate target-owned identities from current initial submission, intent,
   admission, admitted receipt and all four new durable children, cancellation,
   original quota-reservation identity aliases, and complimentary usage. Use
   relational owner/scan columns only, never parse a potentially damaged receipt
   to establish ownership. Retain only identities correlated to admitted-v3 by
   `initial_admitted_settlement_blocked(scan)` or an actual owned v3/receipt/new
   handoff row. Permanent source/M1 fences are correlation evidence, not by
   themselves an eternal target-account ban.
2. Any live private/submission/handoff membership for such an identity blocks,
   including missing or malformed admitted proof. Unknown/already-authorized
   cancellation also blocks even when its private rows have been erased.
   Reserved/uncertain original reservation or held complimentary usage blocks.
3. An identity with only terminal history is eligible only when durable original
   positive-C1 settlement remains provable: owner/scan cancellation
   `dispatch_prevented`, matching `cancelled_pre_dispatch` lifecycle, no private
   family/stage rows, both registry families retired, exactly one original
   target-owned scan-identification reservation with matching request/original
   identity, state refunded, refund_count one, attempt_count one and no stale
   recovery, no surviving reservation-counter links, and no execution/result/
   completion/ingestion contradiction. If complimentary funding is bound, its
   exact original usage is released with `cancelled_before_dispatch` and
   coherent settlement times; no held/consumed/duplicate alias may coexist. No
   source complimentary, quota or ingestion identity may collide with this
   terminal original scan/request: such a collision could otherwise rewrite
   settled target financial history, so it blocks rather than entering existing
   duplicate merge reconciliation for that admitted identity. The guarded C1
   receipt establishes the terminal owner; these remaining durable facts
   independently establish settlement. The erased transient C1 stage is not
   recreated or used as a required lookup.
4. Missing, pruned or contradictory funding/settlement evidence for an
   owner-bound correlated identity blocks; absence of a quota row must not turn
   a surviving unknown cancellation or complimentary hold into eligibility.
   Terminal fences with no remaining owner-bound private, cancellation, quota or
   usage identity do not create a new owner binding or blanket ban.

The guard runs after both ordered public-user locks and before **any** inner
merge side effect. For the terminal exception it uses a dedicated revoked
lock-only owner; it must not call `lock_initial_preparation_scope` unchanged,
because that live-operation helper intentionally rejects terminal cancellation.
Keep that existing helper's terminal rejection intact. Enumerate the owner-bound
candidate scan UUIDs in ascending order, take their exact exclusive ingestion
transaction advisory keys in that order before any terminal subordinate rows,
and then process each scan in the common rank order. A terminal candidate that
cannot acquire/prove its required scope rejects; there is no caught-error
fallback into merge. New private/initial ingress must use the already-held owner
and advisory boundary, so absence is protected by those entry fences rather than
a fictional lock on a missing row.

For each terminal candidate use ranks 2–3 and 5–9 exactly, skipping current
eligibility. Rows expected absent are checked after their family slot; any
private row, live scan/history execution state or foreign-owner mismatch denies.
Within rank 5 attempt precedes links; links use the daily/user/IP CASE order. A
terminal proof requires zero links, so a present link denies before acquiring or
modifying a counter. This branch neither releases counters nor calls any
settlement helper. All actual registry rows are locked in their existing ordered
family slots. After complete acquisition, re-read and validate the entire stable
terminal predicate before merge proceeds; hold locks to transaction end.

| Terminal fact                           | Exact protection and relevant effective writers                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Owner and source alias set              | Both original `public.users` rows `FOR UPDATE` held by `perform_ghost_profile_merge`. Ordinary credit admission/settlement and initial admission/C1 use that owner boundary. Source alias collision is checked before generic merge's duplicate/reparent paths. No helper newly acquires auth/purchase/another owner below this guard.                                                                                                                   |
| Scan/history and lifecycle/cancellation | Ingestion advisory, scan/history `FOR UPDATE`, then lifecycle, intent, submission, cancellation, admission `FOR UPDATE` by scan in rank 3 order. `cancel_initial_analysis_explicit`, generic cancel, request/complete deletion and raw tombstone/scan callbacks use original owner/advisory scope; inner trigger entry uses NOWAIT/try-lock rather than a backward wait. Lock the actual terminal rows as well; do not rely only on owner serialization. |
| Original quota                          | Exact original reservation `FOR UPDATE` in the candidate's funding slot. `finalize_ai_quota_reservation_core` and `refund_expired_ai_quota_reservations` need that row before changes. `prune_ai_quota_state` DELETE needs the row and is additionally excluded by the permanent operation fence. A missing or extra original reservation denies the terminal exception.                                                                                 |
| Provider attempt                        | Exact reservation's attempt rows `ORDER BY attempt_count FOR UPDATE`, requiring only original attempt one. This explicitly excludes an UPDATE/DELETE of an existing child; parent locking alone is not claimed to protect a child UPDATE. The held parent also prevents new FK children/cascade deletion; `guard_initial_cancellation_erased_attempt` independently rejects forbidden retired-state writes.                                              |
| Reservation-counter links               | `FOR UPDATE` using the exact C1 CASE order and keys. Terminal proof requires no links. The parent reservation lock prevents fresh FK links while `finalize_ai_quota_reservation_core` / `release_ai_quota_reservation_counters` require the same parent-owned settlement path; no existing child is silently treated as stable. If links exist, deny rather than touching shared counters.                                                               |
| Complimentary usage                     | Exact target `(user_id,client_scan_id)` `FOR UPDATE` after quota/attempt/links; missing bound usage or conflicting state denies. `settle_complimentary_analysis` takes user then usage; Ghost's credit helper already owns both users then takes `(user_id,client_scan_id)` order. The guard does not enter that helper until proof passes and no source alias collides.                                                                                 |
| Admitted/private absence                | Check all nineteen fixed private catalog members plus both handoff transient tables at their common family slots. Existing owner/advisory serialization, permanent identity and provider barriers reject fresh post-terminal parent/child creation; no FK-parent absence is treated as permission. Any surviving private row denies rather than being repaired.                                                                                          |
| Source registry and fence               | Source fence by scan `FOR UPDATE`, then all actual source objects `ORDER BY object_id FOR UPDATE`; require retired fence and retired union. Retirement owner is `retire_initial_preparation_source_objects`; source claim/finish RPCs lock only retired registry rows, so these explicit object locks serialize their token/marker mutations without any backward outer lock.                                                                            |
| Destination registry and fence          | M1 fence/cohort/v1 slots in rank 8, then destination union `ORDER BY object_id FOR UPDATE` in rank 9; require irreversible retirement. `retire_initial_media_objects` and destination claim/finish RPCs cannot update the locked rows until merge ends.                                                                                                                                                                                                  |
| Permanent identity / execution absence  | Operation fence is immutable under `reject_initial_permanent_mutation`; existing source provider barrier remains blocked. Re-read invocation, result/completion and ingestion aliases after owner/advisory and original accounting scope; callable provider/ingestion paths cannot create admitted-v3 execution behind these fences. A contrary existing row denies. No new execution grant is introduced.                                               |

Generic `prune_ai_quota_state` and `refund_expired_ai_quota_reservations`
exclude reservations whose original or request identity has an
`initial_analysis_operation_fences` row. A valid v3/C1 keeps that permanent
fence; preserve this exclusion. Missing/pruned state is still exercised as
damage and fails closed while owner-bound cancellation or a surviving hold
exists. Permanent fences alone do not invent an owner identity after all owned
evidence is gone. Pruning, finalization, child-update and cleanup races are
explicit post-implementation tests of this stable-proof boundary, not assumed
passed.

Direct-helper bypass inventory: `perform_ghost_profile_merge`,
`prepare_scan_ingestions_for_identity_merge`,
`merge_ghost_complimentary_scan_usage`, `merge_ghost_revenuecat_state`,
`reparent_ghost_user_foreign_keys` and the purchase-principal lock helper all
have only `{postgres=X/postgres}` in the exact486 ACL extract. API roles cannot
call these helpers directly. Their security-definer callers and fixed references
remain in the full catalog; no new caller grant is introduced. A privileged
migration administrator is the existing trusted boundary, not a simulated API
role or proof of private call-stack identity.

Required schedules include source-owned and target-owned admitted work, with
both merge-first and handoff/admission/C1-first winners. Source merge waits on
the original ordered public-user lock then rejects its existing preserve row.
Target merge waits and then rejects live or unresolved admitted funding; if
positive C1 commits first and all terminal settlement facts remain available,
the ordinary merge path may proceed without changing original retired evidence.
If merge obtains both public-user locks first, active admission/handoff/C1
waits; the guard must reject before any merge accounting mutation and rollback
releases the lock for the original operation. Also test unknown cancellation
with a surviving hold, pruned/missing reservation, damaged receipt, target-only
admitted state, paid and complimentary funding, no-source-usage early return,
and a valid terminal-retirement case. Assert exact unchanged merge, entitlement,
quota, credit, handoff and registry state on every denied attempt. Test actual
issue/consume ingress and API denial of direct helpers. Do not infer source
exclusion protects the target or that a terminal label alone proves a refund.

## Cascades, deferred checks and trigger order

Intent DELETE's exact FK graph has five direct children: source mapping, source
verification, execution grant, output manifest, outcome. Output mapping is below
output manifest. All seven intent-root relations enter the event ledger and
statement graph. Source mapping has source-storage/cohort triggers; the other
five private execution children have execution-private/cohort triggers. Their
DELETE checks rely on irreversible source retirement and cannot be skipped.

Submission DELETE cascades through admission and its receipt, M1 cohort, v1 M2
preparation/verification, result and completion. The four new rows attach to
receipt, so C1's submission-root witness must account for their actual nested
OLD images regardless of FK visitation order. The receipt's unique owner pair
already exists. New row images cannot outlive that receipt or survive C1.

All effective trigger definitions, enabled states and RI timing are in the
261-relation extract. Alphabetic ordering is relevant only among matching
triggers for the same timing/event; internal RI triggers are retained but their
OID-derived names/child visitation order are not protocol constants. Statement
frames require physical parent deletion after its BEFORE validation, not the
parent AFTER recorder having run first. Empty direct child DELETE statements are
accounted for; nested output-mapping statements occur only for a deleted
manifest. Transfer-state deferred constraints are forced while its stage exists;
stage-completion constraints remain deferred until exact stage consumption.

Existing admission/C1 guards must inspect competing handoff stage presence and
seal before permitting any relevant root, registry or accounting mutation. No
exception means “a transfer receipt exists” or “a GUC matches.” Handoff guards
must reciprocally reject admission/C1 stages; immutable expected OLD/NEW images
and statement frames remain mandatory. A forged denial seal may only over-deny.

## Qualification after implementation

Fresh exact candidate extraction must verify actual new FKs, ACL/RLS, role
denial, trigger timing, six-relation seal coverage, closed catalogs and changed
effective bodies against this reviewed delta. Static indexes are not race proof.
Required real-role two-session cases include both winners for transfer versus
C1, expiry, scan detach/delete, tombstone and owner deletion; cleanup
claim/finish versus retirement; unrelated-owner contention;
interrupted/rolled-back statement frames; zero-row and repeated same-relation
writes; corrupt-proof raw erasure; and exact post-transfer recovery/C1. No
callback, status, copied byte or transfer authorizes a provider invocation or
refund of uncertainty. Original stage93 deadlocks remain unreproduced, cause
unknown, with only their prior limited inactive acceptance.
