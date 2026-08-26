# Release Evidence Operations

This directory contains redacted, machine-validated templates for release
evidence. It does not contain an approval to deploy. The active production
authority remains `services/supabase/release-holds.json`, and the canonical
rollout order remains the
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#species-dictionary-field-chat-hold-exit-criteria).
The `species_dictionary_chat_production_hold` is active and must remain active
until every checked-in criterion and external control is satisfied.

An active, structurally valid hold is an expected release status rather than a
candidate defect. The deployment workflow therefore reports the hold job green
with `release_status=held` and `deploy_allowed=false`, then skips the Production
job before environment approval or secret access. Missing or malformed hold
state still fails, and a green held run is never deployment evidence. Deployment
history treats its sole `completed/skipped` deploy job as conclusive
nondeployment regardless of why it was skipped, ignores that green held/skipped
run, and continues to older actual deployment history. If bounded history has no
safe actual deployment, production planning selects the full Function fleet and
every predeploy fence.

The checked-in templates are intentionally invalid. Placeholder SHAs, zero
digests, zero artifact IDs, expired timestamps, and `pending` values must never
be interpreted as evidence.

## Sources Of Truth

| Purpose                                                  | Source                                                         |
| -------------------------------------------------------- | -------------------------------------------------------------- |
| Active holds and exact exit criteria                     | `services/supabase/release-holds.json`                         |
| One criterion's redacted statement                       | `release-evidence-statement-template.json`                     |
| Species Dictionary Field Chat Production clearance       | `species-dictionary-field-chat-clearance-template.json`        |
| Legacy purchase-identity rollout worksheet               | `purchase-identity-rollout-template.json`                      |
| Protected evidence publication                           | `.github/workflows/release-evidence.yml`                       |
| Production source and clearance gates                    | `.github/workflows/deploy.yml`                                 |
| Statement, GitHub, artifact, and repository verification | `services/supabase/scripts/github_release_evidence.ts`         |
| Hold-manifest and clearance verification                 | `services/supabase/scripts/verify_production_release_holds.ts` |
| Current release verdict                                  | `docs/legal/production-consent-readiness-2026-08-03.md`        |

The purchase-identity worksheet predates the schema-v2 hold-clearance flow. It
remains the rollout record for that feature and is not a substitute for a
`release-evidence.json` statement or the protected Field Chat clearance.

## Evidence Lifecycle

1. Freeze one reviewed candidate that is the current protected `main` head.
   Dispatch evidence only from `GITHUB_REF=refs/heads/main`; the requested SHA,
   workflow `GITHUB_SHA`, clean checkout, and current `origin/main` must all be
   identical.
2. Select one active-hold criterion directly from
   `services/supabase/release-holds.json`. Do not invent, rename, merge, or
   split criterion IDs or evidence types in an operator-created statement.
3. Copy `release-evidence-statement-template.json` and populate schema version
   2. Bind the exact hold, criterion, evidence type, candidate SHA, expected
   `passed` or `approved` outcome, redacted summary, and required supporting
   workflow runs.
4. Put structured supporting proof in schema-v2 JSON payloads. Bind each payload
   to the same hold, criterion, evidence type, and candidate; compute the
   SHA-256 of the exact JSON bytes before base64 encoding them. A digest proves
   which bytes were retained, not who issued or approved an off-platform
   statement.
5. Keep the statement `observed_at`, every embedded evidence `observed_at`, and
   every supporting workflow run `updated_at` no more than 30 days old at
   verification. Required runs must be successful, complete, exact-SHA runs at
   the exact workflow paths named by the manifest. Retention longer than 30 days
   does not extend evidence freshness.
6. Dispatch **Publish Merian Release Evidence** from the current `main` head.
   Pass manual values through step `env` variables before Bash uses them. Never
   interpolate `${{ inputs.* }}` directly into a `run` script. The separate
   `Release Evidence` environment must approve publication.
7. Record the resulting uniquely named artifact ID and GitHub-reported SHA-256.
   One positive artifact ID may satisfy exactly one criterion; never reuse an
   artifact across criteria. Production verification downloads the archive,
   recomputes its digest, requires exactly one `release-evidence.json`, and
   validates its origin run, bytes, embedded payloads, and supporting runs.
8. Only after every criterion has reviewed retained evidence, review the
   candidate change that marks the hold inactive. Compute the SHA-256 of that
   candidate's exact hold manifest and populate a schema-v2 clearance from
   `species-dictionary-field-chat-clearance-template.json`.
9. Store the completed clearance only in the protected GitHub `Production`
   environment secret `MERIAN_PRODUCTION_RELEASE_CLEARANCE_JSON`. Its approval
   window must be current and no longer than seven days. Never commit the
   completed clearance or synchronize it to Supabase.
10. Before any ordinary production credential or mutation is reachable, the
    deploy workflow rechecks the exact clean current-main SHA, manifest digest,
    complete criterion set, artifact uniqueness and bytes, current GitHub
    controls, and clearance lifetime. Any missing access, mismatch, expiry,
    ambiguity, or unavailable control fails closed.

Do not dispatch a production deployment merely to test a hold. Test the source
gate, statement parser, GitHub verifier, and workflow contracts in the isolated
candidate/tooling suites.

## Redaction And Data Handling

Evidence may contain bounded result summaries, stable criterion IDs, workflow
run IDs and URLs, artifact IDs, candidate SHAs, timestamps, and digests. It must
not contain credentials, personal data, raw coordinates, auth or session state,
production response bodies, raw SwiftData stores, user media, or stable user
identifiers. Summarize device and account results without exporting the store or
identity under test.

The evidence workflow accepts only a bounded base64 statement and writes one
validated JSON artifact. Its logs must remain limited to stable control names,
criterion IDs, artifact IDs, and digests; never print the statement or embedded
contents.

## Approval And Trust Boundary

Repository verification establishes byte integrity, exact-SHA workflow
provenance, current protected-main membership, and the configured GitHub review
and environment policies visible to the read-only audit token. It cannot prove
the authenticity of an off-platform issuer, who may administer GitHub secrets,
or that an environment administrator is independent.

`.github/CODEOWNERS` currently routes all critical controls to one account. That
is not separation of duties. Before clearing the hold, add an independently
owned account or team, require Code Owner review and two current
author-independent approvals, dismiss stale reviews, require approval of the
last push, apply protections to administrators, disable bypass, and configure
both `Release Evidence` and `Production` with independent reviewers, self-review
prevention, and protected-branch-only deployment. Restrict clearance secret
administration to trusted operators. If any of these external settings or
identities cannot be verified, keep the hold active.

## Renewal And Failure Handling

- Generate a new artifact when evidence expires, its candidate changes, its
  supporting run is rerun, or any embedded byte changes. Do not extend a
  timestamp or reuse an old artifact.
- Generate a new clearance when the candidate, manifest digest, criterion
  artifact, or approval window changes.
- Never add a bypass boolean, weaken a required criterion, or substitute a local
  self-skipped database test for a non-skipped hosted/disposable result.
- A failed verification is a release stop. Preserve the artifact and workflow
  summaries for diagnosis, correct the underlying evidence or control, and
  repeat the normal protected flow.
