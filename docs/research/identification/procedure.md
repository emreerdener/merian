# Identification research procedure

Use this with the [research index](README.md) and the specific evaluator's
checked-in contract. Scale preparation to the question; a documentation audit or
synthetic test does not require a paid-study approval flow.

## Choose the question and evidence

Read the [capability matrix](capabilities.md),
[qualification contract](benchmark-contract.md), and relevant experiment/dataset
entries before designing new work. Name the task and exact configuration whose
qualification gap the experiment will address. Identify what prior work ruled
out, what remains unknown and why another experiment could change the product
decision. Distinguish identification quality, rank/answerability, mapping,
preprocessing, latency and confidence calibration. A higher confidence score,
successful decoding or green software tests cannot substitute for
reference-supported identification quality.

Record a stable study ID, modality, hypothesis, exact model/profile/prompt,
preprocessing and context, comparator, dataset family and intended decision.
Development, validation, calibration, engineering verification and deployment
verification are different evidence roles. Label mixed or exploratory evidence
explicitly; do not retrofit confirmatory claims.

## Review data and exposure

Use existing approved assets and evidence where they answer the question. Verify
exact input bytes, related subjects/near-duplicates, source provenance,
taxonomy, reference support and answerability. State who reviewed the
references. An assistant review, owner agreement, source identification and
independent human validation are distinct facts.

Check private input/cluster manifests and every relevant attempted-claim ledger
before describing observations as unexposed. Split labels are historical; an old
held-out case used in a later screen is now exposed. Failed/uncertain attempted
calls still count as exposure. Unknown lineage is an eligibility blocker for
unexposed validation, not evidence of freshness. Do not publish raw assets,
names from private outputs, coordinates or owner identifiers in the register.

Selecting a candidate on development data and then evaluating it on genuinely
untouched validation data is the intended sequence. Exposed observations may be
reused for clearly labelled development work; that reuse cannot restore their
unexposed status.

Preserve unknown mappings as unverified; never reverse a name hash or add
aliases to award correctness after seeing an output. Keep unsupported
specificity, biological error, mapping uncertainty and technical failure
separately visible. For newly justified taxonomy corrections, version the
taxonomy and document any rescoring separately from the original frozen result.

## Freeze and execute only the authorized scope

Reuse the existing evaluator, request builders, parsers, scoring and journals.
Extend only the missing capability. Verify production equivalence rather than
assuming it from a model name; include model settings, prompt/schema,
moderation, image/audio preparation and context. Image-processing changes are
pipeline comparisons. Preserve explanation and response contracts unless the
task changes them explicitly.

Before paid collection, bind reviewed inputs, references, taxonomy, source,
pricing, ordering, scheduled observations, metrics, failure handling and the
selection/stopping rule. For confirmatory comparisons, predeclare the practical
effect, paired inference method and multiple-comparison treatment. No universal
sample size, spending cap, confidence threshold or pass rule is inherited from
an older experiment.

Use the user's existing authorization where it covers the exact operation and
scope; do not repeatedly request routine permission. A closed study's unused
budget does not fund a new one. Arrange indispensable hidden credential entry
without putting keys in chat, files or logs. Freeze the source in a suitable
checkout when the shared checkout is changing concurrently.

Use conservative pre-dispatch reservations, durable exclusive attempt claims and
existing stop/no-retry controls. Do not reset budgets, replace failures, replay
uncertain calls or tune against validation outputs. Unexpected accounting or
execution states follow the selected runner's fail-closed contract.

## Analyze, decide and close

Count scheduled observations and paired outcomes, retaining abstentions,
nonbiological controls and technical failures. Report category/reference-rank
breakdowns, verified named yield, unsupported specificity, mapping failures,
latency, known costs and outstanding reservations. Report uncertainty
appropriate to the design; acknowledge selected diagnostic mixtures and small
samples. Model superiority, calibration and production readiness require their
own supporting evidence.

Write the decision even when the experiment fails or is inconclusive. Preserve
exact source, manifests and ledgers in the approved private archive with
recorded retention. Record exact calls, retries, settlement and unresolved
reservations; close the study without implying permission to spend the
remainder. Update the catalog's study, dataset lineage and source links, plus
the affected task/configuration assessments in `capabilities.json`, then
regenerate the registers and capability matrix. A stopped study may retain
unknown financial liability and must say so.

Keep implementation tested, production integration reviewed, deployment executed
and runtime behavior verified as separate states. Use the relevant
implementation skills for code and the release skill only for an explicitly
authorized operation and target. Documentation organization alone starts no
provider calls or releases.

## Verification and record updates

Edit `catalog.json` and affected `capabilities.json` assessments, preserving
unknown values as `null` plus an explanatory note. The
[qualification contract](benchmark-contract.md) owns required benchmark records
and public commitments for a qualification; an experiment result alone must not
create one. Every entry requires source links; summaries remain qualified by
those sources. Link plans/results that describe the same study in one entry; use
separate IDs for separately frozen comparisons, and note overlapping calls/costs
rather than summing them. Dataset family entries summarize lineage without
declaring every case eligible for reuse.

Run `make generate-identification-research`, format changed Markdown, then run
`make validate-identification-research` and `make validate-markdown-format`. The
catalog check verifies structure, unique IDs, references, dataset links, RFC
coverage, task/configuration/evidence commitments and generated register/matrix
freshness; it cannot certify biological truth, exposure from private ledgers,
deployment or billing. Skill changes also require `make validate-agent-assets`.
Runtime code changes require the relevant full surface gates in addition to
catalog checks.
