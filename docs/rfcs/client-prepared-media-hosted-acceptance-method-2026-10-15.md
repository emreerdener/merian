# HAM-1: hosted acceptance method proposed for approval

October 15, 2026. **Proposal only, not adopted or executable.** Prepared from
existing evidence following HQ-1A; no new platform inventory, tests,
construction or hosted actions. Activation remains disabled, AWS and 160 MiB
unapproved, limits unchanged, auto-prompts paused. History primary owns the
proposal; independent and IC-1 reviewers remain read-only.

## Recommendation

Adopt **separate, candidate-specific acceptance decisions** for local reuse,
hosted request boundaries and complete-product readiness. Preserve the completed
local GAC-1 result. Do not attempt to run its 680-second same-module schedule on
a platform whose documented paid worker lifetime is 400 seconds, and do not
compress that schedule or pool workers under the GAC-1 label.

For the next hosted resource decision, recommend the five-call, serial boundary
method below, **only after its measurement prerequisites are demonstrated and an
exact candidate is separately approved**. At present they are not demonstrated:
HAM-1's current disposition is `hosted_resource_method_unavailable`. Therefore
recommend **zero new tests now**. Approving this method would specify what
future evidence must establish; it would not authorize a speculative campaign to
discover whether the necessary measurements exist.

This is deliberately narrower than full hosted acceptance. It cannot close warm
reuse, concurrent admission, whole-package or complete-verifier acceptance.
Those remain explicit gates. A boundary pass would be useful for a materially
changed candidate, not grounds to repeat the already qualified old transport. If
the objective is to close all hosted acceptance immediately using only the
current metrics, the answer is **not possible under the unchanged contract**.

## Evidence carried forward

| Evidence                           | Retained meaning                                                                                                                             | Limits on reuse                                                                                                                                                                                     |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Local GAC-1 at `2234b483b`         | One exact 20-read same-worker schedule passed; peak partial proxy 38.796025 MiB; cross-cohort Q increase 7.8125 MiB; case-4 warning retained | Finite local partial-V8 evidence only. No hosted/native/CPU or indefinite-reuse claim. Changed allocations, imports, sampling, lifecycle or packaging require an impact decision before reusing it. |
| Prior hosted candidate `9c88cc72d` | 25 verified private-R2 reads and positive scoped cleanup; 25 distinct aliases                                                                | Old candidate transport evidence. Client pairs did not establish physical overlap or same-worker contention. Not transferable to new code by assertion.                                             |
| HQ-1A result at `49f0e0be0`        | Chrome access resolved; report exposes minute/function mean elapsed milliseconds                                                             | No attributed CPU, native peak, current runtime build, retention or affinity qualified. No historical experiment records retrieved.                                                                 |
| Existing TM-1                      | Approved finite partial-V8 characterization with platform-only established total-memory backstop                                             | Still valid for its approved design scope. Does not satisfy the separate total-memory/CPU acceptance targets. HAM-1 does not retrospectively invalidate TM-1.                                       |

Sources: [local result](client-prepared-media-gac1-local-result-2026-10-15.md),
[HQ-1 feasibility](client-prepared-media-hosted-qualification-decision-2026-10-15.md),
[HQ-1A findings](client-prepared-media-hq1a-chrome-result-2026-10-15.md), and
[approved TM-1 design](client-prepared-media-private-fixtures-telemetry-proposal-2026-10-14.md).
The dated platform documentation in those records is the basis here; no new
platform lookup or claim about current target limits was made for this proposal.

## Gate M: establish a usable measurement before execution

The primary must produce a read-only evidence sheet, reviewed independently and
by IC-1, specifying the actual API/report, units, scope, resolution/precision,
reset semantics, delivery latency, correlation and bounded retrieval. A document
mentioning a field is not proof it is exposed on this target. No broad logs, new
telemetry service, paid add-on, credential expansion or generated traffic may be
used implicitly to fill the sheet. Further read-only access also needs its own
bounded scope; HQ-1A's consumed allowance is not reused.

| Required evidence | Pass criterion                                                                                                                                                                                                    | Insufficient substitutes                                                                                                                  |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| CPU               | Per-invocation CPU milliseconds from the target, covering complete wrapper/import attribution, authentication, read/hash, response and cleanup; exact case correlation and an explicit accounting definition      | Elapsed time, minute averages, fleet totals, dividing worker CPU by request count, or absence of a platform CPU kill                      |
| Memory            | Native-inclusive high-water over the whole worker during each invocation, including resident baseline/imports, TLS/fetch/hash, response, cleanup and other resident work; documented scope/reset and completeness | V8 proxy, `rss: 0`, sample maxima, shutdown snapshots, subtracting baseline, or absence of a platform memory kill                         |
| Correlation       | Exact deployed function/build plus invocation and actual worker identity mapped to synthetic local aliases; bounded time interval and allowlisted projection before retrieval                                     | Module alias alone as proof of platform cold start, arbitrary function-name search, unrestricted event bodies or post-retrieval filtering |
| Coverage          | Complete evidence can arrive and be checked within a fixed slot, with no unobserved interval that could hide a threshold crossing; uncertainty/rounding bounds declared                                           | Late eventual logs of unknown coverage, averages, unsupported precision, missing points treated as zero                                   |

Worker-total CPU remains diagnostic in this method. In theory it could bound a
request if its accounting interval is proven to contain the complete request and
all relevant CPU with no resets/undercounting; exclusive lifecycle and absence
of concurrent/background work would simplify attribution. Those facts are not
established here. HAM-1 therefore does **not** accept that alternative without a
separately reviewed measurement amendment. Memory high-water may be
conservatively worker-wide; including other resident allocations is acceptable,
subtracting them to manufacture headroom is not. Platform event semantics must
prove native coverage rather than relying on a field named `total`.

The unchanged 96 MiB sampled partial-V8 guard remains an in-run stop under TM-1.
High-water/CPU evidence for acceptance may be delivered after response; it is
not claimed to enforce a synchronous native/CPU ceiling. Any separately approved
exposure would retain TM-1's explicit platform-backstop limitation. No 160 MiB
guard or relaxed production resource target follows.

If any required item is unavailable, contradictory or cannot be retrieved
safely, stop with `hosted_resource_method_unavailable`, identify that item, and
perform no controls or media reads. Do not repeatedly search alternate metrics
or request another experiment by default. The user then decides whether to keep
the blocker or commission a specifically bounded design/measurement amendment;
no relaxation is proposed here.

## Gate R: resource targets must have the correct adopted domain

Measurement capability does not adopt a resource budget. The active TM-1 96 MiB
stop covers the partial V8 proxy only. The historical 96 MiB whole-worker and
one-second CPU targets remain comparison targets with unqualified acceptance;
this proposal neither promotes them to new hosted acceptance criteria nor
replaces them with higher numbers. The stored-package 96 MiB ceiling is a third,
separate domain.

Before an execution-ready resource packet, return an explicit resource-target
decision binding the established measurement domains to adopted acceptance
criteria, including exact equality and uncertainty predicates. No native ceiling
or CPU acceptance value is adopted through HAM-1. No limit change is requested
now. If that domain/target decision cannot be made within existing approvals,
resource acceptance remains `resource_target_decision_pending`; do not run a
campaign that cannot receive a valid resource verdict. Historical comparisons
may be reported as comparisons, never a qualified pass. The existing proxy stop,
growth stop and deadlines continue unchanged.

## Gate C: exact candidate and purpose

Only after Gates M and R are resolved and the user authorizes preparation, bind
one immutable source/dependency/staged-bundle/driver/assessor manifest. Review
the actual deployment entrypoint and response protocol, runtime compatibility,
authentication, latches, limits, cleanup and every outbound path. The current
legacy hosted entry and local custom controller are not an executable HAM-1
candidate. No custom main service or `userWorkers.create` controller is
deployed.

Record a meaningful changed boundary to qualify. Reuse unaffected checks and old
candidate evidence with exact source comparisons; do not run unchanged transport
simply to obtain a newer date. A new artifact cannot inherit a complete pass by
combining successful pieces from different candidates.

This five-call scope targets the existing representative TLS/length/hash/closure
path. It omits product claims/receipts, source retention, media decoding,
funding, AI, publication, deletion races and app journeys. If any such component
is added, return a complete-verifier scope instead; do not relabel this small
scope as complete. Any new protocol/schema remains test-only and separately
reviewed; this proposal expands no production schema agreement.

## Conditional single-run method

Only a later exact-candidate hosted approval authorizes these operations. Target
remains existing project `qlarqavoqhkuwzmevrmf`, test route
`cpm-verifier-characterization`, private bucket `merian-cpm-verifier-fixtures`.
Use one attended run and one fixed driver with no restart/retry/replacement.

| Ordered case | Operation                 | Required observation                                                                              |
| ------------ | ------------------------- | ------------------------------------------------------------------------------------------------- |
| D            | One denied caller/control | Explicit denial, zero media reader opened                                                         |
| C1           | One 64 KiB control        | Exact bytes/hash, positive closure, valid proxy/runtime/correlation and complete resource metrics |
| C2           | Second 64 KiB control     | Same requirements; no assumption it shares C1's worker                                            |
| A            | One 32 MiB fixture A read | Complete request-boundary acceptance below                                                        |
| B            | One 32 MiB fixture B read | Complete request-boundary acceptance below                                                        |

D, C1 and C2 precede bulk fixture uploads. If either control cannot demonstrate
Gate M's actual live semantics, stop before A/B. This confirmation occurs only
when the measurement mechanism was established before deployment; it is not a
replacement for Gate M. Each admitted case owns a fixed **60-second wall slot**
from dispatch for response, positive closure and its resource-evidence receipt;
the handler's existing **30-second deadline is unchanged**. The slot is a
proposed stricter scheduling bound, not an extension to request execution.
Missing/late resource evidence is unqualified, not a pass. At most one
explicitly preplanned, bounded telemetry retrieval per case; no polling/retry.
If the chosen mechanism cannot meet this bound, return the method for review
before execution, not a longer wait during the run.

No next case dispatches until the previous slot's response, closure and metric
checks pass. If ready early, leave the remainder idle; no catch-up or keepalive.
The slots allocate at most 300 seconds of request/measurement time. Insert one
separate **at most 120-second bulk-upload interval** after C2 passes and before
A dispatches. Both bulk PUTs and their positive closure must complete within
that interval; otherwise stop before A, with no retry. This is a proposed
stricter allocation within the unchanged outer setup/run limit. Thus slots plus
that gap allocate at most 420 seconds, not 300 seconds elapsed. Control setup
and deployment also consume the existing 30-minute setup/run envelope; reserve
the full remaining slots and cleanup allowance before proceeding. This does
**not** guarantee they land on one worker or stay within an existing worker's
remaining lifetime. Worker replacement is allowed for this request-boundary
method, explicitly recorded, and never resets an in-flight obligation. No
same-worker drift result is computed from these five cases.

Retain the existing legacy hosted four-point growth stop on any worker that
actually serves enough ordered reads; do not reset its module history, disable
it, or interpret its absence as a GAC-1 pass. GAC-1 remains the separate frozen
local cohort method. A later adapter must specify the exact protocol and
preserve both method identities; selecting a fresh method label cannot waive a
stop.

For read cases C1, C2, A and B require exact size/digest, bounded telemetry,
acknowledged EOF/awaited reader/hash cleanup and a matched complete response. D
instead requires explicit denial and zero opened reader. The resource verdict
uses only the domain-correct criteria separately frozen at Gate R; without them
there is no resource pass and no execution. Account for precision and upper
uncertainty bounds using exact predicates fixed before results are known.
Observed violations fail; uncertainty-only inability to prove the predicate is
unqualified. Neither can pass or trigger more work.

The already adopted proxy rule is unchanged: sampled `heapTotal + external` **at
or above 100,663,296 bytes** stops at existing sample points. This does not
bound native memory. Preserve the 30-second request/eligibility deadline and
existing growth rule. Do not convert absent platform limit events into a
one-second CPU or total-memory pass. Any denial error, unsafe read, failed
digest, resource stop, invalid metric, unexpected runtime, lost response,
unresolved reader or cleanup failure ends the run. No extra case may compensate.
In particular, unknown delivery permits only approved original-operation
reconciliation, never another media read or AI request. Failure of the resource
verdict never authorizes refund or dispatch.

## Unchanged ceilings and cleanup ownership

This method allocates five calls out of the existing maximum 26 invocations;
unused slots are not permission for additional tests. It reduces offered
concurrency to one for this boundary method; the maximum two-client envelope and
one-reader-per-worker rule are not raised. The synthetic inventory remains one
64 KiB and two 32 MiB objects. Do not duplicate retained local fixture bytes.
Setup PUTs must close before reads; positive reader closure precedes fixture
reuse or deletion. No client upload tickets or multipart writes are introduced.

Retain $10 incremental cost, 30 minutes setup/run plus 15 minutes reserved
cleanup, 192 ordinary plus 64 cleanup application calls (256 total), 2 GiB
transfer, 512 MiB aggregate local evidence and 20 GiB free-disk floor. Retain
all package/per-asset/storage limits, sampling definition and 8 MiB growth
values. An exact packet must enumerate setup, five driver calls, handler
outbound calls, at most five bounded telemetry retrievals, health observations
and emergency cleanup reservations before launch. Do not consume cleanup reserve
for metrics. No workload or storage cap is enlarged by the five-slot proposal.

Emre remains accountable operator. History primary owns the sole writing path,
exact package and sanitized evidence. Independent/IC-1 reviewers are read-only;
Supabase owns physical scheduling and lifetime. A later packet must separately
name the test-route installation, seven temporary shared-project settings,
fixture operations and disable/cleanup authority. A disabled route's
installation is still deployment. No PR116 push/merge, fleet deployment,
migration, device work, hosted scheduling, provisioning or ordinary app
activation is implied.

Stop admission and remove only the experiment route/settings under the later
approved cleanup scope. Delete only fresh-run objects with positive writer and
reader closure; retain unresolved objects and fences for named reconciliation.
Retain the user's two stored R2 keys; remove only temporary copies. Expiry,
route deletion, HEAD or local process exit never proves physical closure. No
change to old retained objects, bucket policy or credentials is authorized now.

## Decisions, limits of inference and finite stopping rule

| Outcome                                     | Permitted conclusion                                                                    | Next action                                                                                    |
| ------------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Gate M unavailable (current state)          | No feasible hosted resource acceptance demonstrated                                     | No test. Return the missing mechanism; approval of HAM-1 alone does not open execution.        |
| Gate R/C incomplete or runtime mismatch     | Resource criteria or exact applicable candidate absent/unqualified                      | No hosted run; return the concrete packaging/compatibility gap.                                |
| Controls fail or metrics missing            | Method failed live confirmation                                                         | Cleanup; A/B remain unrun. No retry.                                                           |
| All five cases and cleanup pass             | Only this candidate's named serial request boundaries qualified within measured domains | Preserve result; do not claim complete verifier, warm reuse, concurrency or product readiness. |
| Any later failure/unobserved required field | Failed or incomplete boundary evidence                                                  | Cleanup and one decision report; no adaptive variant or repeat-to-pass.                        |

Warm reuse and concurrency remain separate **open** requirements, not mandatory
routing outcomes for this serial boundary method. The exact hosted GAC-1 demand
remains infeasible; approving HAM-1 does not waive it or substitute the local
pass. Same-worker busy admission and physical reader overlap would need a
supported correlated observation method and a separate fixed scope. A pair of
client sends, different aliases or shared timestamps is insufficient. No
additional pairs or affinity probes are proposed now.

This yields a concrete stopping point: we already have enough evidence to avoid
another representative diagnostic campaign under current observability. More
testing is justified only by a candidate change **and** a credible method that
can close a named gate. No proposal here claims all release/resource acceptance
can be achieved without a further explicit decision on the remaining gaps.

## Approval requested

Approve **HAM-1 as the acceptance-method decision only**: separate local reuse
from candidate-specific hosted serial boundary qualification; adopt Gates M, R
and C and the conditional five-call method (300 seconds of request slots plus at
most 120 seconds for bulk uploads), with unchanged existing limits and explicit
open gates. Keep the current disposition `hosted_resource_method_unavailable`
until supported evidence clears Gate M.

This approval authorizes no implementation, checks, tests, read-only hosted
inventory, uploads, secret installation, deployment or cleanup. Any next local
construction/validation scope and exact hosted execution packet return for
separate approval with independent and IC-1 concurrence. Existing implementation
ownership and media-required submission, immutable supporting descriptions,
original-operation recovery and later deletion/export/redesign sequencing stay
unchanged. Broader engine hardening and capture UI remain separately owned.
