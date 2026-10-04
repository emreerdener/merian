# Benchmark qualification and model assignment

The [capability matrix](capabilities.md) answers which evaluated configurations
have useful evidence for which identification jobs. Its authored source is
[capabilities.json](capabilities.json); the [catalog](catalog.json) owns the
linked studies and dataset families. This contract owns prospective
qualification rules. Original frozen protocols and results retain authority over
historical decisions. Nothing here changes an old score, starts collection or
activates routing.

## Unit of qualification

Qualify a **task, exact configuration, input pipeline and benchmark version**
together. A model name alone is insufficient. Record provider,
returned/requested model, native profile if present, binding, prompt/schema,
reasoning and token settings, safety behavior, preprocessing, context,
reference/taxonomy version and frozen request/source digests. Historical study
manifests own identity; do not resolve an old study against a changing current
production registry.

The initial matrix covers photo identification, visual evidence sufficiency,
photo confidence, photo explanation grounding, audio, descriptions and video.
Operational reliability, latency and cost are assessed within each task. Field
Chat and other generative jobs need their own task contracts and evidence; these
identification results do not qualify them.

Distinguish five facts:

| Fact                       | What establishes it                                                   |
| -------------------------- | --------------------------------------------------------------------- |
| Implemented                | Executable code and relevant software verification                    |
| Studied                    | Actual attempts and a bounded, reconciled outcome record              |
| Qualified in scope         | A reviewed decision against a prospectively frozen benchmark protocol |
| Assigned to a product task | A separate reviewed routing/configuration decision                    |
| Deployment verified        | Exact release and hosted/runtime evidence                             |

The matrix records research decisions and qualifications only; it does not
attest to current production assignment or deployment. A retained baseline is an
operational recommendation under uncertainty, not a qualification. A failed
screen limits that configuration in that study; it does not prove the model is
incapable of all related tasks. An unlisted configuration is unassessed, never
implicitly qualified.

## Three different uses of benchmark data

1. **Development/regression:** exposed examples for diagnosis, candidate design
   and reproducible regressions. Small difficult-case sets are useful here.
   Repeated calls measure variability within a subject; they do not create new
   independent observations.
2. **Qualification:** an untouched, reference-supported set for the selected
   candidate and frozen decision. Audit source-subject and near-duplicate
   clusters across all prior ledgers, not just byte hashes or old split names.
   Once outcomes inform decisions or tuning, record that exposure and retire the
   set from fresh confirmatory use.
3. **Calibration and calibration validation:** separate data after selecting the
   identification configuration. Choose confidence rules using calibration data,
   then evaluate the frozen rule on untouched validation. Confidence transfer
   between models, prompts, ranks or modalities requires evidence.

Version case membership, taxonomy, reference judgments, preprocessing and
protocol separately. Preserve original keys and scores; corrections create a new
version and explicit rescoring record. No finite local audit proves absence from
a provider's training data. State the actual exposure claim.

## Freeze a task contract before collection

Every prospective qualification protocol must fill these fields. A missing field
blocks qualification; this document does not supply universal sample sizes,
thresholds or spending authority.

| Field                | Required content                                                                                                                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Decision and scope   | Task, candidate/comparator, intended input population, supported ranks/states, product use and explicit exclusions                                                       |
| Exact identity       | Full configuration tuple and request/source digests; explain every pipeline difference                                                                                   |
| Data and references  | Benchmark version, membership/reference/taxonomy digests, provenance, retention, cluster/split audit, reference reviewer provenance and unresolved holds                 |
| Primary endpoint     | One scheduled-observation outcome and denominator, including unattempted/failed calls; distinguish supported outcomes from species accuracy                              |
| Guardrails           | Unsupported specificity, false abstention, subject errors, named precision/yield, mappings, technical failure, explanation/safety criteria and required per-group minima |
| Decision rule        | Practical effect or noninferiority margin, paired interval/test, multiplicity treatment, target power/precision and cluster-aware sample-size justification              |
| Operational envelope | Provider and end-to-end latency separately, tail latency/timeout ceilings, accounted cost and reservation basis; same comparisons on matched inputs                      |
| Review procedure     | Model/arm/outcome blinding where feasible, diagnostic cards, rubric, reviewer qualifications/independence, agreement and predeclared dispute policy                      |
| Execution boundary   | Attempt ceiling, exact authorized cost ceiling, conservative reservation, fixed order/seed, no retry/replacement, incomplete-run and stop policy                         |
| Closure              | Exact ledger/accounting, uncertainty, all guardrail results, limitations, qualification decision and separate release implications                                       |

For photo identification, keep biological error, unsupported rank, insufficient
evidence, unknown taxonomy mapping and technical failure separately visible. A
mapping-dependent gain is improved verified yield, not proof of a corrected
biological mistake. Appropriate abstention and correct nonbiological rejection
belong in the primary endpoint, with separate denominators.

For explanation and evidence judgment, fluent or plausible prose is not visual
support. A correct name cannot excuse invented traits. Assistant review is
labelled as such; two browser slots do not establish two independent people. The
feature development screen's conservative double coding is a specific
prospective protocol, not independent expert validation.

For audio and video, adjudicate what is supported by the actual model-visible
clip or frames. A source caption or visible animal outside the supplied audio
cannot establish the audible species. Different context or DSP makes a pipeline
comparison, not an isolated model/prompt effect.

Numeric cost and latency values in the initial matrix belong to their historical
studies. They are not current prices, invoices or forecasts. Update pricing
through the existing evaluator before a new authorized run.

## Qualification record and maintenance

Every current matrix assessment has a decision, linked study IDs, limitations
and an explicit nullable qualification. None of the initial rows is qualified in
scope. Null means no established qualification, not a hidden pass.

A future `qualified_in_scope` row must link a completed validation study and
separate prospective protocol and qualification decision records. Qualification
requires provider-attempt validation of the exact task modality; mixed
historical studies remain usable only as limited nonqualified evidence. Record a
benchmark version, configuration/corpus/reference digests and an indexed
exposure-audit source. Bind these to a versioned public JSON record under
`docs/research/identification/benchmarks/`, indexed by the same study, with
`benchmarkRecordSource` and its canonical `benchmarkRecordDigest`. The record
has version 1, benchmarkVersion, taskId, configurationId, taskContractDigest,
configurationDigest, corpusDigest, referenceDigest, studyId, protocolSource,
exposureAuditSource and decisionSource. Its corpus/reference digests are copied
from the actual reviewed private freeze; never place those private contents
here.

The qualification and benchmark record also pin a task-contract digest: the
canonical task ID, modality, primary metric, coverage and qualification
requirements. Changing these rules invalidates the qualification; changing the
display title or next action does not.

The configuration digest is the SHA-256 of the canonical public configuration
tuple (all fields except navigation ID and study links), using recursively
sorted object keys as implemented by the generator. Exact native request/source
digests remain in the linked frozen protocol. The validator recomputes this
configuration commitment, hashes the public benchmark record and requires the
qualification's task/corpus/reference/identity fields to match that record.
Changing a configuration or record invalidates the existing qualification. The
precollection record pins the intended decision-document path; the decision is
written after collection and must be separate from both the protocol and
exposure audit. Preserve accepted records; changes require a new version and
review. These checks detect inconsistent metadata; they do not authenticate the
private freeze or prevent an authorized author deliberately rewriting every
record.

The reviewed decision must show all frozen thresholds, uncertainty and
guardrails, assess reference quality, and state its exact scope. A calibration
study that selected a cutoff is not its independent validation.

The validator enforces metadata structure, configuration/study/task links,
modality compatibility, completed validation provenance and source membership.
It cannot read a PDF and prove a claim, authenticate reviewers, certify private
exposure or verify biological truth. A syntactically valid record is not
automatically scientific qualification; the referenced review owns that
decision.

Missing legacy identity fields stay null and block qualification. Where a native
snapshot has no profile field, `not_applicable` may be recorded explicitly with
that reason; do not invent a native profile. Existing rows preserve their
historical identities even when current production keys change.

After a study closes, update its catalog entry and the affected capability
assessments, with explicit scope and unknowns. Run
`make generate-identification-research`, then
`make validate-identification-research` and Markdown formatting. Generated
registers and the capability page must agree with authored JSON. CI uses the
existing Agent Quality research gate. Keep credentials, private outputs, media,
coordinates and personal reviewer identities outside this public metadata.

## Turning evidence into assignments

Choose among configurations that meet the task's quality and reliability
requirements, then compare cost and latency within that eligible set. A cheaper
model cannot compensate for failing an essential quality guardrail. A more
expensive model or subscription tier is not evidence of better identification.

Conditional routing needs its own evaluation. The router must select using
information available before the answer is known, such as modality or a
separately validated input-quality signal. Do not construct an oracle that picks
whichever model was correct after seeing benchmark labels. Evaluate the full
router, fallback and any additional calls on untouched data, including their
cost, latency and errors. Confidence alone is not a validated difficulty signal.

Requalification is needed when a material model, prompt, schema, preprocessing,
context, taxonomy/reference or routing change invalidates the old scope. Retain
historical records and repeat qualification on a fresh eligible set; never
repeatedly tune against a once-held-out leaderboard.

## Current work order

Update, 3 October: the
[matched low/medium/Gemini development comparison](../../rfcs/identification-reasoning-tradeoff-2026-10-02.md)
is complete and closed. Medium met the speed gate but failed quality advancement
with zero gains and one mapping-dependent regression; low and Gemini tied on
supported count. Retain low and obtain supported references for actual reported
regressions while pursuing the visual-evidence sufficiency question. The two
admitted library plants do not resolve the four ambiguous reference holds. No
configuration gained qualification and no paid allowance remains open. Fresh
validation, calibration and separate release requirements still apply.

1. Maintain this matrix and preserve the current released-photo recommendation.
   No challenger has established the required advantage.
2. Complete the separately frozen feature-observation development screen when
   its collection prerequisites and spending authorization are satisfied. Its 18
   exposed photos cannot become the final qualification benchmark.
3. If a candidate passes its existing hurdle, audit approved assets for genuine
   remaining eligibility and independent reference support. Freeze task-specific
   numeric acceptance criteria and sample size before any validation output.
4. Run and close that one qualification experiment under its bounded
   authorization, accepting an inconclusive or negative decision.
5. Calibrate confidence only for the selected configuration on separate data.
   Qualify any proposed task routing and complete compatibility/release review
   before activation.

This order makes each experiment answer a product decision instead of producing
a general model ranking. The research framework approval creates no new paid
attempt allocation and does not reopen closed budgets.
