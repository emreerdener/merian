# CPM-1 approved local preparation checkpoint

> October 13 subsequent feasibility review: **do not adopt IVI-1 yet**. The
> [operational review](client-prepared-media-ivi-feasibility-review-2026-10-13.md)
> identifies unsupported all-writer closure and provider-transient storage
> guarantees, an unqualified marker-based reconciliation alternative, and
> recommended verification-retry/measurement revisions. Earlier design
> concurrence is historical evidence, not feasibility closure. Recommendations
> remain unadopted; no schema expansion, implementation or experiments follow.

> October 13 follow-up: the human authorized drafting the
> [IVI-1 incremental verifier and ingress contract](client-prepared-media-incremental-verifier-ingress-2026-10-13.md)
> within the approved limits for independent and IC-1 review. It is a design
> draft only: runtime implementation and further experiments remain gated,
> activation disabled and AWS unapproved. Prior evidence is unchanged.

Status: October 13, 2026. The human approved proceeding with the reviewed
[limits, retention and PR116 integration plan](client-prepared-media-limits-and-integration-proposal-2026-10-13.md)
after its local documentation checkpoint
`3e1405447f4c43f01413adb3b8a35bcca9da6a1b`. This dated decision supersedes the
earlier proposal's pending-approval wording. It does not retroactively qualify
its assumptions or any executable candidate.

## Approved work and continuing boundaries

- Adopt the documented original-byte definition, private retention/ownership
  rules and numeric envelope as CPM-1 product targets, including
  oversized-import refusal and the whole-backend release-hold tradeoff.
  Original, AI and preview identities stay distinct. Client derivation remains a
  claim, not server proof.
- Proceed with the bounded local F1–F4 feasibility preparation/evaluation and
  source-integration safeguards. Two engineering days, synthetic local material,
  no AI calls and no AWS. Device and hosted components need separately named
  authorization and remain pending. Local results never qualify them.
- Keep the old admitted contracts unchanged. A fresh versioned CPM schema, audio
  recipe/quality agreement, effective caller/reference/clock/lock agreement and
  feasibility evidence still precede runtime implementation. Numeric policy
  adoption does not close G1–G4 or the alpha acceptance matrix.
- History primary owns all writes. IC-1 and independent reviewers are read-only.
  No new writer, broader hardening, Field Trip or capture visual handoff occurs.
- Keep activation disabled, ordinary access nil and AWS unapproved. No push,
  merge, deployment, hosted scheduling, provider call, device installation,
  TestFlight or distribution. PR115 remains untouched. The source-integration
  checkpoint and later redesign keep the reviewed sequence.

## Local production hold

`services/supabase/release-holds.json` now has active
`identification_history_integration_hold`, scoped to `supabase_production` and
owned by the History release owner. It uses the existing verifier and workflow;
no deployment workflow change is needed. The Field Chat entry remains unchanged.
This is a local candidate change, not protection already installed on main or on
a running job.

For a scoped push or manual dispatch, the existing source-status job must return
`held` and `deploy_allowed=false` before the Production job. The
automatic-release verifier must independently deny the manifest before live
control access. Candidate Validation remains independent and may validate held
source. A docs commit after undeployed backend work still includes that whole
undeployed range.

The hold blocks all Supabase production releases. Removal requires a separate
exact-SHA/target backend release decision, reviewed complete undeployed
migration/function/secret plan, compatibility and rollback/forward-repair
qualification, and live repository/job/external-hook checks. No local test can
prove that old jobs or external integrations are stopped. No workflow is
remotely dispatched for this checkpoint.

The integration cut remains committed history through `70b75279f`, reviewed
proposal/approval documentation and this hold delta. Exclude the pre-existing
115 unrelated paths, further CPM runtime implementation and redesign. Freeze and
review the resulting exact source tree before any later push/merge request; this
small hold checkpoint does not claim full integration validation.

## Evidence and next boundary

Evidence is retained under `.artifacts/client-prepared-media/approved-plan/`.
Local source-hold verification and documentation checks qualify only the listed
candidate files. Failed evidence and earlier snapshots remain intact. Backend
feasibility must first resolve bounded ingress and immutable late-write
behavior; measurement of hashing alone cannot prove that transport contract. Do
not start runtime adapters merely because a local hash or model test succeeds.

F1/F2 retain user-run device qualification; F3 needs a separately named hosted
nonproduction target for resource qualification; F4 needs separately authorized
private-storage integration for late-write closure. Until then those acceptance
rows stay open, and uncertainty keeps its original identity and reserved storage
liability without another provider invocation or inferred refund.

## First bounded feasibility result

The 12-case offline reuse experiment feeds synthetic 64 KiB, 12 MiB and 32 MiB
streams into the existing `readInitialStream` and `initialMediaHash` primitives,
with valid, corrupt, oversized and truncated cases at each size. It calls those
primitives in an isolated harness without entering runtime admission or the old
adapter, whose 12 MiB guard remains unchanged. Network and environment access
were denied; no originals, provider calls, uploads or device runs were used. All
expected byte/length/hash outcomes passed.

Observed process RSS reached **172.59 MiB**, exceeding the proposed 96 MiB
worker-memory target. Sampling is only a lower bound on true peak usage; local
Deno is not hosted Edge qualification. The current reader retains chunk copies,
aggregates a complete buffer and then hashes the complete buffer. Merely feeding
it 1 MiB chunks does not make it an incremental verifier. Do not transplant that
path into CPM with raised constants. This is failed reuse-feasibility evidence,
not a reason to raise the approved target or add AWS.

Next local design requirement is a bounded incremental verifier/ingress contract
for the new CPM envelope, including cryptographic/library compatibility,
pre-accept byte limits, immutable destinations and original authority clocks.
That contract must be independently reviewed before runtime implementation. Its
hosted feasibility still needs the named nonproduction target and all-writer
storage policy; a local model cannot close late-write liability. Preserve the
failed measurement in `buffered-verifier-spike-results.json` with its harness
and source hashes. F1–F4 remain open.
