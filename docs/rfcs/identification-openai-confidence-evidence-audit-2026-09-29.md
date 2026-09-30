# OpenAI confidence thresholds: retained-evidence audit

Date: 2026-09-29

Status: The offline audit is complete. **Retain the provisional Strong cutoff of
0.95 and Possible cutoff of 0.60.** Existing results do not support selecting
different cutoffs or claiming empirical calibration. No provider call ran. These
findings remain valid for the audited profile. The owner's later
[optimization-first decision](identification-openai-confidence-display-2026-09-28.md#sequence-update--optimization-first)
defers calibration collection until the configuration is selected; it supersedes
this audit's earlier confidence-first next-work ordering.

Later integration note, 29 September: the
[observed-traits production revision](./identification-openai-observed-traits-candidate-2026-09-29.md#production-integration--29-september-2026)
is implemented in source. Every reference below to the current or equivalent
production request describes the original `openai_identify_vision_v1` at this
audit checkpoint. Its frozen controls retain that request; they do not establish
calibration for the revised prompt. The audit and original counts are unchanged.

## Decision and scope

The
[confidence plan at the audit checkpoint](identification-openai-confidence-display-2026-09-28.md#calibration-priority--2026-09-29)
kept the current Sol photo model, request instructions, schema and explanation
format fixed. The same profile serves Free and Pro. Existing Strong / Possible /
Weak labels stay in place. This audit does not activate an experimental producer
or change a model score, display policy, backend confidence qualification or
automatic acceptance/reward rule.

The question was whether retained score/identity evidence can validate or
improve the existing two boundaries. A model does not need perfect
identification accuracy before calibration. The limitations here are sparse
score coverage, repeated photos and incomplete identity references.

## Which records match the current profile

| Retained evidence                                                                              | Treatment                                                                                                                                     |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Sol controls from the Luna evidence-limit, corrected Sol-rank and explicit-primary comparisons | Eighteen normalized controls, technically equivalent requests to the current production photo configuration; inspect as a development sample. |
| Earlier direct evaluations                                                                     | Twelve records, including one unknown execution, kept separate because their evaluation bindings differ from production.                      |
| Earlier hosted Gemini/OpenAI comparison                                                        | Eight OpenAI records, kept separate for the same binding difference; photo and description inputs remain distinct.                            |
| Luna, changed Sol-rank, explicit-primary, concise and null-field candidates                    | Excluded from current-profile threshold selection because the model, instructions, output contract or request settings differ.                |

`openai_photo_sol_low_v1` is an evaluation identity. Its reconstructed request
matches `openai_photo_v1` at policy version 1, including `gpt-6-sol`, native
moderation, the current instructions and strict schema, low reasoning, high
image detail and the 8,192-token output limit. The audit proved full request
equality and matched the stored request and snapshot digests for all eighteen
controls. Every included control returned the exact model, default service tier,
allowed moderation and a normalized result.

The older `openai_gpt_6_sol` evaluator lacks the production photo binding's
inline moderation request/decoder boundary and also admits descriptions. Older
high scores therefore remain separate supporting context; they do not fill the
current-profile Strong bin. No historical result was discarded from its original
report or relabeled as a current-profile response.

This establishes technical compatibility with checked-in production policy 1,
not a new audit of the deployed service or of representative customer traffic.
The eligible controls contain still photos without description text. A later
model, prompt, schema, moderation or policy change requires a new compatibility
decision.

## Score coverage after accounting for repeats

The eighteen compatible controls are **three runs of the same six photos**. Five
photos produced fifteen named biological results. One non-biological photo
produced three controls, reported separately from named-identity reliability.
Matching media, prepared inputs and complete request hashes confirm the repeats.

| Existing display band | Raw score          | Named biological attempts | Distinct photos represented |
| --------------------- | ------------------ | ------------------------: | --------------------------: |
| Weak                  | `< 0.60`           |                         1 |                           1 |
| Possible              | `0.60` to `< 0.95` |                        14 |                           5 |
| Strong                | `>= 0.95`          |                         0 |                           0 |

The photo represented in Weak also appeared in Possible on its other attempts.
Distinct-photo counts across bands must not be summed as independent sample
size. The fifteen named outputs represent **five**, not fifteen, observations.
No held-out validation set is available in these reused development controls.

Across those five biological observations:

- One has later mapped agreement with a usable provisional species reference.
  Its original attempt retains its historical mapping gap.
- One has a reviewed diagnostic limit supporting a broader rank; the two later
  attempts exceed that limit. This is an assessable specificity problem, not
  proof that the named species is biologically false.
- Three retain mapping or identity-reference limitations. Those limitations
  prevent a reliable correct/incorrect label.

The only Weak result belongs to that last, unassessable group. Explanation
failures remain recorded but do not substitute for identity correctness labels.
Likewise, correctly classifying a mineral as non-biological does not measure
species-identification precision. False named biological assertions on reliable
negative controls would belong in confidence analysis; none occurred in these
three control attempts.

## What this resolves

The audit identifies why another general comparison would not resolve the
cutoffs. There is no Strong-band coverage for the matching profile, no
assessable Weak identity result, and too little distinct, assessable Possible
evidence to select a boundary reliably. A zero Strong denominator is **not
estimable**, not zero error or proof of reliability.

The current data cannot justify lowering or raising either boundary. Searching
for a cutoff that separates the few available development cases would not
validate that cutoff. Retaining 0.95/0.60 preserves the documented schema-based
display interpretation while `openai_unqualified_v1` remains unchanged. It is a
provisional product decision, not a finding that Strong means 95% accuracy.

## Smallest useful next evidence

Only a **single-profile confidence-calibration collection** is relevant to the
next step. It should use the current production-equivalent Sol request and
record confidence plus reviewed identity/rank correctness. No competing model,
prompt candidate or additional reasoning setting is needed.

Before any paid execution:

1. Prepare distinct observations with source-backed, assessable identities and
   explicit visually supported ranks. Include clear positives, confusable or
   limited-evidence inputs, and reliable non-biological controls. Reuse suitable
   existing source material when possible; repeated attempts on the same photo
   add stability evidence, not new independent observations.
2. State the badge reliability/coverage objective and freeze the selection rule,
   reference review and validation split. Keep threshold-selection observations
   separate from the evidence used to validate the selected thresholds.
3. Bind one unchanged profile and a bounded call/cost plan. The purpose of every
   new case is score-band coverage and correctness, especially the absent Strong
   band and unassessable Weak band. Model scores cannot be known or forced in
   advance; an empty band after a run remains an evidence gap.
4. Report counts, unassessable labels, errors and uncertainty before
   recommending any new cutoff. Do not declare a minimum number of calls
   sufficient merely because the run completed. The eventual evidence
   requirement depends on the chosen reliability target and observed band
   coverage.

This follows the task-specific, representative-data principles in
[OpenAI's evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices).
The repository's
[scoring contract](identification-evaluation-srd.md#5-scoring-and-denominators)
owns identity/rank semantics and observation-level denominators. This audit
prepares no new paid run or execution approval and does not repurpose the
completed comparison's journal or unused spending ceiling.

## Evidence and verification

Private artifact directory: `2026-09-29-openai-confidence-audit-v1`, containing
`audit.json` and the exact offline `audit.ts` analysis. Audit source revision:
`51f7536a0` on `codex/openai-free-pro-evaluation`.

Audit JSON SHA-256:
`0354e544a22610f7518e2a26cf3f0a7a70fb102ba7d797950280d5e6ff13c35d`.

The audit validated all eighteen control records with checked-in parsers,
reconstructed their production-equivalent requests, and verified input,
reference, fact, claim, result and review bindings. It checked media bytes
during preparation and verified **102 input JSON files** retained identical byte
hashes before and after analysis. Raw responses, provider prose, credentials and
media were not copied into the audit output. Earlier records and their reviews
remain unchanged. A separate read-only check of the hash-bound original results
verified that all fifteen biological predictions explicitly have
`resolution: named`; the aggregate audit's subject filter was not relied on to
infer that fact.

The audit script passed Deno type checking and ran with network and environment
access denied; write access was limited to its new private output directory.
There were **zero model calls** and no credential reads. An independent
read-only code audit confirmed the production/control request equivalence and
the exclusions for changed candidates and legacy evaluators.

This repository update is documentation only. Changed Markdown formatting, local
links, the recursive Functions/scripts format gate and diff whitespace are
checked; runtime, database and iOS suites are not repeated. The existing
user-level Supabase skill links are out of date; the reviewed checked-in skills
were used, and no unrelated skill installation was changed.
