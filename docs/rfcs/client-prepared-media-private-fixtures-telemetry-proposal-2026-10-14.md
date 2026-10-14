# CPM-1 private fixtures and partial telemetry: decision proposal

Status: October 14, 2026. **R2-F1 and TM-1 design choices approved; Emre
confirmed as operator.** Direct human approval was verified in advisory turn
`01a138f7-a38d-75a0-b0c8-31f2d0eb9665` for checkpoint `a39525950`. The
[bounded local construction request](client-prepared-media-local-construction-request-2026-10-14.md)
was subsequently approved for four hours of local construction and review. That
local candidate has independent and IC-1 local-only concurrence; hosted
setup/execution remains separately gated. Approval accepts TM-1's measurement
limitations and platform-only established total-memory backstop as a design
direction, not permission to execute hosted risk or proof of a production
budget. The 160 MiB guard is not adopted. Emre owns future separately authorized
setup/disable/revocation/cleanup. Package/storage limits stay unchanged,
activation disabled, AWS unapproved, auto-prompts paused.

The original proposal below is retained as the approved design text. Its
requests to approve the two design choices or confirm Emre are now satisfied;
wording about other approvals still applies. No provisioning, credentials
changed, construction, installation or hosted testing follows from design
approval.

## Recommended decisions

**R2-F1:** choose one dedicated private Standard R2 bucket in the existing
Cloudflare account for synthetic verifier fixtures. No suitable existing private
bucket was visible in the authorized inventory. Proposed name:
`merian-cpm-verifier-fixtures`, subject to availability at an authorized setup.
Keep the current public `merian` bucket and unrelated `portfolio` unchanged.
This is storage configuration using the existing service, not another execution
server. It does not provision or qualify the eventual private history store.

**TM-1:** replace the unexecutable proposed 160 MiB total-memory abort guard
with an explicitly partial V8 trend experiment, conservative sampled stop rules
and the existing finite workload controls. Native-inclusive memory has no proven
application-visible guard on this target. Platform enforcement would be the only
established total-memory backstop; approving TM-1 must explicitly accept that
limitation and possible termination before cleanup. This is not adopted
implicitly and is not a production memory-budget decision. If that risk is
unacceptable, keep the hosted experiment blocked; another Supabase project would
not fix the metric gap.

## R2-F1: concrete arrangement

| Concern         | Proposed choice                                                                                                                                                                                                                                                                                                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Privacy         | No custom domain, r2.dev disabled, no public bindings/proxy, CORS absent. HTTPS authenticated S3 API only. Verify settings before loading any fixture.                                                                                                                                                                                                                            |
| Contents        | One run namespace `cpm-verifier/<opaque-run>/`; exactly two 32 MiB objects and one 64 KiB control, 67,174,400 bytes total. Synthetic deterministic bytes only, no user media, original metadata, operation IDs or customer object inspection.                                                                                                                                     |
| Placement       | Existing account, Standard class; request an eastern North America location hint near the selected Supabase region if offered. A hint is not an exact placement or latency guarantee.                                                                                                                                                                                             |
| Operator access | Existing authorized account operator creates/configures the bucket only after approval. Setup/cleanup credentials, if needed, are dedicated Object Read & Write scoped to this bucket, held off the function and app. Planned operations are three single-part PUTs, bounded HEAD/LIST reconciliation and three DELETEs; no copy, multipart, overwrite or customer-prefix access. |
| Runtime access  | Dedicated bucket-scoped Object Read only credential for the experiment. Handler additionally pins the exact three keys, lengths and digests and permits GET only. The credential may also allow LIST; do not claim provider-enforced exact-key or GET-only scope. No bucket admin/write credential enters the function.                                                           |
| Write closure   | Complete and acknowledge each setup PUT before its fixture can be read; close the setup process before bulk runs. No writes during measurement. Unknown PUT result stops setup for bounded reconciliation; never overwrite/resend or invent more fixture keys. This is a trusted-operator benchmark, not proof of hostile-client ingress or general immutable-create semantics.   |
| Lifecycle       | No object-expiry rules on the run namespace, no copied staging/quarantine rules and no bucket lock that would prevent reviewed cleanup. Incomplete multipart defaults may remain, but multipart is never used and their expiry is not closure evidence. No event notifications, Worker, cron or access-log sink added.                                                            |
| Retention       | Keep only through the approved run and cleanup window. Delete acknowledged, run-owned fixtures after positive writer/reader closure. An unresolved fixture remains private and counted in the fixed inventory; no automatic TTL deletion, capacity release or new run. Review an unresolved obligation within 24 hours.                                                           |

R2 buckets are private by default; both public access paths must remain off.
[R2 public-access documentation](https://developers.cloudflare.com/r2/buckets/public-buckets/).
Bucket-scoped read/read-write credentials are supported; exact operations above
are an additional reviewed driver/handler restriction, not a claim of
prefix-scoped permanent tokens.
[R2 credential permissions](https://developers.cloudflare.com/r2/api/tokens/).

**Ownership:** History primary owns the candidate, fixed manifest and evidence.
Recommend Emre as the accountable operator for later authorized setup, disable,
credential revocation and cleanup, with History primary preparing the exact
packet. IC-1 and independent reviewers stay read-only. The execution approval
must confirm the available operator. Fixture ownership uses that fixed manifest;
no production shared-asset reference or erasure schema is introduced. Production
asset release remains server-authoritative under CPM-1's separate open gates.

At normal completion, disable the test route, close readers, delete the three
owned objects, confirm absence and revoke experiment credentials. The empty
private bucket may remain with no active experiment credentials; bucket deletion
is a separate optional operation. On uncertainty, disable first, retain the
small private unresolved inventory and record its owner; do not treat route
removal, expiry or credential revocation as proof that in-flight work ended. No
cleanup action is performed now.

### Expected costs

At published Standard R2 rates, under 65 MiB for a day and this packet's small
operation count have unrounded consumption cost well below one cent. Existing
free allowances may cover it, but the account's remaining allowances were not
inventoried. Billing rounds storage and operation units: crossing existing
monthly boundaries could add one storage GB-month ($0.015), one Class A million
($4.50), and one Class B million ($0.36), approximately **$4.88** combined. R2
direct egress is free. This is an estimate of this finite packet, not a cap on
the shared account's bill. No new paid logging or compute service is proposed.
[R2 pricing and rounding](https://developers.cloudflare.com/r2/pricing/).

Supabase's 26 invocations are similarly tiny usage, but could cross one $2
million-invocation billing boundary. Recommend a later **$10 incremental
experiment allowance**, covering these roundings with room for bounded
telemetry/network charges; no spend-cap change or paid add-on. Exact execution
approval must confirm pricing and current allowances. Shared traffic and a
fixture retained into later billing periods are not covered by this estimate.
[Supabase invocation pricing](https://supabase.com/docs/guides/platform/manage-your-usage/edge-function-invocations).

## TM-1: what can usefully be measured

| Measurement            | Proposed method and interpretation                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V8 heap                | Record `heapUsed`, `heapTotal` and `external` separately in bytes at entry, read/hash phases, cleanup and quiescent boundaries; sample every 100 ms only while active. Aggregate locally, include timer overhead, bound sample storage and stop the timer before terminal acknowledgement.                                                                                                                                            |
| Partial stop proxy     | Define `P = heapTotal + external`, a deliberately conservative sum of reported V8 fields only. Keep component values; overlap or accounting changes may distort P. It excludes unreported native allocations and is neither RSS nor total memory. Propose abort at sampled P >= 96 MiB, including before opening a reader. This is a new proxy rule needing approval, not equivalence to the historical 96 MiB process-memory target. |
| Retention signal       | Compare same-worker quiescent samples across serial reads. Propose stopping on three consecutive positive quiescent P increments with a cumulative increase >= 8 MiB. This heuristic favors early investigation and may stop on normal GC timing; it neither proves a leak nor establishes a plateau when absent.                                                                                                                     |
| Timing and closure     | Monotonic phase/overall wall time, bytes, digest outcome, cleanup completion and bounded case/boot aliases. Use the previously accepted positive reader-closure acknowledgement; memory returning to baseline is not part of that proof.                                                                                                                                                                                              |
| Runtime events         | Retain available shutdown reason, memory snapshot, CPU total and worker correlation as diagnostics. RSS zero is unavailable, not zero consumption; shutdown memory is not lifetime peak. Worker CPU totals are not divided among requests or inferred from wall time.                                                                                                                                                                 |
| Warm reuse/concurrency | Retain the two nine-request cohorts and three arrival pairs, worker aliases and actual topology. Routing gaps remain gaps; no added calls, forced affinity, keepalive or claim of same-worker contention when workers differ.                                                                                                                                                                                                         |

The upstream user-worker
[bootstrap](https://github.com/supabase/edge-runtime/blob/main/ext/runtime/js/bootstrap.js)
and
[runtime operation](https://github.com/supabase/edge-runtime/blob/main/ext/runtime/lib.rs)
currently expose V8 statistics and hardcoded zero RSS. This does not identify
the deployed build. The two previously reserved observability calls must check
actual fields, sane units, correlation, bounded reporting and closure before
bulk-fixture upload/read. Missing/invalid fields, unusable sampling or closure
failure stops the packet. A V8 field's label does not prove native coverage.

[Supabase shutdown metadata](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained)
can add failure diagnostics. Public documentation lists 256 MB memory, 2 seconds
request CPU and 400 seconds paid-plan worker lifetime; these are provider
limits, not new product targets or empirical measurements of this candidate.
[Platform limits](https://supabase.com/docs/guides/functions/limits). Exact
runtime evidence available at execution must be recorded; no induced memory/CPU
kill is proposed to test those limits.

### Safety amendment and production-alpha isolation

Retain the accepted 26 invocations, two concurrent clients, one physical reader
per worker, no simultaneous reads of the same fixture globally, 30-second read
deadline, 30-minute run plus 15-minute cleanup, 256 application HTTP calls (192
ordinary + 64 reserved cleanup), 2 GiB media transfer and 512 MiB local artifact
limits. Warm cohorts span at most 320 seconds. One fixed driver, no automatic
retries, redirects, restarts, callbacks or background work. A sampled proxy
breach, growth rule, runtime kill, integrity failure, uncertain closure, missing
telemetry or bounds breach stops new work; preserve evidence and disable.

The proxy and timer can miss native growth, short peaks or a blocked event loop.
Cancellation may lag. **No application-enforced total-memory ceiling below the
platform limit is claimed.** TM-1 would accept this residual exposure for this
finite synthetic representative handler only. The unapproved 160 MiB proposal
becomes non-executable historical design, not a fallback setting. A clean result
would support only measured V8 trends and the observed runtime behavior; total
peak, native retention, one-second CPU and complete-verifier acceptance remain
open. No automatic runtime implementation or higher budget follows.

For a later separately approved installation, propose a unique test-only route
`cpm-verifier-characterization` in the existing production project, never wired
to the app, identify, funding, queue, database mutation, provider or scheduling
paths. Use the reviewed auth helper plus a server-controlled single operator
identity, dedicated run capability and fixed expiry; reject ordinary callers
before media access. Pin run/case/fixture choices server-side. The sole trusted
driver owns the 26-call bound; there is no new distributed limiter and no claim
that leaked credentials could not cause extra calls across workers.

Only experiment-specific secret names may be added later. Do not reuse, rotate
or overwrite app R2 credentials. Supabase secrets are project-level; this is not
a separate credential sandbox. Runtime built-ins can include privileged project
keys. Review imports and every outbound path for absence of database/provider
calls; function naming and disabled feature flags are not security or resource
isolation.
[Supabase environment boundaries](https://supabase.com/docs/guides/functions/secrets).

Independent stop controls must be named in the exact installation packet:
operator stops the driver, removes/disables only the test route through a
reviewed control-plane path, and revokes the experiment R2 read credential.
Fixed expiry blocks fresh authorized calls, but is not a kill switch for active
work. Preserve outstanding reader obligations if termination cannot be proved.
Do not rely on restarting the project or altering ordinary app routes to stop.
The existing whole-backend release hold is not waived: the exact-SHA test-route
installation/disable path needs separate release approval, not a fleet deploy.

This shares project Auth, gateway, telemetry, quotas and billing; physical
resource isolation from app traffic is unproved. Recommend an operator-attended
quiet window, no other planned deployment, and review of existing aggregate app
health before/between cohorts within the fixed observation-call budget. Any
service alert, new throttling/5xx pattern or operator concern stops new work
without attributing causality to the experiment. No synthetic calls to ordinary
app routes, production response capture or extra monitoring service is proposed.

## Approval requests and sequence

1. **Decision only, requested now:** approve R2-F1's private fixture arrangement
   and TM-1's partial measurement/safety change, explicitly including that the
   platform supplies the only established total-memory enforcement. Confirm Emre
   as the proposed operator. This selects the design; it performs nothing.
2. **Local construction, separate:** after those decisions, authorize at most
   four engineering hours for the already bounded representative handler and
   fixed driver, with local correctness checks and independent/IC-1 review.
   Return exact sources, dependency manifest, metric definitions, admission and
   disable behavior. No complete-verifier, schema or production workflow work.
3. **R2 setup, separate named operation:** approve creation of only
   `merian-cpm-verifier-fixtures` in the inventoried Cloudflare account, the
   private settings above and bucket-scoped experiment credentials. No fixture
   writes, Supabase secret changes or function installation are included in that
   setup approval. Name the exact operator and allowed configuration checks.
4. **Exact-candidate execution, later:** approve the production Supabase route
   installation and independent disable path, experiment-specific secret
   changes, the three fixture uploads/closure, 26-call packet, bounded
   telemetry, $10 incremental allowance and run-owned cleanup/revocation.
   Confirm the window, owner and local reviewed evidence. The two-call preflight
   precedes bulk work; failure does not authorize a different test. No ordinary
   endpoint deploy, activation, provider call or app/device distribution is
   included.

Step 2 was subsequently approved under the bounded local construction request;
its current outcome is recorded there. Step 3 still requires separate explicit
approval and can be scheduled independently. Step 4 requires both, completed
runtime packaging and exact candidate review. Existing push/merge/deployment
restrictions continue. History primary remains the only writer; independent and
IC-1 review may correct this proposal but cannot adopt it for the human.
