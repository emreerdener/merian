# CPM-1 bounded local construction: approval request

Status: October 14, 2026. **Approved local construction and review complete.**
The direct human instruction approved this bounded work with activation
disabled, unchanged package/storage limits and no provisioning, credential
changes, uploads, deployment or hosted tests. The clock began at
`2026-10-14T06:00:01Z` and ends at `2026-10-14T10:00:01Z`, including checks,
review and corrections. The
[local representative candidate](../../services/supabase/tests/cpm_verifier_characterization/README.md)
has independent and IC-1 local-only concurrence. Its local results do not close
any hosted, resource or complete-verifier acceptance gate. The original request
below is retained to define the approved boundary; its request-for-approval
wording is historical for this local construction only.

The human approved R2-F1 and TM-1 at checkpoint `a39525950` and confirmed Emre
as operator in advisory turn `01a138f7-a38d-75a0-b0c8-31f2d0eb9665`; the primary
verified the direct human message. This approves the
[private fixtures and partial telemetry design](client-prepared-media-private-fixtures-telemetry-proposal-2026-10-14.md),
including its limited measurements and platform-only established total-memory
backstop. It does not authorize running that risk on production or close any
feature/resource acceptance gate. The 160 MiB total-memory guard is not adopted.

## Completed local checkpoint

The reviewed source set is
`4b01085e547685374d9c65191d31ab4c4197d31de7dadcdb56a2698cb0c7e2e6` in
`.artifacts/client-prepared-media/verifier-local-candidate/candidate-manifest-04.json`.
All 13 TypeScript files match `validation-03.json`; its 26 network/environment-
denied local tests, formatter, lint and full candidate/transitive type checks
passed. The only subsequent source-directory edit corrected a README import
claim; formatting and both reviewers confirmed that documentation-only delta.
The local deployment selector selected zero functions from all 18 owned paths.
This does not clear the shared dirty checkout, PR116 or any backend deployment.

Independent review and IC-1 reviewed and re-reviewed the corrected candidate.
IC-1 concurrence is turn `01a13918-fd82-7853-b8e4-f685a1b54180` in the existing
Harden main analysis engine thread. Corrections cover post-Auth cancellation,
worker-wide abort of active readers, absolute deadlines even with delayed timer
delivery, and the 15-minute cleanup-reservation window. Failed checks and
initial findings remain in the evidence directory. History remained sole writer.

Local topology, trusted Auth, transport and memory samples are injected. Case 26
is a policy-selected denial, not proof of rejected-caller hosted Auth. One
handler instance per physical worker is a future packaging requirement, not
proven routing. No platform/native-memory, CPU, hostile-ingress or complete-
verifier qualification follows. The local code has no function registration,
default transport, credentials or production-helper changes.

## Next separate approval packet: R2 setup only

The next operational request can be limited to **R2-F1 setup only**, with Emre
as accountable operator: create `merian-cpm-verifier-fixtures` in the same
Cloudflare account identified by the October 14 read-only inventory; confirm
that account and bucket-name availability immediately before any authorized
mutation. Use the already approved Standard/private settings: no public domain,
no r2.dev access, no public binding/proxy, no CORS, no object-expiry rules on
the run namespace, no bucket lock, no event/Worker/cron/log-sink setup. Create
only bucket-scoped experiment credentials with the previously approved separated
operator-write and runtime-read roles. Do not broaden or alter app credentials.
Inspect resulting configuration/permission metadata only; credential values must
remain outside source, artifacts and logs.

That would be a new named-operation authorization. It is **not granted here**.
It would include no object uploads/reads, fixture writes, Supabase secrets,
function construction/installation/invocation, hosted measurement, production
activation or changes to the current `merian` and unrelated `portfolio` buckets.
An unavailable name or inability to establish the approved settings/scopes
returns a blocker; it does not authorize a substitute account/bucket or broader
permission. No setup is needed merely to retain this completed local checkpoint.

A later exact hosted packet remains blocked on actual Auth/principal binding,
runtime metric adapter/build evidence, private fixture readiness, unique
worker/handler packaging, genuine denied-caller scope, and reviewed independent
operator disable/revocation/cleanup controls. Those missing packaging changes
need their own bounded authorization/review. The existing production alpha
Supabase project remains the intended target; no separate project is required.
No new hosted call count, resource guard or product limit is adopted. The
[R2-F1/TM-1 sequence](client-prepared-media-private-fixtures-telemetry-proposal-2026-10-14.md)
continues to separate setup from exact installation/execution approval.

## Requested authorization

Authorize **at most four hours of local work**, beginning only after explicit
approval of this request, to build and review a qualification-only
representative handler and fixed driver. Use the existing checkout and
installed/pinned tools. The timebox includes preparation, focused local checks,
review and corrections; record start/end and stop at the cap even if review is
incomplete. No automatic extension. No R2 provisioning or hosted access is
needed to do this local work.

History primary is the sole writer. Independent reviewer and IC-1 are read-only.
Emre remains the accountable operator for later separately authorized setup,
disable, credential revocation and cleanup, with no action required now.

## Exact deliverables and write boundary

Place qualification-only TypeScript and its README under
`services/supabase/tests/cpm_verifier_characterization/`; retain manifests and
results under `.artifacts/client-prepared-media/verifier-local-candidate/`.
These approved paths now contain the local candidate and evidence. Update only
these sources, related CPM decision/acceptance notes and the three continuation
summaries.

1. **Representative handler:** the selected real wrapper/auth/import
   composition, bounded manifest parsing, fixed-fixture private-GET adapter,
   incremental length/hash verification, TM-1 sampling and bounded response
   serialization. Provide injectable Auth/GET/clock/telemetry boundaries for
   local checks; distinguish real helpers from substitutes in the manifest. Keep
   any entrypoint outside `functions/*/index.ts`, with no function registration
   or app route.
2. **Fixed driver:** prepare the existing 26-case hosted schedule as data and
   driver logic, with attempt-before-send accounting, two-client maximum,
   same-fixture exclusion, no retries/redirects/resumption, positive terminal
   acknowledgement validation and stop/cleanup inventory. Local execution uses
   injected transports only; no usable hosted run configuration or credentials.
3. **TM-1 implementation in the candidate:** separate byte-valued `heapUsed`,
   `heapTotal`, `external`; sampled `P = heapTotal + external` stop at 96 MiB;
   three consecutive positive quiescent increments totaling at least 8 MiB stop
   further work. Use bounded active-only 100 ms sampling, component maxima and
   worker aliases. Label P as partial V8 accounting, never total memory/RSS or
   the historical 96 MiB process-memory result. Timer/heap growth and missing
   fields must not be silently ignored.
4. **Source/dependency manifest:** exact Git base and candidate hashes, all
   files and transitive runtime imports, existing lockfile/tool pins, helper
   reuse, stubs, outbound paths, permission assumptions, fixture size/hash
   identities, telemetry units, known omissions and the future packaging
   boundary. No new dependencies, downloads or root lock/configuration changes
   in this timebox; if existing dependencies cannot suffice, return that
   blocker.
5. **Evidence and handoff:** local check results including failures, reviewed
   cleanup states, independent/IC-1 findings and re-review after correction,
   plus an exact candidate summary. End with readiness or concrete gaps and the
   next separate R2/setup or hosted approval packet. Do not execute that packet.

The candidate omits SQL claims/receipts, funding, admission, provider execution,
production shared-asset references/deletion, iOS media preparation and the later
redesign. It is not the complete verifier. No production helper changes are
allowed: if representative composition needs them, document the required delta
and stop that work for a revised request. Preserve the 115 unrelated changes,
release holds, existing dependencies and all earlier evidence.

## Local correctness and cleanup checks

Use the pinned Deno tooling with explicit local read/write permissions and
network denied. Auth and R2 responses are synthetic injected values; never use
configured hosted credentials, ordinary app identities, customer media or live
endpoints. Do not start a Supabase stack, Docker runtime, simulator or managed
build. These checks establish local logic only, not real TLS/fetch allocation,
hosted Auth, private storage or runtime behavior.

| Check group          | Required evidence                                                                                                                                                                                                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Authorization/inputs | Wrong operator/capability, expiry, unknown case/key and oversized/malformed manifest open no reader. Auth adapter tests are labelled simulated; real hosted denial remains unqualified.                                                                                                         |
| Stream integrity     | Exact lengths/digests for deterministic fixtures, boundary overrun, truncation and corruption; no whole-file aggregate copy; reject invalid response/status and redirect. A correct synthetic stream is not proof of provider transport limits.                                                 |
| Reader lifecycle     | EOF success, stalled acquisition/read, abort before/after acquisition, late body after timeout, cancellation failure and cleanup failure. One reader per simulated worker; release lock/state/timer/slot only at the specified boundary. Unknown cleanup never produces success or another GET. |
| Driver uncertainty   | Lost/truncated/mismatched acknowledgement, duplicate case, restart attempt and one incomplete pair member stop advancement. Busy denial cannot close the paired reader. Fixture reuse waits for positive closure; no retry or replacement read on uncertainty.                                  |
| Telemetry            | Missing/nonfinite/negative fields stop; zero RSS labelled unavailable; 96 MiB proxy and 8 MiB growth-rule boundaries, same-worker ordering, timer cessation and bounded storage/serialization checked with injected samples and clocks. No forced-GC plateau claim or resource-budget pass.     |
| Finite bounds        | Dry-run scheduler accounting stays within 26 cases, two clients, 256 HTTP attempts (192 ordinary/64 cleanup), 2 GiB and fixed deadlines/window. Model separate workers and same-worker denial; do not manufacture hosted routing evidence.                                                      |

Run formatter, focused lint/type checks and the new local correctness tests on
this candidate, including transitive type checking under the existing frozen
configuration. Use the repository deployment selector in a local read-only check
to confirm zero deployable functions are selected by this test-only change; do
not dispatch CI or alter the selector. Review any import-time side effects
before local execution. If the selector or a required check cannot run within
the allowed tools/time/storage, report it unrun rather than relax a gate. Do not
repeat unchanged prior buffered/loopback experiments or broad unrelated suites.
No hosted success, CPU qualification or production isolation is inferred.

## Storage, time and stopping rules

- Three synthetic fixtures remain two 32 MiB files plus one 64 KiB file, with
  streaming generation/reuse; no extra fixture corpus. Local-only fault cases
  use generated streams rather than additional large files.
- Keep combined new fixture, temporary, source-manifest and evidence allocation
  within **512 MiB**. Preserve existing historical evidence; it still consumes
  real disk headroom. Check actual free disk before work and before large
  writes; stop before falling below **20 GiB**. Do not prune shared
  caches/dependencies or old evidence to fit the work.
- Stop at four hours, an unresolved safety/correctness finding, missing pinned
  dependency, necessary out-of-scope helper/schema change, active compilation
  conflict, disk limit or need for hosted access. Failed checks can be corrected
  and re-run within scope/time, retaining the first failure; otherwise report
  the exact remaining work. No automatic new experiment or budget increase.
- Final review is mandatory before claiming readiness or committing a coherent
  local candidate. If the timebox expires with review pending, preserve the
  uncommitted candidate/evidence and report incomplete. Local success permits
  only proposing the next checkpoint.

## Approval wording

“Approve up to four hours of the local construction and checks specified here,
with History primary as sole writer and independent/IC-1 review. No
provisioning, credential changes, fixture uploads, Supabase secrets/function
installation, hosted testing or external operations.”

All package/per-asset/storage product limits remain unchanged. Activation stays
disabled, AWS unapproved, auto-prompts paused. Existing push, merge, deployment,
device and distribution restrictions remain. Approval of this request permits
only the local work above; it does not authorize hosted execution or
provisioning of the approved R2 design.
