# OpenAI concise-prompt comparison outcome

Date: 26 September 2026 (America/Chicago)\
Status: Closed as inconclusive after one control result; concise candidate
untested

**Direction update — 27 September 2026:** The
[current optimization plan](./identification-optimization-preserving-results-2026-09-27.md)
preserves the existing explanation format and detail. Concise explanations are
not a selected next step. The measurements, remaining assignments and spending
closure below remain unchanged; references to candidate selection describe the
earlier plan.

The single-session OpenAI comparison was approved for eight reused cases across
two profiles, at most 16 calls and USD 86 (USD 43 per profile). One control
request completed and matched the provisional saguaro reference. The assistant
review could not assess all explanatory claims against the frozen facts, so the
controller stopped before the next request. Seven control assignments and all
eight concise assignments remain unattempted. No requests were replayed.

Retain the existing OpenAI profile and defer the concise candidate. This result
does not establish that shorter explanations help or hurt, and does not
establish an identification error. It exposes a gap in the reference material
used to assess explanations. The approved experiment is closed; no automatic
restart, retry, or additional spending follows from this record.

The
[bounded evidence](./identification-evaluation-evidence/2026-09-26-openai-concise-screen/results.json)
contains measurements, ratings, accounting and evidence digests. The
[optimization plan](./identification-provider-optimization-plan.md) owns
candidate selection; the
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#concise-openai-candidate-and-private-review)
owns execution and review contracts.

## What the run established

| Measure                                            | Observed result                                          |
| -------------------------------------------------- | -------------------------------------------------------- |
| Identification                                     | Carnegiea gigantea; agreement with provisional reference |
| Provider time                                      | 7.067 seconds                                            |
| Normalization time                                 | 2.977 milliseconds                                       |
| Rate-aware estimated cost                          | USD 0.024711                                             |
| Conservative amount recorded by the spending guard | USD 0.029460                                             |
| Observed cache reads / writes                      | 0 / 0 tokens                                             |
| Explanation grounding                              | Not assessable: insufficient reference                   |
| Explanation decision reason                        | Pass                                                     |
| Explanation uncertainty and supported rank         | Pass                                                     |
| Remaining requests                                 | 15 unattempted                                           |

These times describe a single provider-boundary result, excluding capture,
upload, persistence and app rendering. Costs use reviewed rates and reported
usage; they are not a verified invoice. There are no unknown executions or
retained unknown-usage reservations. The USD 86 ceiling was an authorization
limit, not a charge. Neither full-allocation cost nor a paired latency/cost
improvement can be estimated from this incomplete comparison.

## Why review stopped

The frozen fact card covered the observed cactus structure and the provisional
species reference. The model also supplied comparative claims about lookalike
species. Those distinctions were not covered by the observation or reviewed fact
card. Under the predeclared rubric, claims that cannot be verified receive
`not_assessable / insufficient_reference`; they are not silently accepted or
classified as false.

The durable controller code is `explanation_quality_failed`, which covers a
nonpassing explanation assessment. The actual assessment is an insufficient-
reference outcome, with the other two criteria passing. Read those bounded
ratings alongside the stop code so it is not mistaken for an API failure or a
proven hallucination. The assistant did not alter frozen facts, substitute an
owner assessment, or add external facts after seeing the answer. AI assessment
is provisional and has no independent human validation.

## Disposition and next useful work

Close this optional brevity screen with the existing profile retained. The
[earlier OpenAI pilot](./identification-openai-photo-text-pilot-2026-09-25.md)
already establishes working photo/text inference through the adapter; this
incomplete optimization should not be presented as a prerequisite for reviewing
the provider-flexibility implementation. Production assignment remains subject
to the existing consent, confidence, admission and release controls.

If brevity is revisited, first define how reference material covers every
user-facing explanation field, including alternative-species comparisons. A
prospective reference pack must be reviewed and frozen before another paid
comparison; the current assessment and claims remain immutable. Do not add a
parameter sweep or repeat the same benchmark merely because this screen was
inconclusive. No further owner practice exercise is required for delegated
review.

## Source and validation

The live request used clean commit `546c839b33c5bae0850106cdee14c164d45fd852`.
Its source graph and the exact plan, report, state and result digests are in the
evidence file. The hidden-key session launcher reused the key only in memory,
ended after the recorded stop, and made no candidate call. Report generation was
offline and made no provider requests.

Before dispatch, the complete Supabase tooling gate passed: 438 standard tests
plus 32 steps, 58 isolated evaluator tests plus 29 steps, DTO/media checks and
all 10 shell suites. Focused launcher tests covered one-prompt ordered
execution, actual Deno permission admission, missing state, controller stops on
exit zero, plan changes, child errors and interruption. An independent read-only
review found no launcher blockers. The exact functions/scripts format gate,
changed- Markdown format gate and diff whitespace checks passed. Production
deployment was not part of this work.
