# CPM shutdown diagnostics: clock prerequisite failure

October 15, 2026. **Stopped after baseline; no second control or campaign.**
Activation remains disabled, AWS and 160 MiB unapproved, all limits unchanged.
Auto-prompts remain paused. No product acceptance gate closes.

## Approved scope and exact execution

The user approved the
[two-hour local shutdown scope](client-prepared-media-shutdown-diagnostics-proposal-2026-10-14.md),
proposal SHA-256
`d98b5bee852eb3db8989abfc0849603e174d6fe3a9f7aa1fcada6557fdf7386c`, at local
HEAD `ddc0d98fb05b7eee5562508124f2cbb0ce6ffd57`. The fresh window was
14:33:09–16:33:09 UTC. Construction was limited to copied ignored experiment
harnesses, their operator/journals and focused tests.

Exact control candidate set
`241d99412996fdd20526979a00c6d8f5a2252e4b5c7b085496bff80e97c22e81` binds 36
files in
`.artifacts/client-prepared-media/shutdown-diagnostics/candidate-manifest.json`.
Independent reviewer `/root/diagnostics_review_fallback` and IC-1 turn
`01a14002-fe61-7a63-9538-833b28ce600a` concurred before execution;
`control-concurrence.json` records the receipt. No campaign concurrence was
requested or granted. The existing pinned v1.77.0 image and exact ESZIP were
reused; zero new bundles or downloads.

The first control executed once:

```sh
python3 -B .artifacts/client-prepared-media/shutdown-diagnostics/run.py --execute-approved-once baseline
```

It created one worker and forwarded only the authentic handler's case-26 denied
request. The 403 response was fully consumed before terminal handling. Media
reads, bytes, closes and cancels were all zero; no post-terminal forwarding or
AI invocation occurred. The baseline reproduced:

```text
main worker has been destroyed
failed to send the shutdown signal to user worker pool: SendError { .. }
```

Exit was 1; EOF was complete, with no partial line. Recorded operator elapsed
was 0.8272625 seconds. Guardian removal and attachment cleanup were confirmed;
no cleanup obligation remains. This is a successful failure reproduction, not a
qualified lifecycle. Outcome SHA-256:
`06170d37b5ba11d524f55f010eabc6b3dd3261fff5d3bf8d34336b3801f551b0`.

## Clock defect and evidence limits

The operator journal records error receipt before stop intent within its own
process: error timestamps 0.66111075/0.661193916, stop intent 0.682128666. The
guardian records stop invocation at 0.51181425 after observing the operator's
finished marker. These numeric values cannot establish cross-process chronology.
Do not subtract them to estimate a signal delay or infer runtime causality.

The selected interpreter is Xcode's Python 3.9.6 at
`/Applications/Xcode.app/Contents/Developer/usr/bin/python3`. Its
`time.monotonic()` reports `mach_absolute_time()` but uses a process-relative
origin on this macOS version. The
[Python documentation](https://docs.python.org/3/library/time.html#time.monotonic)
identifies Python 3.10 as the change making this clock common across macOS
processes. A fresh process's approximately 0.0246-second value and the
conflicting journals corroborate the platform mismatch. `clock-finding.json`
records the interpreter and available clock APIs without treating availability
as proof.

The defect also affects the inherited guardian: the operator's absolute
`time.monotonic()` deadline is passed to a process with a different origin.
Consequently the specified pre-creation absolute cutoff is unqualified. Cleanup
in this run completed promptly through `driver_finished`; no actual overrun was
observed. Its success does not prove the independent hung-parent deadline.
Historical normal cleanup, counts and raw failures remain valid observations;
any previous absolute-watchdog applicability claim using this interpreter needs
requalification. This finding does **not** establish the cause of Edge Runtime's
worker-pool error.

Eighteen focused Python tests and two Deno tests passed; cached offline type
checks of all three entries and lint of 13 files also passed. Earlier failed
preparation checks are retained. Synthetic clocks and mocks did not test this
actual platform prerequisite. The primary and pre-control reviews missed it;
passing those checks does not override the observed failure.

## Stop decision and preservation

Independent review and IC-1 turn `01a14006-471b-7a12-bf0d-ebaa743788e1`
concurred with stopping before the second control. The approved method freezes
the operator/guardian and does not permit changing the clock basis and treating
the completed control as applicable. Unused time and allowances do not authorize
a replacement method or automatic retry.

One control is consumed. The second control and conditional campaign remain
unused. Runtime sources are unchanged after baseline. No credentials, hosted
resources, uploads, secrets, deployment, provisioning, device operations or
external publication were accessed or changed. The primary remains sole writer;
reviewers remain read-only. All 115 unrelated dirty paths are preserved.

Evidence lives under `.artifacts/client-prepared-media/shutdown-diagnostics/`.
The original 36-file candidate and historical 82-file request-boundary candidate
remain unchanged. Before updating six current-status documents, their exact
previous bytes were archived under `prior-status-snapshots/`, with mapping and
hashes in `prior-status-snapshots.json`. The prior 23-file result manifest stays
unchanged: its historical status bytes are available through that mapping, while
the other bound files remain at their original paths. Current status updates
must not be misreported as matching the old status hashes. The new
`result-manifest.json` binds this report, current statuses, snapshots, baseline
outcomes and preservation evidence; review receipts remain separate to avoid
self-referential hashes.

## Recommended next amendment — not yet authorized

Recommend one fresh two-hour local window, with no hosted actions, downloads,
interpreter installation, changed product limits or new bundle. First qualify a
single shared OS monotonic timebase used by both operator and guardian, then
repeat only the controls whose applicability was invalidated. Keep the original
15-second control deadline plus 30-second cleanup, and 900-second campaign plus
120-second cleanup, anchored before creation and never renewed. Keep the
original resource, byte, journal, storage and growth limits.

`time.clock_gettime(time.CLOCK_MONOTONIC)` is available in the existing
interpreter and is a candidate to evaluate; it is not yet adopted or qualified.
Alternatively use an already installed interpreter with documented shared-clock
semantics if one is found and reviewed. None beyond Python 3.9.6 was found on
PATH. Do not substitute wall time or silently install a new interpreter.

The amendment should explicitly allow, in order:

1. A bounded cross-process clock check (one parent/child pair, delayed child
   startup, at most five scalar samples, ten seconds total). Confirm the same
   clock implementation and comparable readings against parent send/receive
   brackets. A failure stops; no alternative-clock retry.
2. One short watchdog control proving the pre-creation absolute deadline with a
   delayed guardian start and a stalled parent, using only an owned inert
   network-disabled container. At most 15 seconds execution and 30 seconds
   cleanup; no verifier or media. Prove deadline nonrenewal and confirmed
   removal, with explicit clock/measurement tolerance reviewed before execution.
3. Two replacement case-26 lifecycle controls, baseline then proposed ordering,
   under the unchanged limits. Preserve this failed baseline; do not relabel or
   erase it. Any failure stops without a replacement attempt.
4. Only after those checks and renewed exact independent/IC-1 concurrence, one
   unchanged synthetic campaign if at least 17 minutes remain. No third
   lifecycle control, campaign retry or window extension.

Exact source, clock semantics, tolerances, ownership and manifests require
independent and IC-1 concurrence before controls; the final campaign requires
separate exact concurrence. Retain same-process order and explicit durable
handoff causality even with a shared clock; stop invocation, runtime signal
receipt and process exit remain distinct observations. A shared timestamp never
proves signal delivery or runtime-internal causality.

This recommendation changes the diagnostic method and adds explicit control
allowances. It requires human approval before construction or execution. No
clock fix, prerequisite test, second control or campaign has been performed as
part of this finding. The shutdown hypothesis, CPM product acceptance, native
journey and later deletion/export/redesign sequencing remain unresolved.
