# Release Evidence Operations

> **Beta policy update — September 18, 2026:** The owner authorized the existing
> beta backend rollout under the
> [Field Chat beta release decision](field-chat-beta-release-decision-2026-09-18.md).
> `species_dictionary_chat_production_hold` is inactive by explicit exception,
> not because every full-release criterion passed. Statements below requiring
> all external/device/hosted-token evidence before backend rollout describe the
> full-release policy; that evidence remains open. Exact-SHA backend validation,
> live repository controls, runtime security/consent, and audited cutover
> activation remain required. This exception does not authorize iOS
> distribution.

## Automatic deployment policy

Every push to protected `main` triggers `deploy.yml` and runs complete Candidate
Validation once for that exact SHA. The read-only production-scope job compares
the candidate with the last successful production deployment, using the former
backend/deploy-support path inventory. Docs-only changes with no pending backend
changes stop after validation; a newer docs commit still carries any undeployed
backend changes. An unavailable or non-ancestor baseline blocks automatic
production selection; an explicitly authorized manual deployment can establish a
baseline. Only an in-scope candidate evaluates the checked-in source hold, and
verifies the exact clean current-main SHA and live repository controls before
accessing Supabase credentials. `--mode automatic-release` uses the read-only
`MERIAN_GITHUB_RELEASE_AUDIT_TOKEN`; missing access or failed controls block
deployment. No per-deployment review or clearance secret is required.

Production and Release Evidence retain environment secret scoping and protected
branches only. Neither has required reviewers, wait timers, or custom approval
gates. Scheduled health monitors that share Production also run without review.
Removing reviewer rules does not automatically prove that already-waiting jobs
have resumed; inspect their job status and rerun a monitor if needed.

## Direct-main development policy — September 22, 2026

The normal path is **commit → push to main → exact-SHA checks pass → release**.
Branches and PRs remain optional for isolated experiments or early feedback.
Their existing checks remain available, but are not required before a normal
push. Do not create a branch, cherry-pick a subset, or merge solely to satisfy
release provenance. Commit the intended work together; keep unrelated unfinished
work uncommitted or on an optional branch.

Protected `main` has **Require a pull request before merging** and **Require
status checks to pass before merging** disabled. Keep administrator enforcement
(**Do not allow bypassing the above settings**) enabled, and **Allow force
pushes** and **Allow deletions** disabled. Do not add a ruleset or merge queue
that reintroduces a mandatory PR or pre-push status gate. `.github/CODEOWNERS`
currently routes all critical controls to one account and continues to identify
owners for optional reviews.

A failing commit can enter `main`, but it is not eligible for release. Backend
mutation requires the successful same-SHA reusable Candidate Validation job,
source holds, current protected-main identity, and environment controls. The
mutation job does not repeat the validation suite. iOS release requires the
complete same-SHA iOS Build and Test run and the existing Xcode Organizer steps;
a scope-only success is not release evidence. Optional PR evidence never
replaces the final main-SHA evidence. See the
[testing strategy](../development-guides/08-testing-strategy.md).

Only production mutation jobs share the production concurrency lock; validation
runs remain independent so later pushes cannot cancel an earlier candidate's
coverage. GitHub's pending-production queue may supersede an older pending job;
the cumulative deployed-to-candidate range retains its changes. Scope is checked
again after the production lock is acquired; an already-deployed range skips all
credential, mutation, and probe steps. A green no-op is excluded from deployment
history: migration and smoke steps must both have succeeded.

This policy supersedes mandatory-PR and pre-push-check rules from September 18.
It does not attest to any deployment or clear a technical hold. Apply the
matching GitHub settings when this implementation is ready to land; older
verifier code will reject the new branch policy until this revision reaches
main.

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

Any future source-hold change requires a source commit and exact-SHA validation
of the resulting commit. Every deployment still checks current source status and
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
