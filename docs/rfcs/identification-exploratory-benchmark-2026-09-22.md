# Exploratory identification experiment record

Date: 22 September 2026\
Status: Offline mechanics recorded; two-photo production-app benchmark
completed\
Scope: Existing Gemini identification; direct evaluator and production-app paths
recorded separately

Current status, updated 22 September: after approving the two prepared photos,
four-call maximum and USD 10 budget, the owner chose the existing production app
and its ordinary identification charges. Both normal app submissions completed
with server-selected identification profiles: the flower returned Rough Hawkbit
as a possible match in a 28.421-second app pipeline; the cat returned
`Felis catus` as a strong match in 22.387 seconds. The
[live benchmark](./identification-production-app-benchmark-2026-09-22.md)
retains the first outcomes, numeric timing evidence and measurement limitations.
The
[simulator startup incident](../incidents/2026-09-simulator-signing-recovery-loop.md)
was corrected locally, and the owner completed onboarding and the UI automation
permission setup. Dedicated evaluation credentials remain a prerequisite only
for the separate direct CLI route. The earlier preparation and access checks
below retain their historical scope; the
[production-app checkpoint](#production-app-checkpoint) records the current
route.

The owner requested automated experiments and retained benchmark results. The
local evaluator now supports a separately versioned exploratory corpus with one
eligibility reviewer, provisional or absent reference labels, and at most twelve
development groups / twenty-four calls. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs)
owns commands and controls; the
[PRD](../product/04-identification-evaluation-prd.md) and
[SRD](./identification-evaluation-srd.md) own scope and requirements.

## What this record establishes

The offline experiment is a regression reference for preparation, request
construction, normalization, accounting, persistence and report generation. Its
invented inputs and outcomes establish no measured biological quality, Gemini
latency or provider cost. The separate live record now adds two measured app
outcomes; a representative quality baseline and paired provider comparison
remain pending.

The real exploratory route retains media eligibility, dedicated project/key
readiness, current pricing, a concrete authorized USD budget, durable claims and
no silent repeat of uncertain calls. Null reference labels remain unverified;
they contribute to operational counts but not provisional quality denominators.
Formal accuracy scores and paired comparisons reject exploratory corpora.

## Recorded execution

The actual CLI executed with Deno 2.9.4, network and environment denied, no key,
and a zero-dollar offline specification. It scheduled twelve synthetic groups
across all six input types, once for each existing Gemini profile. Six reference
labels were provisional and six deliberately absent. All media and model
outcomes were invented.

| Result                                 | Flash/free | Pro/Pro |   Total |
| -------------------------------------- | ---------: | ------: | ------: |
| Scheduled / attempted                  |    12 / 12 | 12 / 12 | 24 / 24 |
| Normalized fixture outcome             |          8 |       8 |      16 |
| Deliberate refusal                     |          1 |       1 |       2 |
| Deliberate invalid output              |          1 |       1 |       2 |
| Deliberate operational failure         |          1 |       1 |       2 |
| Deliberate unknown execution           |          1 |       1 |       2 |
| Local validation failure / unattempted |      0 / 0 |   0 / 0 |   0 / 0 |

The report is intentionally `incomplete` because it retains unknown executions.
This proves uncertainty is visible, not a failed Gemini measurement. A replay
left all twenty-four claims and twenty-four result files byte-identical and
created no additional attempts. Report regeneration without network, environment
access, a Git subprocess or inference reproduced the same summary bytes. The
no-cost synthetic preflight scheduled twenty-four calls but authorized none.

Retained machine-readable evidence:

- [Offline manifest](./identification-evaluation-evidence/2026-09-22-exploratory/offline-manifest.json).
- [Offline summary](./identification-evaluation-evidence/2026-09-22-exploratory/offline-summary.json).
- [Prepared real-photo preflight](./identification-evaluation-evidence/2026-09-22-exploratory/photo-preflight.json).
- [Reviewed public pricing inputs](./identification-evaluation-evidence/2026-09-22-exploratory/photo-pricing.json).

| Identity                        | Value                                                              |
| ------------------------------- | ------------------------------------------------------------------ |
| Run ID                          | `offline-exploratory-v1`                                           |
| Corpus digest                   | `ed8fda7d32f8dc834514a7e2c184ce8926275c0400d103965090e87ef6178ebc` |
| Canonical run digest            | `9fda24cd884ab92823b8b692c14254e4f58ad4895af640eb7b786d41e3b50960` |
| Source graph digest             | `1932bf751d767bd36542776a4ae1565a0cff622be1bad9ba2a0424f31632374d` |
| Base commit, with local changes | `7cb12cce16bd736ea1dc725663cacd10471cac46`; dirty                  |
| Pinned SDK                      | `npm:@google/genai@2.23.0`                                         |
| Manifest file SHA-256           | `ffcc05261e5172f669b86c5c69e7ddc9417f0322e8cadf97d90568b3f5143a01` |
| Summary file SHA-256            | `daec50db139702fb66d8535c1244d7b8a2e8474350d03bbb0c2847b47f7e7ef5` |

The private working directory is
`/private/tmp/merian-identification-record.LP4olg/demo`. It contains the
synthetic media, frozen taxonomy/specification, fixture outcomes and original
run records. The JSON copies above retain the aggregate evidence in the
repository after local temporary files are removed. Canonical hashes and
file-byte hashes use different serialization boundaries and are intentionally
recorded separately.

To reproduce the mechanics, initialize a fresh private directory and run
`demo-exploratory DIRECTORY`, `preflight DIRECTORY`, `offline DIRECTORY`, then
`report DIRECTORY offline-exploratory-v1`, with the exact denied-network and
environment permissions in the tooling guide. New source identities or run
creation timestamps produce a new manifest digest; never rewrite the original
run to make it resume under changed source.

## Local verification

The complete Supabase tooling gate passed: 352 standard tests plus 29 steps,
nine isolated evaluator tests plus four crash steps, the 19-test and 20-test DTO
suites, and all six shell test files. Recursive type checking covered 76
standard TypeScript sources. The CLI test exercises `demo-exploratory`,
`preflight`, report regeneration without assets and rejected formal comparison.
Network and environment access were denied throughout evaluation tests.

Recursive formatting passed for 965 files, recursive lint for 774 files, and
both independent review findings (documentation drift and CLI coverage) were
resolved. Changed-Markdown formatting passed for all 32 changed documents; diff
whitespace checks and all 40 local links in the focused evaluation documents
passed. These are local tooling results. No new deployment, production data
access or real Gemini request was part of that offline verification. The earlier
runtime extraction's full Edge/disposable-database evidence remains in the SRD;
this scripts-only addition does not rerun or replace that evidence.

## Prepared first live experiment

Two public-domain photographs were downloaded, decoded, stripped of metadata,
re-encoded as RGB PNGs at a maximum dimension of 1,024 pixels, and visually
reviewed by the assistant for privacy and duplicates. Each source page
explicitly states a public-domain dedication and permission for any purpose:

- [Flower photograph](https://commons.wikimedia.org/wiki/File:Taraxacum_officinale_flor.JPG):
  reference left unverified; no species label inferred.
- [Domestic cat photograph](https://commons.wikimedia.org/wiki/File:Cat_outside.jpg):
  provisional domestic-cat reference from the source description and visible
  animal, mapped to the local `Felis catus` identity.

A third mushroom download received HTTP 429 and was not retried. It is excluded
from the corpus. The two prepared cases passed actual
asset/taxonomy/native-request preflight with network and environment denied.
They are stored outside Git in
`/private/tmp/merian-identification-public-emm31hsq`, with source, eligibility
and pricing records. No real media is copied into this repository. Retention is
set to 22 October 2026; preserve or move the controlled directory before
temporary storage is cleaned if continuing later, and review retention before
extending it.

| Prepared scope                    | Recorded value                                                             |
| --------------------------------- | -------------------------------------------------------------------------- |
| Real development groups           | 2, still photos only                                                       |
| References                        | 1 provisional; 1 unverified; 0 independently reviewed                      |
| Profiles                          | Current `gemini-2.5-flash` / free policy and `gemini-2.5-pro` / Pro policy |
| Planned calls                     | 4, one per profile per observation; no repeats                             |
| Corpus digest                     | `7f5d46e6a74f8ad91c9ed169924aa061e080db5ae9c0c0da45b66ccd8b33fbb6`         |
| Conservative schedule reservation | USD 9.633792                                                               |
| Proposed run budget               | USD 10; not authorized                                                     |
| Actual Gemini calls / spend       | 0 / USD 0                                                                  |
| Live dispatch                     | Not authorized; no live claims or results exist                            |

The reservation uses the full published 1,048,576-input / 65,536-output token
limits for
[Flash](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash) and
[Pro](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro?hl=en), with
the highest applicable standard paid rates from the current
[pricing page](https://ai.google.dev/gemini-api/docs/pricing). It includes
reasoning, assumes the highest input modality rate without a cache discount, and
uses Pro's higher context-tier rates. This is a conservative reservation, not an
expected bill for four small photos. The live report will record actual returned
usage and estimated cost; a local budget cannot promise invoice-exact billing.
Pricing expires from runner admission after seven days and must be rechecked.

The dedicated evaluation key and its project/readiness record are unavailable.
The private `run-proposal.json` freezes the proposed scope and USD 10 budget but
is deliberately not an executable `spec.json`. The owner must configure the
reviewed evaluation credential/project and authorize that concrete paid run.
Check access to both configured models: Google's current
[Flash documentation](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash)
says 2.5 access is limited to users who previously used those models. Do not
silently substitute a newer model. Source permission and successful preflight do
not establish account readiness or paid-run authorization.

This is a small live execution checkpoint. Audio, descriptions, ordered video
snapshots and paired audio remain untested. The taxonomy map contains only the
provisional domestic-cat identity; other names are unmapped and do not become
verified failures on the unverified flower case. Two public photographs cannot
establish general accuracy, stable p95 latency, confidence calibration or a
provider-switch decision. Prior model exposure to public examples is unknown.
After this live workflow is proven, expand with fresh observations across the
actual input groups while preserving first outcomes, uncertainty and failures.

## Approved budget and simulator access check

On 22 September, the owner approved the proposed four-call experiment and USD 10
budget, explaining that identification already works in the simulator. The
private `run-proposal.json` now records that authorization and
`status: awaiting_project_credential_readiness`; further budget confirmation is
not required for the approved scope.

Read-only code/configuration inspection established that the simulator uses the
hosted Supabase client configuration and an authenticated app request. It has no
Gemini provider key setting. The backend owns the key and reserves the app's
allowance before selecting and invoking a model:

- `InferenceLiveRequestService` calls `identifyMultiModal` through the iOS
  authenticated network client.
- `identify-multimodal/index.ts` calls `reserveAIProviderCall`; the reservation
  selects the actual model and tier for one app request.
- `_shared/gemini.ts` reads the server's `GEMINI_PAID_API_KEY`.
- The local evaluator calls Gemini directly through `liveCredential()` and its
  own exact run specification. It does not use the app's Supabase session,
  subscription or scan allowance.

The required evaluation key was absent from the current shell and launch
environments and the known local configuration locations. No readiness record or
executable live specification was present. The pinned Supabase CLI's read-only
secret-name check could not authenticate because its access token was
unavailable. No secret values, simulator auth/session state, user observations
or raw provider responses were printed or retained; no hosted mutation occurred.
Existing simulator access may fund ordinary app identifications, but it does not
make a direct evaluation credential or the reviewed evaluation project available
to this process.

For the direct CLI route, the remaining prerequisite is to connect a dedicated
evaluation key/project under the existing
[live-run requirements](../../services/supabase/scripts/identification_evaluation/README.md#future-explicitly-approved-live-use),
then bind its real readiness record to the already approved corpus and budget.
Do not mark an unknown or production credential as a dedicated evaluation key.
This access check made no Gemini request and added no benchmark measurements.

## Production-app checkpoint

The owner subsequently authorized using the current production process and
paying through the existing infrastructure, without a special evaluation
allowance. That authorization covers the prepared experiment; another budget
confirmation is unnecessary. The immediate schedule is two sequential ordinary
app submissions, one per prepared photo, within the previously approved
four-call maximum and USD 10 budget. The app/backend retains normal consent,
authentication, allowance reservation, profile selection and submission
handling. This schedule does not force both Flash and Pro or establish a paired
model comparison.

Both metadata-stripped public-domain photos were successfully imported into the
booted iPhone 18 Pro simulator running iOS 27.0. macOS Automation and
Accessibility access were confirmed. At this checkpoint, the installed app
reported version 1.0.3, build 275, source revision
`7cb12cce16bd736ea1dc725663cacd10471cac46`, and a dirty source fingerprint
recorded in the
[preparation receipt](./identification-evaluation-evidence/2026-09-22-exploratory/production-app-preparation.json).
This identifies that preparation installation; it does not establish that the
later benchmark installation, current worktree or hosted backend matches it.

A bounded, read-only observer was exercised against the app's existing numeric
benchmark messages. Its exact-match projection retains durations and HTTP status
only. It discards response bodies, arbitrary log content, identifiers, region,
account details and session data. The initial observation window captured zero
identification metrics and ended normally. Its projection checks passed,
including rejection of unexpected suffixes, nonnumeric values and unknown timing
fields. The observer submits no requests and does not replace the app's capture
controls.

At the preparation checkpoint, capture was unavailable, so the retained receipt
records zero experiment submissions, two unattempted cases and no latency, model
or cost measurements. This is preparation evidence, not a completed live
benchmark. Account or session recovery is outside the experiment; no account
state was modified to enable testing at that checkpoint. The later local startup
repair resolved the false recovery marker through verified Keychain absence,
without manual cleanup. After the owner completed onboarding, the normal capture
screen was observed. A separate macOS window-capture denial then blocked UI
automation until the owner completed the Computer Use helper's permission setup.
The two submissions subsequently completed as recorded in the
[live benchmark](./identification-production-app-benchmark-2026-09-22.md). The
original preparation receipt remains unchanged.

Once the capture screen is available, start a fresh bounded observation window,
select one imported photo through the normal photo picker, complete the required
crop and submit through the app. Preserve its first visible outcome before
attempting the second photo. If crop completion auto-submits, do not send an
additional submission. Associate numeric events only with an observed sequential
submission; unrelated queue activity makes that association unknown. Retain
failures and uncertain executions instead of silently repeating them.

Report app pipeline duration, request duration and available server timing as
different measurements. The first rendered processing frame is not the first
identification result. The `provider` server span measures the awaited provider
call, including transport; client request duration also includes other backend
work. Exact model, returned usage and billed cost are not exposed by this
observer and must remain unmeasured unless authoritative evidence becomes
available. A subscription tier alone does not establish the exact model. The
two-photo sample and provisional references retain the quality limitations
above.
