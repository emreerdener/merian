# Sol rank-consistency candidate: completed photo comparison

Date: 2026-09-29

Status: All eighteen identification requests and assistant reviews completed,
including six candidate screens and six alternating candidate/control pairs.
**Retain the existing Sol photo profile for Free and Pro. Do not promote
`openai_photo_sol_rank_limits_low_v1`.** The candidate respected broader ranks
on three difficult cases, but two other challenge explanations contradicted
visible evidence. The bounded comparison is finished; production rank handling
and confidence thresholds remain unfinished.

## What this comparison establishes

The [rank-consistency plan](identification-photo-rank-consistency-2026-09-28.md)
tests whether the primary identification and explanation agree about the detail
supported by a photograph. The control was `openai_photo_sol_low_v1`; the
candidate was `openai_photo_sol_rank_limits_low_v1`. Both used `gpt-6-sol`, low
reasoning, high image detail, the existing explanation format, an 8,192-token
output limit and the same transport and moderation controls. Only the
candidate's biological instructions and descriptive schema guidance differed.

This is the separately approved corrected-reference comparison. The
[first stopped screen and source adjudication](identification-sol-rank-screen-results-2026-09-29.md)
remain unchanged. The new packet preserved all twelve photographs and all
eighteen request identities, corrected four fact cards before execution, and
explicitly marked five identity references as limited. The facts were frozen
throughout this run. No reference or catalog entry was added after seeing a
result.

The assistant reviewed each explanation against the supplied photograph and
frozen facts, as delegated by the owner. This was neither independent expert
validation nor a blinded or unseen benchmark. Each assignment ran once. These
observations support a conservative selection decision, not population accuracy,
prompt causality or a new confidence scale.

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

All five biological screens agreed with their provisional named references; the
sixth was correctly classified as non-biological. Four screens passed all three
explanation criteria. Two retained `insufficient_reference` ratings, with no
actual explanation failure. The screening policy permits those gaps when the
primary classification agrees, but does not turn them into passing explanation
evidence. Two named screening references themselves remain coverage-limited.

## Six paired challenges

| Case    | Candidate                                                                                            | Unchanged control                                                                                                             |
| ------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `c0101` | Named-reference disagreement; grounding contradicted a visible discriminator and uncertainty failed. | Named-reference agreement; one alternative-comparison reference gap.                                                          |
| `c0102` | Unmapped primary; visible-evidence contradiction and unsupported certainty.                          | Unmapped primary; finer identification and comparison details remain outside reference coverage.                              |
| `c0103` | Supported genus; all three explanation criteria passed.                                              | Species claim exceeded the reviewed rank; uncertainty failed, with a separate comparison-reference gap.                       |
| `c0104` | Source-backed genus; all three explanation criteria passed.                                          | Finer name is unassessable against the limited reference; no species-error claim follows from the source's genus label alone. |
| `c0105` | Cautious provisional genus; all three explanation criteria passed.                                   | Unmapped finer name and insufficient references; no invented needle or cone detail was recorded.                              |
| `c0106` | Correctly non-biological; mineral-composition detail remains outside reference coverage.             | Correctly non-biological; the same mineral-reference limitation remains.                                                      |

`c0101` and `c0102` are concrete candidate explanation failures, based on the
visible evidence and frozen facts. The mapping gap on `c0102` does not erase its
grounding failure. Conversely, an unmapped name by itself is not proof of an
incorrect identity. The summary's subject agreement concerns biological versus
non-biological classification; it does not imply the correct organism or taxon.

The most directly assessable rank improvement is `c0103`, whose reviewed
diagnostic limitation supports genus rather than a species choice. The candidate
also stayed within the available genus references on `c0104` and `c0105`; those
observations do not prove every finer answer from the control was wrong.

| Challenge measurement                       | Candidate, out of 6 | Control, out of 6 |
| ------------------------------------------- | ------------------- | ----------------- |
| Biological/non-biological subject agreement | 6                   | 6                 |
| Named-reference agreement                   | 3                   | 1                 |
| Named-reference disagreement                | 1                   | 0                 |
| Beyond an assessable reviewed rank          | 0                   | 1                 |
| Limited-reference identity comparison       | 0                   | 1                 |
| Unassessable taxonomy mapping               | 1                   | 2                 |
| Taxonomic identity not applicable           | 1                   | 1                 |
| At least one actual explanation failure     | 2                   | 1                 |
| At least one explanation-reference gap      | 1                   | 6                 |
| All three explanation criteria passed       | 3                   | 0                 |

The six identity-interpretation rows partition each profile's attempts; review
counts overlap. In particular, the control's `c0103` has both a concrete
specificity failure and a reference gap. Zero fully passing control explanations
does not mean six wrong identifications. All results supplied specific decision
reasons; that criterion checks the presence of a reason and cannot cancel a
grounding or specificity failure.

## Time and cost

| Measurement on the six identical challenge inputs       | Candidate    | Control      |
| ------------------------------------------------------- | ------------ | ------------ |
| Median provider duration                                | 10.159 s     | 11.180 s     |
| Usage-based conservative cost upper estimate, six calls | $0.199749004 | $0.205408502 |

The candidate's provider median was 9.1% shorter in this run. This is provider
time only, excluding capture, upload, backend orchestration, display and review.
One attempt per profile on six reused cases does not establish a reliable speed
improvement or a mobile marketing claim. Quality failures prevent promotion
regardless of this timing difference.

The six candidate screens added $0.192373504, for a total usage-based
conservative upper estimate of **$0.597531010** across all eighteen requests.
This uses the frozen ceiling tariffs and regional allowance without assuming
cache discounts. It is not an invoice total. The controller's $106.383024 held
reservation and the $110 approval ceiling were spending bounds, not incurred
charges or a remaining allowance for another experiment.

## Decision and next work

Close this experiment and retain the unchanged Sol profile for both tiers. The
candidate demonstrates useful broader-rank behavior but does not satisfy the
quality requirement for promotion. The control also has a concrete rank failure;
retaining it is continuity, not a finding that identification quality is solved.
Luna remains unqualified for the Free assignment.

The next slice is an offline design for explicit primary rank and resolution
across normalization, species enrichment, persistence, retries and presentation.
Separate that contract work from any new prompt candidate: this completed run
does not justify enabling the evaluated candidate. Review the two observed
visual failures before proposing another paid comparison, and retain the current
explanation format. Do not rerun this packet, rewrite its ratings or expand its
frozen catalog to improve its scores.

Confidence thresholds follow the identification-quality decision and an adequate
calibration dataset for the exact selected profile. These reused development
cases and model-reported scores cannot set Strong / Possible / Weak thresholds.
Production rank implementation and activation remain subject to the parent
plan's compatibility and release controls. OpenAI audio remains a later,
separate input/model evaluation.

## Evidence and verification

Private packet: `2026-09-29-sol-rank-reference-corrected-photo-v1`. Source
commit: `56f33e6b57bdbefad734fc04276c3a190e1b06d7`. Implementation digest:
`7e3b07f3bd37570448412e11a530cc1badeaa851c6e858ed509adff036fa1af8`.

| Artifact identity          | Digest                                                             |
| -------------------------- | ------------------------------------------------------------------ |
| Run                        | `25527c1c813d8e72a131617167aa1b887c43ef9cd024208f5acf4340c20268fa` |
| Plan                       | `f194a755a4ca52a415b5b78baf65c17dbfa6e92e7ca52fd19f190d61bb5324a5` |
| Preparation                | `355edfdeeeded65a8b477478313379d480fea10438eded5b10e62126e4767230` |
| Reference review           | `b59c34eff059501e03eec7c31738424f7a4c2d7e781db4e03d34d40000f6d544` |
| Final summary file         | `0e42af69144aa846f0e3a7cdb0a9c9b884e0de0fdf1ecb6e4cea925146c7ddb0` |
| Private outcome audit file | `cb9d655c3f97fe4b66d254227d9b16b8b0bb82083248fee466dc07fbb8939be8` |

After the launcher exited, the offline audit acquired the journal lock, rebuilt
all requests from the frozen inputs, and verified the source, plan, approval,
claim windows, assignment digests, result/review links, facts, rubric, model and
service-tier identities. Checked-in parsers validated every result and rating;
the audit recalculated every cost bound, reservation, screen decision and the
complete summary. All 57 JSON journal artifacts retained their byte hashes. The
audit made no provider call and read no credential; live credential matching was
not repeated offline. The private outcome file contains bounded records, ratings
and hashes, with no provider prose or review-page export.

The implementation gates belong to the committed source and remain recorded in
the
[screen/adjudication report](identification-sol-rank-screen-results-2026-09-29.md#evidence-and-validation).
This follow-up edits documentation only. Markdown formatting, the recursive
Functions/scripts format gate, local document links and diff whitespace are the
relevant checks. Runtime, database and iOS suites are not repeated for the
results documentation; no deployment or production mutation occurred.
