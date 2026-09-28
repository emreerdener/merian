# OpenAI beta still-photo activation

Date: 28 September 2026

## Authorized operation and target

The owner requested enabling OpenAI photo identification and deferring the new
user opt-in for the current beta audience. Target: the existing Naturebook
backend, Supabase Production project `qlarqavoqhkuwzmevrmf`. This authorizes the
photo adapter and photo-only catalog activation through the existing exact-SHA
GitHub deployment path. iOS archive/upload remains owner-operated separately.

This is a project-wide beta policy, not a new per-user cohort flag. Reassess the
deferred opt-in before expanding beyond the beta audience. The policy changes
processing eligibility; it never records an affirmative choice for someone.

## Ordered implementation

1. Deploy the enabled adapter from
   [PR 96](https://github.com/emreerdener/merian/pull/96). Reviewed branch head:
   `50f62e6422d98c83c56a419cb73a6481d26752a0`. Identification bundle SHA-256:
   `0f543cb5651df79aca84736560be3d66316502189427d83ff376225448321eb6`. Catalog
   assignments remain Gemini during this deployment.
2. Only after its successful Function deployment, deploy migration
   `20260928165412_activate_openai_beta_photo_identification.sql` and the
   matching native policy source. The pipeline applies migrations before
   Functions, so these stages must not be combined into the first adapter
   deployment.
3. Confirm exact-SHA deployment evidence and photo catalog selection. Keep
   source completion, runtime activation and installed-client evidence distinct.

## Scope and retained controls

- Every plan/policy binding for `scan_identification` / `multimodal_photo_v1`
  selects OpenAI, `openai_photo_v1`, `gpt-6-sol`, recipient `openai`, and
  minimum identification protocol 4. Existing quota-model keys, entitlements,
  costs and counters are not rewritten.
- Audio, five video snapshots, photo/audio, video/audio, text-only,
  compatibility routes and shared content remain Gemini. An optional note
  remains part of a photo request. The original prompt and full explanation
  format are preserved.
- Ordinary required consent still applies. No OpenAI stream or a granted head is
  eligible during beta; an explicit latest withdrawal across any disclosure
  version denies. The strict receipt validator and immutable consent history
  remain unchanged.
- The native coordinator mirrors beta eligibility without changing
  `hasGrantedOpenAI`. Account changes, uncertain storage and pending withdrawals
  fail closed. Settings offers a real withdrawal; saving a change never resumes
  a paused scan automatically. Old app binaries retain their local opt-in checks
  until the owner installs/distributes an updated build.
- Native input/output moderation, exact binding admission, quota-before-call
  commitment, V2 readers, one invocation, and immutable attempt recovery remain
  required. No provider fallback is added.

## Validation and remaining evidence

The existing Gemini/OpenAI comparison is retained. This beta decision defers the
separate paid production-profile qualification packet; it does not claim that
native moderation was measured by the earlier baseline or that full-path latency
equals provider-only latency. No new paid benchmark is part of this activation
change.

Required implementation evidence is the fresh migration replay and complete
catalog/Edge/tooling gates, native policy/retry tests, and exact-SHA CI. Actual
runtime activation is complete only after both reviewed deployments succeed. An
archived/distributed iOS build and upgrade from the preceding released build
remain separate evidence; development installation is not an upgrade proof.

## Recovery

For fresh-photo rollback, deploy a reviewed forward migration changing only
photo bindings to `gemini` / `gemini_baseline_v1` / `google_gemini`, NULL
`provider_model`, and `minimum_identification_protocol = 0`. Keep quota models,
policies, V2 readers, consent history and immutable attempt snapshots. Existing
OpenAI attempts and saved results retain their original provider; never retry an
uncertain paid call automatically on Gemini. Use the same authorized exact-SHA
Production workflow and record its outcome.

See the
[deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#openai-photo-adapter-deployment-order)
and [rollout record](../rfcs/identification-openai-photo-rollout-2026-09-28.md).

## 28 September correction: default beta access

The owner clarified that all OpenAI-specific consent collection and enforcement
are deferred during beta, including for historical withdrawals. The prior policy
above remains the record of the original activation, but is superseded by the
[beta consent correction](../incidents/2026-09-beta-openai-consent-gate.md). The
correction preserves ordinary required consent and receipt history, hides OpenAI
permission controls and makes owned legacy pauses explicitly retryable. Before
public consent rollout, every permission-required alert must link directly to
the applicable disclosure and return to the same scan for explicit retry.
