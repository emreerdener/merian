# CPM controlled-worker prelaunch finding

> Current October 14: the approved local campaign ran after exact independent
> and IC-1 concurrence, then stopped at the unchanged 8 MiB growth gate after
> approximately 42 seconds. One worker, five attempts, three verified reads; all
> four opened bodies closed and the container was removed. No retry. See the
> [exact result](client-prepared-media-controlled-worker-result-2026-10-14.md).
> Post-run independent/IC-1 review concurs with the corrected report, including
> its shutdown defect. Sustained reuse and product acceptance remain open.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged.
> Earlier status/approval statements below are historical.

October 14, 2026. The user approved the two-hour local scope from commit
`76bde162c`, requiring exact-candidate independent/IC-1 concurrence before
execution and unchanged limits. Preparation found a runtime-policy conflict.
**Campaign not launched; single-run allowance unused.** No harness or package
was constructed. Activation remains disabled and AWS unapproved.

## Evidence and launch decision

The cached v1.77.0 arm64 image remains
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`. Its
offline `start --help` confirms default supervisor policy `per_worker`. An
unstarted inspection container exposed no standalone source files; bounded
embedded API strings confirm the option names. Both temporary inspection/help
containers were removed and absence checked. No verifier, service, Supabase
stack or campaign ran. Public upstream source was read for the exact release; no
application/service account, credentials, R2 or Supabase target was accessed.

The tagged API accepts an unsigned timeout and forwards it without an upper
clamp in the inspected mapping. This supports the configuration shape, not an
observed long-lived worker or binary reproducibility attestation.
[Creation options and mapping](https://raw.githubusercontent.com/supabase/edge-runtime/v1.77.0/ext/workers/lib.rs)
(lines 104–123 and 241–251).

The `per_worker` supervisor schedules retirement at half the configured wall
clock lifetime. It also compares accumulated worker CPU against the soft/hard
budgets; the soft limit retires the worker. Consequently the proposed 900,000 ms
lifetime retires at approximately 450 seconds, before the nominal last request
at 682 seconds. This is a source-derived feasibility finding, not a measured
failure or CPU estimate.
[Supervisor](https://raw.githubusercontent.com/supabase/edge-runtime/v1.77.0/crates/base/src/worker/supervisor/strategy_per_worker.rs)
(lines 168–185, 313–333 and 390–411).

Retaining the JavaScript handle cannot bypass retirement: the pool rejects
requests for a retired worker.
[Pool send_request](https://raw.githubusercontent.com/supabase/edge-runtime/v1.77.0/crates/base/src/worker/pool.rs)
(lines 527–548). No new worker, reset or request replay is an authorized remedy.

The approved proposal explicitly blocks launch for incompatible runtime
semantics. That gate failed. Raising a timeout or changing supervisor policy
without approval would contradict the user's unchanged-limits instruction. No
campaign was spent proving a conflict already visible before execution.

## Recommended narrow amendment, not adopted

Keep `per_worker` and all CPU, memory, storage, request, workload and real
elapsed schedule bounds. Propose changing only the local runtime's internal
`workerTimeoutMs` from **900,000 to 1,800,000 ms**. Its halfway retirement would
then occur around the external campaign deadline rather than midway through the
schedule. This raises one internal lifetime setting and requires explicit
approval; it is not represented as already authorized or as a product limit.

| Control                  | Proposed amended treatment                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| Internal worker lifetime | 1,800,000 ms, local harness only; pending approval                                        |
| External deadline        | Unchanged 900 seconds from campaign launch; cannot renew                                  |
| Cleanup                  | At most 120 seconds, including container termination/absence check                        |
| CPU                      | Unchanged cumulative soft 5,000 / hard 10,000 ms; retirement stops run                    |
| Memory                   | Unchanged 96 MiB partial proxy / 8 MiB growth stops; 256 MiB worker / 512 MiB container   |
| Workload                 | Unchanged 21 attempts maximum, one worker, serial schedule, no retry                      |
| Other limits             | Unchanged 24 MiB retained / 16 MiB tmpfs / 512 MiB aggregate evidence / 20 GiB disk floor |

This removes the identified timing contradiction but does **not** establish that
18 large reads fit the cumulative CPU budget. A CPU stop is a valid incomplete
result; no CPU increase or second campaign follows automatically. Do not claim
full reuse qualification unless all original success criteria actually pass.

Switching to `per_request` is a different option with different CPU and lifetime
accounting. The tagged implementation resets CPU accounting at request start and
refreshes its wall timer after a request. It is **not** a transparent way to
retain the existing limits, so it is not recommended in this narrow amendment.
[Per-request supervisor](https://raw.githubusercontent.com/supabase/edge-runtime/v1.77.0/crates/base/src/worker/supervisor/strategy_per_request.rs)
(lines 164–174 and 223–234).

Before any amended execution, construct and review the exact local harness and
synthetic package, including an external watchdog that terminates the named
container even if driver or worker hangs. This requirement is more important
when the internal timeout exceeds the external deadline. Confirm watchdog and
bounded log behavior with isolated local control tests, without consuming a
verifier campaign. No new product code, deployments, hosted calls or
credentials.

## Approval boundary and evidence

If the user accepts this amendment, authorize a fresh two-hour local window for
remaining construction, focused checks, exact-candidate independent/IC-1 review,
one campaign of at most 15 minutes, cleanup and reporting. The earlier window is
stopped at this prelaunch gate, not extended. The single campaign remains
unspent. No action follows this amendment automatically.

Evidence and review bindings:
`.artifacts/client-prepared-media/controlled-worker-reuse/`. The approved
original proposal is preserved as historical scope. Ordinary production access
stays nil; original product, media, recovery, shared-asset and IC-1 acceptance
remains open. Credentials stay in the user's store untouched.

Approval wording: “Approve the local-only internal worker lifetime amendment to
1,800,000 ms, retaining the 900-second external deadline and every other limit.
Proceed within one fresh two-hour window, with exact-candidate independent and
IC-1 concurrence before the single campaign. Keep activation disabled and AWS
unapproved.”
