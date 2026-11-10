# History beta backend release decision — proposed November 9, 2026

## Status and authority

This is an unapproved deployment proposal. The owner approved preparation and
one validation run of backend `71aa7bf3dd87ed76f0e0848c4216bf6a3f3b38bc`, and
requested moving to the existing primary beta sooner while accepting temporary
functional limitations. That direction is not exact-SHA deployment approval. Do
not publish this hold-clearing successor until the owner approves its exact SHA,
protected-main publication and operation set for Supabase project
`qlarqavoqhkuwzmevrmf`. Retain that approval with the final release receipt.

The proposed change makes `identification_history_integration_hold` inactive
while retaining its complete criteria. The inactive manifest already clears the
source gate; pending-approval prose is not an executable restriction. Keeping
this revision unpublished until explicit approval is the authorization boundary.
It does not attest that all product or public-launch acceptance has passed.
Source clearance permits qualifying future main workflows to reach their normal
controls; it is not blanket authorization for future agent pushes or mutations.
No new hosted environment is required.

## Exact upgrade plan

The deployed baseline is `e8af791a3f531c7db1e231bd7369d03b4ba37b70`,
[deployment1860](https://github.com/emreerdener/merian/actions/runs/37105971469).
Its migration and production-smoke steps passed. Later green1863/1864 runs
skipped deployment. Git ancestry to71aa is verified.

The existing planner selects all125 functions from the complete1438-path
undeployed delta. No web/admin source paths changed. The retained November8
21:25:46UTC target ledger has372 versions;71aa has516 migrations,144 unapplied,
including the eight exact history gaps. The planner selects `reviewed-backfill`;
it checks the digest-pinned filenames and tip. The live workflow must repeat its
read-only ledger check and dry-run; unknown history or changed content stops
release. Version metadata does not prove live SQL or data contents. Do not
rename migrations or repair history to force deployment.

Use the existing protected-main **push** route. Its actual delta requires early
Ghost-merge mapper deployment, but neither early recovery-consumer deployment
nor the Field Chat cutover. Manual dispatch forces those additional operations
and is outside this proposal. The Ghost mapper's changed local dependency adds
two error-to409 mappings, with no new database call or write before migration.
Functions requiring new schema deploy after migrations. No planner flag or
workflow gate is relaxed.

The operation includes the existing workflow's synchronization of named
Production credentials to their existing destinations, ordered migration push,
function deployment, ACL audits and post-deployment schema/RPC/bundle/smoke
checks. It proposes no new credential values or rotation. Read-only GitHub
metadata confirms required secret names and the DB URL path exist; values and
validity remain checked by the workflow. Optional AI quota hashing and R2 event
overrides are absent and remain optional. No secret value belongs in evidence.

## Applicable evidence and limits

[CI524](https://github.com/emreerdener/merian/actions/runs/42723268361)
validates 71aa and remains pending at proposal preparation. Its final outcome
must be recorded; earlier CI516 does not qualify71aa. The final hold-clearing
SHA must pass its own existing Candidate Validation before any Production
mutation.

Existing evidence is reused only where source hashes match:

- All516 migration hashes in completion281 catalog evidence match71aa.
  Completion282 independently verifies4,390 Edge tests/1,170 steps, 125
  entrypoints and341 SQL-to-HTTP checks. These are local evidence, not hosted
  execution or a whole-candidate code audit.
- All22 CI516 handoff runner-source manifests match71aa. Its1,043 recorded
  checks cover account/public deletion, scan detach/delete, merge funding,
  legacy quota, completion/recovery contention, immutable media ownership,
  cleanup, expiry and pruning. Exact current CI remains mandatory.
- The existing delayed-order replay reconstructs the old tip without the eight
  history gaps, applies the pending candidate and checks the preserved Gemini
  assignment and history/security catalogs. Synthetic replay does not prove
  every existing beta-data distribution or mixed-client interaction.
- Engine's bounded upgrade-plan review maps those receipts to history ownership,
  account/deletion/scientific retention, funding/dispatch/cancellation,
  immutable media and protected-chat/recovery contracts. It found no concrete
  new uncovered destructive operation in that mapping. This is not a new
  complete code audit or a guarantee against every mixed-version failure.

The release packet retains the complete filename/hash/function plan and current
GitHub controls. Main is protected with administrator enforcement, force pushes
and deletions denied, and no mandatory PR/pre-push checks; Production and
Release Evidence allow protected branches without review/wait gates. Recheck
controls and queued/running deployment jobs at release. Empty repository-hook
metadata alone does not inventory every external provider integration.

## Preservation, repair and accepted beta limitations

Preserve accounts, scans, media, selections/revisions, original results,
permanent retired identities and invocation/quota records. Do not force blocked
merges, reset stores, run destructive/contention tests on beta, or substitute
new provider execution for uncertain original recovery. Matching delete-scan
must retain `legacy_observation_delete_requires_upgrade` before tombstone/media
work. Existing old-client failure responses are not permission to bypass fences.

Applied migrations are not undone by function rollback. Stop new work with the
existing gates and use compatible readers or reviewed forward repair. Never
remove schema, funding, evidence or retained result rows to restore service;
never independently roll back ingestion/quota/usage/scan guards while intents or
retired child identities exist. Do not assume that an older app or function can
consume new retained state. Live restore availability remains unverified; no
backup/PITR rehearsal or destructive restore is claimed or included. History
owns diagnosis and the concrete forward-fix proposal, with Engine reviewing
account/lifecycle/funding effects before any separately approved repair.

Temporary unavailable recovery/transfer responses, unfinished native/manual
walkthrough and broad resource qualification may remain beta limitations. The
user's complete current-scope engineering/manual acceptance remains open and
must finish before later deletion/export/redesign milestones. These limitations
do not waive data/account/funding safety or falsely close failed tests.

Runtime feature activation, protected-media/erasure workers, new schedules,
paid-provider test calls, phone installation, TestFlight and distribution remain
outside this operation. Existing default-off gates and installation/account
controls remain unchanged. Storage/write/expiry/erasure qualification remains
required before activating those paths; source deployment alone does not make
new journeys usable. No intentional test inference is included; existing service
traffic and workflow compute can incur normal costs. Exact cost is unknown.

After the authorized run, record actual migration/function/secret-sync and smoke
results, failures, elapsed time, deployed SHA and remaining qualification. A
skipped or held green workflow is not successful deployment evidence.
