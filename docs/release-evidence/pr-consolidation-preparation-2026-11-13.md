# PR consolidation preparation — November 13, 2026

Status: local preparation only. No publication, merge, deployment, activation,
phone update, or distribution is authorized by this record. Automatic prompts
remain paused. The exact candidate and executed-check results belong in the
local approval packet, not a claim that this whole baseline is
release-qualified.

## Scope

Consolidate the existing development baseline
`6b91a4cf654524da6e6a5a3e947bd35dd110c639` and compatible updates from PRs 118,
121–128, 133, 136, 138, 148, 149 and 151. PRs 116 and 141 are already
represented in the baseline and can be superseded only after their work is
verifiably integrated. PR 150 (Gemini 3.0) is excluded; Edge Gemini stays
2.24.0. Dirty isolated worktrees remain separate and preserved.

The package updates preserve existing Next.js 16.4.6 and Sharp 0.35.5 security
pins. Tiptap's four direct packages and their peer family move together to
3.31.4. The Edge fleet moves to Supabase JS 2.119.0 and JOSE 6.2.15, including
all generated function configurations, frozen graph and Field Chat bundle
identity. Supabase CLI stays 2.109.1 despite its setup Action update.

## Migration ordering and release controls

The two web-branch migrations previously named `20261108062742` and
`20261108185855` precede the deployed November 12 schema tip. Their
byte-identical SQL is prepared as
`20261113222833_public_web_explore_pagination.sql` and
`20261113222835_quarantine_public_web_explore.sql`. Original files remain in Git
history. The privileged recovery allowlist is unchanged.

Before approving execution against beta project `qlarqavoqhkuwzmevrmf`, the
bounded read-only migration-version inventory must establish that neither old
version was applied. If either exists, stop: this candidate is not suitable;
never repair the ledger or bypass migration preflight. Exact-candidate replay,
catalog tests and the normal migration planner must pass before deployment.

This candidate proposes setting `identification_history_integration_hold` to
inactive so an explicitly approved consolidation can deploy. That proposed
source change is not authority to publish or execute it. The eventual combined
approval must name this hold disposition, exact source SHA, protected main, beta
project, workflow effects and downstream web targets. Other hold criteria and
deployment protections remain intact.

## Coordinated execution, subject to approval

1. Publish one immutable candidate and validate that SHA through the required
   workflows. Do not independently merge obsolete Dependabot lockfiles or
   request another full validation for an unchanged, reusable result. Reuse
   requires the successful workflow-dispatch run and main to share the same
   commit SHA, named evidence artifacts, and the resolver’s 24-hour freshness
   and attempt checks; an equal source tree at a different SHA is insufficient.
2. Confirm live protected-main SHA, deployment controls, migration inventory,
   active jobs and exact approval. Stop on drift or failed required evidence.
3. Promote protected main to the exact validated commit object (not a new squash
   or merge commit) and use the existing protected Production workflow for beta
   Supabase. Include its credential synchronization, function plan/fallback,
   conditional existing Field Chat cutover and eligible queued maintenance
   effects in approval. Preserve History flags, saved scans and private media;
   no ad-hoc repair.
4. Verify migration/function readback before promoting the same source to public
   web (`naturebook.earth`). Pagination and visibility/quarantine require the
   new RPCs. Admin (`admin.naturebook.earth`) requires its own quality and
   deployment checks. Ensure automatic Vercel production promotion cannot run
   ahead of the database; unresolved integration ordering blocks promotion.
5. Close superseded PRs only after replacement integration is confirmed. Keep PR
   150 open and separate. Preserve branch references and recovery evidence.

## Limits and recovery

This baseline contains the owner's cross-surface refinements. The known native
audio reanalysis route that presents photo staging, remaining all-media
walkthrough, and approved UI/UX redesign are not resolved by dependency
consolidation. No TestFlight/App Store readiness or full functional acceptance
is claimed. Existing passing evidence remains scoped to its source and checks.

Before execution, retain the current Vercel deployments and beta source/version
inventory. On failed backend deployment, stop downstream web promotion and use
the canonical forward-repair procedure; do not reverse migrations or delete user
data. Any rollback or repair mutation needs its own explicit authorization
unless the final reviewed packet names that exact operation and target.
