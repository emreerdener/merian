# CPM clock qualification and replacement lifecycle controls: result

October 15, 2026. **Clock and watchdog qualified locally; proposed lifecycle
control failed. The conditional campaign did not run.** Activation remains
disabled, AWS and 160 MiB unapproved, all limits unchanged. Auto-prompts remain
paused. No product, native or integrated acceptance gate closes.

## Approved scope and exact candidate

The user approved the
[reviewed clock-method amendment](client-prepared-media-shutdown-clock-finding-2026-10-15.md#recommended-next-amendment--not-yet-authorized)
in a fresh two-hour local window, **14:57:29–16:57:29 UTC**. The earlier
proposal and failed baseline remain historical. The primary alone wrote and
operated the local experiment; independent and IC-1 reviewers remained
read-only.

The final executed candidate set is
`0b09eb9fa54afc6a886be74dee937dd0cfe1e5c864d7f4d53b0357e66e9feef8`, binding 43
files in
`.artifacts/client-prepared-media/clock-qualification/candidate-manifest.json`.
Both reviewers concurred before execution; IC-1 turn
`01a1401a-46e1-7a91-bd57-8a0d1991cf7a` and `control-concurrence.json` record the
final authorization boundary. A campaign would require successful controls and
separate exact concurrence; neither condition was established.

Before execution, review corrected child-reaping failure recording and removed
minimum timeout floors. One launch preflight then rejected the unresolved versus
resolved Xcode Python path. That failure occurred before the one-shot directory,
child or container existed, so it consumed no execution allowance. Both
reviewers concurred with the narrow resolved-path correction. Previous candidate
manifests, failed preflight evidence and test logs are retained.

All baseline/proposed/campaign TypeScript and the existing verifier ESZIP remain
byte-identical to the prior reviewed candidate. The host operator, guardian and
journal now share explicit `time.clock_gettime(time.CLOCK_MONOTONIC)` with no
fallback, using the same pinned Xcode Python 3.9.6 executable. No interpreter
was installed. The
[Python clock API](https://docs.python.org/3/library/time.html#time.clock_gettime)
selects the OS clock; the observations below qualify its cross-process use for
this local candidate rather than assuming API availability proves it.

## Observed results

| Stage                          | Observation                                                                                                                                                                                                                                                                | Disposition                                                                                     |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Delayed-child clock check      | One child delayed 1.5 seconds; all three readings fell inside parent send/receive brackets with no added tolerance; clock metadata matched; child reaped; total 1.626363 seconds                                                                                           | Passed                                                                                          |
| Stalled-parent watchdog        | Original deadline fixed before creation; guardian startup delayed two seconds; parent withheld completion and slept through deadline; stop invocation was 0.090780 seconds after the original cutoff and before parent resumed; cleanup confirmed; total 16.005478 seconds | Passed within the reviewed 0.5-second scheduling observation bound and 30-second cleanup budget |
| Replacement baseline           | One worker, one authentic case-26 denied request, fully consumed 403; zero media activity; both original shutdown errors and exit 1; EOF and cleanup confirmed                                                                                                             | Expected failure reproduced; never a lifecycle pass                                             |
| Proposed ordering              | One worker, one denied request, zero media activity; terminal veto and `dispatch_closed`; external signal 15 observed, complete receipt order, exit 15 and cleanup confirmed; worker-pool shutdown error remained                                                          | Failed lifecycle qualification                                                                  |
| Conditional synthetic campaign | No launch, worker, media reads or campaign concurrence                                                                                                                                                                                                                     | Unused; blocked by failed proposed control                                                      |

The watchdog's 0.5-second limit was an observation bound for polling/scheduling
lag, not a deadline renewal or a hard real-time guarantee. No replacement clock,
watchdog or lifecycle attempt occurred. The test covers this local platform and
candidate; it does not prove hosted behavior or independently measure a full
900-second hung-parent interval.

The proposed control's same-clock receipt sequence was:

```text
terminal receipt       3936589.197704
closed-dispatch receipt 3936589.197946
operator stop intent   3936591.285925
guardian stop begin    3936591.384000
signal-line receipt    3936591.440678
pool-error receipt     3936591.440867
EOF receipt            3936591.470222
exit observation       3936591.470478
guardian stop return   3936591.509173
cleanup confirmation   3936591.646702
```

These are host observations, not runtime emission timestamps or proof of
internal causality. The retained raw lines were:

```text
shutdown signal received: 15
failed to send the shutdown signal to user worker pool: SendError { .. }
```

The earlier `main worker has been destroyed` line was absent in this control.
That supports only the observed difference: retaining the listener was
insufficient to eliminate the pool error. It does not establish the underlying
runtime defect, prove graceful worker destruction or justify suppressing the
remaining error. The strict classifier correctly records complete receipt order
but failed lifecycle qualification. Proposed-control elapsed time was 2.884304
seconds; logs were 1,404 bytes.

## Evidence, verification and preservation

Evidence root: `.artifacts/client-prepared-media/clock-qualification/`.

- `clock-result.json`: bracketed samples, interpreter/clock metadata and
  reaping.
- `watchdog-result.json` plus `watchdog-run/`: pre-creation deadline, parent
  stall, guardian journal and confirmed removal.
- `baseline-result.json`: expected reproduction; outcome SHA-256
  `0179329edfea7d1c700898f80e3ddf92aabd967faaafab7634002b55d012ef4d`.
- `proposed-result.json`: failed lifecycle with complete receipt order; outcome
  SHA-256 `9361c4206c627d439b9e80b23250256fb12b5a8aa0ce6825332182451b4e9aec`.
- `result-manifest.json`: exact final reporting/evidence set; review receipts
  are separate to avoid self-referential hashes.

Twenty-eight focused Python checks and two Deno tests passed. No deployable
backend or iOS source changed, so completed unrelated build/contract suites were
not rerun. Changed Markdown formatting and the repository changed-Markdown gate
passed. Final preservation checks retain all 115 unrelated dirty paths, old
candidate source hashes and prior failed evidence. Current status documents are
updated; their previous exact bytes are preserved through
`prior-status-snapshots.json`. Older status snapshots remain at their existing
mapped paths, and older manifests are never rewritten to match new status text.

All three owned containers were removed; no child, attachment or container
cleanup obligation remains. A final read-only local container listing returned
no `merian-cpm` containers. The shared-clock deadline fix is not retroactive
proof of earlier watchdogs. The prior completed media campaign remains workload
passed/lifecycle failed, with its original limits and interpretation.

## Stop boundary and next decision

The clock-check, inert-watchdog and two replacement-control allowances are
consumed. The conditional campaign remains unused. The failed proposed control
requires stopping under the approved scope, regardless of remaining window time.
No runtime sources changed after the first qualification check.

Recommend a separate bounded, read-only source analysis of the pinned runtime's
pool ownership and termination path before proposing another executable change.
Use these exact logs to distinguish normal signal handling from pool-channel
closure; do not waive the error, alter exit expectations, change termination
grace, pull another image or spend the unused campaign on another hypothesis.
Any subsequent fix/control campaign needs a concrete scope, human approval and
exact independent/IC-1 review. This result does not request or infer immediate
execution authority.

No hosted access, upload, secret installation, credential change, deployment,
provisioning, AWS resource, push, merge, device installation or distribution
occurred. Package/storage/CPU/memory/deadline limits and product ownership
remain unchanged. Initial/media/history acceptance and the later deletion/export
and redesign sequence remain open.
