# Consolidation hosted-validation checkpoint — November 13, 2026

The user approved publication and conditional release of
`0b06154b328edbd2cb3d7e060c5a021d48ee2ddf`. It is published in draft PR 152.
Protected main has not moved, and no backend or production-site deployment has
been performed. PR 150 remains separate. The Scan ID History owner confirmed its
independent local simulator work uses synthetic seeds and no beta-dependent test
window; its checkout, app commits, simulator and caches remain untouched.

Both Vercel projects have Auto-Assign Custom Production Domains disabled, saved
and independently read back. Required checks are not yet configured. Importing
the approved SHA on either project exposes only one `test` check, linked to web
job 132315530285 in run 43551741587. The admin identity therefore cannot be
independently verified. The repair gives the two jobs their explicit
package-specific names without changing their validation commands.

The exact-SHA web and admin workflow-dispatch runs passed (43551820397 and
43551822578). Agent Quality passed. Markdown Quality failed on the unformatted
Next.js-generated block in `apps/web/AGENTS.md`; the repair formats that block.
iOS Project Guardrails failed because the new generated-identity test requires
an undeclared `xcodeproj` gem and opens an incorrectly capitalized project path.
The repair keeps the structured assertion, uses the tracked lowercase path,
exposes parser stderr on failure, and provisions a locked parser bundle in the
Ubuntu job. Native startup-safety validation separately timed out during its
18-minute build step before tests ran. The repair allows 35 minutes for that
build within a 65-minute job while preserving the selectors and 12-minute test
limit. This checkpoint does not claim that gate passed. Remaining hosted results
must be read before any release decision.

The unsigned Release archive subsequently passed. Three of six critical UI
smokes failed while looking for `MainTabBar_Scans`. The checked-in production
button already uses `MainTabBar_Naturebook` and sets the same `isScansOpen`
binding. The repair updates only those three stale queries, preserving their
queue, audio and retry assertions. It changes no app source, Debug seed or
shared UI launcher. Their hosted runtime rerun remains required; no repaired
UI-test pass is claimed.

The read-only migration inspection from protected main succeeded in run
43551825109 against beta `qlarqavoqhkuwzmevrmf`: 520 remote versions, no
remote-only versions, and neither `20261108062742` nor `20261108185855` applied.
Comparing the candidate leaves only `20261113222833` and `20261113222835`
pending. The checked-in migration planner returns `normal` against that retained
inventory. This is read-only evidence, not a migration execution receipt.

The repair is local and requires approval of its replacement SHA before
publication or release. The original packet's holds, exact-SHA validation,
protected-main checks, backend-first promotion order and stop conditions still
apply. No failing or ambiguous check may be bypassed.
