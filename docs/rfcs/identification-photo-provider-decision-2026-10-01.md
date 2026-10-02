# Photo provider decision, 1 October 2026

Status: **completed; retain released Sol-low for beta**. This separately
authorized study used 220 of at most 360 attempted identifications and
$8.023640041 of the $20 additional conservative cost ceiling. The September
studies remain closed; their budgets and outcomes are not rewritten.

Follow-up: the
[offline calibration gap audit](identification-calibration-gap-audit-2026-10-01.md)
records catalog consistency, remaining observability limits and the next
implementation design. It does not change this study’s outcomes or reopen
collection.

## Morning decision

**Retain released `gpt-6-sol` with low reasoning for beta. Do not promote the
OpenAI evidence candidate or switch production to Gemini Pro on this evidence.**
The candidate improved genus support, but its validation gain was only **3.3
percentage points**, below the frozen five-point practical threshold, and it
lost three species-supported outcomes. Gemini had the highest measured supported
outcome rate, **6.7 points above released OpenAI**, but did not demonstrate
superiority under the frozen paired test. This is inconclusive, not equivalence.

All 220 scheduled calls completed once: 40 development and 180 validation.
Conservative usage-accounted cost was **$8.023640041**, with **$0 outstanding
reservations**, no technical failures, retries or replacement cases, and no
blocked work. No further experiment ran. Production remains unchanged.

### Validation comparison: 60 scheduled observations per arm

| Configuration              | Supported outcomes | Marginal 95% Wilson interval | Named precision | Correct named yield / 48 biological cases | Mean / median provider time | Accounted validation cost |
| -------------------------- | ------------------ | ---------------------------- | --------------- | ----------------------------------------- | --------------------------- | ------------------------- |
| Released Sol-low           | 45/60 (75.0%)      | 62.8–84.2%                   | 33/48 (68.8%)   | 33/48 (68.8%)                             | 6.874 / 6.871 s             | $2.244005514              |
| Gemini Pro                 | 49/60 (81.7%)      | 70.1–89.4%                   | 37/48 (77.1%)   | 37/48 (77.1%)                             | 16.092 / 16.277 s           | $2.076105003              |
| Evidence Sol-low candidate | 47/60 (78.3%)      | 66.4–86.9%                   | 35/47 (74.5%)   | 35/48 (72.9%)                             | 6.018 / 5.815 s             | $2.212358520              |

The primary includes correct nonbiological outcomes and appropriate abstention;
it is not species accuracy. Times are provider time only, excluding phone,
upload and orchestration. Gemini's observed mean was about 2.3 times the
released OpenAI mean. The conservative costs use different providers' maximum
rates, including OpenAI's regional allowance; their ordering is not a claim
about invoice or production unit costs. No explanation-quality improvement or
confidence calibration is established.

### Frozen paired comparisons against released OpenAI

| Challenger         | Both correct / both incorrect | Challenger-only / released-only correct | Difference | Simultaneous paired interval | Exact McNemar p / adjusted p | Superiority |
| ------------------ | ----------------------------- | --------------------------------------- | ---------- | ---------------------------- | ---------------------------- | ----------- |
| Gemini Pro         | 45 / 11                       | 4 / 0                                   | +6.7 pp    | −6.9 to +19.1 pp             | 0.125 / 0.250                | No          |
| Evidence candidate | 42 / 10                       | 5 / 3                                   | +3.3 pp    | −14.8 to +20.8 pp            | 0.7265625 / 1.000            | No          |

Intervals have at least 95% simultaneous family coverage under the predeclared
conservative paired method. Marginal intervals in the first table are not the
paired test. The sample supports neither a general Gemini-superiority claim nor
an equivalence claim. No new candidate-versus-Gemini confirmatory test,
alternative scoring rule or post-hoc taxonomy repair was introduced.

### Category and rank outcomes

| Supported outcomes                    | Released | Gemini Pro | Evidence candidate |
| ------------------------------------- | -------- | ---------- | ------------------ |
| Clear, /12                            | 9        | 12         | 8                  |
| Lookalike, /12                        | 12       | 12         | 10                 |
| Limited evidence, /12                 | 0        | 1          | 5                  |
| Cultivated, /12                       | 12       | 12         | 12                 |
| Nonbiological, /12                    | 12       | 12         | 12                 |
| Species-supported references, /36     | 33       | 36         | 30                 |
| Genus-supported references, /6        | 0        | 1          | 5                  |
| Appropriate biological abstention, /6 | 0        | 0          | 0                  |

All configurations named every unresolved biological case. The candidate's
broader-rank gains therefore did not solve abstention. Its one unresolved output
was an incorrect nonbiological rejection of a species-supported spider, not a
valid cautious biological answer.

### Biological failures versus mapping limits

The following rows partition each arm's failed supported outcomes. A mapping gap
is unverified; it is not automatically a wrong species. Unsupported assertions
can overlap mapping gaps, so the separate total below must not be added to this
partition.

| Failure partition                                         | Released | Gemini Pro | Evidence candidate |
| --------------------------------------------------------- | -------- | ---------- | ------------------ |
| Unmapped named outputs                                    | 9        | 5          | 7                  |
| Mapped unsupported specificity                            | 6        | 6          | 3                  |
| Broader genus where the frozen reference supports species | 0        | 0          | 2                  |
| Wrong biological/nonbiological subject                    | 0        | 0          | 1                  |
| Technical failure / unattempted                           | 0 / 0    | 0 / 0      | 0 / 0              |
| Total unsuccessful scheduled outcomes                     | 15       | 11         | 13                 |

Total unsupported named assertions, including unmapped outputs on references
requiring abstention, were **9/48**, **9/48** and **6/47** named answers. None
of the mapped failed names establishes a different, incorrect species here:
released and Gemini failures are over-specific or unsupported claims; the
candidate also returned the correct broader genus _Phallus_ instead of supported
_P. impudicus_ on two cases. Those two answers fail the frozen exact supported
rank/ID rule but are not inventions of a different organism.

Gemini's four primary gains all replace released **unmapped** answers: three
separate _Coprinus comatus_ observations (`c0004`, `c0114`, `c0163`) and the
genus-supported _Rosa_ case (`c0049`). They demonstrate better verified output
coverage under the frozen catalog, not four demonstrated biological mistakes by
released OpenAI. The unknown OpenAI names cannot be reconstructed from their
hashes. Three gains concern one species despite distinct reviewed observation
clusters, further limiting breadth of the finding.

The candidate's five gains are genus-supported cases. Two correct demonstrated
species overclaims (`c0007`, `c0021`); three replace unmapped answers (`c0049`,
`c0050`, `c0195`). Its three regressions are the two overly broad _Phallus_
answers (`c0005`, `c0006`) and the false nonbiological rejection of _Argiope
bruennichi_ (`c0013`). This tradeoff explains why development's gain did not
become a meaningful validation improvement. No reference was changed after
seeing these outputs.

At the unchanged diagnostic score cutoff 0.95, released had **3/23**
unsuccessful named answers, all unmapped; Gemini **2/28**, both over-specific
species claims on genus-supported references; candidate **5/29**, all unmapped.
The candidate also falsely rejected the spider at **0.97**. That non-named
subject error is outside the named-only high-confidence denominator and must not
disappear from the interpretation. Confidence did not establish correctness; no
badge threshold was calibrated or changed.

The new bounded name-form diagnostic recorded all named outputs as plain,
without detected qualifiers/annotations. It does not reveal their unknown names
or rule out missing synonyms, spelling issues or genuinely wrong taxa. The
privacy-preserving evaluator still limits biological conclusions about unmapped
outputs. A future separately reviewed taxonomy/identifier-capture process should
resolve that observability problem before a fresh confirmatory experiment; it
must not award retrospective credit to this run. Explicit primary rank and
biological unresolved support across normalization/readers remain a separate
contract design, not an overnight production patch.

### Practical beta and rollout decision

Retain the current released configuration and its confidence policy. Keep the
tested candidate evaluation-only. Gemini is a reasonable candidate for future
confirmation, but four mapping-dependent gains, unresolved rank failures,
assistant-reviewed references, the 60-observation diagnostic mixture and greater
observed latency do not justify switching the beta provider now. The study does
not estimate production traffic accuracy.

The concrete proposed production change for this decision is **none**. If later
evidence supports activation, the compatibility steps below identify the exact
prompt-only or Gemini-routing changes and their release requirements. Do not
silently enable the candidate because its development screen passed. No
production prompt, routing, thresholds, stored results, explanation format,
public response shape or credentials changed; no merge, deployment or app
distribution occurred.

## Diagnosis and candidate

Released photos use `gpt-6-sol`, low reasoning,
`openai_identify_vision_confidence_v1`, high image detail, 8,192 output tokens
and inline moderation. The earlier confidence development set recorded 54/60
species-reference matches, but named assertions on all ten unresolved biological
cases. Twenty of 80 named answers were unmapped; only five were mapped failures
(four over-specific species and one species mismatch). These overlapping
categories must not be added. Unknown name hashes do not establish synonyms or
correctness. The small Gemini recheck does not establish overall superiority.

One candidate, `openai_identify_vision_evidence_v1`, applies the existing
reviewed `solPhotoRankInstructions`/`solPhotoRankSchema` transformations to the
**current** production confidence builder. It removes conflicting mandatory
species/binomial and alternative-species instructions, permits supported
genus/family or unresolved answers, and requires distinguishing features to be
seen rather than inferred absent. It preserves supported species answers. No
benchmark identities enter the prompt. The model, low reasoning, moderation,
image preparation, confidence rule, explanation field/instructions, JSON shape,
and normalization remain unchanged. The older explicit-primary candidate has a
different schema and is not used.

The
[29 September rank comparison](identification-sol-rank-comparison-results-2026-09-29.md)
already tested the underlying wording on an older prompt: broader-rank behavior
improved on three challenges, but two candidate explanations contradicted
visible evidence, so it was rejected. This is not a novel wording hypothesis or
permission to revive that profile. The present screen tests whether its evidence
limits produce an actual supported-outcome benefit when composed with the
current confidence prompt on twenty exposed diagnostic cases. The earlier
failures remain a promotion risk even if the numeric screen passes; no
explanation-quality improvement is claimed from normalized identity scoring.

`openaiPhotoEvidence.ts` and its adapter have evaluation-only authority. No
production registry, routing row, deployed prompt, threshold, stored result or
reader contract changes. Native images are cropped/downsampled by iOS; this
experiment compares identical existing prepared JPEGs across providers, not the
complete phone image pipeline. No demonstrated orientation/normalization defect
justifies changing the pipeline here. The shared evaluator's mixed-image MIME
issue is outside this one-image-per-observation packet.

## Eligibility and precollection review

Reuse the prior 200-image confidence packet's supported references and frozen
reviewed taxonomy, **as a new study**, never as completion of that confidence
assessment. Its held-out assets were unattempted under its stopping rule. A scan
of 1,082 available historical JSON files outside that packet found no exact
held-out image-hash match; original claims establish 100 development attempts
and zero held-out attempts. This proves only recorded local exposure, not
absence of unrecorded or provider-training exposure.

The first hash-only audit was insufficient: final answerability records for
`c0150`, `c0151` and `c0187` still contained pending grouping notes. Unique
hashes and the old one-case group labels do not prove independent observations.
The old candidate register is provisional and has reassigned IDs, so it is not
authority for the final assets. Preserve all historical findings with this
limitation.

Before any new output, the assistant inspected contact sheets of all 200 final
images. A read-only assistant audit checked ten held-out
source/reference/license records, two per category, against public sources; the
ten sampled media records reported CC0 and their source revision IDs resolved.
This is **source-supported automated review, not independent human validation**.
It does not prove every reference biologically correct, nor supply a
reproducible original-to-prepared image derivation manifest. Existing
exact-image answerability records remain the reference basis. Any later invalid
reference defeats a confirmatory claim; accepted answers cannot be rewritten
after collection.

Conservatively exclude suspect pairs `c0150/c0151`, `c0169/c0170`,
`c0182/c0183`, `c0186/c0187`, and `c0115` (possibly related to exposed `c0116`).
Related held-out/dev puffball records are grouped conservatively as well. The
new receipt binds semantic clusters across all 200 cases and forbids a selected
validation cluster from overlapping any of the 100 exposed development cases or
another selected validation case. Cases are excluded for eligibility **before**
collection, not for difficulty or provider failure.

Freeze **60** validation observations, twelve per original exclusive category:
clear, lookalike, limited evidence, cultivated plants, nonbiological. Each of
the first three categories has three plants, fungi, invertebrates and
vertebrates. Limited evidence has six genus-only and six unresolved biological
references. This preserves the diagnostic category proportions; it is not
estimated traffic. The smaller sample weakens power and is disclosed instead of
treating suspect repeated subjects as independent. Forty original holdouts
remain unused.

The private plan binds all selected case IDs, corpus/taxonomy/evidence hashes,
original manifest and claims, exposure inventory, actual request/settings
hashes, source graph including the pre-existing uncommitted pilot work, and
reviewed prices. The owner's new authorization is recorded for both recipients
over those exact approved cases, expiring with asset retention on 22 October.
Credentials stay in process memory; each provider child receives only its own
key and API host. No source facts, reference names, filenames, description text
or location context enter the requests.

## Frozen experiment and selection

Development uses twenty already exposed cases, four per diagnostic category,
with two genus-only and two unresolved limited cases. Run released OpenAI and
the one evidence candidate once each: **40 calls**. Historical results remain
context, not substitute randomized controls. A candidate advances only with a
net gain of at least two supported outcomes, at least one newly supported
outcome that is not merely an unmapped-name or technical-failure repair, and at
most one regression on a species-supported reference. This is a screening rule,
not a confirmatory significance test. Do not revise the candidate after this
screen.

Before any validation call, durably record the development result digest and
selection. Validation compares released OpenAI against preserved Gemini Pro, and
adds the candidate only if selected. Thus the schedule has **160 calls without a
candidate or 220 with one**, below the owner's 360 ceiling. No extra development
candidate, medium-reasoning repeat, retries, replacement cases or second study
is planned. Shuffle observations with seed `20261001` using the existing PRNG
and rotate first arm by observation. The private selection list records a
separate Python seeded shuffle used for quota sampling; provider dispatch uses
the frozen TypeScript order, never runtime resampling.

Gemini retains `gemini-2.5-pro`, `identify_vision_v1`, temperature 0.1, seed 42,
8,192 output tokens, 5,000 thinking tokens and 90 seconds. Providers receive the
same pixels/context but their preserved prompts and native safety differ. This
is a comparison of product configurations, not an isolated underlying-model
test.

## Development result and frozen advancement

All 40 development calls completed with normalized results and known usage.
Released OpenAI supported 14/20 outcomes (70%; marginal Wilson 95% interval
48.1–85.5%); the evidence candidate supported 16/20 (80%; 58.4–91.9%). The
candidate gained both genus-supported limited cases, lost no supported outcome,
and had zero species regressions. Both arms retained two unmapped answers and
made named assertions on both unresolved biological cases. Thus the gains are
actual rank-support improvements, not mapping repairs, confidence inflation or
technical recovery. Neither arm demonstrated appropriate abstention here.

The fixed rule selected the evidence candidate. The development-only difference
is not a confirmatory superiority finding. The validation freeze binds all three
arms before any validation attempt, with development-result digest
`d74fdcb40c47e34999c2fa2ec4e7a2719cff2c57ef35d48a458c841c746f6277`. The schedule
is now 40 development plus 180 validation calls.

Development mean provider time was 6.520 seconds released versus 6.139 seconds
candidate; medians were 6.337 and 5.515 seconds. Conservative accounted costs
were $0.748572001 and $0.742599003, totaling **$1.491171004**. These twenty
exposed observations are excluded from validation accuracy and paired inference.

## Outcomes, uncertainty and decision

Primary: correct evidence-supported outcome per **scheduled observation**,
including an accepted canonical ID/rank, appropriate biological abstention, or
correct nonbiological rejection. Unsupported specificity fails even if source
identity happens to be that species. Unknown/ambiguous mappings receive no
credit and remain unverified, distinct from demonstrated wrong taxa. Technical
failures and unattempted cases stay in scheduled denominators; partial
collection cannot support superiority. No alternative answer rescues an
incorrect primary.

Report named precision, correct named-answer yield, species/genus and category
breakdowns, unsupported specificity, inappropriate abstention, mapping and
technical failures, timing, cost and high-confidence errors. The 0.95 diagnostic
error threshold does not change either provider's production badge policy.
Historical `correctAnswerYield` from the confidence helper is not repurposed as
the primary; `correctNamedYield` explicitly restricts the numerator to names.

Pair by case ID. For each challenger versus released OpenAI, report
both-correct, both-incorrect and each discordant count, risk difference, and
exact two-sided McNemar p. Reserve a two-comparison family even if no candidate
advances: Bonferroni p correction uses two, without recycling alpha.
Simultaneous paired difference intervals subtract Clopper–Pearson bounds for the
two discordant probabilities, each of four tails across two comparisons
receiving 0.00625. The union bound gives at least 95% family coverage. These
intervals are conservative; small samples may remain inconclusive despite a
useful point gain.

A superiority claim requires complete collection and accounting, valid
references, a point gain of at least five percentage points, adjusted p at most
0.05, and a simultaneous lower bound above zero. No third confirmatory
candidate-versus-Gemini comparison is added. Failure to establish superiority is
not equivalence. Assistant reference review and the diagnostic sample limit all
conclusions.

## Accounting and safe execution

Reuse exclusive fsynced claims, process locks, bounded production adapters,
frozen request builders, normalization, taxonomy resolution and usage
projection. One shared new journal owns both phases. Before each sequential
dispatch require settled cost plus outstanding reservations plus the next
reservation to fit $20. Failed or uncertain attempts consume their slot; unknown
usage retains the full reservation and stops. Known-accounting technical
failures remain scored failures and are never replaced. Budget headroom is a
stop condition, not a reason to lower reservations or change settings.

The [OpenAI model page](https://developers.openai.com/api/docs/models/gpt-6-sol)
was reviewed on 1 October. Retain maximum long-context/cache-write rates of $5/M
input and $15/M output, plus the 10% regional premium: reserve the full
1,050,000 input ceiling and configured 8,192 billable output, **$5.910168** per
sequential call. Reconcile every input token at that maximum rate, with
reasoning already inside billable output. No cache discount is assumed.

[Google pricing](https://ai.google.dev/gemini-api/docs/pricing) and
[model limits](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro)
support $2.50/M input,
$15/M output including thinking, and full 1,048,576/65,536 token
ceilings: **$3.60448** reservation. These deliberately conservative accounting
amounts are upper estimates, not invoices or expected production prices. Prices
expire after seven days; expiry cannot reset the ledger or permit retries.

Records retain normalized taxon IDs/ranks, numeric scores/usage/timing, hashes
and a bounded lexical name-form enum. A qualifier/annotation flag is diagnostic
only: it supplies no inferred name, rank or correctness. Old missing names
cannot be reconstructed; no retrospective credit or taxonomy update is allowed.

## Rollout proposal for review

Keep released Sol-low during this study. A successful evidence candidate would
require a new exact prompt/provenance identity, corresponding native reader
recognition before activation, unchanged V2 wire shape and historical readers,
and the existing exact-SHA release gates. Then the reviewed production photo
builder alone would select the evidence instructions/schema descriptions; no
routing, model, tier, threshold or storage rewrite is needed. Do not alias the
new prompt to the old prompt identity.

Concretely, a prompt-only OpenAI rollout can retain `openai_photo_v1`: change
the production `OPENAI_PHOTO_PROMPT` and builder in `openaiPhoto.ts`, update
request/provenance tests and deployment identity, and add the new prompt to iOS
`InferenceConfidencePolicy.openAIPhotoDisplay(forPrompt:)` with its provenance
acceptance/persistence/boundary tests. The V2 wire parser accepts bounded prompt
identifiers, but the native display allowlist recognizes exact prompt names;
without that reader update the new result falls back to Needs review. Keep old
prompt recognition for saved results. Do not route the evaluation binding into
production. A new database/quota binding is unnecessary for this prompt-only
path.

A Gemini preference instead requires the explicit photo admission/catalog change
to the preserved Gemini binding and reviewed model/tier behavior. Current Gemini
admission distinguishes Flash/Pro; this study of Pro cannot justify sending Free
photos to Flash or promising Gemini Pro to both tiers without that compatibility
work. Preserve recipient handling, native result provenance, moderation and
confidence policy; never make a client-side provider switch. Any rollout needs a
separate explicit production operation and target, followed by its canonical
reviewed deployment and rollback process. No merge, deployment, secret mutation
or app distribution is authorized here.

## Implementation verification

The primary agent is the only writing owner; pre-existing uncommitted pilot
code, documentation and CI changes were retained in the source fingerprint. The
evaluation-only adapter preserves request settings, wire schema,
explanation/confidence instructions, inline moderation and accounting.
Regression tests cover matching inputs, production non-admission, unsupported
snapshot rejection, single dispatch, missing moderation, scheduled failures,
unknown mappings, paired symmetry, candidate selection, cross-split clusters,
interrupted claims, uncertain usage, tampering, frozen selection and child
credential/host isolation. No credential or provider prose is saved.

Local gates on the frozen implementation passed:

- Edge Functions: 2,236 tests and 343 steps; 11 ignored.
- Complete `make test-supabase-tooling`: 483 standard tests/34 steps, 140
  filesystem evaluation tests/47 steps, 20 and 21 isolated DTO tests, and all 17
  discovered shell test files. It checked 123 standard TypeScript sources, 58
  standard test files and 34 shell sources. The first full run exposed a stale
  generated deployment digest; canonical regeneration corrected it before the
  final freeze. Sandboxed pseudo-terminal echo control then prevented the older
  Gemini launcher fixture; all synthetic terminal scenarios and the complete
  tooling gate passed outside that sandbox, without provider requests.
- All 103 isolated Edge Function entrypoints type-checked; all 103 config and
  dependency graphs passed, covering 406 runtime files.
- Edge DTO contract validation passed; lint checked 1,020 files.
- Recursive Functions/scripts formatting checked 1,218 files. Changed Markdown
  formatting and diff whitespace are rechecked after this report is finalized.

The generated deployment identity reflects local source only; it was not
published. No SQL, schema, native runtime or public wire shape changed, so no
new database or iOS build was required. Hosted CI and deployment were not run.

The final precollection manifest file SHA-256 is
`25f3c4bed5287148f90ba0859bee3767223704d5cf51b1149de6b5c774595796`; its source
digest is `383343f4c272707644cd305c3e68dfa31a179e55f99c7735fcb832ee34cfeddd`. An
earlier offline preflight manifest was superseded before any claim and is
retained as such; no attempted slot or budget was reset. All 80 scheduled
released-arm request hashes exactly match the earlier confidence manifest's
corresponding requests. That validates input/configuration equivalence, not
reuse of historical outcomes in the new paired experiment.

## Closed accounting and retained evidence

The final offline parser rebuilt the frozen source, inputs, requests and ledger
without credentials or network permission. A separate read-only assistant audit
verified 220 unique claims/results, 20 complete development pairs, 60 complete
validation triples, selection after the forty development results and before
first validation dispatch, unchanged reference digests and exact settlement
sums. An independent Python calculation reproduced the primary outcome counts
and per-arm settlement totals. Every result was within its original reservation.
All 220 outcomes normalized; there were zero refusals, invalid responses,
operational failures, unknown executions, retries, replacements or skipped
cases.

| Accounting                           | Final value                                  |
| ------------------------------------ | -------------------------------------------- |
| Development calls                    | 40 (20 released + 20 candidate)              |
| Validation calls                     | 180 (60 per configuration)                   |
| Total attempted / authorized ceiling | 220 / 360                                    |
| Development conservative cost        | $1.491171004                                 |
| Validation conservative cost         | $6.532469037                                 |
| Total conservative accounted cost    | $8.023640041                                 |
| Outstanding uncertainty reservations | $0                                           |
| Unused authorized allowance          | $11.976359959 and 140 attempts; study closed |
| Stop / blocked work                  | None / none                                  |
| Credential process                   | Exited successfully; no key saved            |

These are usage-based conservative upper estimates, not provider invoices.
Unused allowance does not extend this experiment. The paid launcher exited
successfully and no second study was started.

Private archival evidence is retained at
`/Users/emreerdener/Developer/merian-evaluation/2026-10-01-photo-decision-v1`.
The original authorization is bound to
`/private/tmp/merian-photo-decision-20261001/study`; the archival copy cannot be
resumed from its new path. Keep approved photos private and honor the existing
22 October 2026 retention deadline. The archive retains inputs, bounded
claims/results, frozen prices/references/selection, source inventory, the exact
1,163-file evaluated source graph, assistant clustering contact sheets and
verification logs. Credentials and provider prose are absent.

| Final artifact         | SHA-256                                                            |
| ---------------------- | ------------------------------------------------------------------ |
| Decision report file   | `44f167d697e0e3b5f17cc8df91ac5e5c3f920583819c70432c331dff1ccacbf7` |
| Validation freeze file | `c94ead3dbb3caa753c606c140396ad27d0dd5fcf5d82e67b1e298c2bde23ffc0` |
| Evaluated source graph | `383343f4c272707644cd305c3e68dfa31a179e55f99c7735fcb832ee34cfeddd` |

Final recursive formatting passed for 1,218 Functions/scripts files; changed
Markdown formatting and diff whitespace passed. Earlier failing preflight logs
remain alongside the passing final gates so they cannot be mistaken for hidden
or unresolved failures. Historical pilot work remains preserved in the working
tree. The final recommendation requires no deployment.
