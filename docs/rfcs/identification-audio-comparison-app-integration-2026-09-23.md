# Audio comparison app and observer integration — 23 September 2026

Status: implemented locally; server configuration remains unset. No deployment,
activation or paid comparison was performed in this slice. Gemini remains the
only identification provider. The formal development/held-out qualification
counts remain 0/60 and 0/240.

Live follow-up, 23 September 2026: the
[partial processing benchmark](./identification-audio-processing-comparison-2026-09-23.md)
records seven admitted slots after authorized deployment and activation. The run
stopped before slot 8 because the installed app changed; hosted setting removal
and absence were verified. Five slots remain unsubmitted. The original
implementation and verification status below remains historical.

Follow-up, 23 September 2026: live staging exposed Core Audio WAV padding added
by the ordinary replay transcoder. The source's PCM was unchanged, but its full
file hash failed the frozen assignment before admission. The comparison preparer
now preserves an exact validated canonical WAV copy; the
[current measurement contract](../development-guides/21-identification-app-measurement.md#fixed-context-for-foreground-audio-comparisons)
owns that behavior. The original verification below remains historical and did
not cover this full-file preparation boundary.

This follows the
[server assignment slice](./identification-audio-comparison-assignment-2026-09-23.md)
and preserves its frozen twelve assignments, owner/bundle/window restriction,
quota semantics and single fresh primary invocation per slot. The existing
source packet and historical app observations remain immutable.

## Native assignment and receipt

**Debug replay → Stage comparison slot** presents the twelve numbered slots. The
ordinary private `Documents/IdentificationReplay/audio.wav` inbox still supplies
the input; staging alone never submits. The menu requires the existing empty,
active capture workspace. It adds no launch argument or persisted model setting.
The generated Swift table shares the reviewed server plan and derives each
reserved UUID through the backend's existing function.

The preparer checks the prepared WAV's byte length and SHA-256 off the main
actor, then rechecks preparation/account/session ownership before staging. A
mismatching clip is discarded with a bounded error. The normal Identify action
retains consent, admission and durable queue ownership. The selected slot
participates in the admission snapshot and supplies its fixed scan UUID before
enqueue. The queue rejects existing queued/saved IDs or absent foreground
ownership before funding and file side effects. Request serialization verifies
the actual inline bytes again before adding only `{planSha256, slot}`. The
server independently enforces all source/processed/request/settings bindings.

The authenticated transport rechecks the exact live attempt on the same
main-actor turn that adopts the response receipt. Only the initial fresh HTTP
success can qualify. Every `X-Merian-Audio-Comparison` field must match the
generated table. No arbitrary header fields enter the retained record. A second
HTTP response invalidates the ephemeral receipt, and recovery cannot restore it.

## Native outcome and observer admission

The unchanged measurement-v2 JSON is joined by its exact UTF-8 SHA-256 to three
separate compact `identification_audio_comparison_v1` events:

| Event       | Emission boundary                                                                                                                                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `receipt`   | Validated authenticated initial response, exact current foreground attempt and frozen assignment                                                        |
| `finalized` | Result parsing/persistence accepted, result publication accepted, exact durable queue finalization completed and current-owner follow-up permit granted |
| `rendered`  | Existing UIKit `draw` probe reports that exact scan in a window; proof is consumed once                                                                 |

The result service's actual persistence outcome crosses the pipeline as a typed
value: `saved` or `completed_without_record`. The latter is a legitimate
terminal no-match outcome under the existing native policy; it is not claimed as
a saved Library record. Finalization retains only that value, the 0–1 confidence
and the biological flag. No species name, provider prose, media, coordinates,
auth state, owner ID or scan ID appears in these logs.

The presentation owner holds the render proof only after fenced publication.
Replacement, cancellation, queue handoff and Auth transitions clear it.
Rendering can happen while queue finalization is suspended; admission therefore
accepts either order but requires both events. Incomplete persistence, stale
ownership, failed publication, failed queue finalization or missing first draw
cannot produce a complete admitted observation. Every proof record remains below
the 1 KiB native log limit.

The passive observer now creates `identification_app_observation_v2` envelopes.
It hashes only successfully projected measurement JSON, using its original
logged spelling rather than re-encoding floating-point timings. Raw OS rows and
unrecognized content are never retained. Rejected proof rows and oversized rows
are counted. Old observation-v1 and measurement-v1 files remain readable by
their existing consumers but cannot be upgraded into comparison evidence.

Offline admission requires one initial HTTP success, one fixed-context Pro
measurement with the reviewed complete app/backend identity, all three proofs
for the expected plan/slot/hash, one first-render timing, and a normally closed
bounded observation window. Missing, duplicate or malformed proof, retries,
replays, missing identities, interrupted collectors, oversized rows, early exits
and legacy envelopes fail closed. Other unprojected timing rows are counted; the
observer is not an exhaustive call or billing ledger.

## Offline command

After a separately approved live run, use its new private observer file and an
expectation file containing `slot`, `backendBundleSha256` and `app`. The latter
contains the exact `version`, `build`, `sourceRevision`, `sourceFingerprint` and
`sourceState` from the reviewed built app. These fields are required; no missing
identity is guessed. Keep those files in the private evaluation packet, with no
owner configuration, credentials or raw response bodies.

From the repository root, replace the uppercase paths with private absolute
paths. This command performs no network, environment or provider operation:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=OBSERVATION,EXPECTED --allow-write=OUTPUT \
  services/supabase/scripts/admit_audio_comparison_observation.ts \
  --observation OBSERVATION --expected EXPECTED --output OUTPUT
```

OUTPUT must be new. The command creates it mode 0600, binds the input file's
SHA-256, and retains the frozen assignment, sanitized measurement, native
outcome, first-render duration and existing primary-attempt cost estimate. It
never modifies the source observation or manually supplies missing proof. The
native receipt is an authenticated response claim; this local hash join is not a
standalone signature or independent reference review. Admission does not score
species agreement, estimate total billed work or establish accuracy improvement.

## Verification and activation

Synthetic tests cover mismatched source/identity, exact receipt fields, initial
versus replay/stale responses, one-shot proof, ownership transitions, duplicate
queue/saved IDs, persistence/publication/queue failures, cancellation and
no-match completion. Observer tests cover exact JSON hashing, both
completion/render orders, every missing/duplicate boundary, malformed and
interrupted windows, privacy projection and private exclusive file creation. The
CLI filesystem test runs in the existing disposable evaluator directory with
network/environment access denied; pure tests retain their narrower permissions.

The final complete `merianTests` run passed **4,311 tests**, with zero failures
or skips: 1,358 XCTest tests and 2,953 Swift Testing tests. This includes the
main-actor receipt-adoption regression and the seven pipeline outcome scenarios.
The result bundle is retained locally at
`.artifacts/local-ios/9884f63d3f3c4700993e4c74d3005fc8.xcresult`. Focused native
runs also passed before the complete run.

The complete Supabase tooling gate passed **380 standard tests and 29
substeps**, **10 isolated evaluator tests and four substeps**, **39 DTO tests**
and all seven shell test files. Its recursive TypeScript checks covered the new
generator, observer and admission modules. Both generated plan outputs and the
unchanged backend deployment identity passed their freshness checks. Script
lint, whole-tree function/script formatting, generated iOS project/resource
gates, changed Markdown formatting and `git diff --check` passed.

The unsigned Release device build passed. Its executable contains none of the
six checked comparison markers: the menu ID/title, proof event version, receipt
header, frozen plan digest and reserved scan-ID prefix. The result bundle is
`.artifacts/local-ios/706f25cfefc445479c1572dbc68a9dd4.xcresult`; the adjacent
`706f25cfefc445479c1572dbc68a9dd4-comparison-marker-check.json` records the
binary hash and zero counts. The build emitted the existing three
unreachable-branch warnings in
`CaptureWorkspaceViewModel+NonVisualSubmission.swift` from Release simulation
guards, with no errors.

No new UI automation, physical-device identification or hosted execution was
performed. Native behavior tests use injected providers and synthetic media;
they do not establish hosted behavior, species accuracy or paid-run outcomes.

Keep `IDENTIFICATION_AUDIO_COMPARISON_V1` unset. A reviewed deployment, explicit
target/owner/window activation and the bounded paid run remain separate release
operations. The deployment runbook retains the exact-SHA and rollback controls.
