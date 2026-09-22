# AI provider flexibility — deployment and verification

Date: 21 September 2026 (America/Chicago)\
Status: Gemini-only backend deployed; owner verification confirmed; post-merge
iOS CI pending\
Deployed commit: `37bd9ce40fc40b54964abc7090844d61db196d65`\
Source: [PR #68](https://github.com/emreerdener/merian/pull/68)

This record follows the
[Slice 6 local verification](../rfcs/identification-foundation-verification.md).
It adds deployment evidence and owner-reported manual acceptance without
rewriting the earlier working-tree tests or benchmark measurements. The
[PRD](../product/03-identification-foundation-prd.md) and
[SRD](../rfcs/identification-foundation-srd.md) continue to define the
Gemini-preserving scope.

## Verified source and deployment

PR #68 merged into `main` on 21 September 2026 at 22:46 CDT. GitHub reported 17
checks passed. The merge commit above is the candidate and deployment identity;
the earlier local baseline SHA is not the deployed candidate.

The
[Deploy Merian to Supabase run #1791](https://github.com/emreerdener/merian/actions/runs/35684379230)
completed successfully for that exact SHA. Its complete candidate-validation,
Candidate readiness, release-hold, and production `deploy` jobs all ran and
passed. The release summary reported clear automatic-release controls,
protected-main provenance through PR #68, and a final plan covering all 101
functions. This was a completed production deployment, rather than a green
validation-only or held run.

Gemini remains the only enabled provider for identification and scoped
supporting content. No alternate provider, model cascade, native-video
inference, or family-plan change was introduced. Video identification retains
sampled images and any included companion audio.

## Owner-reported manual acceptance

The owner reported that AI testing in the simulator succeeded, then confirmed
the requested post-deployment verification. The requested follow-up covered the
backend target, photo, audio, five-second video, saved-result reopening, and
interrupted-request recovery, including a physical-device check.

This is an owner-reported confirmation recorded from the task conversation.
Individual case logs, the tested app build/device, and measured latency or cost
were not supplied. The confirmation is not expanded into claims about other
acceptance cases, measured production thresholds, a rollback exercise, or
alternate-provider qualification.

## Remaining CI observation

At 2026-09-22 04:10 UTC, the
[post-merge iOS Build and Test run #513](https://github.com/emreerdener/merian/actions/runs/35684379036)
was still in progress for the deployed merge SHA. The Current-SHA Release
archive job passed for `1.0.3 (275)`; the archive was unsigned validation
output. Full iOS unit tests were still running and Production readiness had not
completed. No iOS distribution is claimed by this record.

Record that final CI result when available. Retain the earlier distinction
between deterministic/local evidence and formal production quality, timing,
account-transition, public-job, and return-path evidence that this manual
confirmation did not enumerate.

## Follow-up ownership

The provider-flexibility implementation and backend rollout are delivered. File
organization proceeds as a separate change with its own candidate and
validation. Moving files does not transfer this record's results to the new
commit. Keep future provider integration governed by
[Adding a provider later](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).

The
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
continues to own release and recovery operations; this evidence record grants no
new deployment or distribution authorization.
