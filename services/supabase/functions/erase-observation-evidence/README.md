## November 20 — typed capture-stage cleanup

The local V4 successor also drains retired capture stages through the existing
dispatcher. The new typed acquisition selects one oldest due obligation across
History and stage registries. Stage objects use `capture-stage/v1/` and require
their recorded private backend digest; History retains `evidence/v1/`. Marker
writing and settlement preserve the namespace/backend/object/token tuple. No
stage TTL, additional retirement RPC or second worker is introduced. Old worker
acquisition remains History-only. All existing request/claim/reserve budgets
stay unchanged, and exact prior settlement remains available after pause.

The current terminal receipt is V4. SQL can reconcile old V2/V3 receipts, but
health schema2 and the monitor require V4 before stage cleanup is qualified.
Stage failures, expired claims, pending/deferred work and unknown/oldest age are
reported separately and count toward the shared drain budget. Local contract
checks do not establish hosted storage or rollout qualification. Any future
cutover requires the same explicit target authorization, pause and positive
drain before replacing SQL/Edge; no activation is part of this work.

## November 14 — local mixed cleanup integration

The prepared V3 worker adds one composition retirement opportunity under the
existing current-dispatch fence. No schedule, flags or credentials change. The
90-second request, 50-second pre-claim reserve, original 60-second claim and
single-object marker limit remain unchanged. Three worst-case 12-second
retirement stages still leave the required claim/marker/settlement budget;
scheduling overhead can make the worker decline a fresh claim.

Deployment must pause and positively drain the existing worker before changing
its receipt generation, apply the SQL/Edge candidate, verify V3 support, then
resume only with the explicitly approved target operation. Retained unknown
requests are never cleared automatically. Migrations accept old V2 terminal
receipts, but an old database cannot consume V3 receipts. This is local
preparation, not deployment or complete mixed reanalysis acceptance.

# Erase observation evidence

Prepared service-authenticated POST worker for private History and capture-stage
outboxes. `private_evidence_erasure_enabled` defaults false and independently
gates new retirement and claims. The prepared private scheduler and monitor are
inactive; no cron registration or activation is included. Configured source
participates in normal future main deployment planning; runtime-off is not a
deployment exclusion. This worker is separate from public-copy erasure.

One invocation gives each existing retirement owner one bounded opportunity:
photo/audio retires at most one expired unbound cohort (up to five receipts) or
one legacy receipt; video retires at most one complete six/seven-object
allocation; mixed compositions retire at most one complete allocation of up to
eight objects. Immutable descriptors and expiry remain with their SQL owners. A
failed or unknown retirement acknowledgement does not retry that lane or block
the other lanes and already-enqueued obligations. The worker then claims at most
one due opaque object, writes a permanent empty marker using dedicated
private-history write credentials, verifies HEAD, and settles the original
token. The outbox survives private history deletion. Caller bodies and keys are
never used as authority. Only service authentication can reach the service-only
database facades.

The 90-second shared request deadline includes twelve-second RPCs. The original
60-second claim is never renewed; the effective deadline is capped by its exact
returned expiry and the local claim-start clock. PUT and HEAD share 25 seconds
and begin only with 38 seconds remaining, leaving twelve seconds plus a margin
for completion. Parent cancellation reaches both storage requests. The worker
never DELETEs the object: the permanent marker blocks delayed conditional
uploads. A missing object alone is not erasure evidence.

The local recovery-fence successor requires `X-Merian-Evidence-Dispatch`;
missing or malformed values return400 before work. A canonical lowercase UUIDv4
is passed into each versioned acquisition RPC, which independently verifies the
current enabled dispatch under a singleton lock held through that operation.
Only completed work returns the strict nine-field terminal receipt:
`schema_version: 4`, `dispatch_id` equal to that UUID, plus seven counters
including `composition_retired` (0–8). SQL still accepts already-dispatched
V2/V3 receipts and records their generation; they do not certify capture-stage
cleanup. A present empty, malformed or duplicate-combined header returns400
before any worker operation; it never falls back to legacy. The UUID never
replaces service authentication or object-claim authority. It is not logged or
included in health telemetry and is echoed only after terminal work. Errors
never emit a terminal correlation receipt. A failed lane's zero count is
unknown, not proof that its transaction made no changes. Each retirement RPC has
its own12-second cap under the same90-second absolute deadline. Parent
cancellation or overall expiry stops subsequent work. The worker does not
acquire a claim with less than 50seconds remaining for its12-second request and
existing38-second reserve; zero claims never proves an empty registry. `marked`
means the origin marker was verified; `acknowledged` means SQL accepted a
success or failure report. Failed marking may therefore return
`marked=0, acknowledged=1` and remains retryable. Unknown writes or
acknowledgements are never retried inside the request; claim expiry and the
durable registry retain recovery. Existing-token settlement remains available
after the gate closes. No owner, object key, raw error, inference or credit
information is returned or logged.

Monitoring must treat retirement failures, a claimed-but-unmarked object, or a
marked object without acknowledged settlement as unhealthy. HTTP200 alone is not
success. One invocation still marks at most one object, not one cohort.

Activation requires separately authorized recurring draining and backlog/oldest
age monitoring, real private-bucket policy and credential verification, and
storage race qualification. Local fake transport tests do not prove hosted
storage or CDN behavior. See the
[canonical contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-private-evidence-cleanup-rpcs).

Regression owners are the worker's `*_test.ts` files, the SQL dispatch-fence
catalog, and `observationEvidenceDispatchConcurrencyDb.test.ts` /
`observationEvidenceDispatchUpgradeDb.test.ts` under `functions/_tests`. The
upgrade test loads the exact migration through Deno and rolls back its legacy
reconstruction; it does not prove a hosted cutover. Run pristine catalog tests
before committed full Edge/race fixtures, which intentionally can retain
accounting and erasure evidence after deleting synthetic users.

## Prepared operations and unknown outcomes

Migration `20261110190707_history_private_evidence_drain_health.sql` prepares a
private singleton dispatch slot, aggregate service-only health RPC and immutable
`first_observed_at` for future outbox obligations. Older rows retain NULL age;
retry clocks are never substituted for original age. Existing evidence tied to
an intent or result remains retained and is counted separately.

The scheduler is `internal.dispatch_observation_evidence_erasure()`. It accepts
no caller arguments and requires its private `enabled` flag plus exact
`approved_project`/Vault URL agreement. Vault values take precedence; only NULL
falls back to the existing app settings. The existing server-header helper
handles opaque keys and legacy service JWTs. Its fixed private endpoint uses a
120-second HTTP timeout. The proposed one-minute cron is not created here.

A durable pending request prevents overlap across cron transactions. Only a
strict, bounded V2, V3 or V4 terminal worker receipt with the original durable
random `pending_dispatch_id`, exactly one matching transport response, and a
finite nonfuture response timestamp releases the slot automatically. Migration
`20261111200839_correlate_private_evidence_dispatch.sql` adds this correlation
without backfilling legacy pending slots. Numeric transport IDs can repeat after
unlogged pg_net storage recovery, including recovery without a new postmaster;
ID, boot time or catalog OIDs alone are not correlation proof. Valid failure
receipts release the transport slot while retaining the underlying object
obligation. Missing responses, gateway errors, malformed receipts and timeouts
remain unknown and hold the original slot. Elapsed time alone never releases it.
Success ages use the retained transport response timestamp, not the later
scheduler observation time. pg_net0.19.5 defaults `created` to transaction
start, so it can precede dispatch and is a conservative age clock, not the
actual HTTP completion time. Neither bodies, headers nor raw errors enter
persistent telemetry. UUID and request ID are committed and cleared together; an
enqueue ID collision rolls back the queued request as well.

The local successor migration
`20261112003746_fence_legacy_private_cleanup_acquisition.sql` permanently denies
all three original no-argument acquisition RPCs **in place**, preserving their
OIDs. It copies effective retirement/claim implementations into new private OIDs
and adds distinct `*_for_dispatch(p_dispatch_id UUID)` facades. The original
exact-token finish RPC remains available after rotation or pause. Missing/stale
UUID, disabled worker, missing slot, wrong project transport or closed cleanup
gate refuses acquisition. This does not promise one invocation per dispatch;
same-dispatch redelivery remains subject to existing registry/claim safety.

This successor is local and incompletely verified; deployment1867 uses frozen7c
and is unaffected. Migration does not change gates, cron, pending request or
claims. Old deployed workers become unable to acquire work after permanent
legacy denial. New workers never fall back to old RPCs. Preserve the original
legacy hold through the coordinated cutover.

Before activation, commit the permanent denial while producer and cleanup gates
remain closed, then establish and verify a post-commit transaction drain
barrier. Already-running old bodies can survive DDL/revocation. Positive
transaction-exit proof must cover every capable backend and prepared
transaction, with complete activity visibility, fresh observation and a retained
server cutoff; elapsed time alone is insufficient. Confirm no prior external
claim/effect and recheck the original empty-work invariant. A delayed old HTTP
delivery then encounters a permanent database denial even after new media
admission opens. This procedure is still preparation, not an approved executable
recovery command.

`get_observation_evidence_erasure_health()` reads aggregate queue partitions,
known oldest age, unknown-age count, expired retirement discovery candidates,
intent/result-bound objects, unbound objects outside discovery, and sanitized
worker/schedule readiness. Discovery is a lock-free estimate, not authority or
proof of locked retirement eligibility; video discovery does not revalidate the
full source/descriptor receipt. The retirement owners remain authoritative. The
monitor accepts both exact legacy and mixed health shapes. Mixed health requires
the paired composition count and nullable receipt generation; null/V2 reports
`composition_receipt_unverified` even with an empty queue. V3 does not override
heartbeat age, worker failures or object-capacity limits. Unknown or partial
fields reject without exposing the response body. Health reads never reconcile a
slot, claim work or modify any state.

The monitor script is
`services/supabase/scripts/monitor_observation_evidence_erasure.ts`. It requires
a recent successful heartbeat even when no work is claimable. Proposed local
thresholds are ten/thirty minutes of queue or discovery age, sixty/180 objects,
and five minutes without a successful heartbeat. These are finite-beta alert
policies awaiting qualification, not a proved throughput or retention SLA. One
invocation marks at most one object; sixty objects already imply at least an
hour at one invocation per minute before failures or transport delay. The GitHub
observation cadence is ten minutes and can itself be delayed.

The workflow requires `main`, the Production environment and explicit repository
variable `EVIDENCE_ERASURE_MONITOR_ENABLED=true`. Nothing in this change sets
that variable. Deployment and later activation must bind the exact candidate,
endpoint configuration, dedicated storage policy/credentials, approved project,
cron command and monitor to one reviewed operational packet.

For an unknown slot, pause new dispatch and preserve the original request and
object-claim evidence. An operator must establish that the original worker is
quiescent and reconcile its durable marker/settlement outcome before any
explicit maintenance clears that exact slot. A missing response, expired
response retention or an elapsed timeout is not sufficient proof. This may
require separately authorized inspection or maintenance; the health RPC and
monitor deliberately cannot repair or clear it. Do not assume a pg_net TTL;
verify the deployed extension and response retention before activation.

## Failure-stage diagnostics

The proposed diagnostic patch emits `private_evidence_rpc_failed` through the
shared identity-safe logger. Its stage is one of `retire_history`,
`retire_video`, `retire_composition`, `claim`, or `finish`. Its category
distinguishes parent cancellation, the existing RPC deadline, four allowlisted
database error classes, and otherwise generic database or transport/runtime
failure. `database_query_cancelled` (SQLSTATE 57014) does not distinguish a
statement timeout from another query cancellation, nor execution from lock
waiting. A permission category does not distinguish dispatch-fence refusal from
other authorization refusal. A malformed finish response emits only the fixed
`rpc_invalid_response` category; its payload is never logged.

The HTTP boundary also emits `private_evidence_worker_failed` with fixed
`worker` / `worker_unavailable` tokens. No error messages, SQL text, response
bodies, dispatch identifiers, object identifiers, claim tokens, backend digests,
or request headers enter these events. Logging failure cannot replace the
existing response or error. The patch changes no deadlines, retry policy, SQL
locks, claim/settlement rules, terminal receipts, activation flags, or
monitoring thresholds. It is diagnostic preparation, not proof of the November
27 cause or permission to restart cleanup.
