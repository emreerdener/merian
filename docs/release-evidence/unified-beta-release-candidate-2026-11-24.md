# Unified beta release candidate — November 24, 2026

Status: prepared proposal, not publication, merge, deployment, or hold-removal
approval. The exact commit containing this record must be named in the separate
publication decision and final target-operation approval. Earlier approvals do
not authorize this successor.

## Executable effect and scope

This candidate sets `identification_history_integration_hold` inactive. That is
an executable source-gate change: once merged to protected `main`, the existing
workflow can deploy automatically after Candidate Validation and live-control
checks. There is no new approval gate, waiting period, or automatic hold expiry.
Keep this candidate off `main` until all conditions below pass. Merely
publishing a PR is not permission to merge it or start a production workflow.

The proposed targets are beta Supabase `qlarqavoqhkuwzmevrmf`,
`naturebook.earth`, and `admin.naturebook.earth`. PR150 and its Gemini SDK 3.0
change remain excluded. History, Capture and Gemini feature activation, paid
provider activation, TestFlight upload/distribution, secret rotation, and data
cleanup are not included. Preserve existing default-off feature gates.

## November 25 acceptance-policy supersession

The owner approved implementing the
[proportionate acceptance route](../development-guides/08-testing-strategy.md#consolidation-evidence-recovery-and-proportionate-acceptance--november-25-2026).
For this consolidation, verified original passes plus the single 1/6/11
recovery, reviewed change-impact evidence, final combined checks and essential
feature acceptance replace the repeated complete-native-run prerequisite stated
below. The old failed workflow remains failed. This is policy approval, not a
claim that recovery, combined checks or feature prerequisites have passed. PR152
remains frozen while the successor policy/candidate is prepared. PR150 stays
excluded. Merge, deployment, activation, holds and TestFlight authority remain
unchanged.

## Required decisions and evidence (November 24 record)

The November 24 packet required one complete exact-source hosted native gate
before the main merge; that native requirement is superseded for this candidate
by the November 25 route above. Final exact-source Supabase Candidate
Validation, web/admin checks and fresh external control readbacks remain
required for their respective operations. Retain all ordinary native suites, all
six critical UI cases, archive and coverage reconciliation. The separate opt-in
native/SQL app integration belongs to affected app activation/distribution; it
is not an added backend/sites gate. The backend Candidate Validation's C1 and
private-handoff artifacts remain mandatory and are different from that app
integration.

Prepare the source-hold change before freezing the final candidate so validation
is not repeated solely for a later hold-manifest edit. No earlier-SHA result is
relabeled as a final-candidate pass. Any later source change must be evaluated
under the approved exact-source packet.

The November 24 read-only inspection reported 520 applied migrations against 590
candidate migrations, with no remote-only or old web-retime versions. The actual
last deployment is `c435ea80f5bace1d28b6fc383f290c264c73d3d9`; the reviewed plan
contains 70 ordered migrations and all 130 functions. These are planning
observations, not final clearance. Refresh and bind the ledger, function/secret
plan, compatibility and forward-repair review, current main, running/queued
release jobs, both Vercel holds/checks and repository controls to the final
approved SHA before mutation.

## Cleanup and deployment ordering

The deployed cleanup worker is active V2. Before replacing cleanup SQL or Edge
code, a separately reviewed, exact-target operation must pause new dispatch,
cleanup admission and its cron, preserve the original pending request and UUID,
reconcile that exact invocation, and positively drain capable transactions with
full visibility and a same-server cutoff. Healthy aggregate status, timeout or
an empty single sample is not drain proof. Do not clear an unknown slot, reset a
sequence, replace a request, terminate a backend or delete private objects.

Keep cleanup paused through the existing protected Production workflow. Run
Ghost predeploy when the final function plan requires it, then normal ordered
migrations and the matching function fleet. Verify V4 catalog/worker
compatibility and aggregate health before approved resumption; then observe a
new correlated V4 receipt and exact owner settlement. The migration itself does
not perform or authorize that operational sequence.

Require backend positive/negative smokes before checked web/admin promotion. On
failure, keep downstream site promotion held, retain applied migrations and user
data, and prepare a compatible forward repair. Do not resume an old worker
against incompatible newer receipts or perform an automatic schema rollback.

The canonical deployment runbook and retained operation-specific evidence own
the executable procedure. This proposal does not claim those operators, hosted
checks, final approval or deployment have completed.
