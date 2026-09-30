# Luna/Sol photo screening results

Date: 28 September 2026, America/Chicago

Status: Six Luna screening calls completed across the original run and approved
continuation. All five biological identifications and the non-biological control
matched the provisional references. The mineral explanation failed the
specificity criterion, so the protocol stopped before all twelve paired
challenge calls. No Sol control ran. Retain the current Sol photo assignment;
this screen does not qualify Luna or establish a comparative model advantage.
The first stop and reference-gap rating remain preserved below.

## Scope and retained evidence

The [approved plan](identification-openai-free-pro-models-2026-09-28.md)
allocated at most 18 generation calls and $40 in the Naturebook project: twelve
Luna-low calls and six Sol-low controls. The
[preparation record](identification-luna-sol-photo-preparation-2026-09-28.md)
retains the twelve inputs, frozen references and full-context reservation.

Execution used clean source `d8bce425dffa8d306c3a5b505470570dfb1d70b0`, with
implementation digest
`f418b29134e12a3fb16ca83294a5a24fdb4b379a39dacb5156ffb04e0dd11f4d` and plan
digest `b56c6df95010d470024596687c91826b2415afddd5ae509134eb2fbca400673b`. The
first claim began at `2026-09-29T01:15:32.664Z`. The private packet is
`2026-09-28-luna-sol-photo-preparation-v1`; its `photo-model-run/` journal and
terminal stop remain immutable. The derived `photo-model-outcome-summary.json`
records bounded measurements and the source artifact byte hashes outside Git.

## First request: observed outcome

| Measurement                                 | Result                                     |
| ------------------------------------------- | ------------------------------------------ |
| Requests claimed and completed              | 1 of 18; no automatic retries              |
| Returned model                              | `gpt-6-luna`, Standard service tier        |
| Case                                        | `c0001`, original bison screening photo    |
| Primary identification                      | Matches the frozen species-level reference |
| Schema, normalization and native moderation | Accepted; safety disposition `allowed`     |
| Provider duration                           | 7.653 seconds                              |
| Normalization duration                      | 6.321 milliseconds                         |
| Input / output tokens                       | 4,787 / 591                                |
| Reasoning tokens                            | 107, already included in output            |
| Cached / cache-write tokens                 | 0 / 4,784                                  |
| Usage-based conservative cost upper bound   | $0.001804001                               |
| Grounding review                            | `not_assessable / insufficient_reference`  |
| Decision-evidence review                    | `pass / supported`                         |
| Uncertainty review                          | `pass / supported`                         |
| Controller state                            | `screen_failed`, `complete: false`         |

The cost above uses the frozen conservative pricing and regional multiplier. It
is not an invoice. The controller retains a $0.2955084 reservation for the one
claimed call; that reservation is not measured spend. The other seventeen
assignments were not dispatched.

The qualitative review was performed by the assistant against the image and
frozen notes. It is not independent human adjudication. The schedule already
identified the screen as Luna, so model blinding is not claimed.

## Why the first screen stopped

The explanation included a comparison with domestic cattle. The frozen bison
fact card explicitly leaves those comparative discriminators unverified. The
image and supplied notes support the primary bison identification, but do not
supply the missing cross-species reference for every material comparison. Under
the existing rubric, that gap is `insufficient_reference`; it is neither an
observed contradiction nor proof that the model invented evidence.

The original `photoModelRunner.ts` mode requires both a correct primary result
and passing ratings for all three explanation criteria before continuing the
screen. Its terminal `screen_failed` code therefore includes an unassessable
reference outcome. Reports must inspect the retained ratings rather than
interpret that code alone as a wrong identification or demonstrated
model-quality failure.

This also exposes a preparation limitation: the production photo contract
requires two alternative candidates with distinguishing features, and the review
projection includes those features. A fact packet covering only a subset of
plausible comparisons can leave a valid output unassessable. This run does not
resolve the factual validity of the uncovered comparison.

## Decision after the first request

Retain the current production Sol photo assignment for both tiers. One
compatible Luna request does not establish comparative accuracy, explanation
quality, a cost-saving percentage, median latency, mobile end-to-end speed or
confidence-badge thresholds. No contemporary Sol result exists in this run.

The owner subsequently approved this protocol revision on 28 September. It is
implemented in a separate continuation; the execution outcome is recorded below:

1. Keep the stopped journal and its unassessable rating intact. Do not rerun the
   first request or silently replace its reference facts after seeing output.
2. Separate observed identification/explanation failures from missing reference
   coverage. Record unassessable claims explicitly; they cannot count as quality
   passes or evidence of a Pro advantage.
3. Before further calls, specify a continuation that carries forward this first
   attempt and permits only the seventeen unattempted assignments: eleven Luna
   and six Sol, with a combined maximum of eighteen calls and $40 across both
   records. Bind the continuation to this journal and prevent overlap.
4. Keep the existing stop conditions for technical failures, unknown billing,
   safety problems and actual screening errors. A reference-only gap may permit
   collecting the remaining comparison evidence under an explicitly revised
   protocol, while continuing to block claims that require the missing evidence.

The original execution mode and terminal stop remain unchanged. The separate
continuation validates the stopped journal and inherits ordinal 1 without
redispatching it. It uses a new source/credential/parent-bound approval and a
sibling journal for ordinals 2–18, locks both journals and counts the inherited
reservation toward the same cap. Reference gaps on any of the six screening
cases remain unassessable and may proceed; actual screening failures still stop.
The
[operating procedure](../development-guides/22-alternative-identification-provider.md#approved-continuation-after-the-reference-coverage-stop)
documents the distinct preflight, approval and launcher mode. This revision
changes no prompt, model settings, explanation format or production assignment.

## Continuation verification

The continuation passed the complete `make test-supabase-tooling` gate: 455
standard tests, 86 isolated evaluator tests, both DTO groups, all 12 shell test
files and recursive script type checks. The evaluator includes 20 photo-model
tests covering the original and continuation modes. Recursive Deno formatting
and lint, changed-Markdown formatting and diff checks passed. These checks make
no live provider requests.

Independent read-only review found no controller, locking, accounting,
provenance or release-control blocker. Its documentation-sync finding was
resolved in the operator guide, evaluator README and current plan. Function
runtime code, database objects and iOS code are unchanged in this continuation;
their full runtime/database/native suites were not rerun for this scripts-only
change. The original preparation record retains their earlier evidence.

## Approved continuation outcome: 28 September

The owner entered the existing Naturebook credential and the separate launcher
ran clean source `2fdb2f9ec1898d9a56caf3b07ca5642dd181661f`, implementation
digest `02cd7f243245ae6926bcb124841ab9a502ef277bbea7ceeead408922a667717c`. Its
continuation run digest is
`3e0376da23bf9c72b1c743188cebe1c25870fe350c1ffb0408ca372bce122b90`. The original
plan and assignment order were unchanged. The controller inherited ordinal 1 and
dispatched ordinals 2–6 once each; ordinals 7–18 were never claimed. No
automatic retry or replacement request occurred.

The original first-call journal's retained byte hashes still match. The private
`photo-model-continuation-outcome-summary.json` binds both journals, source,
plan, ratings, measurements and artifact byte hashes. It contains no provider
prose or credential. Artifact verification acquired both run locks after the
process stopped, recomputed result/review/cost bindings, and verified the exact
new claim/result/review inventory.

| Screen case                | Primary reference outcome             | Grounding review            | Uncertainty review            | Provider seconds |
| -------------------------- | ------------------------------------- | --------------------------- | ----------------------------- | ---------------- |
| Bison (`c0001`, inherited) | Species matches                       | Unassessable: reference gap | Pass                          | 7.653            |
| Bald eagle (`c0002`)       | Species matches                       | Unassessable: reference gap | Pass                          | 6.627            |
| Monarch (`c0003`)          | Species matches                       | Unassessable: reference gap | Pass                          | 8.758            |
| Sunflower (`c0004`)        | Species matches                       | Unassessable: reference gap | Pass                          | 5.772            |
| Saguaro (`c0007`)          | Species matches                       | Pass                        | Pass                          | 6.657            |
| Mineral (`c0008`)          | Non-biological classification matches | Unassessable: reference gap | Fail: unsupported specificity | 5.662            |

Decision-evidence ratings passed for all six. Schema, normalization and native
moderation were accepted for all six, with the requested `gpt-6-luna` model and
Standard service tier. The five named biological matches use provisional
references; this small reused screen is not a general accuracy estimate.

The mineral failure concerns explanation wording, not a false biological
classification or a proven wrong mineral. The frozen notes support a tentative
mineral description, but do not establish a particular mineral identity. The
assistant judged that the explanation treated its specific mineral
identification as established while limiting uncertainty mainly to the variety.
It therefore received `fail / unsupported_specificity`. Its physical appearance
still supported the non-biological decision. The missing factual reference
separately remained `not_assessable / insufficient_reference` for grounding.
Neither rating asserts that the specimen cannot be quartz.

Reference-only gaps on the earlier cases continued under the approved revision.
The actual specificity failure retained the agreed screening stop, giving
`screen_failed`, `complete: false`, six combined completed calls and five new
claims. The twelve remaining challenge assignments include six Luna and six Sol
calls; none ran. The assistant performed all reviews, with no independent human
adjudication or model blinding claimed.

### Measured timing and cost

- Six-case provider median: **6.642 seconds**, range **5.662–8.758 seconds**.
  This covers the completed Luna screening subgroup, not the incomplete full
  comparison or capture-to-result time in the app.
- Median normalization time: **4.842 milliseconds**.
- Usage: **28,188 input tokens**, **3,597 output tokens**, including **900
  reasoning tokens**; **15,624 cached input tokens** and **12,546 cache-write
  tokens** were reported. No tool calls were reported. Reasoning is included in
  output and is not counted twice.
- Combined conservative usage-based cost upper bound: **$0.010719231**, about
  **1.07 US cents** for all six requests. This uses the frozen pricing and
  regional multiplier; it is not an invoice or a guaranteed production price.
- Retained claimed reservation: **$1.7730504**. The full preflight reservation
  remains $39.0071088 under the approved $40 cap; neither reservation is
  measured spend.

### Selection decision

Keep the current Sol photo profile for both Free and Pro. Luna showed compatible
execution and correct primary outcomes on this screen, but did not satisfy all
of the planned explanation criteria. No contemporary Sol challenge results
exist, so this run cannot establish a Free/Pro quality advantage, comparative
latency or cost-saving percentage. It does not establish confidence thresholds
or justify raising a badge because of a model tier.

The next candidate change should address evidence limits for non-biological
identifications while preserving the current explanation format. A review of
that proposed change can proceed locally. Any new paid comparison needs a new
bounded plan and approval; the unused budget does not authorize clearing this
terminal stop or repeating completed calls. Audio evaluation remains a later
milestone. This result makes no production assignment or deployment change.

The subsequent
[candidate plan](identification-luna-evidence-limits-candidate-2026-09-28.md)
implements that wording hypothesis as a new Luna evaluation profile and separate
v3 packet. This does not amend either stopped run or establish an improved
outcome. The candidate retains the current explanation format and Sol control.

The subsequent candidate has now completed its separately approved comparison;
see the
[eighteen-call results](identification-luna-sol-candidate-results-2026-09-28.md).
Its mineral checks passed, while biological quality failures retained the
decision to keep Sol for both tiers. These later results do not change the
historical screen, its stops or its ratings.
