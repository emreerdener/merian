# Audio confidence V2 production deployment

Date: 24 September 2026\
Status: deployed; production smoke and health checks passed

[PR #75](https://github.com/emreerdener/merian/pull/75) merged the
[audio confidence V2 implementation](../rfcs/identification-audio-confidence-v2-2026-09-24.md)
and Field Trip subject eligibility repair. The owner explicitly authorized the
PR, merge and deployment to Production Supabase `qlarqavoqhkuwzmevrmf`.

## Source and validation

The reviewed candidate was `8c831e90fafe582a2cce7bc22ab63a17d0c507ac`. The
resulting main commit was `b91e42ded94fe0904a30209b00d6aac8d2151d8c`; GitHub
commit-tree comparison verified an identical tree. All seven PR workflows
passed, including the complete native test/archive/UI gate and disposable
backend candidate validation. Live Agent Quality evaluation was skipped by its
scope policy; it is not counted as a performed experiment.

The
[post-merge native gate](https://github.com/emreerdener/merian/actions/runs/36011318114)
also passed on the actual main SHA: full unit tests, critical scan UI smokes,
Release archive and production readiness. No iOS build was distributed.

## Deployment and recovery

The
[automatic deployment](https://github.com/emreerdener/merian/actions/runs/36011318771)
passed candidate validation but stopped while resolving historical release
evidence, reporting:
`Successful deploy job lacks unambiguous mutation and smoke
steps.` The
production job was skipped, so this attempt made no production mutation. The
cause of the historical-input ambiguity remains unresolved.

The documented manual full-fleet recovery then ran on the same main SHA. The
[successful recovery workflow](https://github.com/emreerdener/merian/actions/runs/36012851637)
preserved exact-source checks, fresh disposable candidate validation, release
holds, live Production control checks, pre-migration fences, permission audits
and post-deployment checks. No workflow protection or baseline resolver was
relaxed.

| Production step      | Verified result                                                                      |
| -------------------- | ------------------------------------------------------------------------------------ |
| Migration            | Applied `20260924062640_gate_field_trip_progress_by_subject.sql` at 14:35 UTC        |
| Database privileges  | Pre-migration audit and both post-migration enforcement checks passed                |
| Function rollout     | All 101 planned functions deployed, including `identify-multimodal` and `audio-spec` |
| Endpoint smoke tests | Passed at 14:43 UTC                                                                  |
| Ghost merge health   | Passed at 14:43 UTC                                                                  |

The repair preserves selected-goal preferences while withdrawing ineligible
derived Field Trip progress. Deployment evidence proves migration execution; it
does not claim that invalid production credit existed or report an affected row
count. Any recovery after the repair must preserve its effects through a
reviewed forward fix or redeployment.

## Runtime identity and follow-up

The generated identification bundle for this source is
`61b69c048f009b62c45681da4219ea01fc9fef039048a9760fc57ca28b73ccc1`. Source and
deployment evidence are distinct from live response attestation. The subsequent
[six-case simulator benchmark](../rfcs/identification-audio-confidence-v2-app-benchmark-2026-09-24.md)
records those fresh response checks separately.

The
[sanitized deployment record](../rfcs/identification-evaluation-evidence/2026-09-24-audio-confidence-v2/deployment.json)
retains workflow/job links, step results, deployment scope and recovery
provenance. Raw deployment logs, credentials, account identifiers and production
response bodies were not retained. No comparison configuration was activated and
no rollback was performed.

Follow up on historical baseline ambiguity using retained sanitized resolver
diagnostics before changing its fail-closed behavior. This operational issue is
separate from the deployed confidence contract and its acoustic evaluation.
