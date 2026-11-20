# CPM request-boundary campaign result

October 14, 2026. **Workload passed; overall lifecycle qualification failed.**
The single approved local campaign is consumed. No retry, replacement worker,
new controls or hosted action followed. Activation remains disabled, AWS and 160
MiB unapproved, all existing limits unchanged, auto-prompts paused.

## Authority and exact candidate

The user approved the narrower request-boundary amendment to the
[allocation-diagnostics scope](client-prepared-media-allocation-diagnostics-proposal-2026-10-14.md),
following the preserved
[prelaunch finding](client-prepared-media-allocation-diagnostics-preflight-2026-10-14.md).
The original two-hour window was 19:01:48–21:01:48 UTC. Actual launch was
19:38:43.632 UTC and the operator finished after 683.005 seconds, within that
window. No allowance or threshold was increased.

Exact candidate set:
`82f1c3a6e4bf3911f5924b4ff0504aec8894a15b4b9c649ec5e086951dcce333`. ESZIP
SHA-256: `3f28f9b7ac99d6d55d87cd1b47be19d4b6a2bebffcd0eb3531a340ade752fbf6`
(8,435,444 bytes). All 82 bound file hashes remained unchanged through
execution. Independent read-only reviewer and IC-1 concurred before launch; IC-1
turn `01a13beb-77b5-79a1-a5af-97bfe35345fa`. Receipts and the launch gate are in
`.artifacts/client-prepared-media/allocation-diagnostics/boundary/execution-concurrence.json`.

## Observed results

| Observation                             | Result                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| Worker instances / acknowledged aliases | One / one throughout                                         |
| Attempts / forwarded requests           | 21 / 21; denial 26, then cases 1–20 in order                 |
| Verified and closed reads               | 20 / 20: two 64 KiB controls and eighteen 32 MiB reads       |
| Verified bytes                          | 604,110,848, all exact fixture digests matched               |
| Cohort spans                            | 320.067 and 320.049 seconds, each meeting 320-second minimum |
| Workload terminal                       | Passed at 682.342 seconds                                    |
| Peak partial V8 proxy                   | 40,678,197 bytes (38.794 MiB), below 96 MiB                  |
| Original growth gate                    | No stop across all 17 four-point windows, including controls |
| Diagnostic observations                 | 63 bounded records; 19 same-worker boundary pairs            |
| Shutdown acknowledgement / EOF          | Present / present; no partial log line                       |
| Process exit / lifecycle qualification  | Exit 1 / failed                                              |
| External container cleanup              | Confirmed; stop/remove succeeded, trigger `driver_finished`  |
| Total log / operator duration           | 30,977 bytes / 683.005 seconds                               |

These results establish that the instrumented local synthetic workload completed
on one retained worker under the unchanged gates. They do not establish a
complete successful lifecycle or hosted behavior. `operator_failure: null` is
not an overall pass: the collector separately retained runtime errors and marked
`shutdown_evidence_complete: false` and
`termination_disposition: failed_or_unknown`.

## Memory interpretation

Only the existing original memory dependency calls were observed; no extra
memory calls, background observers, timing probes, forced GC or replacement
worker. Original acknowledgements and growth calculations remained
authoritative.

There were 17 pairs following large reads, of which six had a lower proxy at the
next request's first original call. For example, case 3's last value was
32,224,053 bytes and case 4's first was 16,036,629 bytes, a decrease of 15.438
MiB over approximately 39.885 seconds. Large-read sample gaps ranged from 39.847
to 39.901 seconds. The final request has an explicit missing pair because there
is no subsequent request; no extra request was sent to obtain one.

The last original call is not necessarily Ack.quiescent, and the next first call
includes incoming-request allocations. Therefore these are request-boundary
observations, not pure idle measurements or proof of completed GC. The measured
proxy decreased across those boundary samples. These observations do not
identify the mechanism or prove absence of a leak. The final quiescent value was
also the run's peak, so a stable memory plateau is not established.
Instrumentation overhead is included; this run does not invalidate the previous
uninstrumented growth-stop evidence or establish numeric equivalence between the
two candidates. No RSS or attributed CPU measurement was obtained.

## Lifecycle failure and cleanup

The main service emitted its passing workload result, awaited server shutdown
and emitted `server_shutdown`. The following two runtime lines then appeared:

```text
main worker has been destroyed
failed to send the shutdown signal to user worker pool: SendError { .. }
```

The process exited with code 1. These are unclassified runtime failure evidence,
not the narrowly accepted operator SIGTERM/exit-15 pattern. They have not been
suppressed, reclassified as benign or converted to a pass. Removing unsupported
`Deno.exit` fixed that earlier source issue but did not qualify the complete
runtime shutdown lifecycle. The precise cause of this remaining runtime error
has not been established by this campaign.

The independent guardian confirmed removal of the owned immutable container ID.
All opened stream obligations closed before terminal result. There is no
recorded outstanding container or attachment obligation. Cleanup success is
separate from lifecycle qualification. No credential was accessed, installed,
rotated or revoked; no Supabase/R2 objects or settings were changed.

## Construction and verification

One offline bundle attempt succeeded; the second was unused. The two inert
controls from preparation remain consumed and unchanged. Earlier failed nominal
control evidence and its narrowly derived replay remain distinct.

Five synthetic Deno diagnostic tests, three offline pairing tests, four static
checks, three cleanup-budget tests, five parser regressions, two cleanup-owner
and two attachment-deadline regressions passed. Recursive offline no-run type
checking and focused lint passed. Post-run evidence checks verified order,
identity, digests/bytes, closure, cohort spans, unchanged growth calculation,
log bounds, exact candidate preservation and external cleanup. Prior signing
source-level proof was hash-bound and reused, not rerun or represented as fresh
R2 verification. Unchanged native/database/product suites were not rerun.

Independent and IC-1 preparation review corrected response replacement on
logging failure, a cleanup deadline anchored too late, a guardian/fallback
writer race, and attachment signals after budget expiry. Each material
correction was re-reviewed before launch. Earlier manifests, findings and failed
preparation checks remain retained. No verifier core, policy, signing,
dependency/lockfile, production function, iOS source or schema changed. All 115
unrelated dirty paths remain preserved.

Retained new evidence is approximately 8.53 MiB; aggregate CPM evidence is
approximately 467.47 MiB, plus the 16 MiB temporary reservation below 512 MiB.
Free disk was approximately 50.97 GiB. Source and candidate evidence live under
`.artifacts/client-prepared-media/allocation-diagnostics/boundary/`; results are
in `campaign/{runtime.log,outcome.json,analysis.json,verification.json}`. The
separate result manifest and final review receipts bind this report and
evidence.

## Remaining boundary

Overall lifecycle qualification remains open. Any further execution needs a new
explicit bounded approval; the unused second bundle allowance does not authorize
another campaign. A next proposal may isolate main-service/user-worker-pool
shutdown behavior before requesting another full verifier run. No root-cause fix
or alternative runtime lifetime is adopted here.

Hosted affinity/concurrency, resource measurements beyond the partial proxy,
original-media retention, audio quality, recovery, shared-asset deletion, native
journeys and integrated acceptance remain separate open gates. Existing
deletion/export then redesign sequencing and capture-tools ownership are
unchanged. Push, merge, deployment, hosted tests, device operations, activation
and AWS remain outside this completed local scope.
