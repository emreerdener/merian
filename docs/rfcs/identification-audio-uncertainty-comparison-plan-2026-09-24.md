# Controlled audio species-confidence comparison

Date: 24 September 2026\
Status: Slices 1–2 complete; Slice 3 controls and offline execution preparation
implemented. Reviewed release, actual execution freeze, paid observations and
report remain pending.

Compare the current Gemini audio prompt with one stricter species-evidence
instruction. Use **six existing clips, two arms and three planned repeats: 36
app submissions**, split into three blocks of twelve. Keep Gemini Pro, audio
processing, context, schema, confidence meanings and displayed bands the same.
The question is whether the candidate reduces Strong source-label mismatches
without making useful animal answers disappear.

The
[machine-readable design](./identification-experiment-plans/2026-09-24-audio-uncertainty/design.json)
records exact source WAV hashes, the proposed instruction, full order and
decision rules. Its original `design_only` and `implemented: false` fields
remain frozen planning facts; the dated implementation checkpoint below records
later progress. It is **not an executable RunSpec, admitted corpus or activation
configuration**. No app request, model call or deployment has occurred for this
plan. The dated checkpoints below distinguish local implementation from live
activation. Missing future source/app/request bindings are explicit nulls, to be
generated before a live execution freeze.

## Why this comparison

The [current V2 contract](./identification-audio-confidence-v2-2026-09-24.md)
already separates species confidence from animal-presence confidence and permits
**Unidentified Wildlife**. Nevertheless, the
[visible-caller benchmark](./identification-audio-visible-caller-app-benchmark-2026-09-24.md)
returned Peregrine Falcon with Strong match for the provisional pika reference.
The earlier
[six-clip pass](./identification-audio-confidence-v2-app-benchmark-2026-09-24.md)
also retained strong source-label mismatches. These observations motivate a
test; they do not prove that a stronger instruction fixes recognition or
calibrates confidence.

This is a small development screen on previously observed cases. Passing it only
justifies a fresh, separately reviewed sample. It cannot qualify a provider
switch or general production promotion. Both references and prior predictions
remain separate from model input and unchanged in their historical packets.

## Arms and the single intentional difference

| Arm | Prompt                                              | Change                                                                  |
| --- | --------------------------------------------------- | ----------------------------------------------------------------------- |
| A   | `identify_audio_v2`                                 | Current resolved system instruction, unchanged                          |
| B   | Proposed `identify_audio_uncertainty_experiment_v1` | Insert the following block immediately before `# Response Detail Rules` |

```text
# Species evidence check
Before choosing identified_non_human, require audible features that distinguish the proposed species from other plausible animals. Familiarity with a call, a best guess, clarity, repetition, or geographic plausibility alone is insufficient.
When non-human animal presence is confident but the recording does not distinguish among plausible species, choose unidentified_non_human even if one species seems most likely. Use the existing Unidentified Wildlife fields, omit scientific_name, and return no candidates. Do not turn clear animal presence into a non-biological result to avoid naming a species.
When the recording does distinguish a species, retain identified_non_human and score that identity using the existing Audio Confidence definition. Preserve the existing Human and non-biological precedence and response rules. Return only the existing JSON structure; do not add fields.
```

The candidate block SHA-256 is
`ad95cee2b2732cc80036fd30bf2ac44dd5e8ca397eb830024872be83365b5f83`. It contains
no case names or expected taxa. Keep the existing role, subject priority,
response rules and confidence description. This is a stronger requirement to
distinguish species, not a new score target, score cap, threshold change, model
or additional call. The existing below-0.70 guidance for ambiguous named results
remains present.

Freeze the fully assembled instructions and native requests after
implementation. For every A/B pair, the prepared native request with only
`systemInstruction` removed must be identical. Source and processed WAV hashes
must also match across arms and repeats. Both arms use `merian_audio_v2`,
`gemini_audio_v2`, `gemini-2.5-pro`, temperature 0.1, seed 42, 8,192
output-token setting, 5,000 thinking-token budget and 90-second timeout. Leave
all other current settings unchanged. Full policy digests may differ because
they include prompt identity.

Both arms use the same current sinc/partial-tail processing and
`audio-minimal-v1`: synthetic locale `en`, timezone `UTC`, month 1, time
`12:00 PM`; no location, weather, description, images or reference video. This
is fixed context, not context-free inference. Current Pro Strong is >=0.85 and
Possible >=0.65. The 0.99 primary candidate cutoff controls alternatives; it is
not the Strong badge boundary. No threshold changes belong in this test.

## Cases and treatment of references

| Case    | Source clip                | Role                   | Reference status          |
| ------- | -------------------------- | ---------------------- | ------------------------- |
| `c0025` | American Pika              | challenge              | Provisional species       |
| `c0020` | Canada Goose               | positive retention     | Provisional species       |
| `c0023` | Rain                       | non biological control | Owner-reviewed non-animal |
| `c0026` | Domestic Chicken / Rooster | positive retention     | Provisional species       |
| `c0021` | Coyote                     | positive retention     | Provisional species       |
| `c0024` | Chainsaw                   | non biological control | Owner-reviewed non-animal |

Pika is the challenge case. Goose, coyote and rooster check whether the
candidate retains useful named answers. Rain and chainsaw check non-animal
handling. The rooster mapping accepts domestic chicken at _Gallus gallus_
species rank; retain the exact returned name and do not infer domestic/wild or
breed correctness.

Robin `c0019` and pig frog `c0022` stay in their diagnostic reports because
their audible references remain unresolved. They are excluded prospectively from
this new six-case screen, not deleted from past results. The four selected
animal references also remain provisional. No new acoustic reviewer or
species-truth claim is created by selecting them. A mismatch is descriptive
source agreement, not independently measured error.

Reuse the exact reviewed WAVs, source/eligibility records and group IDs from the
two retained packets; create a separate admitted execution packet. Verify all
hashes, permissions, retention and duplicate grouping again. Unchanged
recordings do not require the owner to repeat the same listening confirmation.
Any changed crop, processing input or new media needs its own review before
admission. Source retention currently ends 24 October 2026.

## Fixed schedule and execution

Each table entry is one case pair; `AB` means A followed by B. Each numbered
case is `c` plus the four digits. Repeats are planned new slots, not retries.
The JSON lists all 36 slots individually. Case order rotates and first-arm order
reverses between blocks; each block has three AB and three BA pairs. This is
deterministic counterbalancing, not a claim of random sampling.

| Block / repeat | Case pairs, in order                                      | Submissions |
| -------------- | --------------------------------------------------------- | ----------: |
| 1              | 0025 AB → 0020 BA → 0023 AB → 0026 BA → 0021 AB → 0024 BA |          12 |
| 2              | 0023 BA → 0026 AB → 0021 BA → 0024 AB → 0025 BA → 0020 AB |          12 |
| 3              | 0021 AB → 0024 BA → 0025 AB → 0020 BA → 0023 AB → 0026 BA |          12 |

Run one slot at a time through the authenticated simulator app using its normal
production billing and Gemini entitlement. Restart the same signed app between
slots, preserve account/consent, stage only the assigned audio, wait for passive
observer readiness and tap Identify once. Wait for the complete 120-second
window plus at most 30-second shutdown grace before the next slot. No parallel
requests, retries, spare slots or replacements. Retain all completed results,
including mismatches, low confidence and unresolved outcomes.

Use a new unique assignment and scan identity for every slot. Authenticate the
same privately reviewed owner and require Pro admission without fallback. Each
block gets a bounded activation window of at most two hours; the planned three
blocks make restart and expiry manageable without increasing that limit. Both
arms and all repeats must use the same reviewed app and backend implementation.
Historical build 275 and bundle `61b69c…` are evidence of prior runs, not a
substitute for the new implementation identities.

Stop after an uncertain submission, error/refusal/invalid response, unexpected
model or identity, missing/wrong arm proof, extra response, replay, retry,
background/queue recovery, account change or incomplete window. Retain the
failed/unknown slot and mark the rest unattempted. Do not stop early because a
valid result is unfavorable or a screening threshold has already been met.
Incomplete runs support diagnosis only; resuming or replacing uncertain slots
must never silently expand this schedule.

## What to measure and how to decide

Retain normalized subject state, the conditional native confidence score and
displayed band separately. High unresolved-presence confidence is not a species
match. A low score on a named species is not taxonomic abstention. Failed,
refused, invalid and unknown executions are not successful abstentions.

For all 36 slots, record the first visible name and band; arm/source/request
bindings; fresh HTTP/model/app/backend evidence; receipt, finalization and first
draw proof; provider, Edge and first-render time; and primary usage-cost
estimate. Reuse the compact proof pattern, with a bounded normalized-subject
enum for the new lane. Keep species-label observations separate from
content-free logs; names are not cryptographically attested. Never retain raw
responses or provider prose.

Report each case as three outcomes per arm, plus raw totals. There are six
source groups, not 36 independent examples. Do not compute confidence
calibration or a population accuracy percentage from these provisional labels.
Report named agreement, all named mismatches, Strong mismatches, unresolved
wildlife, Human, non-biological output and operational failures separately.

These practical screening rules are chosen before results, not statistical
significance tests. B advances to **fresh development examples only** when all
of the following hold:

1. All 36 first-attempt observations have complete, matching evidence. Unknown
   timing, score or cost is inconclusive, never zero.
2. All six B control trials return non-biological. Neither Human nor unresolved
   wildlife counts as a correct non-animal result. Show A control violations
   too. All twelve B animal trials must retain non-human animal presence, either
   named or unresolved; relabelling them Human or non-biological cannot satisfy
   the uncertainty objective.
3. B has at least two fewer Strong source-label mismatches across the twelve
   animal trials. Neither Strong mismatches nor all named mismatches may
   increase for any animal case. If A has fewer than two Strong mismatches, the
   test is inconclusive for the planned minimum signal. Merely changing a wrong
   name's displayed band cannot hide the all-named mismatch count.
4. On each of goose, coyote and rooster, B retains at least two named reference
   agreements out of three and no fewer than A. An always-unresolved candidate
   fails this useful-answer check. Pika abstention is recorded separately from
   species agreement.
5. B's median tap-to-first-frame and total estimated primary cost are each at
   most 1.20 times A's over their equal 18 slots. Also show per-case/provider
   timings and raw token counts. Cache/enrichment and model variability can
   affect timing; the screen is not a latency causality study.

Failure means retain A and investigate the failing dimension. An incomplete run
or insufficient baseline mismatch signal means inconclusive, not a candidate
win. If B meets every rule, test fresh reviewed examples before any broader
decision. The old single observations motivate this design but are never counted
as fresh A trials. Frozen seed/settings are experimental controls, not
additional independent species observations.

## Implementation in three slices

| Slice                           | Deliverable and completion gate                                                                                                                                                                                                                                                            |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Offline preparation          | Add the versioned prompt candidate and a separate typed prompt-comparison manifest builder; assemble both requests, prove only the instruction differs, generate the 36 new assignments and validate the schedule without network or credentials. Ordinary production remains V2.          |
| 2. Scoped app integration       | Add a default-off server-owned prompt lane and Debug simulator assignment/proof support. Only authenticated reviewed-owner slots can choose B; quota, consent and normal durable recovery remain authoritative. Complete backend/native contract and release validation before activation. |
| 3. Bounded execution and report | Freeze actual source, app, bundle, private owner/window, assets, requests, pricing and decision bindings; run the three blocks through the existing app account, close each window, deactivate the run configuration and report every scheduled slot against the rules above.              |

Prefer a new versioned **prompt-comparison lane**, separate from the consumed
twelve-slot DSP experiment. Reuse proven validators and
receipt/finalization/draw mechanics where their contracts fit, but keep the old
plan, slot IDs, processing arm semantics and evidence immutable. A client
supplies only the new bounded plan/slot handle; the authenticated server
resolves the allowlisted prompt. No client prompt text, arbitrary provider/model
or unrestricted variant selector is accepted. Unmarked app requests retain V2.
Disabled, expired, malformed, wrong-owner and wrong-input marked requests fail
before provider dispatch.

The new request handle/header/native proof is an intentional cross-surface
contract change. Update Deno validation, Swift request/receipt types, generated
assignment data, observer/admission and contract tests together. The successful
Identify response schema and conditional score semantics stay unchanged; no new
database column or threshold change is planned. Any newly discovered persistence
requirement gets its own explicit schema review rather than an implicit bypass.

The live direct evaluator is not the execution route: its current exploratory
contract schedules Flash and Pro once per case and has no prompt-arm dimension.
Ordinary fixed-context telemetry alone also cannot attest a prompt arm. Do not
pass this design JSON to either existing RunSpec or old comparison-plan parser,
globally swap the prompt between trials, or borrow app credentials for a new
direct runner.

Implementation owners are the
[AI boundary](../../services/supabase/functions/_shared/ai/README.md)
(`contracts.ts`, `registry.ts`, `geminiRequest.ts`), primary audio instructions
and route-private comparison owners, Debug capture/request/proof owners, and the
[evaluation scripts](../../services/supabase/scripts/identification_evaluation/README.md).
The [API contract](../backend-and-data/05-api-contracts.md),
[measurement guide](../development-guides/21-identification-app-measurement.md)
and [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
remain canonical. Update those current contracts with implementation, not by
claiming this RFC is already supported. Use the API-contract, Supabase and iOS
skills; regenerate source-owned artifacts instead of editing generated outputs.

Required implementation checks include default-off/ordinary-route parity,
wrong-owner/expired/consumed/altered-input rejection, exact A/B request deltas,
unresolved/Human/non-biological consumer and Field Trip guards, no duplicate
dispatch, score/state proof binding, interrupted/retried-window rejection,
backward compatibility, regenerated DTO review, recursive Deno checks and the
complete affected Supabase and native gates. Unit fixtures establish mechanics,
not acoustic accuracy. Exact-SHA release and named project activation remain
separate from implementation under repository policy; this plan asks for no
extra provider credential, special allowance or quota bypass.

## Cost, time and status

The selected six historical primary-attempt estimates total
$0.1522075. Repeating comparable usage six times suggests about
**$0.91** for 36 primary calls; using the highest selected historical estimate
for every call gives **$1.09**. These are planning extrapolations, not a cap or
a promise: the candidate can change output/thinking usage, and app enrichment,
other attempts, storage and transport are additional. Continue using existing
production billing. Refresh the pricing snapshot at execution and keep
failed/unknown cost separate.

The [Gemini pricing page](https://ai.google.dev/gemini-api/docs/pricing),
checked 24 September, lists Pro standard short-context rates of $1.25/M input
and $10/M output including thinking. For consistency, the existing conservative
estimator uses the higher-context $2.50/M input and $15/M output rates without a
cache discount. These planning estimates use that conservative basis.

Thirty-six observer windows require 72 minutes, or up to 90 minutes including
all shutdown grace. Allow roughly **2–3 hours total** for staging, validation
and three block transitions; this is a planning estimate, not measured
throughput.

This planning slice passed retained source/reference hash checks, all 36 slot
and pairing checks, candidate-text hash matching, cost arithmetic, 213 local
links, Markdown formatting and whitespace checks. Independent read-only review
found no remaining material feasibility or contract issue. No runtime code
changed, so backend/native runtime gates and live candidate testing were not
run. Formal progress remains **0/60 development and 0/240 held-out groups**. The
next concrete work item at that planning checkpoint was **Slice 1: the offline
candidate and manifest builder**.

## Slice 1 implementation checkpoint — 24 September 2026

The
[offline builder](../../services/supabase/scripts/prepare_audio_uncertainty_comparison.ts)
now prepares the candidate in scripts-only tooling. It reuses the current audio
processor, Pro policy and native Gemini projection. It verifies that removing
only the system instruction makes A and B identical; source and processed audio,
schema, generation settings, context and thresholds remain equal. Candidate
policy identity changes only the prompt name. There is no new live registry
entry.

The two retained private packets passed the pinned freeze, corpus, taxonomy,
owner eligibility/permission, retention, source/reference-record and selected
WAV checks. All six clips produced both request hashes and all 36 assignments.
The
[prepared evidence](./identification-evaluation-evidence/2026-09-24-audio-uncertainty-preparation/preparation.json)
retains hashes/settings only; its canonical digest is bound by the
[freeze record](./identification-evaluation-evidence/2026-09-24-audio-uncertainty-preparation/freeze.json).
The exact-file digest describes the original private output; this formatted
public copy has the same canonical JSON digest. Private retention remains 24
October 2026.

Preparation slot handles belong to the new `audio-uncertainty-v1` namespace and
have no scan identities or dispatch authority. All live execution bindings
remain pending. This preparation produced **zero provider calls and zero app
submissions** and provides no accuracy or confidence-calibration evidence.

The complete Supabase tooling gate passed, including the five focused prompt
tests and four isolated packet/CLI tests. Recursive Supabase formatting and
lint, changed-Markdown formatting, whitespace checks and 367 local documentation
links also passed. The retained preparation's implementation digest matches the
final functions/scripts graph. The user-level skill-link check reported links
pointing to the primary checkout rather than this isolated checkout; its
checked-in reviewed guidance was read directly and those unrelated links were
preserved. Independent read-only review found no remaining material gap after
adding explicit validation of the processed WAV format. The current
[tooling contract](../../services/supabase/scripts/identification_evaluation/README.md#offline-audio-uncertainty-prompt-preparation)
and [testing strategy](../development-guides/08-testing-strategy.md) describe
entry points and coverage. Full native/database/runtime deployment gates were
not run for this scripts-only change. The next implementation work is **Slice 2:
the default-off server-owned assignment lane and Debug simulator proof
integration**; execution remains Slice 3.

## Slice 2 implementation checkpoint — 24 September 2026

The default-off prompt lane and Debug simulator integration are implemented. The
generated plan contains 36 separate scan identities and binds the immutable
Slice 1 preparation, source/processed audio and A/B native-request hashes. Only
server-validated owner/block/window/first-attempt Pro assignments can select the
candidate. Both arms use current DSP; ordinary identification remains V2. The
historical DSP plan, IDs, assignment implementation and controller are
unchanged.

Native staging and serialization verify actual source bytes. Receipt adoption,
queue finalization and first draw reuse the existing foreground lifecycle.
Prompt proof adds the actual subject state and conditional score; named animals
add a normalized scientific-name digest. The separate offline admission path
requires a complete 120-second window, rejects mixed/stale/incomplete proof and
reports provisional species agreement without logging names. This does not turn
unresolved-presence confidence into species confidence or qualify accuracy.

The
[local validation record](./identification-evaluation-evidence/2026-09-24-audio-uncertainty-integration/validation.json)
retains the generated plan/backend bindings and the tested dirty Debug app
fingerprint. It is local implementation evidence, not an exact-SHA release or
live execution freeze. Its backend bundle is
`1949f9c56f0bfa70378adf2f35d8a7275effeeb34c2d6a3afad7bae91f8ad9dd`; the old
Slice 1 source digest still describes only its dated preparation graph. No
historical preparation or benchmark was regenerated.

Validation passed:

- Complete Supabase tooling, generated server/native tables and unchanged DTO
  contracts; 101 function entrypoints checked with their deploy-time configs.
- All 347 static migration tests, complete migration replay on a fresh
  disposable database, 53 catalog files / 389 assertions, and 2,083 Edge tests /
  233 steps with no failures or ignored tests. The initial older local catalog
  failed; the complete successful run used the fresh migrated database. That
  disposable database was removed afterward.
- Database lint and the configured advisor error gate. Advisors retain 105
  security and 80 performance warnings from the unmodified migration catalog;
  this slice makes no schema change or claim to retire that debt.
- Generated iOS project validation, Debug test build, all 1,358 XCTest tests and
  2,959 Swift Testing tests. The tests include both comparison lanes, source/ID
  drift, all subject states, persistence/cancellation and exact draw proof.
- Recursive Supabase format/lint, changed-Markdown formatting, local link and
  whitespace checks. Independent read-only review found no remaining material
  runtime issue; its canonical-document and error-taxonomy findings were fixed.

This slice made **zero provider calls, zero experiment submissions and zero
production mutations**. Formal qualification remains 0/60 development and 0/240
held-out groups. It adds no alternative provider and changes no ordinary Gemini
assignment.

At this Slice 2 checkpoint, the next work was Slice 3 preparation: implement the
separate activation controller/workflow, freeze the actual reviewed
app/backend/private run bindings, and obtain final exact-SHA candidate evidence
before the named release/activation operation. The old DSP controller cannot
enable this lane. Follow the
[activation prerequisites](../backend-and-data/06-supabase-deployment-runbook.md#audio-prompt-comparison-activation-prerequisites)
before any of the three paid blocks. The configured setting remains unset.

## Slice 3 preparation checkpoint — 24 September 2026

**Subsequent tooling amendment — 24 September 2026:** The original execution
ledger remains non-resumable. A separately versioned continuation can retain a
completed prefix after expiry strictly between trials, following verified
post-expiry cleanup and a newly reviewed bounded authorization. It keeps the
original packet unchanged, uses only untouched original assignments, and records
the interruption and amended windows separately. Open claims, exclusions,
uncertain submissions, early voluntary closure, pricing/runtime drift and
replacement slots remain ineligible. The original screening thresholds remain
unchanged; all 36 unique first attempts with known required measurements and
cleanup are still required before evaluating them. Combined evidence is an
explicitly amended run, never an uninterrupted original execution. See the
[current amendment contract](../backend-and-data/06-supabase-deployment-runbook.md#amend-an-expired-prompt-comparison-between-completed-trials).
This tooling capability provides no live execution or identification-quality
evidence.

The separate prompt activation controller and workflow are implemented. They
retain the protected environment, shared deployment lock, exact clean-main
candidate and deployed-runtime checks, private environment-only transport,
selected block and two-hour bound, and verified cleanup. The old DSP controller
and plan remain unchanged. Each activation can admit exactly one block's twelve
slots; replacing an active configuration requires verified absence first.

`prepare_audio_prompt_execution.ts` now verifies the reviewed source packets and
current generated app/server bindings, requires a clean actual build and
reviewed deployment/pricing/windows, and creates a new private six-asset,
36-assignment packet. The ordered ledger rechecks source and all six asset
hashes before each first-attempt claim. It requires a fresh boolean-only private
operator preflight, which is not an authentication attestation. Actual owner and
consent enforcement remains in the backend.

One immutable claim precedes each Identify tap. A complete 120-second
observation must be admitted before the next slot; uncertain claims and rejected
observations block progression without replacement. Every valid unfavorable
result is retained. Cleanup is recorded after completion/exclusion and before
activating the next block. The tools contain no automatic identification or
provider invocation. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#offline-prompt-execution-freeze-and-ledger)
and
[runbook](../backend-and-data/06-supabase-deployment-runbook.md#audio-prompt-comparison-activation-prerequisites)
own the commands and recovery rules.

Local synthetic validation is retained in the
[Slice 3 preparation record](./identification-evaluation-evidence/2026-09-24-audio-uncertainty-controls/validation.json).
The full Supabase tooling gate includes controller lifecycle/transport,
three-block runtime compatibility and isolated filesystem progression checks.
Formatting, lint and documentation checks cover the resulting tree. Independent
read-only review's asset-integrity, private-preflight and exclusion-ordering
findings were fixed. This scripts/workflow/documentation slice changes no
backend runtime, native source or database schema beyond the already validated
Slice 2 state; its earlier complete backend/native record remains separately
dated.

No actual execution packet has been frozen from this dirty implementation
checkout. This checkpoint performed **zero hosted mutations, zero provider calls
and zero experiment submissions**. It is preparation for Slice 3, not completion
of its live run or a candidate-quality verdict. Next: commit/review the
candidate, complete the named release process, freeze the actual clean
app/deployed backend and private run facts, then activate and execute the three
blocks with their required cleanup and all-slot report. Gemini remains the
ordinary provider.
