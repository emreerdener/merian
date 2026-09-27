# Shared species-content qualification

Status: implemented and verified locally. All assignments stay Gemini.

## Decision

Primary identification and shared species content have independent assignments.
Descriptions, lookalikes and group tags are canonical public knowledge reused
across observations. Group tags also feed discovery/Field Trip semantics, and
lookalike relations retain their own taxonomy, ranking and curation rules.
Changing the primary identification provider must not implicitly change those
content producers or accept a new profile into their shared writers.

`_shared/ai/sharedContent.ts` now owns a qualification boundary independent of
the routing registry. The preparation wrapper accepts only the existing Gemini
binding, Flash model for user and public-job profiles, task/prompt/schema,
English overview locale and exact generation configuration. Unknown additional
snapshot or generation fields fail closed. The wrapper runs after existing
admission but before user quota commitment or provider invocation. Local
rejection refunds the user lease; public-job rejection records failure through
its existing bounded retry lifecycle. Biology helpers also validate snapshots
before invoking. These checks grant neither recipient permission nor job/scan
authority. The shared-operation quota policies use Flash for every plan; the
broader adapter registry's ability to prepare Pro does not qualify it for these
canonical writers.

Foreground overview/lookalike singleflight keys include a fixed shared-cache
contract namespace, task, canonical species ID (name fallback), exact input
name, locale and taxonomy evidence. Equivalent requests still share the
completed write; different evidence no longer shares a pending result. Existing
cache-hit predicates, curated/rejected relation rules and public response
payloads remain unchanged.

## Historical data and future candidates

This is a generation guard, not a migration of historical cache provenance.
Existing canonical rows retain their established interpretation, including
curated, GBIF/Wikipedia and legacy model content. They are not assigned invented
exact provider snapshots, cleared or automatically regenerated. The public
`species_content_provenance` row remains generic source/freshness metadata; no
private execution configuration is placed there.

Before another content provider can replace canonical values, qualify each task:
overview factuality/locale, group-tag semantics and downstream discovery/Field
Trip behavior, and lookalike identity resolution/ranking/merge policy. Competing
candidate outputs need private storage or an explicitly reviewed promotion
design. Updating a model name or the routing registry alone will not pass the
independent guard. Primary identification can progress separately while these
tasks retain Gemini, with their existing independent permission and quota rules.

## Remaining activation gates

The local infrastructure slices now cover recipient preflight/recovery, durable
result provenance, native/public/chat/export metric interpretation, provider
usage attribution and the shared-content generation boundary. OpenAI remains an
evaluation adapter, not a production assignment.

The next provider-selection milestone is a prospective matched, qualified
held-out comparison. Existing Gemini and OpenAI measurements use different
inputs/timing boundaries and do not establish a winner. A selected candidate
still needs exact usage-unit/pricing mapping, reviewed disclosures, a supported
client capability and the documented genuine released-build upgrade check.
Enabling consent collection, adding a production profile and deployment must
follow those decisions and the explicit operation/target release authorization;
no automatic rollout is added.

## Verification

- Focused provider/helper/worker tests passed: 20 tests and 70 steps. They
  verify baseline request preservation, pre-commit rejection/refund for changed
  provider, prompt or Pro model, public-job rejection without invocation/write,
  singleflight identity dimensions and helper rejection before HTTP invocation.
- The complete Edge suite passed with the disposable database: 2,130 tests and
  277 steps. All 101 deployment entry points passed recursive type checks, as
  did whole-tree format/lint, isolated dependencies, generated contracts and
  migration contracts. No SQL migration or database grant changed in this slice;
  the database retained the preceding successful fresh replay and
  62-catalog/405-assertion gate.
- Complete tooling passed: 438 standard tests/32 steps, 58 evaluation tests/29
  steps, 19 DTO tests, 21 wire-contract tests and ten shell suites. The required
  Identify deployment digest was regenerated and diff-reviewed; the Field Chat
  identity remained unchanged.
- Independent read-only review found the initial guard too broad for the actual
  Flash-only quota policies. Restricting canonical generation to Flash, with
  regression tests for rejecting Pro, resolved that finding. No remaining review
  blocker was found. No live model request, hosted mutation or production
  assignment change occurred; no native/admin/public-web runtime changed in this
  slice.
