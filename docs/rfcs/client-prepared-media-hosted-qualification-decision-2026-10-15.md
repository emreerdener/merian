# HQ-1: next hosted qualification decision and approval packet

October 15, 2026. **Proposal only; no hosted action authorized.** The user
requested a bounded proposal following local checkpoint `2234b483b`, with
independent and IC-1 review before approval. Activation remains disabled, AWS
and 160 MiB unapproved, all existing limits unchanged, and auto-prompts paused.
This proposal changes neither GAC-1 nor a product acceptance requirement.

## Recommendation

**Do not launch another hosted fixture campaign yet.** The unchanged local GAC-1
schedule cannot be qualified as a same-worker hosted schedule on the documented
platform. Recommend one optional, tightly bounded read-only capability inventory
to resolve the remaining telemetry questions below. It must not become an
invocation-based discovery experiment. Return its findings and an explicit
acceptance-method decision before constructing a new candidate.

The local pass is sufficient to close the finite local checkpoint. Prior hosted
transport evidence remains useful; repeating it merely to seek worker affinity
adds no defensible acceptance evidence. No additional test is needed to confirm
the lifetime mismatch already established by documentation. If the named
telemetry fields are already answered by retained evidence, reuse that evidence
and omit the corresponding live observation.

## Evidence and feasibility

The [local result](client-prepared-media-gac1-local-result-2026-10-15.md) binds
source set `5246e1b990dadab2ca1398698cda8f11b9c72cd45e26782416fe748e8f046e4a`,
executable set
`dd9a608d5f79e7190c0d9f299eb79c866587bb9638188f06214053fc8d96954c` and final
result set `9b0577f633987035d28b6c51480299ff957c949c3f1a17cea321714d9b8b1130`.
Twenty serial reads verified and closed on one observed worker; cleanup passed.
Peak partial proxy was 38.796025 MiB. Cross-cohort Q increased 7.8125 MiB, only
196,608 bytes below the unchanged 8 MiB gate; case-4 warning remains. This is
finite local partial-V8 evidence, not a leak fix or hosted acceptance.

The prior attended `hosted-qdeec80c5e139e0/outcome.md` retained under
`.artifacts/client-prepared-media/` reports 25 verified private-R2 reads and 25
distinct module aliases on candidate `9c88cc72d`. Client pairs completed but
neither warm reuse nor physical reader overlap was established. Its setup,
cleanup and approval are consumed, not reusable execution permission.

Official [Supabase limits](https://supabase.com/docs/guides/functions/limits),
checked October 15, specify a paid-plan worker lifetime of 400 seconds, 256 MB
maximum memory, two seconds CPU per request and a 150-second request idle
timeout. GAC-1's first-to-last large-read interval is 680 seconds, before
allowing for startup or controls. Therefore its exact same-module schedule does
not fit this documented hosted envelope. The local 30-minute internal worker
lifetime is a diagnostic override, not an available hosted setting. The
experiment's 30-second request bound and 96 MiB partial-proxy stop remain
stricter, separate controls; platform ceilings do not replace them.

The source/package gaps are concrete:

| Boundary             | Existing evidence                                                                                                              | Consequence                                                                                                             |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Local lifecycle      | `gac-1/campaign/index.ts` uses a custom main service, `EdgeRuntime.userWorkers.create`, a retained handle and local retirement | Its synthetic bundle, loader and controller are non-deployable; no hosted affinity or retirement capability follows     |
| Hosted entry         | `runtime/entrypoint.ts` calls `createWorker` without GAC-1 and registers `Deno.serve`                                          | Current deployable entry remains legacy version 1; local pass is not qualification of a new hosted artifact             |
| Serial method        | `gac1.ts:GAC1.accepts` requires cases 1–20 in one module in order                                                              | Worker replacement cannot reset the sequence or contribute points to another worker's cohort                            |
| Hosted driver        | `driver.ts:acknowledgement` accepts the exact version-1 shape; GAC-1 adds version-2 growth fields                              | A future protocol adapter needs explicit preparation and exact review; old staged package cannot be silently relabelled |
| Concurrent admission | `handler.ts` has a module-local busy latch; driver pairs are separate HTTP calls                                               | Paired sends and different aliases do not establish physical overlap or same-module contention                          |
| Measurement          | Existing telemetry reports partial V8 samples and wall timing                                                                  | Neither whole-worker/native peak nor attributed CPU is proven                                                           |

Source paths in this table are relative to
`services/supabase/tests/cpm_verifier_characterization/`, except the local
controller under `.artifacts/client-prepared-media/`. The unchanged memory
measurement call and GAC-1 predicates must not be adapted opportunistically to
make a hosted run pass. No compressed timing, combined multi-read invocation,
cross-worker statistical pooling, forced GC, keep-alive background task, custom
server, new Supabase project or AWS worker is proposed.

## HQ-1A: bounded read-only scope proposed for approval

**Target:** existing production-alpha Supabase project `qlarqavoqhkuwzmevrmf`.
The existing private R2 bucket `merian-cpm-verifier-fixtures` remains the future
fixture target, but this inventory needs no R2 access. No production app route,
database, user, media object or provider is invoked.

**Owner:** Emre is accountable operator; History primary performs only approved
reads and owns the sanitized report. Independent and IC-1 reviewers remain
read-only. Existing control-plane access may be used; no new credential,
permission, login identity, credential-store discovery or secret installation.
Do not request the R2 keys for this scope. If access is unavailable, stop rather
than initiate login or expand permissions.

**Bounds:** one 45-minute window from the first authorized hosted read, at most
12 application-level control-plane observations, no polling/retries, at most 64
KiB new sanitized retained evidence, and zero function invocations, fixture
transfers, uploads or mutations. The observation count is not a claim to count
every dashboard network subrequest. Prefer an existing bounded metadata API; do
not browse unbounded logs. At most 100 experiment-only event records may be
examined across the entire inventory, with a bounded query/projection before
retrieval. If the existing interface cannot enforce that selection, record it
unavailable without fetching raw logs. This is a smaller allocation within the
existing 256-call and 512 MiB evidence ceilings, not a limit increase. Preserve
at least 20 GiB free disk and all prior evidence; no cache/evidence pruning.

| Allocation | Exact observation sought                                                                                                                                                                                                                    | Decision supported                                                                                                                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Up to 2    | Existing project's plan/status and any exposed runtime/build/version or resource-policy metadata                                                                                                                                            | Confirm target context; absent build/override metadata stays unknown. Do not infer a longer lifetime or use this as a current health pass for a later test                                                                                                   |
| Up to 4    | Available telemetry field definitions, units, time resolution, aggregation window, scope and retention; whether data is per invocation, isolate, container or fleet                                                                         | Decide whether an attributed CPU or native-inclusive memory method is even available without new instrumentation/add-ons                                                                                                                                     |
| Up to 4    | Only retained October 14 experiment events, selected by exact function/deployment and its recorded attended-run interval; allowlisted termination reason, CPU value/domain, memory value/domain, event time and opaque correlation metadata | Determine whether existing observations can be joined to a synthetic invocation/worker, whether values are snapshots/totals/peaks, and whether concurrent work contaminates attribution. Retention expiry is a result, not permission to generate new events |
| Up to 2    | Existing platform metadata/help for supported routing/identity and read start/end correlation                                                                                                                                               | Establish a supported measurement mechanism if one is actually exposed. No invocation probes, settings changes, support ticket or third-party message                                                                                                        |

Do not retrieve customer event bodies, request headers, auth state, secret
values/digests, object contents/keys or unrelated traffic. Map any necessary
experiment correlation identifiers to local aliases; retain only allowlisted
numeric fields, capability booleans, units, provenance and unavailable reasons.
No raw production log export. If telemetry is only worker-total CPU, do not
divide it among requests. A terminal memory snapshot cannot establish lifetime
peak; an average or fleet value cannot enforce an in-request stop. Absence of a
limit event is not proof of a passed resource budget. The official
[shutdown-event guide](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained)
describes diagnostic events; target availability, coverage and attribution must
remain separate findings.

Stop at the first target/access ambiguity, unsafe/unbounded output, exhausted
observation/evidence/time budget, or action requiring mutation. Missing optional
fields are recorded once; do not search repeatedly or create traffic to fill
them. Finish with one capability table and exact independent/IC-1 review, with
no further execution authorization. Read-only inspection creates no remote
cleanup obligation and does not authorize deleting the retained old control
object or changing the two retained R2 credentials.

## Fixed disposition and acceptance matrix

| Requirement                                      | Current disposition                                                        | What could close it                                                                                                                                                        |
| ------------------------------------------------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Finite local GAC-1                               | Passed on the reviewed exact candidate; no rerun needed                    | Retain the result and warnings                                                                                                                                             |
| Prior hosted byte transport                      | Qualified only for its old representative candidate and named observations | Reuse unchanged-path evidence; new material composition requires its own candidate evidence                                                                                |
| Exact hosted GAC-1                               | Blocked by documented lifetime and absent deterministic affinity           | A separately approved, supported hosted method; HQ-1A cannot waive the mismatch                                                                                            |
| Hosted CPU/native memory                         | Unqualified                                                                | Attributable measurements with known domains and coverage; missing data remains open                                                                                       |
| Hosted same-worker contention / physical overlap | Unobserved                                                                 | Supported correlated evidence and accepted methodology; client pairs alone are insufficient                                                                                |
| Complete verifier and CPM/IC-1                   | Open                                                                       | Product identity/ownership, complete composition, source retention, audio quality, ingress, recovery/deletion and native/integrated acceptance on one applicable candidate |

If HQ-1A finds no usable additional measurement, stop and report the capability
gap. Do not rerun the old hosted schedule, create a shorter surrogate or begin
another local diagnostic campaign. The next decision is explicitly whether to
approve a different hosted acceptance method, or retain the blocker. This
proposal does not adopt either choice. A short request-admission/paired-request
check could only prove its own bounded observations; it would not be hosted
GAC-1, would not close the missing gates, and is not recommended merely to
repeat the old transport result.

## Required contents of any later hosted-test packet

There is **no execution-ready hosted candidate in this packet**. Before asking
for fixture execution, bind an actual immutable source/stage/driver manifest,
reviewed protocol/method changes, passing affected checks, bundle identity and
exact independent/IC-1 concurrence. Local construction and packaging need their
own bounded approval. Reuse unchanged passing evidence; do not rebuild or rerun
suites without a changed boundary. Do not deploy the local synthetic bundle or
reuse the legacy package under a new label.

Any later packet must retain these existing upper bounds and name all actions:

- One attended setup/run of at most 30 minutes including installation, followed
  by at most 15 minutes cleanup; $10 ceiling; at most 26 driver calls, two
  clients, one reader per module, 30 seconds per request, 192 ordinary plus 64
  cleanup application calls, 256 total, and 2 GiB transfer. No automatic retry,
  journal resume, replacement request, expiry extension or paid add-on.
- Only route `cpm-verifier-characterization` in the existing project, through an
  explicit one-route deployment exception. Product flags stay disabled;
  installing even a disabled test feature is still a backend deployment. No
  PR116 push/merge, fleet deployment, migration or activation is implied.
- Exactly seven temporary shared-project settings: `CPM_Q_RUN`,
  `CPM_Q_OPERATOR_KEY`, `CPM_Q_CAPABILITY`, `CPM_Q_EXPIRES_AT`,
  `CPM_Q_R2_ENDPOINT`, `CPM_Q_R2_ACCESS_KEY_ID`, `CPM_Q_R2_SECRET_ACCESS_KEY`.
  Every project function can access these settings. Only the existing
  bucket-scoped read credential is installed; operator write credential stays
  local. Keys are retained in the user's secure store, not rotated/revoked by
  routine cleanup. Fresh run key and capability remain independent, private and
  one-run. Current credential scope and access must be checked then.
- Fresh namespace and exclusive conditional single-part uploads only after
  approval; reuse verified existing local synthetic files without duplicating
  their 67,174,400 bytes. Denial and two closed 64 KiB controls precede any bulk
  upload. Runtime compatibility and remaining schedule must pass the barrier; an
  unqualified newer runtime stops, never silently substitutes.
- Existing 96 MiB partial-proxy and 8 MiB acceptance values remain fixed; 160
  MiB remains unapproved. A platform hard limit is no substitute. Package,
  per-asset, temporary and retained-storage limits are unchanged. Reserve room
  for candidate, bounded logs and cleanup before setup; do not assume the old
  storage inventory still fits.
- On failure or uncertainty stop admission, remove only the experiment route and
  seven settings, verify their absence, and delete only fresh-run objects with
  positive reader/writer closure. An unresolved writer/reader retains its
  private object and reconciliation obligation. Expiry, route removal, HEAD or
  local process loss do not prove closure. Remove temporary local/hosted secret
  copies; preserve stored keys and all evidence. No recursive purge, old-object
  deletion or bucket deletion. Cleanup authority and remaining budgets must be
  explicit even on a failed run.

This envelope is preserved for later approval; none of these operations is
requested for immediate execution. The exact workload and measurement must be
decided first, so an old approval, generic “proceed,” or this proposal's review
cannot silently select them.

## Approval requested now

“Approve HQ-1A only: one 45-minute read-only capability inventory of existing
Supabase project `qlarqavoqhkuwzmevrmf`, up to 12 bounded observations and 64
KiB sanitized evidence, reusing retained evidence wherever possible. No function
invocations, R2 access, credentials changes, construction, tests, uploads,
deployment or provisioning. Return the capability findings and next acceptance
decision for review. Activation disabled, AWS unapproved, all limits unchanged.”

This approval has not been granted. No hosted action occurred while preparing
this packet. The primary remains sole writer; no broader engine handoff or
capture-UI ownership change occurs. Fresh initial/reanalysis still requires
actual photo/audio/video, optional immutable supporting descriptions, preserved
historical text records and exact admitted-operation recovery. Unknown AI
execution permits only original-operation recovery/reconciliation, never a new
provider invocation or refund. Version deletion/export follows current-scope
acceptance, then Identification/History redesign. Those gates remain open.
