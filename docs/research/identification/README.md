# Identification research

This is the starting point for Naturebook identification research across photos,
audio, text, models, prompts, preprocessing and confidence. Last reconciled: 1
October 2026, with completed reasoning-comparison results through 3 October.
This hub records decisions supported by completed evidence; it does not attest
to the current hosted deployment.

## Where to start

- [Task-to-model capability matrix](capabilities.md): current evidence and gaps
  by job, with exact or explicitly incomplete configuration identities.
- [Benchmark qualification contract](benchmark-contract.md): held-out evidence,
  acceptance criteria and the boundary between qualification and product
  assignment.
- [Experiment register](experiments.md): questions, configurations, outcomes,
  limitations, costs and decisions, with links to original records.
- [Dataset and exposure register](datasets.md): dataset families, reuse and
  answerability limits. Actual per-observation eligibility comes from private
  manifests and claims, not this summary.
- [Research procedure](procedure.md): how to select, freeze, execute and close
  an experiment using the existing evaluator.
- [Catalog](catalog.json): authored source for both registers. Regenerate with
  `make generate-identification-research`; check with
  `make validate-identification-research`.
- [Evaluation skill](../../../skills/merian-identification-evaluation/SKILL.md):
  task guidance for agents. Historical evidence stays in the linked reports.

## Current decision

Keep the released Sol-low photo configuration described in the
[30 September activation record](../../release-evidence/openai-confidence-activation-2026-09-30.md).
Verify implementation and deployment evidence separately before asserting what a
live environment runs. The evaluation baseline uses the confidence photo prompt;
older Sol studies used different prompts and private profiles.

The
[60-observation comparison](../../rfcs/identification-photo-provider-decision-2026-10-01.md)
measured 45/60 supported outcomes for released Sol, 49/60 for Gemini Pro and
47/60 for the evidence-limit candidate. Neither challenger met the frozen
superiority rule. Failure to demonstrate superiority does not establish
equivalence.

The subsequent
[explicit-primary screen](../../rfcs/identification-photo-primary-screen-2026-10-01.md)
improved supported outcomes from 7/20 to 11/20 on selected exposed cases,
including four genus-reference gains. It failed its advancement criteria: one
species regression, one historical gain not retained and no appropriate
abstention on six unresolved cases. The run and its budget are closed. It did
not change production.

The
[confidence development assessment](../../rfcs/identification-openai-confidence-results-2026-09-30.md)
selected no qualifying cutoff. Existing confidence thresholds have not gained a
calibration guarantee from any later model comparison. Audio results also have
their own input/reference limitations; photo outcomes cannot qualify audio.

## Next justified question

The owner's everyday-regression report motivated the completed
[matched reasoning-effort comparison](../../rfcs/identification-reasoning-tradeoff-2026-10-02.md).
On 3 October all 60 calls completed: low 10/20 supported outcomes, medium 9/20
and Gemini 10/20; mean provider times 6.732, 10.961 and 15.542 seconds. Medium
passed the speed gate but had no gains, one unmapped regression and no library
improvement. It did not advance. The $2.335830008 run has zero outstanding
reservations and its remaining allowance is closed. No production change.

The two admitted library plants were solved by every arm; four ambiguous library
groups remain reference holds. Neither admitted case was a confirmed
owner-reported failure. Keep low reasoning and establish supported references
for actual reported regressions before more provider/reasoning comparisons. This
narrow development result does not establish equivalence or settle the owner's
experience. The current evidence does not justify medium or a Gemini switch.

The broader research question remains:

Investigate whether insufficient distinguishing evidence can be recognized
reliably, while retaining species identification when the evidence supports it.
The [gap audit](../../rfcs/identification-calibration-gap-audit-2026-10-01.md)
and latest failed screen motivate this question. No new candidate, paid run,
model switch or confidence threshold is authorized by this recommendation.

The
[exact-image answerability audit](../../rfcs/identification-answerability-audit-2026-10-01.md)
reviewed all 20 exposed screen photos. Two species-reference cards assert
distinguishing detail not securely visible, and the six unresolved references do
not separately adjudicate family-level support. The original study scores remain
unchanged; these holds limit their use in a new evidence-sufficiency screen.

The subsequent
[reference adjudication](../../rfcs/identification-reference-adjudication-2026-10-01.md)
accepts 18 provisional development references and retains two explicit holds.
Three formerly unresolved cases support family answers; one species reference
supports genus instead. Two cases remain scoreable biological abstentions.
Historical scores are unchanged.

The
[offline feature-observation implementation](../../rfcs/identification-photo-feature-preparation-2026-10-01.md)
now prepares this separate 18-case reference version and both request profiles.
Its transient review contract records bounded judgments without saving model
prose. The subsequent
[collection and review workflow](../../rfcs/identification-photo-feature-workflow-2026-10-01.md)
implements bounded collection, private double coding and paired scoring. Offline
software validation establishes no accuracy benefit. The proposed 36-attempt
screen still needs an isolated freeze, current pricing, actual reviewer
assignments and a new spending authorization. A final selected configuration
needs separate confidence calibration and compatibility/release qualification.

## Authority and maintenance

`catalog.json` is the study navigation and concise summary source.
`capabilities.json` owns task/configuration assessments and generates
`capabilities.md`; `benchmark-contract.md` owns prospective qualification
requirements. Neither declares current hosted routing. Original plans, results,
manifests, claims and release evidence remain authoritative for their own facts;
resolve disagreements against those sources and record a dated correction.
Preserve historical reports and frozen artifacts. Do not move them just to make
the index look tidy.

Update the catalog when a study is proposed, frozen, interrupted or closed;
update this hub only when the current decision changes. A new identification RFC
must be linked from an experiment or the catalog's supporting-document
inventory. Unknown call counts, prices, lineage or validation status stay
explicitly unknown. Do not infer zero, independent review, fresh data, or
deployment.

The registers deliberately have no grand total or cross-study leaderboard:
repeated observations, continuations, historical comparators and differing
configurations are not interchangeable samples. Study summaries may contain
rounded costs; exact claim ledgers own financial accounting. Private data and
credentials never belong in the catalog. Retention expiration removes access; it
does not erase historical exposure or create new collection permission.

Implementation and operating details remain with the
[evaluator README](../../../services/supabase/scripts/identification_evaluation/README.md),
[provider guide](../../development-guides/22-alternative-identification-provider.md),
[testing strategy](../../development-guides/08-testing-strategy.md) and relevant
release runbooks. This hub does not replace those owners.
