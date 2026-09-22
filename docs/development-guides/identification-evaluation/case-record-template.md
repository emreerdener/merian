# Pilot case record — blank template

Copy this form into controlled storage outside Git. Leave unknown fields
pending. This is a human intake record, not a valid `corpus.json` case and not
an approval. Follow the
[collection guide](../20-identification-evaluation-pilot.md). Never put personal
names, coordinates, keys, production responses or answer-bearing text in the
provider input.

## Intake and evidence

| Field                                                            | Value                                                                                                              |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Status                                                           | pending_collection                                                                                                 |
| Collection slot                                                  | Pending                                                                                                            |
| Case ID / independent group ID                                   | Pending                                                                                                            |
| Split                                                            | development                                                                                                        |
| Input group                                                      | Pending: photos / description / audio / frames / frames_audio / photos_audio                                       |
| Collector role reference                                         | Pending                                                                                                            |
| Source kind                                                      | Pending: purpose_collected / licensed                                                                              |
| Source/permission record reference                               | Pending opaque token                                                                                               |
| Proposed difficulty / biological-group tags                      | Pending; kept out of corpus input                                                                                  |
| Related observations and derivatives                             | Pending; review even if not selected                                                                               |
| Frozen strict input record reference                             | Pending; immutable record that passes `parseEvaluationInput`                                                       |
| Preparation recipe/version                                       | Pending                                                                                                            |
| Final asset IDs, hashes, MIME types and byte lengths             | Pending                                                                                                            |
| Frame indexes / clip and companion-audio relationships           | Pending or not applicable                                                                                          |
| Controlled source-capture and per-asset lineage record reference | Pending; source reference/fingerprint, extraction version, frame times/indexes, audio range and final asset hashes |
| Canonical frozen input digest                                    | Pending; `fingerprintJson` of the validated input                                                                  |
| Evidence fingerprint / prepared-audio review reference           | Pending                                                                                                            |

Suggested states: `pending_collection`, `pending_preparation`, `pending_review`,
`pending_adjudication`, `admitted`, `withdrawn`. These are working labels only;
the executable corpus schema has no draft-state field. Preserve withdrawn IDs
and record a bounded reason without reusing the observation's group identity.

The frozen input includes ordered `observationTexts`, coarse/null `context`,
clip `clipIndex`/`declaredFrameCount`/`includesAudio`, and ordered asset
`id`/`kind`/`path`/`sha256`/`mimeType`/`byteLength` plus the applicable
`sourceIndex` or `clipIndex`/`frameIndex`. Keep lineage and workflow fields in
this controlled form, outside the strict input record. For combined media,
record how both sources belong to the same observation.

## Eligibility and preparation

Record supporting evidence references alongside completed checks. An unchecked
item remains pending; do not convert this form into approval booleans by
default.

- [ ] Source evidence establishes permission to send this material to Gemini for
      identification evaluation; retention requirements are recorded.
- [ ] Evidence contains no personal data, precise coordinates, human faces or
      speech, credentials, account identifiers, or production response content.
- [ ] Final filenames/metadata and observable text contain no leaked answer or
      reference notes; source/answer records remain separate.
- [ ] Final images have been decoded/viewed and final audio listened to,
      including the effect of production audio preparation where applicable.
- [ ] Prepared assets satisfy the tooling format and preserve all declared media
      and frame/audio relationships.
- [ ] The frozen input passes `parseEvaluationInput`; its canonical input and
      provider-eligible evidence fingerprints are recorded for both reviewers.
- [ ] Controlled lineage connects every derived asset to its source capture and
      extraction/preparation step; it is more than a declaration of matching
      `clipIndex` values.
- [ ] Exact and near duplicates, other views, crops and derived descriptions
      have been reviewed; this is one primary case for one independent group.

## Independent review and adjudication

Keep the individual completed review forms separate until both initial reviews
are recorded. Backend must not fill the reference from a Gemini prediction.

| Field                                                                    | Value                                                |
| ------------------------------------------------------------------------ | ---------------------------------------------------- |
| First reviewer role / completed form reference                           | Pending                                              |
| Second reviewer role / completed form reference                          | Pending; a different person and role reference       |
| Same frozen input digest and final evidence fingerprint reviewed by both | Pending                                              |
| Source/asset lineage inspected by both reviewers                         | Pending                                              |
| Independent reference-evidence record                                    | Pending opaque token                                 |
| Final subject                                                            | Pending: biological / non_biological / indeterminate |
| Final resolution                                                         | Pending: named / unresolved                          |
| Most specific supported rank                                             | Pending; null for unresolved                         |
| Explicit acceptable taxon IDs and ranks                                  | Pending; empty for unresolved                        |
| Frozen taxonomy authority/version and accepted aliases                   | Pending                                              |
| Adjudication                                                             | Pending: agreed / resolved                           |
| Disagreement rationale and both reviewers' acceptance                    | Pending or not applicable                            |
| Admission coordinator role / date                                        | Pending                                              |

Only mark `admitted` after eligibility, preparation and both reviews are
complete. Keep individual case admission separate from approval of the complete
corpus and from paid-run authorization. If evidence changes, invalidate the
affected review and return the case to preparation/review.
