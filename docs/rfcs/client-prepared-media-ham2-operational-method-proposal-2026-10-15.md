# HAM-2: bounded operational acceptance with explicit measurement gaps

October 15, 2026. **Proposal for approval; not adopted or executable.** Prepared
from the retained HAM-1, MR-1, TM-1 and GAC-1 evidence. No new account
inventory, tests, instrumentation, runtime construction or hosted actions.
Activation disabled, AWS and 160 MiB unapproved, limits unchanged, auto-prompts
paused.

## Recommendation and exact change

Approve a separate **candidate-specific serial operational qualification** for
the representative private-read verifier path. Explicitly accept that an
eventual attended synthetic test would have incomplete resource visibility. Do
not call this native-memory, CPU, complete-verifier or production acceptance.

HAM-1 requires native-inclusive peak memory, request-attributed CPU and timely
platform correlation before any hosted resource campaign. The
[reviewed MR-1 result](client-prepared-media-mr1-result-2026-10-15.md) found no
qualifying mechanism. HAM-2 would remove those unavailable measurements as
prerequisites **only for this narrower operational verdict**. This is an
explicit change in acceptance scope and accepted experiment risk, not a newly
established measurement or a numerical limit increase.

HAM-1's Gate M remains `hosted_resource_method_unavailable`; Gate R remains
`resource_target_decision_pending`. Neither becomes passed, waived for product
release, or satisfied by HAM-2. The old resource method remains blocked. HAM-2
creates a different result, `serial_operational_qualified`, whose scope must
always accompany it. No bare overall `passed` or production-ready claim.

This is useful only when a materially changed candidate has a specific serial
boundary to qualify. Existing candidate `9c88cc72d` already has retained hosted
transport evidence. Do not rerun it merely to adopt this label or replace its
date. If no meaningful changed boundary exists, the next execution decision is
**no new test**; preserve the evidence and return the remaining design decision.
An adapter-only change must identify the actual authentication, response,
closure or protocol behavior that needs qualification; a renamed method alone is
not such a change.

## What accepting the gap means

| Domain            | HAM-2 treatment                                                                                                                               | Remaining uncertainty / accepted risk                                                                                                                                                                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Native memory     | Explicitly unmeasured. No zero, inferred peak or resource pass.                                                                               | Native allocations and between-sample peaks may exceed the historical 96 MiB comparison without an application-visible warning. Existing platform enforcement is the only established total-memory backstop, as in TM-1. Abrupt termination and incomplete cleanup are possible. |
| Request CPU       | Explicitly unmeasured. No elapsed-time conversion or inference from a successful response.                                                    | The historical one-second comparison can be exceeded undetected. No application CPU budget is established by platform enforcement or this method.                                                                                                                                |
| Partial V8 memory | Required existing samples and components; unchanged stop at `heapTotal + external >= 100663296` bytes.                                        | This is a sampled partial proxy, not a native peak. Missing/invalid required samples cannot qualify.                                                                                                                                                                             |
| Growth / reuse    | Retain existing hosted four-point 8 MiB stop on a module with enough ordered samples. Preserve frozen local GAC-1 separately.                 | A fresh module or too few points yields growth-not-observed, never a growth pass. No reset, shorter GAC-1 substitute or indefinite reuse claim.                                                                                                                                  |
| Runtime identity  | Bind the exact staged artifact and approved compatibility definition; validate the expected runtime/protocol fields in responses.             | Application/module aliases are not physical-worker identities. Reported version is not proof of binary provenance or scheduler affinity. No inferred cold start, physical overlap or concurrency qualification.                                                                  |
| Event delivery    | Require the bounded application response and positive scoped cleanup evidence in the fixed slot. No platform-log retrieval required by HAM-2. | Native/CPU events, complete platform correlation and their latency/retention remain unknown. Their absence cannot produce a resource pass.                                                                                                                                       |

The risk is not confined to synthetic bytes: the test runs in the shared
production-alpha project. Resource termination, interruption, retained private
fixtures and possible effects on shared service are not proven impossible.
Synthetic data, low offered concurrency, narrow credentials, finite exposure and
attended cleanup constrain the experiment; they do not prove isolation or zero
risk. If the operator requires a measured native/CPU bound before any hosted
exposure, reject HAM-2 and retain the HAM-1 block.

The historical native 96 MiB and one-second CPU comparisons remain unresolved;
HAM-2 does not replace them with platform caps. Package, asset,
temporary-storage and pending-storage limits are unaffected. Successful
operational evidence cannot authorize production admission, provider dispatch,
funding or refund.

## Entry gates before a later run

1. **Method adoption:** explicit human approval of HAM-2's limited verdict and
   unmeasured-resource risk. Approval of this document alone authorizes no test,
   local runtime work or hosted preparation.
2. **Purpose and preparation:** a separately approved bounded local scope names
   the changed boundary, source base, files, implementation ownership and
   necessary checks. Primary remains sole writer. If no change warrants a run,
   stop here. Reuse unaffected passing checks with exact source comparisons.
3. **Exact candidate review:** independent and IC-1 concurrence on immutable
   source, dependencies, deployed entrypoint, staged bundle, driver, assessor,
   response schema, sample schedule, limits, authentication and cleanup. The
   legacy hosted entry and local custom controller are not assumed HAM-2-ready.
   No custom main service or `userWorkers.create` controller is deployed.
4. **Separate attended execution approval:** return the exact target, candidate,
   compatibility policy, operation ledger, secrets/settings, health preflight,
   costs, stop and cleanup scope before any hosted action. Later runtime
   mismatch, unhealthy target, unknown credential scope, storage shortage or
   unresolved prerequisite stops setup; it does not authorize an adaptive fix.

Actual worker/build correlation is no longer an entry gate for this narrow
verdict. Candidate artifact identity and a reviewed runtime compatibility
predicate still are. The packet must distinguish those claims and specify what
available bounded observation establishes compatibility; inventing a platform
identity or silently accepting an unexpected version is prohibited. If this
practical predicate cannot be established, return that concrete packaging gap
without another telemetry search or test.

## Fixed conditional workload and evidence

Retain HAM-1's five-call serial schedule; change its mandatory resource verdict
to the explicit domain-separated HAM-2 verdict. No operation occurs now.

| Case | Work                       | Mandatory outcome before proceeding                                                                                           |
| ---- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| D    | One denied caller          | Expected explicit denial; zero opened media reader.                                                                           |
| C1   | One 64 KiB control read    | Exact length/digest; complete bounded response; positive reader/hash closure; valid required proxy/runtime/protocol evidence. |
| C2   | Second 64 KiB control read | Same, without requiring the same module/worker.                                                                               |
| A    | One 32 MiB fixture A read  | Same requirements as controls.                                                                                                |
| B    | One 32 MiB fixture B read  | Same requirements as controls.                                                                                                |

D, C1 and C2 precede bulk fixture uploads. A control must prove the candidate's
application evidence path, not pretend to confirm native/CPU semantics. Each
case retains its fixed 60-second slot from dispatch, including response receipt
and assessment; the handler's existing 30-second request/eligibility deadline is
unchanged. If the case completes early, leave the remainder idle. Between C2 and
A allow the existing single preplanned maximum 120-second bulk-upload gap. Five
slots total 300 seconds, at most 420 seconds including that gap. No keepalive,
catch-up, retry, alternate workload or extension.

Only synthetic fixed-fixture bytes are included. Read completion requires exact
EOF and byte identity plus awaited reader/hash release before a complete
response. The driver and independent assessor must agree on case order,
candidate/protocol, deadlines, mandatory sample coverage and closure. Their
required bounded response fields and maximum sizes are frozen before the run; no
new production schema or receipt is defined here. A missing response or a
handler cancellation request cannot prove reader closure.

Record each domain separately: operational outcome; sampled proxy observations
and stops; growth stop or insufficient points; native peak **unmeasured**;
request CPU **unmeasured**; physical-worker correlation **unqualified**.
Preserve partial-V8 components rather than inventing a single total-memory
number. Do not aggregate different modules into a growth cohort. No hidden
threshold changes, after-the-fact exemptions or coercion of missing fields to
zero.

For HAM-2 specifically, valid mandatory per-case proxy samples with fewer than
four ordered same-module samples yield `growth_not_observed`. This is a recorded
limitation that may accompany `serial_operational_qualified`; it is neither a
missing-required-sample failure nor a growth pass. The legacy growth stop still
applies whenever enough ordered same-module samples exist. Missing or invalid
mandatory per-case proxy fields instead make the operational result unqualified
and stop the run. No additional growth observation is required: do not
manufacture worker affinity, add calls or claim warm-reuse acceptance.

Any denial error, wrong bytes/hash, unexpected response/runtime, deadline or
resource stop, invalid/missing required sample, lost response or unresolved
closure ends the run. Stop on any known adverse platform signal encountered in
approved preflight/response evidence, but absence of such a signal is not
qualification. Do not add logs queries to search for a passing signal. No AI
request is made; uncertainty never authorizes another read/provider invocation
or refund. Read-only verification retries may be safe in other contracts but are
not part of this single no-retry campaign.

## Exposure and cleanup remain bounded

Conditional target: existing Supabase production-alpha project
`qlarqavoqhkuwzmevrmf`, test-only `cpm-verifier-characterization` route,
existing private `merian-cpm-verifier-fixtures` R2 bucket. No new project or
worker service.

Keep $10 incremental spend, 30 minutes setup/run plus 15 minutes reserved
cleanup, 192 ordinary and 64 cleanup application calls (256 total), 2 GiB
transfer, 512 MiB aggregate local evidence and 20 GiB disk floor. Use five of
the maximum 26 invocations, offered concurrency one, at most one open reader per
worker. Unused invocation/query allowance never authorizes extra cases. Retain
one 64 KiB and two 32 MiB fixtures, existing per-role/package/storage ceilings,
sampling, 8 MiB values and cleanup reserve. HAM-2 requires zero
resource-telemetry queries, not a reassignment of that allowance to more work.

The later packet must itemize every setup/read/health/cleanup call, all bounded
data retained, and the reserve before launch. It must separately name route
deployment and seven temporary shared-project settings; disabled activation does
not make installation non-deployment. No credentials enter artifacts or the app.
Runtime fixture access remains bucket-scoped read-only; setup/cleanup access
remains operator-only. Retain the user's stored keys; remove temporary copies
under approved cleanup. No provisioning, credential change, AWS, PR116
push/merge, migration, device installation or distribution is implied.

Emre remains accountable operator; History primary owns the exact candidate and
evidence; independent and IC-1 reviewers remain read-only. Close acknowledged
setup PUTs before reads; require positive writer and reader closure before
fixture deletion. Stop admission and remove only the experiment route/settings
under the separately approved cleanup authority. If closure remains unknown,
retain the private object, capacity obligation and fences for named bounded
reconciliation; never treat a timeout, expiry, HEAD, route removal or process
exit as closure. Cleanup uncertainty cannot produce a qualified result.

## Verdict, stopping rule and what this unblocks

| Outcome                                                                                     | Report                                                                                                  | Permitted next step                                                                                                       |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| All five cases, required application evidence, guards and cleanup satisfy the frozen packet | `serial_operational_qualified` for that exact candidate; native/CPU unmeasured and remaining gates open | Preserve evidence. Return to the documented next design/implementation dependency; no automatic hosted run or activation. |
| Known assertion, guard, digest, denial or deadline failure                                  | `serial_operational_failed`, with any unresolved cleanup obligation                                     | Cleanup/reconciliation within authority and one report; no retry-to-pass.                                                 |
| Missing evidence, runtime mismatch, uncertain execution/closure or incomplete cleanup       | `serial_operational_unqualified`; record any known failures too                                         | Stop and report. No additional diagnostic campaign by default.                                                            |
| No materially changed boundary or no viable exact candidate                                 | `no_new_test_justified`                                                                                 | Reuse applicable evidence with its original scope; return the concrete remaining design decision.                         |

HAM-2 can remove the unavailable native/CPU telemetry dependency from this
specific serial operational checkpoint. It cannot close warm reuse, concurrency,
complete-verifier, whole-package, hostile ingress, original-photo retention,
audio quality, recovery/deletion, native journey or integrated product
acceptance. Local GAC-1 remains a finite local partial-V8 result, including its
retained warning. Earlier hosted results retain their original labels.

Production resource suitability remains unresolved and requires a separate
explicit release/acceptance decision; this proposal supplies neither a
production budget nor a promise of eventual activation. No newly identified
missing product gate may be declared satisfied merely to finish this checkpoint.
Preserve media-required fresh submission, immutable descriptions and historical
operations, server-owned funding/dispatch/recovery, and later deletion/export/
redesign sequencing and ownership.

## Approval requested

Approve **HAM-2 as method only**, explicitly accepting unmeasured native peak
and request CPU for a separately authorized finite synthetic operational test,
while retaining all existing numerical limits and all broader acceptance gates.
This replaces HAM-1 M/R as entry conditions only for the narrowly named HAM-2
verdict; it does not resolve or waive HAM-1 resource acceptance.

After adoption, the next deliverable is a bounded purpose/candidate-preparation
packet for approval. It must either identify a meaningful changed boundary or
recommend no new test. No construction, validation tests, hosted inventory,
uploads, secrets, deployment or execution follows automatically. Exact
independent/IC-1 review and a separate human execution approval remain required.
