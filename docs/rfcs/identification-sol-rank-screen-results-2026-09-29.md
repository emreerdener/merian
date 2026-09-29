# Sol photo rank screen: result and reference adjudication

Date: 2026-09-29

Status: The first candidate screen completed and the controller stopped. A
source audit then found that its frozen reference notes omitted relevant
publisher metadata. The recorded stop is preserved, but this run is
**inconclusive for candidate quality**. It does not establish a model defect or
qualify a prompt change. Sol continues to serve both Free and Pro; confidence
thresholds remain later work.

Follow-up, 29 September: the separately approved
[corrected comparison](identification-sol-rank-comparison-results-2026-09-29.md)
completed all eighteen calls and six pairs. Its two concrete candidate visual
failures block promotion. That new outcome does not rewrite this first run, its
ratings or the source adjudication below.

## What ran

The [rank-consistency plan](identification-photo-rank-consistency-2026-09-28.md)
scheduled six candidate screens followed by six alternating candidate/control
pairs. The first result was reviewed by the assistant in the transient local UI.
Only bounded measurement fields and ratings were saved.

| Measurement                                     | Result                        |
| ----------------------------------------------- | ----------------------------- |
| Planned maximum requests                        | 18                            |
| Claimed, completed and reviewed requests        | 1                             |
| Unclaimed requests                              | 17                            |
| Candidate screen identity and subject agreement | 1 of 1 provisional references |
| Completed challenge pairs                       | 0 of 6                        |
| Historical controller stop                      | `screen_failed`               |
| Run complete                                    | `false`                       |
| Provider time, single request                   | 7.516 seconds                 |
| Normalization time, single request              | 9.465 milliseconds            |
| Usage-based conservative cost upper estimate    | $0.031647001                  |

The single request provides no paired speed, cost or quality comparison. Its
per-call held reservation of $5.910168 is a spending-control bound, not actual
spend. The original $110 ceiling was never an expected bill.

The recorded ratings were grounding `not_assessable / insufficient_reference`,
required information `pass / supported`, and uncertainty
`fail / unsupported_specificity`. The latter caused the stop. Primary mapping
was `matched`, and both primary subject and identity agreed with the provisional
reference. Grounding was not rated as invented or contradicted evidence.

## Why the stop is not evidence of a model defect

The frozen c0001 fact card said individual sex was unestablished. After the run
closed, the original
[NPS asset record](https://npgallery.nps.gov/AssetDetail/aa23c7fd-4c51-4522-b0fa-120c696ecfc5)
was checked and its image details explicitly identified the photographed animal
as a bull. The original preparation record and unchanged image digest bind this
source to c0001. The assistant's specificity-failure judgment was too strong
given the incomplete reference card.

Publisher metadata corroborates an attribute; it does not prove that every
explanatory visual claim is justified. The
[Alaska Department of Fish and Game
identification guidance](https://www.adfg.alaska.gov/index.cfm?adfg=deltabison.identification)
also cautions that sex traits overlap and belly hair can resemble male anatomy.
A future review must assess the actual visible evidence and these limitations
together. It must not simply replace the old failure with a pass.

The append-only private adjudication classifies this as
`frozen_reference_incompleteness`. It binds the run, claim, result, review,
manifest, summary and frozen input file hashes, plus the original source-record
file, record locator, canonical record hash and prepared-image hash. The
journal, ratings, stop, plans and old facts remain unchanged. No raw model
explanation or returned name is reproduced in this report or the adjudication.

## Offline source-to-fact audit

All twelve source/fact relationships were checked. Nine source pages were read,
one supplied only its page title and media metadata, one was available through
the indexed official-page excerpt, and the original treefrog page could not be
reconfirmed through the web tool. The separate diagnostic reference for the
treefrog pair was available. This is a bounded coverage audit, not exhaustive
taxonomy verification.

The new private `photo-model-facts.prospective.json` changes four fact cards:

| Case    | Prospective correction                                                                                                                                                                                                              |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `c0001` | Include the omitted publisher attribute and reviewed morphology cautions.                                                                                                                                                           |
| `c0008` | Separate the publisher's [quartz identification](https://www.usgs.gov/media/images/quartz-crystal-3) from claims of laboratory chemistry or tests unavailable in the image.                                                         |
| `c0102` | Treat the family reference as coverage-limited: the [publisher supplies a species label](https://www.fws.gov/media/american-hover-fly-sitting-leaf), and no bound diagnostic key proves family is the maximum possible visual rank. |
| `c0104` | The [publisher's genus label](https://www.fws.gov/media/freckle-pelt-lichen) establishes genus-level coverage; by itself it does not prove all species identification is impossible.                                                |

The other eight fact cards are unchanged. No corpus label, taxonomy entry,
image, candidate prompt or production setting changed. c0004, c0007 and c0105
retain their existing reference limits; c0102 and c0104 need the same explicit
limited-reference treatment in a future review binding.

Some evidence limits remain affirmative. For example, the
[University of Maine reference](https://extension.umaine.edu/signs-of-the-seasons/indicator-species/gray-treefrog-fact-sheet/)
describes the two gray treefrog species as having identical physical appearance
and differing calls. A still-image assertion that visibly distinguishes that
pair has a concrete diagnostic limitation. That differs from an incomplete
catalog or a source that merely stopped at genus.

The audit is informed by a seen result and uses development cases already seen
in prior comparisons. It must not be described as an independent or unseen
benchmark. Publisher labels, visible features and diagnostic requirements remain
separate; neither missing reference coverage nor a source label alone settles
every quality judgment.

## Prospective summary correction

The reporting fix is implemented as `sol_photo_rank_summary_v2`. Each attempt
retains its raw `assessment` and adds `identityInterpretation`; each
phase/profile retains raw `identityCounts` and adds
`identityInterpretationCounts`. A mismatch against a limited reference becomes
`unassessable_limited_reference` in the new interpretation. Subject
disagreement, missing mappings, valid abstention, reference agreement and
reviewed-rank comparisons remain separate. Explanation ratings and failures are
preserved independently; a reference gap does not erase an actual explanation
failure or create a passing review.

New run bindings use `sol_photo_rank_run_binding_v2` and freeze the summary
version. An old v1 binding is refused before admission or summary generation,
retaining every original journal file, including state, stop and summary, even
when its source or approval inputs have changed. The historical v1 summary was
not regenerated. No screen-decision policy, prompt or provider request changed.
Deterministic synthetic cases exercise limited versus usable references, mapping
gaps, subject disagreement, raw and interpreted counts, explanation failures and
missing reviews.

## Corrected comparison prepared

A separate private packet, `2026-09-29-sol-rank-reference-corrected-photo-v1`,
now contains the corrected fact cards, rebuilt preparation receipt, twelve-case
reference review and a new comparison proposal. Its separately derived
preparation source has no inherited execution approval. The original audit and
stopped packet remain unchanged.

Every candidate/control request, model snapshot, instruction and schema digest
matches the original eighteen-assignment schedule. Only four fact cards change;
the reference review explicitly marks c0004, c0007, c0102, c0104 and c0105 as
coverage-limited. Sixteen original preparation-source files, including all
twelve photos, were verified unchanged. Independent read-only review confirmed
the new input bindings and absence of inherited execution authority.

The new proposal still has six candidate screens and six alternating pairs, with
one attempt per assignment and at most eighteen requests. The conservative
reservation remains $106.383024 against a $110 ceiling, using the standard Sol
tariff ceilings rechecked against
[official OpenAI pricing](https://developers.openai.com/api/docs/pricing) on 29
September. This reservation is not an expected bill. A clean-source preflight
and a fresh execution approval remain necessary before dispatch; preparation
created no credential or execution journal.

| Artifact         | Digest                                                             |
| ---------------- | ------------------------------------------------------------------ |
| Preparation      | `355edfdeeeded65a8b477478313379d480fea10438eded5b10e62126e4767230` |
| Reference review | `b59c34eff059501e03eec7c31738424f7a4c2d7e781db4e03d34d40000f6d544` |
| Plan proposal    | `f194a755a4ca52a415b5b78baf65c17dbfa6e92e7ca52fd19f190d61bb5324a5` |

## Follow-up planned at close of the first run

The recorded next step was to run the corrected proposal against its committed
source and new execution approval, retaining the unchanged prompt candidate.
That separate run is now
[complete](identification-sol-rank-comparison-results-2026-09-29.md). Never edit
or resume the stopped packet. The source audit itself contained no dispatch
authority, and no additional provider call occurred during preparation.

A coverage gap should be `not_assessable / insufficient_reference`. Record an
explanation failure only when a resolved observation or a reviewed diagnostic
requirement supports that judgment. If new evidence exposes an inadequate
reference after execution, append an adjudication and retain the original
journal. Do not tune a prompt to hide a reference defect.

Production rank/enrichment contracts, model selection and confidence thresholds
remain unfinished. This one request supports none of those activation decisions.

## Evidence and validation

Execution source: `ca6efbc37e6301ea411f73014a823f8e4d0e34bf`.

Run digest: `ad3f9d2570a8c53658f27b3e5e6b9dae5788ac0ae4f6924b90ccbb65a82e3cbe`.

Private audit packet: `2026-09-29-sol-rank-reference-audit-v1`.

Adjudication file SHA-256:
`b8896173448f9a97bce6980d42469c8ef1ad90c01928a9f1fe5a1c1a1fa0303f`.

Prospective facts file SHA-256:
`7473432d68ce8c8e85ebd7e1192b29edd0c60671cab78bcb3547a67e762d8f36`.

The audit verified fourteen frozen files and all twelve media digests unchanged.
An independent read-only contract review confirmed the reporting distinction and
source-binding requirements. No additional provider call or production mutation
occurred during the audit. Software gate evidence from the controller
implementation remains in the parent plan; it is not biological-quality proof.

The reporting change passed the complete `make test-supabase-tooling` gate,
including recursive Deno type checks, 470 tooling tests and 103 isolated
evaluation tests, plus DTO, contract, secret-literal and shell checks. The two
new regressions cover limited-reference interpretation and byte-for-byte
preservation of a stopped legacy journal after admission inputs change.
Repository Markdown formatting, the exact recursive Functions/scripts format
gate, changed-file lint and diff whitespace checks passed. These checks use
synthetic evidence and do not call an AI provider. No SQL, iOS runtime or
production Edge Function changed, so database, iOS and hosted deployment checks
were outside this change.
