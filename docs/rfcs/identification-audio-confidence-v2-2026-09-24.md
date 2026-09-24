# Audio confidence V2 implementation

Date: 24 September 2026\
Status: implemented and independently reviewed; local verification recorded
below; not deployed.

This follows the
[rain-control diagnostic](./identification-audio-rain-diagnostic-2026-09-24.md).
The prior experiment exposed a mismatch between animal-presence confidence and a
species-match badge. This change defines what the existing score means; it does
not establish that Gemini now identifies the rain recording correctly.

## Behavior

Both audio-only routes share a single executable confidence description. Named
animals score acoustic evidence for the returned taxon. Clear animal presence
with unsupported taxonomy returns unresolved wildlife and uses presence
confidence with no species-match badge. Human scores its returned identity and
retains the current badge. Non-biological sound scores the source classification
with no species badge. Location, season and abundance cannot inflate a taxon
score. Scores are model estimates, not calibrated probabilities.

Primary audio uses `identify_audio_v2`, `merian_audio_v2`, `gemini_audio_v2`;
compatibility audio uses `identify_audio_compat_v2`, `merian_audio_v2`,
`gemini_audio_compat_v2`. Gemini models, generation settings, tier bands and
candidate cutoffs (`0.99` primary, `0.95` compatibility) are preserved. Blended,
visual and text contracts remain separate. The public DTO shape and
historical/replayed scores are unchanged. Fresh evaluator assignments record V2
prompt/schema digests. The consumed processing-comparison plan and historical
benchmark assignments retain their original V1 bindings.

## Field Trip integration

Source review found that the old scalar confidence gate did not exclude Human
selected taxonomy or Human overrides. No invalid production credit was observed.
The forward migration adds a private row-aware guard to standard/Event progress:
resolved effective taxonomy, non-Human identity/override, not explicitly
non-biological, not tombstoned, and the existing confidence/confirmation policy.
Legacy nullable biological flags keep their prior meaning. Confirmation bypasses
only the score requirement.

Override-only edits now enter the progress trigger and invalidate its atomic
receipt. The migration reuses existing removal helpers for affected historical
credit/receipts, reopening progress and withdrawing derived Event badges and
completion publications while retaining selected-goal preferences. It preserves
valid cached receipts. The ten-second lock and five-minute statement limits
remain fail-closed. This candidate contains the migration; it has not been
applied to production.

## Verification

Validation uses the isolated `codex/audio-confidence-semantics` checkout. The
original working checkout and its unrelated map edits are untouched.

| Gate                                                    | Result                                                                                                                       |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Native build and complete unit suite                    | 4,316 passed; zero failed or skipped on a separate simulator                                                                 |
| Complete Edge suite with configured disposable Postgres | 2,078 tests and 219 steps passed                                                                                             |
| Database migration history and catalog suite            | Full history replay; all 53 catalogs / 389 assertions passed                                                                 |
| Backend tooling                                         | 396 standard tests, 10 evaluator lifecycle tests, isolated DTO suites and all 8 shell suites passed                          |
| Deployment entrypoints                                  | All 101 recursively type-checked with their own frozen configs; dependency graph checks passed                               |
| Static contracts                                        | Deno formatting/lint, migration contract, Markdown and generated DTO validation passed                                       |
| Database lint/advisors                                  | Lint clean; advisor error gates passed, retaining 105 security and 80 performance warnings under the existing warning policy |
| Independent review                                      | All findings corrected; no remaining material cross-surface issue                                                            |

Final database validation followed CI order: catalogs on fresh replayed state,
then the complete Edge suite, lint and the privileged-routine audit. Running
catalogs after the integration suite initially exposed fixture-state conflicts;
rebuilding the disposable database and following CI order passed all gates. The
privileged-routine audit reports zero violations. Independent review also closed
the missing-receipt preference edge case before the final replay.

The Identify DTO block was regenerated with no diff. The identification runtime
fingerprint was regenerated from its final source graph. Historical benchmark
artifacts and the consumed comparison plan have no diff.

Focused coverage includes both audio-only prompt/schema bindings, shared
confidence semantics, both candidate cutoffs, four-state native badge behavior,
exact score persistence/replay, and invalid Field Trip credit. Database
regressions also exercise Human override withdrawal, missing-receipt preference
preservation, subsequent valid recredit and bounded forward repair. The
generated native result bundle is retained outside `.build` at
`.artifacts/local-ios/97b5a19ef50947a8a01529afdf261afa.xcresult`.

No paid identification request, hosted mutation, backend deployment,
physical-device capture test or new acoustic accuracy measurement was performed
in this slice. All provider/storage fixtures are synthetic.

## Acceptance and next experiment

Prompt and fixture tests establish contract behavior, not recognition quality or
calibration. Freeze a fresh bounded V2 plan before another live comparison, with
exact assets, context profile, admitted model/settings, attempt order/count and
stop conditions. Use the existing ordinary-app billing path and retain every
outcome. Do not reactivate or regenerate the consumed twelve-slot processing
plan. Earlier ordinary-context observations remain descriptive history, not a
controlled V2 baseline. Formal corpus progress remains **0/60 development and
0/240 held-out groups**. Deployment remains a separate, explicitly named
operation and target. Run the comparison only after the reviewed backend
candidate is deployed and its identity is verified.
