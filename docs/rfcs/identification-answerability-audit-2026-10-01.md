# Photo answerability audit and experiment decision — 1 October 2026

Status: offline review complete. **Do not start another paid screen with the
existing references.** Resolve the reference issues below before freezing an
evidence-sufficiency experiment. Keep released Sol-low and current confidence
thresholds. This audit made zero provider calls, incurred zero provider charges,
and changed no application behavior, historical scores or accepted answers.

## Decision and evidence boundary

The [explicit-primary screen](identification-photo-primary-screen-2026-10-01.md)
failed its frozen rule. Its 7/20 versus 11/20 supported outcomes remain
historical measurements against its original references. The new review finds
that those references need work before they can qualify a detector of
insufficient evidence:

- Two of seven species controls have a material mismatch between their
  answerability notes and visible distinguishing features.
- The six unresolved references do not separately establish that a family-level
  answer is unsupported. They are not six established examples where every named
  answer must be rejected.
- Several other notes describe features outside the supplied crop, or reuse
  wording despite different views. These are reference-quality issues, not
  demonstrated input-preparation defects.

These findings justify reference repair first. They do not retrospectively award
the failed candidate a pass, establish that its unknown names were correct, or
demonstrate a better production model. The previous failure to establish
superiority remains; current evidence is insufficient for promotion.

The assistant inspected the exact final pixels for all 20 exposed screen cases,
checked all 20 asset SHA-256 values, compared the original source-grounded
answerability cards, and read the bounded result journals. This review knew
prior outcomes; it is neither blinded nor independent human validation. Public
diagnostic sources support comparisons, not the identity of a particular photo.
The
[case-level review](../research/identification/answerability-review-2026-10-01.json)
retains asset hashes, original references, evidence IDs, observations and holds.
It is an audit artifact, not a runnable corpus or replacement answer key.

Private evidence remains in the completed `2026-10-01-photo-primary-screen-v1`
archive, under `study/`. The review used its identical live-packet copies. Byte
hashes in the case review are file-byte hashes; they are deliberately distinct
from the evaluator's canonical JSON fingerprints. Images, private provider prose
and credentials are not copied into the repository.

## What the six unresolved photos actually show

| Case  | Visible evidence and limitation                                                                                                               | Consequence for the next reference                                                                                                      |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| c0027 | Compound white umbels; main stem hairs, blotches and complete bracts are not resolved. The old card's divided foliage is not clearly visible. | Species exclusion is plausible. Evaluate a supported family independently; do not infer that no rank can be named.                      |
| c0031 | Zoned brackets, curled edges and some pale surfaces; diagnostic pore detail is not resolved.                                                  | Distinguish a missing view from an available but insufficient view. Review whether any allowed named rank is established.               |
| c0032 | Small zoned brackets on wood, mainly upper and oblique surfaces; underside texture and reactions are not established.                         | Visual resemblance does not settle the fungal group. Review broader-rank support explicitly.                                            |
| c0062 | Aerial roots and trunk dominate; some peripheral leaves are present. Their attachment, scale and diagnostic detail are insufficiently clear.  | Do not claim leaves are absent. Root architecture alone does not settle the source species; genus/family remain adjudication questions. |
| c0135 | White long-necked bird; bill silhouette is visible, feet and legs are obscured by grass.                                                      | Do not claim the entire bill is invisible. Review broader taxon support separately from uncertain colour, size and species.             |
| c0194 | Mottled gull-like bird from below; folded wing, limited legs and obscured tail.                                                               | Species uncertainty is plausible, but the existing card does not demonstrate that family is unsupported. Review genus too.              |

The botanical comparison uses
[Penn State's stem-character guidance](https://extension.psu.edu/poison-hemlock-identification)
and its
[discussion of related umbelliferous plants](https://extension.psu.edu/is-it-poison-hemlock-or-wild-chervil).
The original page initially returned HTTP 403; its indexed transcript was
available in search. This is not a claim that the current HTML matches the
archived source digest.

For bracket fungi, the
[turkey-tail key](https://www.mushroomexpert.com/trametes_versicolor.html)
requires pore and surface distinctions; the
[Stereum account](https://www.mushroomexpert.com/stereum_hirsutum.html) also
describes overlapping forms. The
[rubber-plant account](https://plants.ces.ncsu.edu/plants/ficus-elastica/)
describes leaf and stipule traits that roots alone do not establish. Cornell's
[egret comparison](https://www.allaboutbirds.org/guide/Snowy_Egret/id) and
[gull account](https://www.allaboutbirds.org/guide/herring_gull/id) support
separating species diagnostics from family membership. A published family
assignment does not, by itself, adjudicate a supplied photo.

The completed candidate declared genus on five of these cases and species on
c0135. Four of those genus answers were unmapped; c0194 mapped to a genus. No
case returned unresolved biological. Thus “all six named” is accurate under the
frozen scorer, but “all six guessed a species” is false. Unknown genus names
remain unknown; this audit does not recover them from hashes.

## Supported-answer controls and reference holds

| Cases        | Review disposition                                        | Reason                                                                                                                                                                                                                                                 |
| ------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| c0005, c0006 | Hold species reference for future scoring                 | Both cards assert the same distinctly pitted mature head. c0005 shows damaged/dissected fruiting bodies without a clearly exposed mature cap; c0006 has a slime- and fly-obscured head. The claimed distinguishing relief is not securely established. |
| c0003        | Retain provisional species control; mapping caveat        | Elongated pale scaly cap, darker crown and stalk are visible. Both arms' unknown names remain unverified.                                                                                                                                              |
| c0012, c0013 | Retain provisional species controls                       | Beetle spot arrangement and spider abdominal/leg pattern remain visible support for the existing references.                                                                                                                                           |
| c0017        | Retain provisional species control; correct future note   | Head, face, chest and neck pattern are visible. The card's barred wing/tail pattern is outside this crop.                                                                                                                                              |
| c0112        | Retain provisional species control; correct future note   | The floral structures are visible. Complete lobed foliage is not established by the cropped background.                                                                                                                                                |
| c0007        | Retain provisional genus control                          | Cage morphology is visible, including projections around openings; source species label cannot settle the competing morphology.                                                                                                                        |
| c0021, c0049 | Retain provisional genus controls                         | Shared colour or vegetative characters limit species claims. c0049 itself contains an unopened bud; the old shared wording mentions another case.                                                                                                      |
| c0050, c0195 | Retain provisional genus controls; distinguish mechanisms | The first bee is front-oblique with partly hidden abdomen; the second shows much of the dorsal colour pattern. Shared traits can limit identification even in a sharp image.                                                                           |
| c0080, c0081 | Retain nonbiological controls                             | Angular cleavage surfaces support rejection of biological identification, not exact material identification.                                                                                                                                           |

The mature cap distinction is supported by the separate
[pitted-head account](https://www.mushroomexpert.com/phallus_impudicus.html) and
[smooth-head account](https://www.mushroomexpert.com/phallus_ravenelii.html).
This review does not declare either photographed specimen a different species.
In particular, the recorded c0006 species-to-genus loss is a loss under the old
answer key; it cannot yet be used as unquestioned proof of harmful caution.

The [cage-fungus comparison](https://www.mushroomexpert.com/clathrus_ruber.html)
supports the existing genus caution. The
[passionflower description](https://plants.ces.ncsu.edu/plants/passiflora-caerulea/)
supports the floral combination in c0112. All retained references remain
assistant-reviewed and provisional; this audit is not comprehensive taxonomic
revalidation of the other 180 photos.

## Failure taxonomy for the next review

Record these independently; a case may have several:

1. **Unphotographed structure:** the needed surface or organ is outside the
   view.
2. **Obscured or unresolved detail:** the region exists in the image but
   occlusion, glare, scale or detail prevents a reliable observation.
3. **Visible but shared character:** sharp pixels still do not distinguish
   plausible taxa, including age, colour form or overlapping morphology.
4. **Reference mismatch:** a review card asserts visibility not established by
   the exact pixels, or fails to evaluate the supported rank.
5. **Mapping uncertainty:** a returned name cannot be verified against the
   frozen taxonomy; this does not establish biological error.

A generic blur score cannot address all five. Likewise, merely reducing a
confidence score cannot repair an unsupported name. Missing evidence must be
distinguished from an observed absence. A named family may be more useful and
fully supported where species and genus cannot be resolved.

## Exposure and eligibility

The 20 reviewed observations are exposed development data. Reviewing their
pixels adds no claim of new validation evidence. The exposure audit is recorded
below after checking the private manifests and journals; historical split names
alone never qualify an observation. No remaining-case pixels were inspected for
this review.

The independent read-only contract audit joined the original confidence claims,
October decision assignments/claims, primary-screen assignments, all-200 cluster
review, and reasoning/Gemini recheck asset hashes:

| Partition or check                            | Finding                                                                                  |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Original corpus                               | 100 development and 100 held-out observations                                            |
| Original confidence collection                | 100 distinct development attempts; no held-out attempts                                  |
| October decision                              | 20 development observations × 2 arms; 60 old-held-out observations × 3 arms              |
| Primary screen                                | 6 decision-development plus 14 decision-validation observations; all already exposed     |
| Remaining old-held-out observations           | 40; zero recorded attempts in those joined journals                                      |
| Reviewed clusters across all 200              | 194 clusters; five multi-case clusters, two cross the old split                          |
| Remaining 40 and multi-case clusters          | No membership in a reviewed multi-case cluster                                           |
| Reasoning/Gemini recheck exact-image overlaps | Three corpus overlaps, all in the original development half; none among the remaining 40 |

This establishes **no recorded local attempt in the reviewed archives**, not
universal non-exposure or automatic eligibility. The parent exposure review
explicitly limits its scope to `available_local_records_only`; its earlier
1,082-file local inventory is historical evidence, not a fresh inventory of
every possible experiment. See the
[provider decision's exposure record](identification-photo-provider-decision-2026-10-01.md).
The exact metadata joins add the completed primary screen without inspecting
remaining-case pixels. Semantic clustering is the existing reviewed clustering,
not a new image-similarity certification.

Before future validation, bind those cases to a current permission/retention
check, all subsequently available attempt records, source/subject lineage and
rank-aware references in a new manifest. The remaining 40 are a reserve to
protect, not an instruction to spend or a promise of statistical power. Original
reference curation is already assistant-led; “unused” must not be confused with
never reviewed by anyone. Retention remains through 22 October for the October
archives; expiration never erases exposure.

## One conditional experiment proposal

**Hypothesis:** requiring a short, structured report of observable diagnostic
features and their visibility within the same identification call can improve
the supported resolution without suppressing justified species answers.

This differs from adding more caution to the prompt. The existing
`solPhotoPrimaryInstructions` already demands visible distinguishing evidence,
broader supported ranks and “unknown, not absent” treatment of unseen features.
The new capability to test is whether the model's feature observations are
accurate enough to support its chosen resolution. Self-reported evidence is
another prediction to evaluate, never independent proof of correctness. This is
a joint identification-and-feature-output comparison. Even a passing result
would not prove that reporting a feature caused the rank decision, or that the
field is a reliable automatic abstention gate.

Proposed development design, **not frozen or authorized for paid execution**:

- Use the same 20 exposed observations as the review frame, only after every
  reference hold is resolved in a separately versioned corpus. If a hold cannot
  be resolved, redesign and freeze the sample before any collection; never
  replace cases after results arrive.
- Compare the existing explicit-primary candidate against one new version with a
  bounded diagnostic-feature observation field. This two-arm ablation isolates
  the added feature-reporting change. The released configuration remains the
  product baseline; historical scores provide context only.
- The proposed field contains at most three brief feature observations, each
  marked visible, not visible, or unclear. It records observable facts, not a
  reasoning transcript. No example taxa, benchmark answers or per-case hints
  enter the prompt. Keep the current explicit resolution and explanation format,
  model, low reasoning, image bytes/detail and one call per observation.
- Review feature observations privately against the frozen visibility cards;
  retain only bounded agreement/error flags. Do not persist provider prose or
  add fields to the public API. A future implementation must specify and
  validate that transient review boundary before collection.
- At most 40 attempted calls, one per observation per arm; no retries or
  replacements. Reuse existing source/input binding, accounting and durable
  claims. Freeze ordering, pricing, a new dollar ceiling and authorization
  before dispatch. Neither prior closed budget is available for this proposal.

Proposed advancement rule, to be frozen after references and software are ready:

1. All 40 scheduled attempts have settled accounting and valid reviewed outputs;
   any failure is reported in the scheduled denominator and prevents
   advancement.
2. At least three paired gains among the predeclared limited-evidence cases,
   covering at least two of mechanisms 1–3 above, and at least three net
   supported outcomes overall. Each gain needs the newly accepted rank/taxon or
   appropriate unresolved result, not simply a lower rank or a lower confidence
   score.
3. No paired loss on an adjudicated species reference, no new nonbiological or
   subject error, and no loss of a previously supported genus/family outcome.
4. Each claimed evidence-sufficiency gain has a correct feature-visibility
   assessment, not just a plausible-sounding explanation. At least one gain must
   be independent of an unmapped comparator answer. No claimed gain can rely on
   an invented visible feature or a rank inferred from a name string.

Freeze the following coding instrument with the adjudicated references:

- Allow observations of anatomy, shape, colour/pattern, surface texture and
  occlusion/view coverage. “Visible” means the asserted feature is discernible
  in the supplied pixels; “not visible” means outside the view or fully
  occluded; “unclear” means the region is present but the feature cannot be
  reliably resolved. Missing visibility never establishes biological absence.
  Source identity, imagined location, smell and microscopy are not visible
  evidence.
- Require at least one diagnostic observation for a biological result. Empty,
  irrelevant, contradictory or confidently invented feature reports fail the
  feature assessment. Proposed per-case mechanisms are in the review JSON;
  finalize them and limited-case membership before calls, not after gains
  appear.
- Assess candidate feature reports in randomized opaque order with the predicted
  name, rank, confidence and outcome hidden. The reviewer knows these are
  candidate reports because the comparator has no such field; do not claim full
  arm blinding. A second read-only reviewer adjudicates disputed coding before
  outcome joins. If disagreement remains, give no feature-gain credit. Record
  reviewer IDs, disagreement counts and automated-review limitations. This is
  assistant review, not independent human verification.
- A supported outcome is an exact mapped accepted taxon/rank or the exact
  adjudicated unresolved/nonbiological state. A paired gain is comparator
  unsupported and candidate supported; loss is the reverse; net support is gains
  minus losses over all 20 scheduled observations. Unknown mappings get no
  support credit. A mapping-independent gain requires a valid comparator with a
  mapped wrong/unsupported answer or an inappropriate non-named result; an
  unmapped, ambiguous, malformed or technically failed comparator does not meet
  this condition.
- Any subject/name/rank contradiction is invalid output, receives no credit and
  fails rule 1. Also reject advancement for any newly unsupported named answer
  on a case where the comparator was appropriately unresolved. This cannot
  escape the paired-loss rule merely because the old reference was not named.

Three gains across mechanisms is a development hurdle intended to avoid
advancing on one anecdote; it is not a statistical superiority test. Report
paired gains/losses, exact rank yield, unnecessary abstention, unsupported
specificity, feature-observation errors, mapping uncertainty, technical
failures, latency and settled cost. Use reviewed accepted answers and the
existing scorer; do not automatically credit every ancestor of an accepted
species.

A pass would justify designing one independent comparison against released
Sol-low. It would not authorize deployment or confidence calibration. Its sample
size and paired inference method must follow the intended effect and coverage;
the number of leftover old cases must not dictate a confirmatory claim.

## Concrete next deliverable

Produce a separately versioned reference adjudication for this 20-case frame:
assess species, genus, family and unresolved support independently; attach only
visible diagnostic claims to each exact image; resolve the two species holds;
and freeze accepted IDs/ranks plus reviewed taxonomy. Keep the original corpus
and results immutable. An unresolved scientific question remains a hold; neither
source captions nor model agreement resolve it.

Then review whether the proposed diagnostic field is implementable with the
existing evaluation and privacy contracts. Only after those prerequisites pass
is candidate implementation and a new paid proposal justified. The current
decision is **go for reference adjudication; no-go for another paid screen**.

## Verification

- All 20 reviewed asset hashes and original references match the immutable
  archive; all four recorded source-file byte hashes match too.
- Review coverage is five retained provisional species, two species holds, five
  retained provisional genera, six resolution holds and two nonbiological
  controls. These are review dispositions, not new accuracy results.
- `make validate-identification-research` passed formatter, lint, two catalog
  tests, source/RFC coverage and generated-register freshness: 27 entries and 10
  dataset families.
- `make validate-markdown-format` passed for all 34 changed Markdown files in
  the shared checkout; `git diff --check` passed. Seventeen local file links in
  this report and the updated research hub resolve.
- No runtime code changed, so no application, backend, deployment or device
  gates are claimed. No new scientific accuracy or confidence guarantee was
  tested.
