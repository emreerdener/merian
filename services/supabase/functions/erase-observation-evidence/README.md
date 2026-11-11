# Erase observation evidence

Prepared service-authenticated POST worker for the private history outbox.
`private_evidence_erasure_enabled` defaults false and independently gates new
retirement and claims. The prepared private scheduler and monitor are inactive;
no cron registration or activation is included. Configured source participates
in normal future main deployment planning; runtime-off is not a deployment
exclusion. This worker is separate from public-copy erasure.

One invocation gives each existing retirement owner one bounded opportunity:
photo/audio retires at most one expired unbound cohort (up to five receipts) or
one legacy receipt; video retires at most one complete six/seven-object
allocation. Immutable descriptors and expiry remain with their SQL owners. A
failed or unknown retirement acknowledgement does not retry that lane or block
the other lane and already-enqueued obligations. The worker then claims at most
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

Legacy requests without `X-Merian-Evidence-Dispatch` return only `retired`
(photo/audio,0–5), `video_retired` (0–7), `retirement_failures` (0–2),
`claimed`, `marked`, and `acknowledged` (0–1 each), and are no-store. A
canonical lowercase UUIDv4 in that service-only header selects the strict
eight-field terminal receipt: `schema_version: 2`, `dispatch_id` equal to that
UUID, plus the same six counters. A present empty, malformed or
duplicate-combined header returns400 before any worker operation; it never falls
back to legacy. Correlation grants no object or service authority, is not logged
or included in health telemetry, and is echoed only after terminal work. Errors
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
strict, bounded v2 terminal worker receipt with the original durable random
`pending_dispatch_id`, exactly one matching transport response, and a finite
nonfuture response timestamp releases the slot automatically. Migration
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

Mixed rollout is intentionally fail-closed. New worker/old scheduler preserves
the legacy shape; new scheduler/old worker holds the six-field response as
unknown. Deploy the compatible worker before allowing new dispatch where
practical. An existing ID with NULL correlation always remains held, including
the currently observed beta slot; deployment never repairs it. A separately
authorized original-receipt recovery is required. No gate or schedule change is
included in this forward migration.

`get_observation_evidence_erasure_health()` reads aggregate queue partitions,
known oldest age, unknown-age count, expired retirement discovery candidates,
intent/result-bound objects, unbound objects outside discovery, and sanitized
worker/schedule readiness. Discovery is a lock-free estimate, not authority or
proof of locked retirement eligibility; video discovery does not revalidate the
full source/descriptor receipt. The retirement owners remain authoritative.
Health reads never reconcile a slot, claim work or modify any state.

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
