# Audio benchmark with visible source animals

Date: 24 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: two first results and two complete observation windows; exploratory
evidence

The pika clip returned **Peregrine Falcon — Strong match**. The rooster returned
**Red Junglefowl — Strong match**, with the planned chicken species mapping
_Gallus gallus_. Both fresh responses passed app, backend, model and
fixed-context validation. This adds a documented source-label/result mismatch;
it does not establish a model accuracy rate or calibrated confidence.

The
[sanitized result record](./identification-evaluation-evidence/2026-09-24-audio-visible-caller-app/app-results.json)
retains the first outcomes and measurements. The earlier
[preparation checkpoint](./identification-audio-visible-caller-preparation-2026-09-24.md)
and its pending-review evidence remain unchanged as historical records.

## Admission and method

The owner reviewed the exact 16.424-second reel and both reference videos, then
confirmed that the calls were audible, no speech or personal information was
present, and the visible animals appeared to produce the calls. This admits the
two cases for solo exploratory evaluation. It does not independently establish
species identity, source authenticity or audio/video synchronization.

The separate admitted packet copied the reviewed WAVs byte-for-byte. References,
captions, source names and video context stayed outside model input. The pika
reference remains _Ochotona princeps_. The rooster's pre-prediction mapping
accepts domestic chicken within _Gallus gallus_; an agreement at that rank does
not establish a breed or domestic/wild status. The exact returned name is kept.

Duplicate review combined distinct recording origins and visible subjects with
exact source/WAV/PCM checks against earlier retained groups. It found no reused
source or exact duplicate. This bounded review does not establish acoustic
independence or unknown editing; the owner did not certify acoustic duplicate
detection. Public-model training exposure remains unknown.

Canonical offline preflight passed two exploratory groups and prepared four
profile variants without network or environment access. Those four variants are
not four live calls: the separately frozen app plan permitted exactly two
ordinary-app submissions. It froze at `2026-09-24T15:58:09.758Z` before either
tap. The actual account-selected route used Gemini Pro in `c0025`, then `c0026`
order.

Each case used **Debug replay → Stage audio with fixed context**, followed by
one normal Identify tap after observer readiness. There were no manual retries
or overlapping windows. The signed app was restarted between cases; source
hashes, unchanged app identity, and current consent/session ownership were
checked privately. No reset, reinstall, provider override, comparison
assignment, comparison-secret activation, direct evaluator call or deployment
occurred.

`audio-minimal-v1` supplies synthetic locale `en`, timezone `UTC`, month `1` and
time `12:00 PM`. It excludes location, weather and observation text but is not
literally context-free. The fresh measurement-v2 responses verified this
profile. Only audio was staged; the separate source videos were for human
reference review.

## First outcomes and measurements

| Case    | Provisional source reference                | First visible result                 | Displayed match | Tap to first frame |
| ------- | ------------------------------------------- | ------------------------------------ | --------------- | -----------------: |
| `c0025` | American Pika, _Ochotona princeps_          | Peregrine Falcon, _Falco peregrinus_ | Strong match    |           21.282 s |
| `c0026` | Domestic Chicken / Rooster, _Gallus gallus_ | Red Junglefowl, _Gallus gallus_      | Strong match    |           20.063 s |

The apparent disagreement against the provisional pika reference was retained
without retry or a reference change. Together with the earlier
[V2 six-clip results](./identification-audio-confidence-v2-app-benchmark-2026-09-24.md),
it supports investigating overly certain species output. It does not by itself
prove whether the root cause is recognition, confidence estimation, context,
processing, or the source recording. The rooster agreement is at the declared
species rank; its displayed common name remains a product-label observation.

| Case    | Provider call | Edge total | App pipeline | Primary estimate, USD |
| ------- | ------------: | ---------: | -----------: | --------------------: |
| `c0025` |     17.5587 s |  19.0750 s |     20.575 s |            $0.0301675 |
| `c0026` |     14.6744 s |  17.4532 s |     18.778 s |            $0.0245300 |

Median tap-to-first-frame was **20.6725 seconds**. Provider, Edge and app
intervals overlap and must not be added. The two observer windows ran from
`2026-09-24T15:59:09.214Z` through `2026-09-24T16:04:51.996Z`. Each covered 120
seconds and closed normally within its 30-second shutdown grace, retaining one
fresh HTTP 200 response, one measurement-v2 record and four timing events. No
oversized or rejected proof rows were recorded.

The primary-attempt estimates total **$0.0546975**. The retained pricing
snapshot was retrieved at `2026-09-23T22:35:58.637Z` and checked against
[Google's paid standard Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)
again on 24 September. The estimate deliberately uses the conservative Pro rates
of $2.50 per million input tokens and $15 per million candidate-plus-thinking
output tokens, with no cache discount. These exceed the short-context rate tier;
they are a primary-attempt upper estimate, not the bill or a complete cost cap.
Enrichment, other or unobserved attempts, storage and transport are excluded.

## Execution identity and evidence

Both responses used requested and returned model `gemini-2.5-pro` on iPhone 18
Pro / iOS 27.0, app version 1.0.3 build 275. The installed app signature passed.

- Clean app source: `fdfb142b6fcb96e6ae8f3c46a561015064c93cd2`.
- App fingerprint:
  `ebfa958011ec4e61dda121eea6b9d00890b67d23099dedf1612372aa5cbdb3df`.
- Existing deployed main: `b91e42ded94fe0904a30209b00d6aac8d2151d8c`.
- Expected and observed backend bundle:
  `61b69c048f009b62c45681da4219ea01fc9fef039048a9760fc57ca28b73ccc1`.

The
[previous deployment evidence](../release-evidence/identification-audio-confidence-v2-deployment-2026-09-24.md)
binds that backend source; these fresh responses independently matched its
bundle. This run did not redeploy it. The evaluator source had
documentation-only changes.

The private input freeze contains **21 files**, hash
`e82342fe83762da7989eaceee103977d318956ba7647d6e99b0e7dfa1599a586`. The
completed freeze contains **38 files**, hash
`deace8cf3681b05d7a9e3b505cbdf8c77a0dcd3613b45f4639112096519746cf`. The frozen
plan hash is `8127b89a2fccedb3c0540849c5079585cc4a505ece69ac5af0f430ad7e040ae9`.
Private directory/file modes are 0700/0600, with retention through 24
October 2026.

Offline checks used the canonical fixed-audio measurement and cost contracts.
Supplemental validation checked observer headers, pricing/scope, normal exit,
120-second bounds plus grace, chronological events and nonoverlap. Completion
rechecked frozen inputs and all retained case bindings. Documentation
formatting, 202 local links and sanitized/private evidence bindings passed
verification. A read-only contract audit checked admission, evidence boundaries
and provisional-reference wording. No runtime code changed, so native/backend
runtime suites were not repeated.

Staged hashes do not attest the complete inference bytes. UI labels were
observed and associated sequentially; they are not cryptographically bound to
telemetry. Native numeric confidence was unavailable. Native persistence,
physical microphone capture, general false-positive rates and provider
superiority remain untested. Raw logs, provider prose, production response
bodies, credentials, account IDs and precise coordinates are excluded from
repository evidence; audio remains outside Git.

## Decision and next step

Planning follow-up on 24 September: the
[controlled comparison plan](./identification-audio-uncertainty-comparison-plan-2026-09-24.md)
fixes the proposed arms, inputs, repeats and screening rules. It adds no new
live result and leaves the evidence above unchanged.

Keep Gemini routing unchanged and retain both first outcomes as diagnostic
cases. Before tuning thresholds or assigning another provider, define a
matched-context comparison focused on species uncertainty: preserve these
reviewed references, include the existing non-animal controls, freeze candidate
policies and repeat counts beforehand, then count every outcome. Resolve
disputed acoustic references independently if the next decision requires scored
accuracy.

This run changed neither routing nor confidence thresholds. It tested no other
provider or specialist model, and it is not a controlled before/after
comparison. Formal qualification remains **0/60 development and 0/240 held-out
groups**, with zero independent biological reviewers.
