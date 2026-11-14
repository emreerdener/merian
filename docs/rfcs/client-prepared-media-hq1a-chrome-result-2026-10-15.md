# HQ-1A resumed inventory: access resolved, measurement gaps remain

October 15, 2026. This is the read-only result of the user-approved
[HQ-1A scope](client-prepared-media-hosted-qualification-decision-2026-10-15.md).
The user identified Chrome after the in-app browser again required sign-in.
Chrome's existing signed-in session worked. The earlier
[access-blocked result](client-prepared-media-hq1a-inventory-result-2026-10-15.md)
remains historical evidence. **No hosted test is recommended or authorized by
this result.** Activation remains disabled, AWS and 160 MiB unapproved, all
limits unchanged, and auto-prompts paused.

## Observations and limits

The resumed window began at 21:05:56 UTC with a 21:50:56 UTC deadline. All
external observations stopped by 21:10:02 UTC. Seven observations were counted
conservatively, including the unsuccessful in-app access, the Observability
navigation shell and three public documentation reads. This stayed within 12
total: one access observation, one target observation, three telemetry
observations and two platform-help observations. Reading a completed loading
page did not reload it. No polling or query retries occurred.

The Chrome browser extension was unavailable; the documented native Chrome UI
provided access to the user's already-open target dashboard. No login,
credential-store discovery or permission change occurred. The user-owned tab was
left open. No raw dashboard snapshot or customer traffic totals were saved as
evidence; only the capability findings below were retained.

| Capability                                 | Evidence obtained                                                                                                                         | Finding                                                                                                                                                                                                                                                                                                |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Target context                             | Existing project `qlarqavoqhkuwzmevrmf`, Pro, main production, Healthy; database region us-east-1                                         | Access resolved. This dated observation is not a later test-health pass. Database region is not an Edge execution-region guarantee.                                                                                                                                                                    |
| Current Edge runtime and resource override | No Edge build/version or worker-lifetime override exposed on inspected surfaces                                                           | Unknown; prior v1.77.0 observations remain historical. No longer lifetime inferred.                                                                                                                                                                                                                    |
| Dashboard timing                           | Edge report's visible query definition averages `execution_time_ms`, grouping by minute and `function_id`; selected range Last 60 minutes | Millisecond execution-time averages, not attributed CPU. Minute grouping does not establish collection resolution or peak coverage.                                                                                                                                                                    |
| Dashboard memory                           | Four report panels cover invocation count, status, execution time and region                                                              | No CPU or native-inclusive memory metric exposed on this inspected report. This is not proof no other platform interface has such metrics.                                                                                                                                                             |
| Shutdown diagnostics                       | Official shutdown guide documents CPU milliseconds, shutdown memory snapshot and execution correlation                                    | Potential diagnostic fields, not measurements from this target. Neither lifetime peak nor per-request CPU attribution established.                                                                                                                                                                     |
| Retained experiment events                 | No event query executed; zero records retrieved                                                                                           | Exact deleted experiment function/deployment selector was not present in the checked retained preflight, operator ledger or result metadata. No safe bounded selection established before retrieval; broad logs were not opened. Retention, coverage and values remain unknown, not expired or absent. |
| Identity and overlap                       | No supported affinity or physical read-overlap mechanism established                                                                      | Prior 25 hosted aliases remain the applicable evidence; client pairs cannot prove same-worker contention or overlap.                                                                                                                                                                                   |
| Exact hosted GAC-1                         | Reviewed proposal retains the 400-second hosted lifetime versus 680-second same-module schedule                                           | Blocker unchanged; this inventory found no override or supported replacement method.                                                                                                                                                                                                                   |

The observed dashboard queries derive counts, status, elapsed-time means and
region from invocation logs. No query was executed by the agent. Inspecting link
definitions is distinct from opening their log results.

The official
[shutdown-event guide](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained)
describes CPU use in milliseconds and memory at termination. A termination
snapshot cannot establish a lifetime maximum; an execution identifier alone
cannot establish exclusive request attribution or deterministic routing.

The official [Logs guide](https://supabase.com/docs/guides/observability/logs)
states that an unfiltered Logs view queries Postgres and API Gateway and that
retention depends on plan. The
[field reference](https://supabase.com/docs/guides/observability/log-field-reference)
uses ClickHouse string-valued attributes and warns that fields need not be
populated on every event. Consequently, opening broad Logs and filtering after
retrieval would not satisfy HQ-1A. No such retrieval occurred. This is a
selection limitation of this inventory, not a claim that historical events
cannot be recovered through a separately established safe selector.

## Recommendation and acceptance disposition

**Keep the finite local GAC-1 checkpoint closed and do not repeat the old hosted
fixture schedule.** This inventory resolves the access question and strengthens
the dashboard timing definition, but does not close CPU, native-memory, affinity
or overlap acceptance. No complete hosted verifier candidate exists. The local
20-read pass and its case-4 warning and 7.8125 MiB cross-cohort increase retain
their exact, limited meaning.

Before another hosted campaign, decide an explicit replacement acceptance method
that fits the supported worker lifetime and names attainable CPU and memory
evidence. Merely shortening GAC-1, pooling workers, dividing worker CPU among
requests, or treating absent shutdown failures as a pass would change the
contract without proving its intended guarantees. No such change is adopted. A
safe exact selector for existing experiment diagnostics could support a separate
bounded read-only follow-up, but is not itself a sufficient reason to run new
traffic. Do not create traffic to fill telemetry gaps.

Product admission, source retention, audio quality, ingress/recovery/deletion,
native journeys and integrated IC-1 acceptance remain open. Fresh submissions
still require actual media; original-operation recovery and immutable submitted
descriptions remain protected. History primary remains sole writer. No engine or
capture-UI handoff changes. Later deletion/export and redesign sequencing is
unchanged.

## Evidence and review boundary

Sanitized ledger, status preservation and exact review manifest reside under
`.artifacts/client-prepared-media/hq1a-chrome-inventory/`. New retained evidence
must remain below 64 KiB, aggregate evidence plus reserve below 512 MiB, and
free disk above 20 GiB. All 115 unrelated paths were verified unchanged before
writing. Prior accepted evidence is preserved by prefix mappings.

Zero function invocations, tests, R2 reads/writes, uploads, credential changes,
secret installation, deployments or remote mutations occurred. No remote cleanup
obligation arose. The retained R2 credentials and old control object were
untouched. Independent and IC-1 review assess the recorded findings and exact
artifacts; they do not independently replay the browser observation.
