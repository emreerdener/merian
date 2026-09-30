# Explicit-primary Sol candidate: completed photo comparison

Date: 2026-09-29

Status: All eighteen identification requests and assistant reviews completed,
including six candidate screens and six alternating candidate/control pairs.
**Retain the current Sol photo profile for Free and Pro. Do not promote
`openai_photo_sol_primary_low_v1`.** Explicit resolution improved several rank
choices, but the fly challenge still produced a concrete visual-grounding
failure. This experiment is complete; producer qualification and confidence
thresholds remain unfinished.

Planning update — 2026-09-29: the owner has redirected the next work to
[confidence thresholds for the current Sol profile](identification-openai-confidence-display-2026-09-28.md#calibration-priority--2026-09-29).
Use existing evidence first. No further comparison should run unless it directly
contributes to resolving those thresholds. Further prompt/model optimization is
deferred. This supersedes the next-work ordering below while preserving the
completed experiment's results and its decision against candidate promotion.

## What was compared

The candidate was `openai_photo_sol_primary_low_v1`; the control was
`openai_photo_sol_low_v1`. Both used `gpt-6-sol`, low reasoning, high image
detail, an 8,192-token output limit, native photo moderation and the same
bounded transport. The candidate changed the biological instructions and strict
output contract to require an explicit species, genus, family,
unresolved-biological or non-biological answer. The current explanation format
was preserved.

The separately approved
[prepared packet](identification-sol-primary-comparison-preparation-2026-09-29.md)
contained twelve no-description still photos. Nine were retained development
cases; three added dog, cat and unresolved-biological coverage. The six
challenge photos were shared by both profiles. Facts, identity references,
catalog and request order were frozen throughout execution. This is a new
experiment, separate from the
[earlier rank-prompt comparison](identification-sol-rank-comparison-results-2026-09-29.md).

The assistant reviewed every explanation against its photo and frozen facts, as
delegated by the owner. This was not blinded, independent expert validation or a
held-out benchmark. Each assignment ran once. Results support a development
decision, not a population accuracy estimate, prompt-causality claim or
confidence calibration.

## Completion and screening

| Measurement                                       | Result                         |
| ------------------------------------------------- | ------------------------------ |
| Planned / claimed / completed / reviewed requests | 18 / 18 / 18 / 18              |
| Candidate screens                                 | 6                              |
| Completed challenge pairs                         | 6 of 6                         |
| Provider failures or retries                      | 0                              |
| Final state                                       | `complete: true`, `stop: null` |
| Production activation authorized                  | `false`                        |
| Confidence calibration qualified                  | `false`                        |

The bison, eagle, dog and cat screens returned species-level answers consistent
with their provisional references, including the existing domestic-animal naming
conventions. The quartz control was non-biological. These five screens passed
all three explanation criteria and earned quality credit.

The microbial-community screen returned unresolved biological presence, a valid
abstention under the limited reference. Its grounding remained
`not_assessable/insufficient_reference`; required information and uncertainty
passed. The screen could continue under `primary_reference_limits_v1`, but
earned no quality or explanation-pass credit. No screen had an actual
explanation failure.

All five resolution states appeared across the candidate's twelve outputs. This
demonstrates contract coverage, not biological qualification: family and
unresolved-biological references remain limited.

## Six paired challenges

| Case                       | Candidate                                                                                                         | Unchanged control                                                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `c0101`, butterfly         | Species agreed with the provisional reference; all three explanation criteria passed.                             | Reference agreement; an alternative-comparison claim remained outside the reviewed facts.                                             |
| `c0102`, fly               | Family answer differed from the limited reference; grounding contradicted visible anatomy and uncertainty failed. | Unmapped primary; grounding was unassessable and uncertainty failed because the primary claim exceeded its own stated evidence limit. |
| `c0103`, treefrog          | Supported genus; all three explanation criteria passed.                                                           | Species exceeded the reviewed diagnostic limit; uncertainty failed, with a separate comparison-reference gap.                         |
| `c0104`, lichen            | Genus agreed with the limited reference; all three raw ratings passed, but no quality or explanation-pass credit. | Finer identity remained unassessable against the limited reference; grounding and uncertainty had reference gaps.                     |
| `c0105`, pine              | Genus agreed with the limited reference; all three raw ratings passed, but no quality or explanation-pass credit. | Finer identity remained unassessable; uncertainty failed because the primary claim exceeded its own stated evidence limit.            |
| `c0106`, mineral dendrites | Correctly non-biological; composition detail remained outside the reviewed evidence.                              | Same subject classification and composition-reference limits.                                                                         |

The candidate's fly failure is an explanation failure grounded in visible
evidence. Its raw identity disagreement is retained, while the limited family
reference makes that identity comparison unassessable. Neither the reference
limit nor a valid family-shaped response cancels the anatomy contradiction.

For the control, the fly and pine specificity failures reflect a conflict
between the primary claim and the explanation's stated limitations. They do not
prove that an unmapped or finer species name is biologically incorrect. The
treefrog's reviewed diagnostic limitation separately supports its specificity
failure.

| Challenge measurement                              | Candidate, out of 6 | Control, out of 6 |
| -------------------------------------------------- | ------------------- | ----------------- |
| Biological/non-biological subject agreement        | 6                   | 6                 |
| Named-reference agreement                          | 4                   | 1                 |
| Unassessable limited-reference identity comparison | 1                   | 2                 |
| Unassessable taxonomy mapping                      | 0                   | 1                 |
| Beyond an assessable reviewed rank                 | 0                   | 1                 |
| Taxonomic identity not applicable                  | 1                   | 1                 |
| At least one actual explanation failure            | 1                   | 3                 |
| At least one explanation-reference gap             | 1                   | 6                 |
| All three raw explanation ratings passed           | 4                   | 0                 |
| Credited explanation passes / quality passes       | 2 / 2               | 0 / 0             |

The five identity-interpretation rows partition each profile's six attempts. Two
of the candidate's four agreements have limited references and earn no quality
credit. Explanation failures and reference gaps can overlap. Subject agreement
means biological versus non-biological classification, not the correct organism.
Zero fully passing control explanations does not mean six wrong identifications.
These counts do not establish a reliable accuracy gain.

## Time and cost

| Measurement on the six identical challenge inputs       | Candidate    | Control      |
| ------------------------------------------------------- | ------------ | ------------ |
| Median provider duration                                | 7.375 s      | 7.867 s      |
| Usage-based conservative cost upper estimate, six calls | $0.211546500 | $0.201217502 |

The candidate's provider median was **6.3% shorter** in this run. Provider time
excludes capture, upload, backend orchestration, display and review. One attempt
per profile on six reused cases does not establish an app-wide speed improvement
or support a marketing claim. The visual failure prevents promotion regardless
of this timing difference.

The six candidate screens added $0.201520003, for a total usage-based
conservative upper estimate of **$0.614284005**, approximately **$0.61**, across
all eighteen requests. Frozen ceiling tariffs and the regional allowance were
used without assuming cache discounts; this is not an invoice total. The
$106.383024 held reservation and $110 approval ceiling were spending bounds, not
incurred charges or authorization for another experiment.

## Decision and next work

Close this experiment and keep `openai_photo_sol_low_v1` for both Free and Pro.
The explicit-primary candidate shows useful rank behavior, but it does not meet
the quality requirement for promotion. The current profile also has observed
specificity failures; retaining it does not mean identification quality is
solved. Luna remains unqualified for the Free assignment.

The next useful slice is offline analysis of the remaining visual-grounding
failure and the conflict between primary claims and stated limitations. Use the
existing findings to decide whether a narrowly scoped instruction or validation
change is justified. Preserve the explanation format. Deterministic contract
checks can reject inconsistent structure, but cannot establish that a visible
feature is real. Any future quality claim needs appropriate evidence beyond
these reused development cases.

Do not repeat this completed packet or rewrite its facts, catalog or ratings to
improve the outcome. No additional paid request is needed to close this run. Any
later comparison needs its own versioned candidate, reviewed inputs and bounded
execution authorization. The
[primary-resolution foundation](identification-primary-resolution-contract-2026-09-29.md)
remains useful, but producer qualification and activation are still separate.

Strong / Possible / Weak thresholds follow the identification-quality decision
and calibration for the exact selected profile. This comparison does not set
those thresholds or qualify a Free/Pro model split. OpenAI audio remains a
later, separate evaluation.

## Evidence and verification

Private packet: `2026-09-29-sol-primary-photo-preparation-v2`. Source commit:
`eee890a19e65f89dfbc927d6e7cdac830c59e6ce`. Implementation digest:
`40a2161a7d74f25dd63c4cb38dcb7ea12dc5d9681c86055c24af36e67ac9c489`. Requests ran
from `2026-09-29T23:49:53.656Z` through `2026-09-30T00:07:29.370Z`; all occurred
on September 29 in America/Chicago.

| Artifact identity          | Digest                                                             |
| -------------------------- | ------------------------------------------------------------------ |
| Run                        | `ca143c38ddbf5d13a78d0cafff29c8b65c96e254126dd34a85cbe3c87c0863b7` |
| Plan                       | `195d95cd17b95fff7ad2cc73d0f0c73309f22446859d4d8ee663d6595b8f3af0` |
| Preparation                | `af7ed530e10f13ab7c39453fd38cdc317f7c2be7163b068341c8131244c53974` |
| Reference review           | `4a41cd1e07e698b3785055b677b22934f9444409b6fc4d256edae643afc71446` |
| Final summary file         | `b9283d8b2da1bdce91930b08a6e8ea9fc6575dc82f16378cf12c57b0a3311373` |
| Private outcome audit file | `885af6ef239b7282cf157d640d1adf09116ba30636a4b2de300f55fd9edb0e30` |

After the launcher exited, the offline audit acquired the journal lock, rebuilt
all 24 prepared request projections and eighteen assignments, and verified the
clean source, packet, approval, claim windows, result/review bindings, facts,
rubric, model and service tier. Checked-in parsers validated results and
ratings; the audit recomputed costs, reservations, screening decisions, final
state and summary. All **57 JSON journal artifacts** retained their byte hashes.

The audit made no provider request, denied network and environment access, and
read no credential. Live credential matching was not repeated offline. Its
private outcome record contains bounded results, ratings and hashes, with no
provider prose, media or review-page export.

The source implementation gates remain recorded in the
[runner checkpoint](identification-sol-primary-comparison-preparation-2026-09-29.md#runner-verification).
This follow-up changes documentation only. Changed Markdown formatting, the
recursive Functions/scripts format gate, local document links and diff
whitespace are the relevant checks. Runtime, database and iOS suites are not
repeated for this results update; no production mutation or deployment occurred.
