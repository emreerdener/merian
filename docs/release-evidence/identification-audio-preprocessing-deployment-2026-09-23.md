# Audio preprocessing — production deployment

Date: 23 September 2026 (America/Chicago)\
Status: Exact-SHA candidate validation, production deployment and automated
post-deployment checks passed; identification comparison pending\
Deployed commit: `c1936403a1096f611c89639048fc5de5626b10be`\
Audio correction commit: `add5ce9b6de4fd5ff6d74e4d7f335d64fe9e2e4d`\
Target: Production Supabase project `qlarqavoqhkuwzmevrmf`

This record follows the
[local audio preprocessing correction](../rfcs/identification-audio-preprocessing-fix-2026-09-23.md).
The owner's existing push to `main` triggered the normal automatic workflow.
This verification observed that run; it did not push code, dispatch another
workflow or invoke a local production deployment.

## Candidate and release evidence

[Deploy Merian to Supabase run #1796, attempt 1](https://github.com/emreerdener/merian/actions/runs/35874154682)
completed successfully for the deployed commit above. GitHub's run/job metadata
and the visible deployment logs were inspected after completion. Times below are
UTC on 23 September 2026.

| Gate                           | Job                                                                                             | Result and timing         |
| ------------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------- |
| Complete candidate scope       | `107225607903`                                                                                  | Passed, 14:26:15–14:26:26 |
| Exact-SHA candidate validation | [107225700317](https://github.com/emreerdener/merian/actions/runs/35874154682/job/107225700317) | Passed, 14:26:29–14:32:27 |
| Candidate readiness            | `107228246199`                                                                                  | Passed, 14:32:30–14:32:32 |
| Production source scope        | `107228280386`                                                                                  | Passed, 14:32:35–14:32:56 |
| Checked-in release holds       | `107228451721`                                                                                  | Passed, 14:33:34–14:33:46 |
| Production deployment          | [107228805776](https://github.com/emreerdener/merian/actions/runs/35874154682/job/107228805776) | Passed, 14:34:00–14:45:08 |

Candidate validation ran the complete backend gate, including formatting, lint,
tooling, isolated dependency graphs, shared/runtime contracts,
disposable-database migration and catalog checks, the complete Edge Function
suite, database lint and advisors. These are successful hosted checks for this
exact commit; the earlier local test counts remain in their original evidence
record.

The production job verified its exact clean source, rechecked scope under the
deployment lock, and passed automatic-release controls. Database migration push
reported that the remote database was up to date. Function deployment completed,
including `audio-spec` and `identify-multimodal`. The actual plan covered all
101 functions; its baseline discrepancy is documented below.

The production smoke step passed and reported that all 101 Edge routes reached
Merian handlers. Its additional probes confirmed 16 routes reached their
fail-closed handlers and nine RPCs reached their no-write validation boundaries.
The post-deployment Ghost merge health audit also passed. This was an executed
production deployment, with successful migration and smoke steps, rather than a
validation-only or skipped run.

## Actual deployment scope and open tooling follow-up

The local planner against the previous successful deployment,
`bcc7ef8de53cefaa04bed81cb32adf7de877bf9a`, selected two functions from 81
changed files: `audio-spec` and `identify-multimodal`. No migration files
changed in that range.

The actual run's Function planner instead logged
`cff7f39e91b805ffdb39cdd29a366d76fc7a79cb` as its last successful deployment,
selecting 101 functions from 2,872 changed files. This record therefore reports
the full-fleet plan, not the locally expected two-function plan.

The prior
[run #1795](https://github.com/emreerdener/merian/actions/runs/35793015142) for
`bcc7ef8de53cefaa04bed81cb32adf7de877bf9a` was a completed successful
deployment. Its deploy job `106967866564` passed migration, Function deployment,
production smoke and health steps on 22 September. It was not a green no-op.
After run #1796's planning, the public Actions API returned that prior run first
for the same successful-main history query used by the resolver; its latest
deploy job satisfies the resolver's required successful-step checks.

The runner's history response at planning time was not retained, so the reason
it chose the older baseline is unresolved. Current API results do not
reconstruct that earlier response. No resolver parsing defect or GitHub API
fault is claimed. The older ancestor broadened the deployment plan without
omitting the audio correction.

Source review identified a separate consistency gap in
[deploy.yml](../../.github/workflows/deploy.yml): it resolves the baseline in
the scope job, again under the production lock, and again when planning
functions. A follow-up should expose the lock-time SHA as a step output and
reuse it for the Function plan and predeploy decisions, retaining the existing
fail-closed scope rules and explicit manual full-fleet path. Record bounded run
IDs and decision reasons when resolving history so a future discrepancy can be
traced. That workflow change and its contract tests are not part of this
evidence-only update.

## Identification scope and limits

Gemini remains the only identification provider. Model assignment, prompts,
generation settings, confidence rules and 16 kHz mono PCM16 output are unchanged
by the audio correction. Video identification still uses sampled images and any
companion audio, not native video inference.

The deployed source's expected identification bundle fingerprint is
`3ca39aaf706f52a560795710d470bd479414cfc961ad4b4780de0eed6ed686ec`, owned by
[deploymentIdentity.ts](../../services/supabase/functions/identify-multimodal/deploymentIdentity.ts).
This is source/deployment evidence. A fresh successful identification response
has not yet been observed with that fingerprint.

The automated smoke probes do not exercise a paid identification or establish
hosted preprocessing CPU headroom. No new app submission, paid Gemini request,
physical-device test or iOS distribution was performed in this verification.
There is no new identification-quality, latency or cost result. Earlier
benchmarks, provisional animal references and formal corpus counts of 0/60
development and 0/240 held-out groups remain unchanged.

## Next measurement slice

The
[app measurement guide](../development-guides/21-identification-app-measurement.md)
owns replay and recording behavior. Current replay retains ordinary location,
weather, locale, timezone and capture-time handling. Replaying the six frozen
clips now can supply integration evidence, but comparison with their historical
answers cannot isolate the preprocessing change.

Before a causal comparison, implement and test a Debug simulator-only,
request-local replay profile that fixes the permitted context and prevents live
location/weather enrichment from altering that request. Carry it through the
ordinary request builder without model, authentication, allowance or retry
bypasses. Keep it out of normal capture and Release builds. Verify the exact
prepared media and context at intercepted request serialization; queued or
replayed results must remain separately classified.

Fixed context alone does not supply both preprocessing arms. The subsequent run
specification must select two fresh, versioned processing arms over the same
frozen inputs, context, Gemini profile and settings. The proposed comparison is
one first attempt per clip per arm, 12 total, with a frozen order, budget and
complete accounting of failures and uncertain attempts. Preserve media and
processor hashes, bounded timings, usage and normalized outcomes; retain no
private context or raw provider responses. Keep the three animal references
provisional and the three reviewed non-biological controls separate. Six cases
cannot qualify a provider or establish an accuracy improvement.

The [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
continues to own release and recovery controls. This record adds evidence for
the completed run, not a new deployment, rollback or distribution instruction.
