# Pilot reference review — blank independent form

Give each reviewer a separate copy in controlled storage outside Git. Follow the
[collection guide](../20-identification-evaluation-pilot.md). Do not expose the
other review, the proposed final label or Gemini output before the initial
assessment. A reviewer may mark any item unresolved; a blank is not agreement.

## 1. Assess the supplied evidence

Complete this section before viewing source identities or reference labels.
Review the exact final prepared input, including all frames, audio and allowed
context. Preserve this initial assessment when completing later sections.

| Field                                                        | Value                                                               |
| ------------------------------------------------------------ | ------------------------------------------------------------------- |
| Reviewer role reference                                      | Pending opaque role code                                            |
| Case ID / group ID                                           | Pending                                                             |
| Input group                                                  | Pending                                                             |
| Frozen input record reference / canonical input digest       | Pending; same immutable structured input used by the other reviewer |
| Final evidence fingerprint / preparation version             | Pending                                                             |
| Review date                                                  | Pending                                                             |
| Every final image decoded/viewed and final audio listened to | Pending or not applicable                                           |
| Subject                                                      | Pending: biological / non_biological / indeterminate                |
| Resolution justified by the evidence                         | Pending: named / unresolved                                         |
| Most specific supported rank                                 | Pending; null for unresolved                                        |
| Possible identities / explicitly acceptable broader answers  | Pending; no unsupported descendants                                 |
| Observable distinguishing features and missing evidence      | Pending; concise, no personal details or coordinates                |
| Primary subject / alternatives when media disagree           | Pending or not applicable                                           |

An apparent organism can have unresolved identity. An uncertain biological
source is `indeterminate`, not a verified negative. Multiple acceptable answers
must each be justified by the supplied evidence. Do not use privileged source
knowledge to upgrade a blurry image or non-diagnostic sound to a species label.

## 2. Verify the reference and eligibility independently

Now consult the controlled source/permission and reference-evidence records.
Record any revision to the initial assessment with a reason; do not overwrite
the original. A name/ID lookup or another model's answer is insufficient proof
of the observation's identity.

| Field                                                                | Value                                                                                              |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Source/permission record reference                                   | Pending opaque token                                                                               |
| Independent reference-evidence record                                | Pending opaque token                                                                               |
| Reference evidence supports observation identity or uncertainty      | Pending, with bounded rationale                                                                    |
| Source permission covers this Gemini evaluation and retention        | Pending                                                                                            |
| Personal data, human content, metadata and answer leakage excluded   | Pending                                                                                            |
| Group/derivative and near-duplicate record reviewed                  | Pending                                                                                            |
| Controlled source/asset lineage record inspected                     | Pending; verify extraction version, frame times/indexes, audio source/range and final asset hashes |
| Final derived assets and any prepared audio reviewed against lineage | Pending or not applicable                                                                          |
| Final proposed subject / resolution / supported rank                 | Pending                                                                                            |
| Acceptable canonical taxon IDs and ranks                             | Pending; empty for unresolved                                                                      |
| Taxonomy authority/version and aliases verified                      | Pending                                                                                            |
| Changes from initial assessment and reason                           | Pending or none                                                                                    |
| Review disposition                                                   | Pending: eligible / needs_information / exclude                                                    |
| Missing evidence or exclusion reason                                 | Pending or none                                                                                    |

## 3. Accept or withhold adjudication

Complete this only after both independent forms exist. Preserve both original
forms. The coordinator records the final case label separately.

| Field                                                                      | Value                                   |
| -------------------------------------------------------------------------- | --------------------------------------- |
| Adjudication record reference                                              | Pending                                 |
| Frozen input digest and final evidence fingerprint still match this review | Pending                                 |
| Decision                                                                   | Pending: agreed / resolved / unresolved |
| Final label and eligibility accepted by this reviewer                      | Pending                                 |
| Remaining concern or reason for resolution                                 | Pending or none                         |
| Acceptance date                                                            | Pending                                 |

An unresolved decision keeps the case out of the approved corpus. Re-review
changed evidence; do not carry acceptance forward to a new input fingerprint.
