# Photo reference adjudication — 1 October 2026

Status: completed offline. The
[answerability audit](identification-answerability-audit-2026-10-01.md) now has
a separately versioned, provisional development answer key: **18 accepted
references and two explicit reference holds**. No paid calls, historical
rescoring, candidate implementation or production changes occurred.

The
[adjudication artifact](../research/identification/answerability-adjudication-2026-10-01.json)
owns the exact case membership, image hashes, rank assessments, accepted IDs,
taxonomy additions and review limitations. It supersedes the audit's holds only
for prospective development use. The original corpus, taxonomy, claims and
published scores remain unchanged.

## Adjudicated outcomes

| Cases        | New development reference          | Basis and limit                                                                                                                                       |
| ------------ | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| c0006        | Phallus, genus (`gbif:2524102`)    | A differentiated slimy cap above a chambered stalk supports genus; obscured cap relief cannot distinguish species.                                    |
| c0027        | Apiaceae, family (`gbif:6720`)     | Compound umbels and small five-petalled flowers support family; stem, bract, foliage and fruit detail do not establish a lower rank.                  |
| c0135        | Ardeidae, family (`gbif:3685`)     | Curved neck, pointed bill and heron body form support family; obscured legs/feet and insufficient comparative detail prevent a lower-rank reference.  |
| c0194        | Laridae, family (`gbif:9316`)      | Gull structural form and immature plumage support family; limited views and overlapping age-dependent traits do not settle a genus or species.        |
| c0031, c0032 | Unresolved biological              | Photographed bracket characters do not establish a specific family or genus. Pore-versus-smooth fertile surface remains inadequately resolved.        |
| c0005, c0062 | Reference hold; no accepted answer | The damaged fungus and aerial-root tree remain scientifically unsettled at the allowed ranks. They are not automatically unresolved-scoring examples. |

The remaining 12 cases retain their existing rank with the audit's corrected
per-image visibility notes: five species references, five genus references and
two nonbiological controls. In the resulting 18-case set there are five species,
six genus, three family, two unresolved biological and two nonbiological
references. None is described as independently human-validated.

Four accepted ranks change relative to the old answer key; two old references
move to a hold. The two bracket references retain unresolved status after
explicit broader-rank review. This is a new reference version, not a declaration
that every previously counted error was a model error or every broader answer
was correct. In particular, a missing taxonomy mapping remains unverified.

## Diagnostic and taxonomy support

The primary assistant used the exact pixels inspected in the preceding audit. A
separate read-only assistant re-inspected all eight held cases against
diagnostic sources, without reading paid predictions during that review. Both
supported the dispositions above. The primary already knew historical outcomes;
the work is not a blinded scientific study. Agreement between assistants is a
review check, not independent biological ground truth.

[UF/IFAS's stinkhorn morphology account](https://ask.ifas.ufl.edu/publication/PP345)
distinguishes cap-bearing Phallus from capless Mutinus. This supports the genus
assessment in c0006 without claiming an odor, hidden cap texture or exact
species.
[Kew's Apiaceae morphology](https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:30000180-2/general-information)
and
[Native Plant Trust's family account](https://gobotany.nativeplanttrust.org/family/apiaceae/)
support the floral structure comparison. These are diagnostic descriptions, not
provenance claims about our image.

Cornell's [egret](https://www.allaboutbirds.org/guide/Snowy_Egret/id) and
[gull](https://www.allaboutbirds.org/guide/herring_gull/id) accounts support the
family/species distinction. The
[UBC bracket-fungus comparison](https://linnet.geog.ubc.ca/Atlas/Atlas.aspx?sciname=Trametes+versicolor)
explains why underside pores matter for visually similar brackets. The
[NCSU fig description](https://plants.ces.ncsu.edu/plants/ficus-elastica/) does
not make root architecture alone a sufficient genus or family diagnostic; c0062
stays on hold.

Public GBIF API exact matches confirmed accepted names/ranks for
[Apiaceae](https://www.gbif.org/species/6720),
[Ardeidae](https://www.gbif.org/species/3685),
[Laridae](https://www.gbif.org/species/9316) and the existing Phallus ID. API
identity matching verifies taxonomy, not photo correctness. The three new family
entries have no speculative synonyms. Their public API response hashes and URLs
are recorded in the artifact, alongside the unchanged parent taxonomy byte hash.
The overlay adds three entries to the existing 91-taxon catalog; it does not
edit old entries, infer unknown model names, or repair old scores.

## Scoring boundary

For an accepted named reference, only its exact reviewed canonical ID and
most-specific accepted rank receive support credit. A supported family answer
does not receive species credit. A broader ancestor of an accepted species is
not automatically correct under this development metric.

For c0031/c0032, the accepted scoring state is biological unresolved: no named
taxon and biological subject true. This is an assistant-reviewed conclusion
about the supplied evidence. It does not assert that the organism lacks an
identity or that no expert could ever identify it.

For c0005/c0062, `reference` is null and status is `hold`. They must be excluded
before a future collection manifest is frozen. They cannot be scored as wrong,
used as required abstentions, silently dropped after collection, or replaced
with a convenient case after outputs arrive. Expert adjudication or additional
diagnostic evidence can revisit them in another reference version; extra imagery
would also create a different input condition.

## Concrete next experiment boundary

The original conditional 20-case proposal is superseded prospectively by an
**18-observation, two-arm development design**, at most 36 attempted calls. Both
reference holds remain visible in this record. No replacement observations are
drawn from the 40 unused old-held-out cases. All 18 selected observations are
already exposed; this is not confirmatory validation or confidence calibration.

Compare the existing explicit-primary configuration with one candidate adding
the bounded feature-observation field described in the audit. Retain its
privacy, exact input/settings comparison, settled-accounting, no-retry,
feature-review and mapping-independent-gain conditions. Use the 18 accepted
references and the new taxonomy overlay for both arms; do not compare new scores
directly with historical totals using a different answer key.

The proposed advancement rule keeps at least three paired limited-evidence gains
across at least two mechanisms, at least three net supported gains, no
species-reference loss, no loss of an accepted broader/non-named outcome, and no
new subject error. It additionally requires **at least one paired gain on the
two unresolved biological cases**. Family gains alone cannot establish better
abstention. Gains must have accurate diagnostic-feature assessments under the
audit's predeclared instrument. Five species controls and two unresolved cases
are a small diagnostic screen; passing supplies no population guarantee.

Next implementation can now target that offline evaluation candidate and its
bounded transient feature-review path. Before any paid collection, materialize
the separately versioned references, taxonomy and evidence cards into an
isolated packet, verify software and permissions, and freeze the source,
ordering, pricing and a newly authorized spending ceiling. This JSON is neither
a runnable packet nor paid authorization. The previously closed budgets remain
closed, and the released model and thresholds remain unchanged.

## Verification

- Verified the parent audit byte hash, all four original source-file hashes, all
  20 image hashes, exact 18/2 membership and the four prospective rank changes.
  Seventeen local links in this report and the updated hub resolve.
- With network and environment access denied, the existing `parseTaxonomy`,
  `resolveTaxon` and `assessReference` accepted the 94-entry composed catalog,
  all 14 named-reference canonical round trips and all 18 synthetic expected
  outcomes. Twenty-one synthetic negative checks rejected unmapped identities,
  wrong family ranks and wrong-subject unresolved outcomes. These are artifact
  and scorer checks, not new model-accuracy evidence.
- `make validate-identification-research` passed formatting, lint, both tests,
  source coverage and generated-register freshness: 28 entries and 10 dataset
  families. `make validate-markdown-format` passed all 35 changed Markdown
  files; `git diff --check` passed.
- No runtime source changed. No application, backend deployment or device gate
  is claimed, and no scientific or confidence-calibration guarantee is implied.
