# CPM allocation diagnostics: local prelaunch finding

October 14, 2026. **Launch blocked; no bundle or verifier campaign executed.**
The user approved the
[two-hour local scope](client-prepared-media-allocation-diagnostics-proposal-2026-10-14.md).
Work began at 19:01:48 UTC, with a 21:01:48 UTC outer deadline. Preparation
found an unproven cross-worker cancellation requirement. Independent and IC-1
review agree that launch must stop before spending the campaign allowance.
Activation remains disabled, AWS/160 MiB unapproved and all limits unchanged.

## Completed bounded work

The original verifier, signing/auth, telemetry, policy, dependencies and prior
failed campaign evidence are unchanged. A new evidence root contains copied
baseline source, a source allocation/lifetime map, a bounded external log
collector, tests and two inert lifecycle controls. Diagnostic entry construction
and campaign packaging are incomplete; this is not an executable candidate
concurrence or a qualified shutdown fix for the full verifier package.

The inert main-service control removes unsupported `Deno.exit`, awaits server
shutdown, emits a lifecycle acknowledgement and leaves process termination to
the external operator/guardian. The operator now continues bounded log
collection through terminal/drain/cleanup, distinguishes errors from a narrowly
evidenced operator SIGTERM, and keeps the original immutable-ID guardian
ownership.

| Evidence                         | Result                                                                                                                                                                                    |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Five Python parser/control tests | Passed; terminal/ack/EOF, late errors, log bounds and exact signal conditions                                                                                                             |
| One strict offline replay test   | Passed; rejects altered/prefixed/suffixed log, missing ack/EOF, unexpected exit or cleanup and other errors                                                                               |
| First inert runtime control      | Initial parser assertion failed; server-shutdown acknowledgement, external SIGTERM/exit 15, EOF and positive removal all observed in 2.926 seconds                                        |
| Derived replay of first control  | Passed only as `expected_operator_termination`; original failed assertion/outcome unchanged; not a repeated runtime test or graceful process exit                                         |
| Second inert runtime control     | Passed; injected post-terminal error retained as failure, driver deliberately stuck, independent five-second control watchdog removed owned container; 6.053 seconds including collection |
| Bundles / verifier campaigns     | Zero / zero                                                                                                                                                                               |

Both inert-control allowances are consumed. Neither control executed the
verifier, generated fixture media or accessed a hosted service. No credentials,
new image, dependencies, device or product state were accessed or changed.

The exact nominal replay requires the ordered terminal-success record,
server-shutdown acknowledgement and single exact SIGTERM line; EOF without a
partial line; process exit 15; successful stop/remove commands and positive
absence for the recorded immutable ID, triggered by `driver_finished`. This is a
derived disposition, not timestamped proof of signal/marker ordering and not a
claim of graceful in-runtime process exit. Unknown stderr and all other failure
evidence remain failures. Independent/IC-1 accepted this narrow replay approach;
the original parser failure remains retained.

The second control proves watchdog wiring and independence with a test-only
five-second deadline. It does not prove a 900-second elapsed-time campaign. No
further control is authorized by the existing two-control allowance.

## Feasibility blocker

The main service owns request scheduling and terminal outcomes. The retained
user-worker handle exposes `fetch`, not a proven method for cancelling
worker-local diagnostic timers after the HTTP response completes. Worker-local
halt/fault/next-request cancellation handles different paths.

A parent-only failure after a successful acknowledgement can occur during
response parsing, validation or scheduling. The proposed +1-second observer may
then execute during the parent's two-second post-terminal drain. Aborting an
already consumed fetch has no established post-response propagation guarantee;
the core handler also removes its request abort listener in `finally`.
Eventually removing the container does not prove cancellation before the
observer executes. A snapshot in the main service would measure the wrong
worker. No extra request/control endpoint or newly assumed runtime API may be
introduced under this scope.

Independent review and IC-1 (turn `01a13bd0-b40a-7631-8f41-9e1e906fb27c`)
require stopping here. No exact campaign candidate exists for concurrence. The
two lifecycle controls do not establish the missing parent-to-worker
cancellation guarantee. The prior 42-second growth stop and its interpretation
remain unchanged.

## Recommended narrow amendment, not adopted

Remove additional idle observations and their background timers entirely.
Instead, record only the first and last co-timed snapshots returned by the
**existing original gate memory calls**, with bounded scalar counters and
unchanged return values/order. Compare the prior request's last snapshot to the
next request's first snapshot across the unchanged scheduled gaps. Keep the
original 21-request maximum, control cohort, growth calculation, deadlines,
memory/CPU/log/storage bounds, independent cleanup and no-retry rule.

Pair snapshots only for a prior successful read and a subsequent request with
both original-call snapshots present and the same acknowledged worker alias. A
missing next request, snapshot or matching identity yields a missing pair; never
substitute data, retry or create another worker. Forty seconds describes
dispatch spacing, not the exact last-snapshot-to-first-snapshot interval. Record
monotonic timestamps within those existing calls, not through added timers.

This trades pure +1/+30-second idle observations for **request-boundary
observations**. The next request has already allocated some transport/auth/
handler state, and the last gate call is not necessarily Ack.quiescent. Record
sample ordinal and phase honestly; do not relabel either as the original
quiescent value, GC-complete idle memory or direct leak attribution. The
existing 40-second gap remains unchanged, but this is not a new 40-second idle
sampling API. There are no new memory calls, observer timers or cancellation
channel to prove. Instrumentation still adds bounded allocations, so exact
numeric equivalence with the earlier uninstrumented run is not claimed.

This recommendation needs **explicit user approval of the method change**; it is
not implemented or authorized by the current scope. Reuse retained lifecycle
evidence only where the exact new candidate review finds it applicable; no new
inert-control allowance is implied. Any required additional runtime proof must
return as a specifically bounded request, not an improvised third control. Exact
independent/IC-1 executable concurrence remains mandatory before any campaign.
The unused campaign allowance is not a waiver of this blocker or a window
extension.

A proven cross-worker cancellation design would be a broader alternative,
requiring a separately bounded transport and runtime proof. Prefer the smaller
request-boundary method if these limited diagnostic observations are useful. No
product/media/recovery/shared-asset/native/integrated acceptance gate closes.

## Evidence and review

Evidence root: `.artifacts/client-prepared-media/allocation-diagnostics/`.
`preflight-manifest.json` set:
`0ed0f853347cc871f7cb24df8d51ab53611d14a51b50e69254ffaaecd053dc34`. This binds
construction and controls, not a runtime campaign candidate.
`controls/nominal/{outcome,assertions,replay}.json` preserve the initial failure
and derived disposition; `controls/hung/` preserves the second control.
`operator-before-signal-classification.py.txt` preserves the initial collector.
Prior campaign/result manifests and all 115 unrelated dirty paths remain
unchanged. Auto-prompts stay paused. Push, merge, hosted actions and activation
remain unauthorized. Final report/amendment review receipts are recorded
separately; proposal concurrence does not itself approve the method amendment.
