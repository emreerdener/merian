# Release Evidence Operations

> **Beta policy update — September 18, 2026:** The owner authorized the existing
> beta backend rollout under the
> [Field Chat beta release decision](field-chat-beta-release-decision-2026-09-18.md).
> `species_dictionary_chat_production_hold` is inactive by explicit exception,
> not because every full-release criterion passed. Statements below requiring
> all external/device/hosted-token evidence before backend rollout describe the
> full-release policy; that evidence remains open. Exact-SHA backend validation,
> live repository controls, runtime security/consent, and the UTC cutover fence
> remain required. This exception does not authorize iOS distribution.

## Automatic deployment policy

Backend-relevant pushes to protected main trigger `deploy.yml` automatically.
The pipeline runs Candidate Validation, evaluates the checked-in source hold,
and verifies the exact clean current-main SHA and live repository controls
before accessing Supabase credentials. `--mode automatic-release` uses the
read-only `MERIAN_GITHUB_RELEASE_AUDIT_TOKEN`; missing access or failed controls
block deployment. No per-deployment review or clearance secret is required.

Production and Release Evidence retain environment secret scoping and protected
branches only. Neither has required reviewers, wait timers, or custom approval
gates. Scheduled health monitors that share Production also run without review.
Removing reviewer rules does not automatically prove that already-waiting jobs
have resumed; inspect their job status and rerun a monitor if needed.

`.github/CODEOWNERS` currently routes all critical controls to one account.
Protected main retains PRs with zero peer approvals, Code Owner review and
last-push approval disabled, stale-review dismissal, strict Candidate readiness,
admin enforcement, no bypass, and no force pushes/deletion. A merged PR is the
source-change record. The automatic gate verifies one unambiguous merged-main PR
for the current SHA and the branch/environment settings.

This policy supersedes the reviewer-based policy introduced earlier on
2026-09-18. It does not attest to any deployment or clear a technical hold.

## One-time release hold

`services/supabase/release-holds.json` is the source authority. The
`species_dictionary_chat_production_hold` is inactive under the owner-authorized
beta decision above. All eight original criteria remain an incomplete
full-release checklist. It is not a machine-enforced backend hold: ordinary
qualifying main pushes may deploy automatically without renewing this exception.
There is no automatic expiry or audience gate. A broader public launch requires
an owner decision on the unfinished checklist and any renewed source hold.

A valid active hold reports `release_status=held` and `deploy_allowed=false`;
Production is skipped before secrets or mutation. Malformed or missing required
holds fail closed. A green held/skipped run is never deployment evidence or a
successful deployment baseline. If no safe deployment baseline is available, the
planner selects the full Function fleet and all predeploy fences.

Any future source-hold change requires a protected source PR and validation of
the resulting commit. Every deployment still checks current source status and
live controls. Ordinary subsequent commits do not require renewing manual
evidence or a clearance secret. Do not dispatch a production deployment merely
to test a hold.

## Retained evidence and optional audits

The canonical
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#species-dictionary-field-chat-hold-exit-criteria)
owns the criteria, rollout order, and recovery. Use
`release-evidence-statement-template.json` for retained hold-exit statements.
The templates are intentionally invalid: placeholders are not evidence.

1. Freeze the exact candidate and bind each statement to its hold, criterion,
   evidence type, outcome, candidate SHA, timestamp, and required workflow runs.
2. Keep the statement, embedded observations, and every supporting workflow run
   `updated_at` no more than 30 days old. Supporting runs must be completed,
   successful, and match the exact candidate and required workflow paths.
3. Embed only redacted structured JSON; compute its digest from exact bytes. A
   digest proves which bytes were retained, not who issued or approved an
   off-platform statement. Actual external approval remains substantive work.
4. Dispatch Publish Merian Release Evidence from current main with
   `GITHUB_REF=refs/heads/main`. It validates the exact SHA and evidence before
   uploading a uniquely named 90-day artifact. Release Evidence has no required
   reviewers. Never interpolate `${{ inputs.* }}` directly into a `run` script;
   manual inputs enter Bash through step environment variables.
5. Retain the artifact ID and digest. One positive artifact ID may satisfy
   exactly one criterion; never reuse an artifact across criteria. Retention
   does not extend the evidence admission window. Candidate changes require
   fresh matching evidence when making an exact-candidate claim.

`github_release_evidence.ts` and `--mode production-clearance` retain the older
clearance parser as optional audit tools. They download artifacts, recompute
archive/embedded digests, and validate origin, successful supporting runs,
criterion bindings, and current live controls. The legacy
`species-dictionary-field-chat-clearance-template.json` uses
`MERIAN_PRODUCTION_RELEASE_CLEARANCE_JSON`; its approval window must be current
and no longer than seven days. Automatic `deploy.yml` does not read that secret
or invoke this mode. Never synchronize the record to Supabase or commit it.

The purchase-identity rollout worksheet is separate feature evidence and does
not replace a Field Chat statement. Archived evidence remains historical; never
rewrite results or timestamps to make them appear current.

## Redaction and failure handling

Records may include bounded result summaries, stable criterion IDs, workflow
URLs/IDs, artifact IDs, timestamps, and digests. They must not contain
credentials, personal data, raw coordinates, auth or session state, production
response bodies, raw SwiftData stores, user media, or stable user identifiers.
Keep external private approvals in the restricted release record.

A failed automated check stops deployment. Correct the underlying issue and
rerun the reviewed flow; do not substitute local production pushes. Retain
candidate SHA, validation/hold outcomes, migration and Function plans,
post-deploy results, and recovery status. The main deployment path stays
automatic while source holds, required checks, and runtime probes remain
fail-closed.
