## October 15, 2026 — MR-1 completed: measurement method unavailable

The user approved MR-1 at `147021f2d`. Bounded documentation/source review
established no qualifying native-inclusive peak and request-attributed CPU
mechanism. Gate M remains `hosted_resource_method_unavailable`; Gate R remains
`resource_target_decision_pending`. Stage 2 was skipped: no account queries or
events, tests, invocations, uploads, secrets or deployment. Independent/IC-1
result review is recorded in the result evidence; no further campaign follows.
Activation disabled, AWS/160 MiB unapproved, limits unchanged, auto-prompts
paused. Result: `docs/rfcs/client-prepared-media-mr1-result-2026-10-15.md`.
Earlier proposal/status text below is historical and exactly recoverable.

# MR-1: bounded HAM-1 measurement and resource-target resolution

October 15, 2026. **HAM-1 adopted as method only; MR-1 proposed, not approved.**
The user explicitly approved HAM-1 at checkpoint `f4226a92b`, document hash
`be983c8f4b3b425ae946b1682cc2a4125deff4893f37cf8b9b09ca140de044c1`, reviewed set
`97683c716fc6ae31dec11d4ae07c52e7bdf0e3ebc136a1bb581885686193898e`. That
adoption authorizes no tests, implementation or hosted actions. This turn
prepares MR-1 and records adoption only. Activation disabled, AWS and 160 MiB
unapproved, all limits unchanged, auto-prompts paused.

## Recommendation and finite deliverable

Approve **one two-hour read-only investigation and decision report**, including
independent and IC-1 review, to resolve HAM-1 Gates M and R. Start with retained
evidence and documented measurement semantics. Permit at most one conditional,
strictly bounded retrieval of already-existing experiment telemetry if a
credible qualifying metric and safe selector are established first. Do not
repeat HQ-1A's dashboard survey or create traffic to discover metrics.

The deliverable is either a concrete, target-supported measurement specification
plus a proposed resource-target decision for human approval, or a precise
`hosted_resource_method_unavailable` finding. Resolution may be a demonstrated
capability gap; it must not be manufactured into a pass. There is no automatic
follow-up investigation, instrumented candidate or test after either outcome.

The highest-value question is whether the current backend exposes a usable
**native-inclusive worker high-water and per-invocation CPU** at all. Prior V8
samples and shutdown snapshots cannot answer that question. If the answer is
unsupported or unresolvable within this scope, stop before spending account
reads on events that cannot change the decision.

## Owners, target and hard bounds

History primary is sole writer and reads only explicitly scoped information.
Emre remains accountable operator. Independent and IC-1 reviewers review local
sanitized evidence only. No new implementation handoff, agent writer, provider
contact, support ticket or message to anyone else is included.

| Item                     | Proposed bound                                                                                                                                                                                                                                           |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Window                   | One 120-minute outer window including analysis, report and review; at most 30 minutes of hosted inspection within it. Stop on expiry and report unresolved work.                                                                                         |
| Existing target          | Production-alpha Supabase project `qlarqavoqhkuwzmevrmf`, existing signed-in Chrome session or already configured authorized read-only interface; no CLI repair, token/session extraction or new login/permission.                                       |
| Public/source references | At most four focused official documentation pages and four relevant files from an existing pinned/runtime source checkout or official immutable source revision. Reuse known sources; no dependency install, build, checkout or new runtime download.    |
| Account observations     | At most four application-level read-only observations, allocated below. No polling, retries or broad dashboard exploration. Dashboard network subrequests are not claimed as this count.                                                                 |
| Existing events          | At most one capability metadata record, two mapping rows and 19 allowlisted experiment events: maximum 22 returned records/rows across the scope. Filter and limit before retrieval. No customer event bodies, headers, tokens, object keys or raw logs. |
| Evidence/storage         | At most 64 KiB new sanitized decision/evidence artifacts, within existing 512 MiB aggregate allowance and retained cleanup reserve; at least 20 GiB free disk. No fixture duplication or pruning.                                                        |
| External changes         | Zero invocations, controls, tests, R2 operations, uploads, secret installation, deployment, configuration changes, paid add-ons, provisioning or credential changes.                                                                                     |

The two-hour budget is an upper bound, not a requirement to spend time. The four
public pages are a separate, explicit research allocation, not four extra
account observations. Read-only queries use existing service access and may
consume normal platform query allowance; no change to plan, spend cap or billing
settings is authorized. If the available path requires a paid service or cannot
bound retrieval safely, stop.

## Stage 1: semantics first, using existing evidence

Allocate at most 35 minutes. Trace only these three questions:

1. **Memory accounting:** identify whether an existing platform metric is a
   worker high-water across the full invocation, with native TLS/fetch and hash
   allocations, resident baseline/imports, response and cleanup included.
   Determine scope, reset/lifetime, exact units, collection precision and
   omitted allocations. The known `Deno.memoryUsage` partial V8 fields, zero RSS
   and shutdown snapshots are already insufficient; do not retest them.
2. **CPU accounting:** identify true per-invocation CPU attribution, including
   initialization and cleanup, with units and precision. A worker cumulative
   total or execution time is not HAM-1's CPU method. Do not infer attribution
   from a field named `execution_id` or divide totals among requests.
3. **Correlation and delivery:** identify an existing safe retrieval surface,
   exact function/deployment/invocation/worker linkage, retention and delivery
   semantics that can meet the adopted 60-second case slot. Aggregate minute
   reports cannot establish this. Published semantics must be distinguished from
   observed target values and actual live confirmation still needed later.

Pin every source by URL/revision or retained file hash. A runtime source symbol
can explain what a build measures; it cannot identify the deployed build or
prove that the hosting platform exposes that metric. Source-to-host mismatch is
an unresolved item, never an assumed match. No local code execution, memory
probe, synthetic stream, parsing benchmark or tests are performed.

**Exit early:** if any essential domain is positively unsupported, or no
credible qualifying mechanism is found after these bounded references, record
Gate M unavailable and skip all event retrieval. Do not widen source review,
search new providers or propose AWS to keep the investigation alive. This avoids
another cycle of tests that cannot close acceptance.

## Stage 2: conditional target confirmation, not a new experiment

Only if Stage 1 identifies a credible mechanism, use at most four observations
within the 30-minute hosted subwindow. The plan must be reviewed read-only by
independent and IC-1 reviewers before a query is submitted. Review the exact
projection, target, interval, row limits and unavailable behavior. Preparation
of the query is permitted; running candidate code or a test is not. A query
review finding consumes time, not a new query allowance.

1. **One metadata observation, at most one bounded record:** confirm only the
   target's exposed telemetry capability/build mapping and retention metadata
   relevant to Stage 1. Reuse HQ-1A's dated Pro/Healthy context; do not browse
   general project health or treat it as future execution preflight. Missing
   build/retention metadata is recorded once.
2. **One selector-discovery observation, only if needed:** resolve the deleted
   experiment's platform function/deployment mapping from existing invocation
   metadata. Restrict source to invocation metadata, the exact experiment route
   `/functions/v1/cpm-verifier-characterization`, and the recorded October 14
   attended interval **17:28:43 UTC through 17:44:36 UTC**. Return at most two
   distinct function/deployment pairs and nothing else. One valid pair may be
   used; zero, two, a missing component, truncation or any ambiguity stops event
   retrieval. Do not enumerate other functions, dates or customer routes. If a
   unique exact pair already exists in retained evidence, reuse it and omit this
   observation.
3. **At most two event observations:** use the unique exact function/deployment
   pair, the same fixed time interval and explicit allowlisted event types. The
   first query returns at most ten CPU/invocation-correlation rows; the second
   returns at most nine native-high-water/coverage rows. The purposes are
   disjoint. Order and tie-breaking, selection completeness/truncation detection
   and safe field limits must be specified before retrieval. Require server-side
   filtering and projection, never `SELECT *` or whole JSON/maps. Missing fields
   or empty results are an unavailable finding, not permission for fallback
   queries.

This selector-discovery allocation is the narrow addition to HQ-1A: it is
explicitly proposed to resolve its missing exact identifiers before examining
runtime events. It does not retroactively authorize an HQ-1A query. Invocation
path metadata must be documented as usable by the chosen interface before
submission; do not guess field names or parameterized URLs. If only broad
log-view navigation is available, skip retrieval. Do not extract browser
cookies, tokens, hidden application state or use an alternate privileged login.

Only field/domain definitions, numeric CPU/memory values, event timestamps,
coverage flags and sanitized aliases may be retained. Raw identifiers needed for
correlation remain transient in the authorized interface and map to local
aliases before logging; no raw telemetry export. If secure bounded projection or
aliasing cannot be implemented by the existing read-only surface, stop rather
than add a local proxy or unreviewed helper. No secrets are needed for R2 here.

The finite row sample cannot prove complete coverage or a delivery guarantee.
Those require the Stage 1 semantics and explicit target support; even a matching
historic event is corroboration only. Missing older data is not proof of
absence, retention expiry, safe resource use or a limit violation. Do not extend
the interval to obtain shutdown events after the attended window. Current build
identity may remain unknown after deleted-route cleanup; that prevents claiming
the old run qualifies today's runtime.

## Stage 3: resolve resource-target meaning, not change limits

Allocate the remaining time to one decision table and review. Trace the original
IVI-1 targets, TM-1 amendment, GAC-1 adoption and HAM-1 Gate R by source/hash.
List what is adopted, what is a historical comparison and what still requires
human adoption. Merely sharing the number 96 does not make domains equivalent.

| Quantity                                                         | Current meaning to preserve                                                              | Proposed output for the next decision                                                                                                                                                                                             |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stored package / per-role assets / pending and temporary storage | Existing approved storage limits; unrelated to worker accounting                         | Preserve unchanged with owner references; do not tune to fit a measurement.                                                                                                                                                       |
| Partial V8 proxy                                                 | Adopted `heapTotal + external` sampled stop at or above 100,663,296 bytes                | Preserve this exact stop and component/sampling definitions; it is not native RSS or peak.                                                                                                                                        |
| Growth                                                           | Existing 8 MiB values and separate legacy-hosted/local-GAC-1 method meanings             | Preserve both method identities and historical warnings; no pooling or shortened GAC-1.                                                                                                                                           |
| Whole-worker memory                                              | Historical 96 MiB comparison target; native accounting/hosted acceptance not established | If Gate M supports the exact domain, recommend the existing 100,663,296-byte comparison as the candidate target for explicit Gate R approval, with conservative strict-below and uncertainty predicates. Do not adopt it in MR-1. |
| Request CPU                                                      | Historical one-second comparison target; target attribution/acceptance not established   | If the exact domain is supported, recommend 1,000 ms as the candidate target for explicit Gate R approval, with at-most and uncertainty predicates. Do not substitute the platform's larger cap.                                  |
| Request deadline                                                 | Existing 30-second execution/eligibility bound                                           | Preserve unchanged. HAM-1's 60-second observation slot cannot extend execution or receipt authority.                                                                                                                              |

No new higher number, percentage-of-platform reserve or memory budget is
proposed. For a future Gate R decision, show the exact measurement upper bound
including precision/error: memory would require upper bound strictly below
100,663,296; CPU would require upper bound at most 1,000 ms. Observed violations
fail; uncertainty-only inability to establish the predicate is unqualified.
Report these as **proposed application of historical targets**, not already
adopted hosted criteria. If native coverage or attribution differs from the
historical target, give the mismatch rather than invent a conversion.

If Gate M remains unavailable, the report may still reconcile these meanings,
but Gate R stays `resource_target_decision_pending`. No nominal target choice
can repair missing observability. No final production resource budget follows
from representative-path measurements, even if all proposed comparisons pass.

## Deliverables and stopping decision

Produce one compact matrix with a row for CPU, native high-water, scope/reset,
correlation, precision, retention and delivery. Each row names evidence,
observed/documented/inferred status, concrete limitation and whether it
satisfies HAM-1. Include the exact sanitized observation ledger, query plan if
applicable, resource-target provenance and independent/IC-1 review. Retain
failed evidence and all prior accepted sets; do not rerun unchanged validations.

Allowed conclusions are:

- **Mechanism supported, target applicability resolved:** propose the exact Gate
  R decision for the human, list the live confirmation still needed, and return
  a separately bounded local candidate-preparation proposal. No implementation
  or tests start automatically.
- **Mechanism missing, ambiguous or unobservable:** retain
  `hosted_resource_method_unavailable` and identify the specific unavailable
  measurement. Recommend stopping hosted qualification under this method. Do not
  offer another identical inventory or diagnostic campaign.
- **Time/access/retrieval limit reached:** report precisely what remains unknown
  and stop. No refresh loops, new session discovery, additional reads or
  automatic extension. Reviewer delay leaves review pending; it does not extend
  the window or produce concurrence by default.

Warm reuse, concurrency, complete-verifier, media retention, audio quality,
ingress/recovery/deletion and native/integrated product acceptance remain open.
Unknown AI execution still permits only original-operation recovery, never a new
provider request or refund. PR116 integration, push/merge/deployment/device
restrictions and later deletion/export/redesign sequencing remain unchanged.

## Approval requested

“Approve MR-1 only: one two-hour read-only measurement/resource-target review,
with at most four official documentation pages, four relevant immutable source
files, four conditional account observations and 22 projected existing
records/rows (one capability record, two mapping rows, ten CPU rows and nine
memory rows). Use only the named existing Supabase project and authorized
access. Require independent/IC-1 query review before any event retrieval and
review the final decision. No tests, construction, provisioning, uploads,
credential changes or deployment; no adoption of new resource criteria. Return
findings and the concrete Gate R decision before further approval. Activation
disabled, AWS unapproved, limits unchanged.”

This approval is requested, not inferred from HAM-1's adoption or the
instruction to prepare this proposal. No MR-1 investigation or hosted read has
started.
