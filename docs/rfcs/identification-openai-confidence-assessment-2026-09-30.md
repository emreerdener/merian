# OpenAI identification confidence assessment

Date: 30 September 2026

Status: Implemented locally; development collection completed with no eligible
cutoff. The 100 held-out cases were not dispatched; retain 0.95/0.60 without
qualification. See the
[results record](identification-openai-confidence-results-2026-09-30.md). Reader
distribution and backend activation remain pending.

## Meaning and scope

Confidence means the model's estimated likelihood that the displayed
identification is correct at the taxonomic level actually named. Keep the
percentage heading (for example, “84% confident”), Strong / Possible / Weak, the
identification explanation format, and one identification call per observation.
This study concerns named biological identification reliability; nonbiological
decisions and abstentions are reported separately.

`openai_identify_vision_confidence_v1` preserves the released observed-traits
instructions. Its OpenAI-only instruction and confidence-field description
remove the blanket 70–88% range and conflicting diagnostic anchors. Missing
diagnostic evidence and plausible competitors matter; uncertainty about finer
details or the required alternatives does not automatically penalize a supported
identification. Geography and season keep their tie-breaking role, without an
automatic confidence bonus. Model, generation settings, moderation, explanation
format, field shape, stored scores, Gemini behavior and historical requests stay
unchanged. `openai_unqualified_v1` remains in force.

The prepared builder is `openaiPhotoConfidence.ts`; it derives the request from
the production photo builder and changes only these two confidence directions.
Its evaluation-only binding cannot pass current production admission. Transport
tests intercept the actual request and verify settings, evidence, schema shape,
observed traits and moderation. This implementation does not activate it.

`ConfidenceHeader.swift` replaces only its explanatory body with:

> Naturebook’s confidence score is the AI model’s estimate of how likely the
> identification is to be correct, based on the available identification
> evidence.

The percentage heading, typography, spacing and layout are preserved. A
successful badge study does not calibrate each individual percentage or qualify
automatic verification, rewards, sharing, candidate suppression or public
metrics.

## Frozen evidence and scoring

References describe what the supplied images support. Known source identity,
model agreement and user confirmation alone do not prove image answerability.
Use independently supported, reviewed references and recipient-specific asset
rights. The confidence-specific `openai_confidence_corpus_v2` records
`source_grounded_visibility_v1`: separate source, reference and exact-image
answerability records, independent supporting evidence references, and an honest
automated reviewer reference. It reports `independentHumanValidation: false`.
The older formal Gemini baseline's two-person review rule does not apply to this
solo-owner study. Unknown or unverifiable references are ineligible before
freezing. Reviewed genus-only and unresolved conclusions are eligible cases.

Source records retain asset-level rights, source identity/revision and
final-byte hashes. Reference records link independent identity evidence; a file
title or model agreement alone is insufficient. Answerability records inspect
the exact prepared pixels, list visible traits and missing diagnostics, and
justify the accepted rank or unresolved conclusion before provider collection.
Keep source identity separate from what this particular image supports.
Automated visibility review is not independent human validation or evidence of
biological truth by itself. Missing source support cannot be repaired with
invented reviewer IDs.

The first local implementation inherited two reviewer IDs from the separate
formal baseline. Corpus v2 corrects that mismatch before any live confidence
collection; v1 records are rejected rather than silently reinterpreted. The
historical evaluator and its formal-review requirement remain unchanged.

Resolve returned scientific names only through `evaluation_taxonomy_v2`: exact
canonical names or frozen, unambiguous synonyms map to canonical IDs and ranks.
Normalization of case, Unicode and whitespace does not infer identity. Unknown
or ambiguous names stay unmapped, with no rank. No fuzzy parsing, live lookup,
model adjudication or new primary-rank response field is introduced.

| Outcome                                                                        | Scoring                                                                                                                                                 |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supported name or unambiguous synonym                                          | Correct only when canonical ID and rank match a predeclared acceptable answer.                                                                          |
| Broader name                                                                   | Correct only when explicitly accepted before collection; report its resolved rank.                                                                      |
| Unsupported specificity                                                        | Unsuccessful even if the asserted species is the photographed organism.                                                                                 |
| Reviewed genus-only or unresolved reference                                    | Retained in the study and its scheduled denominators.                                                                                                   |
| Abstention                                                                     | Appropriate only when unresolved output is permitted and subject classification agrees; otherwise a missed answer. Excluded from named-confidence bins. |
| Nonbiological control                                                          | Correct rejection contributes to subject accuracy. A named biological assertion fails and enters Strong errors when its raw score reaches the cutoff.   |
| Unknown or ambiguous mapping                                                   | Named, unverified outcome without canonical identity/rank; no correctness credit, retained in named/Strong denominators and separately reported.        |
| Refusal, invalid output, operational failure, uncertain execution, unattempted | Distinct outcomes retained in scheduled coverage/yield/failure reports. No invented score.                                                              |

Do not replace failed attempts, remove difficult observations, revise acceptable
answers or extend the study after seeing results. A later invalid reference
makes the threshold decision ineligible. Preserve the frozen corpus; record an
invalidation separately, rather than silently editing labels or removing a case.

## Sampling and decision protocol

Use 200 distinct still-photo observations without description text, split into
100 development and 100 held-out validation cases. Freeze permitted region/month
context with each observation. The mixture is diagnostic, not estimated traffic.

| Exclusive category                                | Development | Validation |
| ------------------------------------------------- | ----------: | ---------: |
| Clear, species-answerable                         |          20 |         20 |
| Species-answerable lookalikes                     |          20 |         20 |
| Limited: 10 genus-only and 10 reviewed unresolved |          20 |         20 |
| Species-answerable indoor/cultivated plants       |          20 |         20 |
| Nonbiological controls                            |          20 |         20 |

Each of the first three categories contains five plants, five fungi, five
invertebrates and five vertebrates per split. The seeded allocator uses
`20260930`, canonical group ordering and the existing deterministic PRNG. It
keeps related subjects/crops/near-duplicates in one split while satisfying all
quotas; impossible clustering fails instead of leaking groups. Supplied plant
examples need independently supported references and `developmentOnly: true`.
This flag keeps their entire group in development. Exact duplicate asset hashes
are rejected. The parser verifies that frozen membership reproduces the seeded
allocation; a separate seeded order determines dispatch within each split.

All bins and comparisons use raw scores before display rounding. Fixed bins are
`[0,.60)`, `[.60,.70)`, `[.70,.80)`, `[.80,.90)`, `[.90,.95)`, `[.95,1]`.

- Named precision: correct accepted named answers / all named answers.
- Strong precision: correct accepted Strong answers / all Strong named answers,
  including mapping failures and named false biological assertions.
- Overall Strong coverage: Strong named answers / all scheduled cases.
- Biological answer coverage: named biological answers / all
  reference-biological cases. Correct-answer yield uses correct named answers
  with the same denominator.
- Subject accuracy: correct subject classifications / all scheduled cases.
- Report abstentions, unsupported specificity, ambiguous/unmapped identities,
  technical outcomes and cost completeness separately.

Strong errors are partitioned into mapping failures and mapped incorrect
identifications; named outcomes have the corresponding separate counts. An
unverified mapping is not presented as a demonstrated taxonomic error.

Report aggregate, category, reference rank and resolved returned rank
breakdowns, including unmapped/ambiguous groups. Every proportion has numerator,
denominator and two-sided 95% Wilson intervals. Zero denominators are “not
estimable.”

On complete development results, select the lowest cutoff in `0.61...1.00` at
increments of `0.01` with at least 40 Strong predictions and 95% observed
correctness. Durably freeze that one choice and its development-result digest
before any validation call. Adopt it only after complete validation also has at
least 40 Strong predictions and 95% observed correctness. Report uncertainty and
coverage; the rule deliberately does not require a 95% lower confidence bound.

If development has no candidate, stop without collecting validation. Incomplete
collection, invalidated references, unresolved cost accounting or failing
validation retains `0.95`; Possible remains `0.60`. Do not search validation for
another cutoff, change the prompt or expand the study. Passing supports observed
performance on this mixture, not population accuracy of at least 95%.

## Execution, budgets and evidence

The separate report contract is
`identification_openai_confidence_assessment_v1`. The historical evaluator and
its disabled OpenAI confidence bins/Strong metrics are unchanged. Requests use
the candidate production-equivalent builder, production adapter decoding and
pure normalization. References and taxonomy never enter provider input.

One private study directory owns both splits and all attempts. Hash the actual
requests/settings, corpus, taxonomy, protocol, source graph, reviewed pricing
and selected cutoff. A frozen manifest prevents resume under changed inputs,
pricing or source. Attempts store bounded outcome, canonical identity, rank, raw
numeric score and accounting only; never media, explanations or credentials.

`confidence-evidence.json` freezes the actual source, reference, answerability
and independent diagnostic records under `openai_confidence_evidence_v1`. Case
records bind their final asset hashes and accepted reference; independent
records retain public source/revision references and reviewed diagnostic facts.
Preparation rejects missing or inconsistent links and manifest v2 hashes the
complete bundle. Resume and each dispatch recheck its content, so opaque record
IDs cannot hide changed evidence. Only the digest enters the report.

Live dispatch applies the existing evaluator's seven-day pricing freshness
convention and rejects future-dated pricing. Expiry stops new attempts without
changing reservations or preventing offline reporting. It does not authorize
replacing a frozen pricing snapshot or restarting the study budget. The scoped
existing OpenAI key workflow is unchanged.

The original hard limits are 200 attempted requests and $10 across both splits.
The later owner-approved $20 continuation is specified below; the frozen
protocol remains intact. Before
dispatch, fsync an exclusive claim reserving reviewed maximum input and billable
output cost, including reasoning tokens. The current pricing contract reserves
the full model input-context ceiling, not a bytes-to-tokens guess. Reconciled
cost plus outstanding reservations plus the next reservation must fit the
effective cumulative cap ($10 without a continuation, $20 with one). Charge all
input at the highest reviewed rate without assuming a cache discount; output
already includes reasoning and is not charged twice.

Failures and uncertain executions consume a request. Required
missing/contradictory usage, unknown execution or unpriced model/tier retains
the reservation and stops dispatch. A reviewed provider-billing reconciliation
can settle cost; it cannot rewrite the outcome or permit another attempt. Claims
use exclusive creation and file/directory sync; the study uses a process lock.
Torn/altered artifacts fail closed. No retries, replacement observations, new
run ID to reset budgets, or automatic expansion is supported.

### Accounting correction and explicit continuation

On September 30, the first request completed with a normalized identification,
but its v1 cost projection returned unknown. The old record did not retain
numeric usage, so it cannot establish which field caused the stop. A genuine
provider usage/billing receipt was required before another call; the result,
score and consumed request cannot be replaced. The supplied usage export and
matching one-minute provider UI bucket subsequently resolved the accounting hold
with a $0.03499 upper cost allowance. The immutable continuation was prepared
with one consumed attempt and ordinal 2 next; the release record retains its
hash and source identity.

The zero-only cache-write condition was overconstrained:
[OpenAI documents positive cache-write counts](https://developers.openai.com/api/docs/guides/prompt-caching).
The corrected assessment accepts valid nonnegative counts with cached plus write
tokens no greater than input tokens. An omitted optional write count remains
null and is conservatively bounded by charging every input token at the maximum
reviewed rate, including cache writes. No zero is invented. Explicitly
malformed/contradictory writes, missing required token totals, unknown
model/tier or uncertain execution still retain reservations and stop dispatch.
Historical adapters remain unchanged. New `openai_confidence_result_v2` records
retain only bounded numeric accounting facts alongside the existing observation;
readers recompute their upper cost and continue accepting immutable v1 results.

The owner explicitly permitted a higher budget; this correction uses **$20
cumulative**, with **200 total attempts** unchanged. Offline
`prepare-continuation` exclusively creates `openai_confidence_continuation_v1`
after genuine predecessor reconciliation. It binds the original manifest/source
digests, complete replacement source identity, authorization/review references,
fixed cumulative cap, original attempt limit, reconciled journal prefix and next
ordinal. The prefix digest covers exact bytes of existing
claims/results/reconciliations, including absent results where appropriate.
Reconstruct and match corpus, taxonomy, evidence, pricing, protocol, order and
every request/settings digest before accepting it.

The continuation uses the same directory and original claim format. The old
manifest, claims and results are never overwritten. Dispatch starts at the next
unclaimed original case, counts all prior cost and attempts, rechecks the prefix
and replacement source on resume, and still stops on unreconciled usage. The
report retains original hashes and adds continuation/execution-source hashes.
This correction changes accounting only, not sampling, prompt, generation,
normalization, scoring, selection criteria or the frozen possible/strong rules.

See the
[tooling instructions](../../services/supabase/scripts/identification_evaluation/README.md#openai-confidence-assessment)
for local preparation, execution and reconciliation files.

## Reader-first acceptance and release

`InferenceConfidencePolicy` maps each exact production profile separately:

| Prompt                                      |                                   Strong | Possible |
| ------------------------------------------- | ---------------------------------------: | -------: |
| `openai_identify_vision_v1`                 |                                     0.95 |     0.60 |
| `openai_identify_vision_observed_traits_v1` |                                     0.95 |     0.60 |
| `openai_identify_vision_confidence_v1`      | Selected cutoff, currently fallback 0.95 |     0.60 |

All other provenance checks remain exact. Unknown/altered provenance keeps Needs
review. Only the revised profile's constant may change following the assessment.
Wire/persistence/reopening/history tests cover both sides of each boundary,
exact boundaries, percentage-rounding crossings and preservation of the raw
score. Automatic confidence policies remain unqualified.

Distribute the final iOS mapping and explanatory copy first. Record its exact
version/build verified on a device, with restored historical results and a
revised-profile fixture. Capability versions 4/5 do not distinguish these prompt
revisions and cannot substitute for installed-reader evidence. Older readers may
still show Needs review. Then request backend activation explicitly, naming the
target, and use the normal exact-SHA release procedure. Archive/upload remains
owner-handled. No audio evaluation is included.

Current evidence: a separate 200-photo reference packet passed offline
preparation on September 30, with the exact 100 development/100 held-out
allocation and category/rank quotas. Its source-supported automated review,
taxonomy, pricing and production-equivalent request hashes are frozen; the
earlier exploratory packets retain their provisional status. Development
collection completed with 99 normalized results and one invalid output across
100 attempted cases. No candidate cutoff met both development requirements, so
the 100 held-out cases remain unattempted. The provisional threshold stays
0.95/0.60; it is retained by fallback, not qualified by this study. The
[results record](identification-openai-confidence-results-2026-09-30.md) reports
the measured precision, mapping failures and uncertainty. The
[release record](../release-evidence/openai-confidence-assessment-2026-09-30.md)
records the freeze, completed development stop and remaining installed-reader
evidence. All attempted costs are reconciled, with a conservative total of
$3.512790008. No further paid collection is scheduled under this assessment.
