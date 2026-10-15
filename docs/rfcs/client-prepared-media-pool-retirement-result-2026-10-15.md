# CPM pool retirement: controls passed, campaign stopped at growth gate

October 15, 2026. **Local shutdown evidence passed; the campaign did not
qualify.** Activation remains disabled, AWS and 160 MiB remain unapproved, all
limits unchanged. Auto-prompts remain paused. No product/native/integrated
acceptance closes.

## Outcome

The approved bounded retirement method removed the retained pool-send error in
both the proposed short control and the campaign's early-stop teardown. The
campaign nevertheless stopped at its unchanged 8 MiB growth gate. One successful
shutdown control and one failed-workload teardown do not establish general
runtime shutdown safety, sustained reuse qualification or hosted behavior.

| Observation            | Result                                                                                                                                                                           |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Baseline short control | Expected sole pool-send error reproduced; signal/exit 15; complete receipts and removal; 2.956677 seconds                                                                        |
| Proposed short control | True acknowledgment 1; empty registry after 2 inventory calls; exactly one matching early-drop event; no errors; signal/exit 15; complete receipts and removal; 3.020882 seconds |
| Campaign workload      | FAILED `growth_stop` after 42.234860 seconds; 1 worker, 5 requests including denial, 4 media reads, 3 verified and 1 stopped                                                     |
| Campaign teardown      | Passed the scoped shutdown envelope; acknowledgment 1,2inventory calls, matching early-drop, empty-pool receipt before stop, no errors, signal/exit 15, EOF and removal          |
| Total campaign elapsed | 44.993477 seconds including teardown/cleanup                                                                                                                                     |
| Remaining execution    | Both controls and the single campaign consumed; no retry or window extension                                                                                                     |

Four opened media bodies consumed 67,239,936 bytes and all four reported closure
and cleanup. Cases 5–20 did not run; the planned 604,110,848-byte workload and
both sustained cohorts were not completed. No provider invocation, real user
media, hosted call or credential access occurred. The synthetic container had
networking disabled and no published port.

## Why the growth gate stopped

The existing gate evaluates four ordered post-request points from the same
worker. All four increased, and their first-to-fourth difference exceeded 8 MiB:

| Case | Recorded post-request proxy, bytes | Outcome  |
| ---- | ---------------------------------: | -------- |
| 1    |                         17,644,757 | Verified |
| 2    |                         17,845,063 | Verified |
| 3    |                         19,903,285 | Verified |
| 4    |                         31,961,909 | Stopped  |

Growth was 14,317,152 bytes (**13.653900 MiB**). Maximum reported request proxy
was 36,713,785 bytes (**35.012994 MiB**), below the unchanged 96 MiB proxy
ceiling. These are the existing partial-V8 measurements, not RSS or proof of a
physical leak. The case 4 first-original-call proxy was 16,036,629 bytes, lower
than case 3's last point; this demonstrates that the observed boundary values
vary across phases. It does not justify bypassing the four-point gate, forcing
GC, changing sampling, increasing limits or declaring retained memory safe.

Earlier full-workload evidence remains historical and unchanged. Its workload
pass and lifecycle failure cannot be combined with this run's successful
teardown to claim an end-to-end passing candidate. A bounded read-only
comparison of retained allocation/boundary evidence would be the next useful
proposal; no new measurement method, campaign or implementation is inferred
here.

## Shutdown evidence and interpretation

The proposed control observed pool-empty receipt about 57.6 ms after
cleanup-start receipt. The campaign observed it about 32.1 ms afterward. Each
was strictly before its operator stop intent. These are host receipt intervals,
not exact internal runtime durations. The main's 1500 ms absolute phase budget
and the existing 2-second host drain were not extended. No runtime grace, worker
lifetime, Docker grace, watchdog, workload or resource gate changed.

Exit 15 means expected external operator termination. It is **not graceful
process exit**. `campaign-run/outcome.json` records
`shutdown_evidence_complete:true`, `receipt_order_complete:true` and
`graceful_process_exit:false`. The offline assessor's `qualified:false` and
`overall_lifecycle_passed:false` include the failed workload predicate; those
fields are not evidence of a new shutdown error. Preserve these raw outputs
without rewriting their classifications.

The post-terminal pool inventory reads were excluded from workload memory/growth
measurements. No inventory values, paths or keys were retained. The already
created synthetic worker UUID was used only for the exact expected early-drop
line comparison. All other runtime errors remained fatal.

## Exact approval, candidate and reviews

User-approved local window: **15:48:12–17:48:12 UTC**, October 15. Execution
stopped on the campaign failure; remaining wall-clock time authorizes no further
run. Method owner:
[reviewed retirement proposal](client-prepared-media-pool-retirement-proposal-2026-10-15.md).
Execution/evidence root: `.artifacts/client-prepared-media/pool-retirement/`.

- Executed 61-file candidate set:
  `af9802a14a9833e1ef8e2eb9f7c5b6f65a2549cef3351347dff5f607b3e4e147`.
- Independent reviewer: `/root/diagnostics_review_fallback`; controls and
  qualified clock/watchdog reuse concurred after deadline correction.
- IC-1 control concurrence turn: `01a1404c-4fe0-7db2-a37b-1bc54b073549`.
- Both reviewers separately concurred for the conditional campaign after
  control-result review; IC-1 turn: `01a1404f-7d69-7023-ac1a-c31e6bff9ddf`.
- Control-evidence 22-file set:
  `ccec36c3f2718dfaa3bbee75475b9d62e1e27104269919e540937dfbdb217344`.
- Baseline outcome SHA-256:
  `884c0ebc7898badfcfda3eb57b5a9f524d9c4dcd7219b31d8b8e275a43819d0a`.
- Proposed outcome SHA-256:
  `8748c379a61006a42b642850d4e919ddcec23a22372642cbffa6056276ed0a1f`.
- Campaign outcome SHA-256:
  `f0a3aa7aa72f5267046bd2406abc674bf2bc16c234af450e789a6fde61a45f5b`.

Runtime image and verifier ESZIP remained the exact previously reviewed hashes.
No new bundle/image/dependency/interpreter was constructed or downloaded. The
existing qualified clock basis and guardian were byte-identical; reuse was
explicitly reviewed and no clock/watchdog observation was repeated.

## Verification, corrections and preservation

Before execution: 25 Python checks, 8 Deno tests, 3 entry-point type checks and
the Markdown gate passed. Five focused preservation checks passed again after
the retirement correction. The initial Deno timer-handle typing failure is
retained as `deno-01.log`; later successful logs are separate.

IC-1 identified a deadline-renewal gap before controls. The corrected helper
fixes each operation deadline from one clock reading capped by the phase end,
checks again immediately before deferred invocation and after settlement, and
checks the phase end immediately before empty-pool success. Deterministic
clock-advance regressions cover scheduling, deferred invocation and final
decision boundaries. Both reviewers concurred on the corrected exact candidate
before execution. No source changed during controls or campaign.

Old proposal status bytes are retained in `prior-status-snapshots.json`; exact
executed candidate status bytes are retained in
`execution-status-snapshots.json` before current summaries were updated. Source
files, prior failed outcomes, review manifests and raw logs remain preserved.
The 115 unrelated dirty paths remain unchanged. Final Docker inventory confirmed
no experiment containers remain; there are no pending container cleanup
obligations.

Independent and IC-1 result review concurred with this failed-workload and
successful scoped-teardown classification. Exact receipts are retained alongside
the result manifest in the evidence root. No push, merge, deployment,
provisioning, secret change, device installation, distribution, AWS use or
activation is authorized by these local results.
