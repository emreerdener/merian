# Explicit-primary Sol comparison preparation

Date: 2026-09-29

Status: offline packet prepared and reference coverage reviewed. No model calls
have run for `openai_photo_sol_primary_low_v1`. Production continues using the
current Sol photo profile for both Free and Pro; confidence thresholds remain
unqualified.

This checkpoint follows the
[explicit-primary implementation](identification-primary-resolution-contract-2026-09-29.md#isolated-explicit-primary-candidate--2026-09-29).
It prepares a comparison that can assess supported species, broader groups and
abstention while preserving the existing explanation format. The completed
[Sol rank experiment](identification-sol-rank-comparison-results-2026-09-29.md)
and its eighteen paid calls remain historical evidence for a different profile.

## Selected evidence

The new packet contains twelve no-description still-photo cases: nine retained
development cases and three newly reviewed public images. Source review and fact
cards remain private. No source title, reference identity, comparison species,
diagnostic notes or reviewer prose enters either model request.

| Cases            | Reference purpose                        | Support and limits                                                                          |
| ---------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------- |
| `c0001`, `c0002` | Preserve supported species answers       | Usable provisional species references                                                       |
| `c0201`          | Domestic dog naming                      | Usable provisional dog identity; pedigree and exact breed are not established               |
| `c0202`          | Domestic cat naming                      | Usable provisional cat identity; visible coat pattern does not establish breed or ownership |
| `c0203`          | Unresolved biological subject            | Microbial-community source reference; limited visual and taxonomic evidence                 |
| `c0008`          | Non-biological mineral control           | Usable provisional subject classification; no laboratory composition claim                  |
| `c0101`          | Viceroy/monarch lookalike                | Usable provisional viceroy reference with a distinct monarch comparator                     |
| `c0102`          | Family-level fly reference               | Limited: the reference does not prove family is the finest visually supportable rank        |
| `c0103`          | Genus-level gray treefrog                | Usable provisional genus reference; missing distinguishing evidence is recorded             |
| `c0104`, `c0105` | Lichen and pine genus references         | Limited: more specific identities require additional adjudication                           |
| `c0106`          | Non-biological branching-pattern control | Usable provisional mineral-subject reference                                                |

This replaces three earlier screening cases while retaining all six challenge
cases, including both earlier visual-explanation failures. It does not add
requests to an existing run.

The new images are the NPS
[Denali dog portrait](https://www.nps.gov/dena/planyourvisit/nepa.htm), the
USFWS [cat photograph](https://www.fws.gov/media/feral-cat), and the NPS
bacterial-column image on its
[thermophilic communities page](https://www.nps.gov/yell/learn/nature/thermophilic-communities.htm).
The NPS images carry NPS credits and public-domain usage; the cat page specifies
Creative Commons Attribution 4.0. The private review retains source and asset
URLs, license and attribution. Downloaded site renditions were visually reviewed
and checked for embedded EXIF, XMP and comment metadata. No local visual edits
were made. They contain no visible people, personal information or species
labels.

The dog and cat cases use Merian's existing naming conventions:
`Canis lupus familiaris` and `Felis catus`. The dog convention is an application
compatibility rule, not an assertion that every taxonomic authority assigns it
species rank. Source facts about the animal's name, ancestry or work history are
not observation evidence. The cat's source description does not allow a model to
infer that an individual is feral from its appearance.

## What the coverage establishes

| Resolution in provisional references | Cases | Usable provisional | Limited reference |
| ------------------------------------ | ----: | -----------------: | ----------------: |
| Species                              |     5 |                  5 |                 0 |
| Genus                                |     3 |                  1 |                 2 |
| Family                               |     1 |                  0 |                 1 |
| Unresolved biological                |     1 |                  0 |                 1 |
| Non-biological                       |     2 |                  2 |                 0 |

All five resolution states and the dog, cat, lookalike and mineral/object roles
have cases. The receipt therefore reports `present_with_reference_limits`, with
`family` and `unresolved_biological` in `limitedOnly`. Four cases have limited
references overall. Presence does not establish biological accuracy or make the
packet a held-out, independently verified benchmark.

The microbial image illustrates the distinction. Its source documents a
biological community, but the photograph does not resolve a single family, genus
or species, and mineral-looking surfaces remain visually ambiguous. It can
exercise uncertainty handling; a different identity is not automatically an
error. The source's explanation is available only to the reviewer.

## Frozen comparison and interpretation

The proposed schedule contains six candidate-only screens, followed by six
candidate/control pairs. Pair order alternates. There are eighteen proposed
assignments, with one attempt each. The new profile is compared with
`openai_photo_sol_low_v1`. Both use the same evidence, Sol model, reasoning,
image detail and output limit; the candidate changes the primary-resolution
instructions and strict output contract. Screen-only cases cannot establish a
head-to-head win.

`primary_reference_limits_v1` defines the intended interpretation:

1. Record explicit resolution and mapped identity separately. A format error,
   operational failure or refusal is not a biological answer. A name missing
   from the finite taxonomy is unmapped, not automatically wrong.
2. Compare identities to the provisional reference while preserving its support
   status. A limited-reference mismatch is unassessable unless specific reviewed
   evidence resolves a contradiction. A broader reference alone does not prove
   that a narrower result is unsupported.
3. Review explanations against the image, observed facts and missing evidence
   using the existing grounding, required-information and uncertainty rubric. An
   invented visible feature can fail even when identity is unassessable. An
   unseen feature must not be treated as an absent feature.
4. Keep the confusable species separate from accepted answers. The viceroy case
   accepts its viceroy reference; monarch is a catalog-bound comparator. A role
   annotation alone cannot claim lookalike coverage.
5. Assess the existing dog/cat primary-name convention separately from optional
   breed or coat details. Preserve non-biological geological names where
   supported. Broader or unresolved biological answers must not fabricate
   species alternatives or pet details.
6. Report coverage limits, failures and unassessable cases alongside any timing
   or cost comparison. Do not average missing evidence into a success rate,
   qualify a Free/Pro split, or derive confidence badges from this packet.

This slice binds the references, rubric and interpretation-policy identifier; it
does not implement live scoring for the new draft. The future runner must
implement and test these interpretation rules before dispatch. Assistant review
remains the intended workflow; the owner does not need to score explanations.

## Packet identity and isolation

The active private source is `2026-09-29-sol-primary-source-v2`; the prepared
packet is `2026-09-29-sol-primary-photo-preparation-v2`, both under the existing
private evaluation directory. Earlier `v1` preparation copies remain untouched
and are superseded by this revision, which adds the explicit lookalike
comparator. All 24 prepared candidate/control request identities and the
eighteen-assignment order are unchanged by that review correction.

| Artifact            | Canonical SHA-256                                                  |
| ------------------- | ------------------------------------------------------------------ |
| Corpus              | `1aed321be10b66e170534dab7e25f26d844a4452a706dfa8c407a630031a3ea0` |
| Taxonomy            | `203da0287891fcb6a210780eac7006c7c9a7bfe8ca9b7162a5f860d829b0a42a` |
| Facts               | `98a6eeeed391bd59895c5a1b3b9b73c03d0488878cfb0ad84d72bfad8a3cf481` |
| Reference review    | `4a41cd1e07e698b3785055b677b22934f9444409b6fc4d256edae643afc71446` |
| Preparation plan    | `a33ea3d81717b6d35a5e1c3b47b60b26a2e51046d3fbf22e8bf5e4a76e8f6fbd` |
| Preparation receipt | `af7ed530e10f13ab7c39453fd38cdc317f7c2be7163b068341c8131244c53974` |
| Explanation rubric  | `6465cb618e8c9c6ed90be86f0aebd684d31c2fb3dda99ab8f113d7491c1d8e33` |

`prepare_sol_primary_candidate.ts` accepts two local paths. Its new closed
preparation/review contracts bind twelve cases, references, facts and finite
taxonomy to both exact request projections. It rejects live flags, ambient
network/environment permissions, stale digests, mislabeled pet roles, missing
lookalike comparators, altered media, symlinked roots, public parent
directories, nested paths and existing destinations. The destination is private
and created exclusively; its completion receipt is written last after asset
revalidation.

Only corpus, taxonomy, fact cards, the new reference review, the new preparation
plan and selected assets are copied. Historical approvals, budgets, keys,
claims, journals and results are not read or inherited. Source URLs and reviewer
prose remain in the private review, while CLI output contains only bounded
coverage metadata and hashes. The retained corpus curation token is a legacy
input format, not provider execution permission.

The receipt records `false` for `dispatchAuthorized`, `readyForLive`,
`liveControllerAvailable` and `qualityQualified`. Its schedule is preparation
only. No historical plan parser, provider registry, production policy or
confidence display is expanded.

## Verification and next implementation

Five focused offline tests pass, covering immutable copying, paired request
identity, missing and limited references, stale bindings, unsafe paths,
historical-authority rejection, comparator validation and CLI permission denial.
Independent read-only review confirmed the comparator fix. Historical source
inputs and copied asset hashes were verified unchanged.

The complete Supabase tooling gate passed: 470 standard tests, 108 isolated
evaluator tests, both generated DTO suites and all twelve shell suites.
Recursive backend formatting and lint passed, all four changed Markdown files
were formatted, and 86 local documentation targets resolved. No runtime
function, SQL or native-client implementation changed, so no database or iOS
build was run for this tooling slice.

Next, implement the separate bounded live adapter, explicit-primary evaluation
record and interpretation path. Preserve exact returned-model validation, native
moderation, time/output ceilings, single invocation and durable claim/restart
handling. Then bind a clean source revision, current pricing and fresh bounded
authorization to this new packet. A successful development screen alone cannot
establish the unresolved reference questions or confidence thresholds.
Production admission and deployment remain a separate release step.
