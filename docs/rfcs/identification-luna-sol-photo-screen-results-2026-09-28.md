# Luna/Sol photo screen: reference coverage stop

Date: 28 September 2026, America/Chicago

Status: One Luna request completed; the approved comparison stopped before its
second request. The species matched the frozen reference, but explanation
grounding was not assessable against the supplied notes. No Sol control ran and
no model selection or production change is justified by this result.

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

## Observed outcome

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

## Why the screen stopped

The explanation included a comparison with domestic cattle. The frozen bison
fact card explicitly leaves those comparative discriminators unverified. The
image and supplied notes support the primary bison identification, but do not
supply the missing cross-species reference for every material comparison. Under
the existing rubric, that gap is `insufficient_reference`; it is neither an
observed contradiction nor proof that the model invented evidence.

`photoModelRunner.ts` requires both a correct primary result and passing ratings
for all three explanation criteria before continuing the screen. Its terminal
`screen_failed` code therefore includes an unassessable reference outcome.
Reports must inspect the retained ratings rather than interpret that code alone
as a wrong identification or demonstrated model-quality failure.

This also exposes a preparation limitation: the production photo contract
requires two alternative candidates with distinguishing features, and the review
projection includes those features. A fact packet covering only a subset of
plausible comparisons can leave a valid output unassessable. This run does not
resolve the factual validity of the uncovered comparison.

## Decision and next scope

Retain the current production Sol photo assignment for both tiers. One
compatible Luna request does not establish comparative accuracy, explanation
quality, a cost-saving percentage, median latency, mobile end-to-end speed or
confidence-badge thresholds. No contemporary Sol result exists in this run.

Recommended next protocol revision, not implemented or activated by this record:

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

The original controller does not support that continuation. Its terminal stop
must not be deleted or edited to simulate one. This report performs no further
provider calls, changes no prompt or model settings, and grants no activation.
