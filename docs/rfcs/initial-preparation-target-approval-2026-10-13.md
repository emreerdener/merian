# Preparation qualification target and ownership proposal

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain.

Status: October 13, 2026. **Pending user approval; no infrastructure or runtime
operation authorized.** Prepared at the user's request after documentation
checkpoint `f24f5d2e9b7cd9a6a4c4220887febd53b85afb4c`. This is a concrete
decision proposal supplementing the reviewed
[target composition](initial-preparation-target-composition-2026-10-13.md), not
evidence that a target exists or qualifies.

## Recommended decision

Adopt **`merian-prep-qualification-01`** as the planned qualification target:
one dedicated AWS EC2 `m7i.xlarge`, x86-64 GNU/Linux, Canonical Ubuntu Server
24.04 LTS, in `us-east-1`, under an owner-controlled nonproduction AWS account.
History primary owns the complete implementation; IC-1 remains the independent
interface reviewer; the repository owner controls infrastructure and execution
authorization. No second implementation writer is needed.

This chooses the deployment shape and responsibility needed to write a concrete
implementation agreement. It does not assert that an AWS account, host, AMI,
network, signing key or qualification environment has been supplied. Their exact
identities belong in a later private installation manifest and execution
request. Account access is not required to approve this design or continue local
work.

## Target specification

| Item          | Proposed choice                                                                                                                                                                                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Purpose       | Isolated, synthetic-media qualification of the original preparation owner; no customer traffic or provider calls.                                                                                                                                             |
| Compute       | One on-demand `m7i.xlarge`: 4 vCPUs, 16 GiB memory; one active preparation cohort, no pending grant queue or autoscaling.                                                                                                                                     |
| Region        | `us-east-1`. The repository deployment runbook records the production Supabase pooler in this region; this is geography rationale, not permission to connect to production.                                                                                   |
| OS            | Canonical Ubuntu Server 24.04 LTS amd64, systemd and unified cgroup v2; freeze exact AMI, kernel, systemd, filesystem and package identities before qualification. No floating image in accepted evidence.                                                    |
| Storage       | Proposed encrypted gp3 volumes: 40 GiB system plus 40 GiB dedicated journal/output data, ext4. Preserve at least 20 GiB free in the data volume before admitting a cohort. Disk sizing is a starting configuration, not measured sufficiency.                 |
| Network       | Private subnet, no public listener or public IP. Approved administrative access only. Decoder network disabled. Trusted broker egress restricted to explicitly approved test endpoints; no production credentials, provider credentials or production routes. |
| Runtime       | Existing pinned Deno 2.9.4 orchestrator; systemd-owned supervisor and isolated native decoder bundle as proposed in the composition RFC. Exact native build closure remains to be reviewed and pinned.                                                        |
| Test services | Disposable synthetic database/object fixtures only for initial qualification. Real backend/storage semantics require a separately named nonproduction integration target and authorization later. Local fixtures cannot qualify hosted late-write behavior.   |
| Default state | Worker service disabled and stopped, no boot enablement, timer, schedule, public endpoint, eligibility registration or production selection. These are preparation requirements, not changes made by this proposal.                                           |

AWS documents this instance's CPU and memory in its
[general-purpose specifications](https://docs.aws.amazon.com/ec2/latest/instancetypes/gp.html).
Canonical documents how to identify its
[official amd64 Ubuntu images](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/).
Those sources establish available building blocks, not Merian qualification.
Before installation, resolve and freeze one exact image rather than using a
moving `current` alias. Existing recorded decoder release baselines also require
fresh security/compatibility assessment and exact closure pinning.

The recommendation is an engineering judgment: native x86-64 Linux matches the
reviewed composition, while a dedicated VM gives direct control of the service
manager, journal and hostile decoder sandbox. Four vCPUs and 16 GiB provide an
initial host envelope for one cohort and its trusted controls. They do not relax
the proposed per-cohort bounds or prove hard CPU/memory enforcement. Changing
instance family, image or sandbox after qualification requires evidence review.

No spending is approved now. The later provisioning request must include the
account, region, exact resources, current compute/storage/network pricing,
maximum run window, budget ceiling and evidence-preserving shutdown plan.
Private networking and stopped volumes can incur charges; compute pricing alone
is not a complete estimate. No reservation or long-term commitment is proposed.

## Ownership agreement proposed for approval

| Responsibility                                                                                                | Owner                                                                    | Boundary                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| Infrastructure account, billing, access, installation approval and eventual operations                        | Repository owner, acting as infrastructure approver/operator             | May explicitly designate another operator later. Codex receives no standing cloud authority.                                          |
| Supervisor, broker, journal, attestation, recovery adapters, inactive manifests, migrations and DTO consumers | History primary, chat `01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1`             | Sole implementation writer under IC-1; includes the preparation-specific functional native contract.                                  |
| Lifecycle, funding/recovery boundaries, caller/privilege/lock agreement                                       | Harden main analysis engine, chat `01a112ae-2c97-77a1-bd53-5a4434510d4c` | Read-only review and explicit interface concurrence. Its automation stays paused; broader hardening does not transfer.                |
| Independent security/concurrency and cross-contract review                                                    | Read-only project reviewer/auditor                                       | Findings return to History for corrections and re-review. No parallel writes.                                                         |
| Capture visual/session refactor                                                                               | Existing Simplify capture tools workstream                               | Remains separate and awaits its own approval/handoff. Functional source-plan compatibility is not permission to absorb that refactor. |
| Device acceptance and external activation                                                                     | Repository owner                                                         | Existing device results/questions preserved. Every external operation retains its separately named authorization.                     |

The installed supervisor would own process creation, consume-before-launch
journal and installation-bound signing. The trusted broker would own fixed
source/destination resolution and credentials. Credential-free decoders would
own only one granted transform. The existing SQL preparation owner remains the
sole grant issuer and lifecycle authority; the supervisor can only narrow that
authority. No worker becomes a funding, refund or provider-dispatch owner.

## Concrete recovery choice

Use **one installation, no automatic failover, no restoration of execution
authority from a snapshot** for this qualification target.

- Every operation binds an immutable installation generation, bundle and
  supervisor identity. The original channel and positively received grant plus
  durable consume-before-launch remain mandatory.
- Process restart on the same intact installation may service new operations
  after journal integrity checks. Previously reserved or consumed operations
  never receive a replacement execution channel. Unknown journal integrity
  disables all fresh launch.
- Machine replacement, restored volumes/snapshots, journal rollback or lost
  state retires that installation for fresh execution. Old signing keys are
  never cloned into an executable replacement. Preserved verification keys and
  historical installation identities remain available for original proof checks.
- A new installation gets a new generation and may handle only genuinely new
  operations after its own authorization and qualification. It cannot reset,
  regrant, reassign or re-create the logical identity of held operations.
- Recovery for an old operation has no decoder or fresh signing capability. It
  can use exact registered output bytes plus the original authenticated
  statement and original deadlines, or return original status/outcome. Missing
  bytes or uncertain execution hold; no transform, provider invocation or refund
  is inferred. After settlement expiry, only committed outcome replay or hold is
  permitted; original erasure obligations continue.

The next private contract must enforce installation retirement and per-operation
binding server-side, in addition to the protected local journal. An operator
label or filesystem lock alone is insufficient. The first version deliberately
accepts loss of availability for uncertain work. Reconsidering high availability
would require a new reviewed fencing protocol, not an infrastructure toggle.

## What approval unblocks

Approval of this proposal selects the target design, ownership and recovery
policy and authorizes the following **repository-local** sequence under the
existing review and checkpoint rules:

1. Complete the target-specific implementation agreement: versioned bundle and
   installation identity; authenticated statement and atomic registration;
   installation retirement; exact private caller/privilege/lock inventory;
   original recovery/deletion behavior; generated consumers and test vectors.
   Obtain independent and IC-1 concurrence before the corresponding code or SQL.
2. Settle the distinct functional photo/audio/video source-plan agreement. Keep
   the current native crop/WebP/JPEG/44.1 kHz behavior and the proposed video
   recipe explicitly distinct. No new duration, resolution, format restriction
   or resampling policy becomes a product requirement by approving a VM.
3. Implement the agreed bounded increments locally, with inactive configuration,
   focused tests and complete affected gates at coherent milestones. Commit
   independently reviewed local checkpoints. No placeholder schema or invented
   installation identifiers stand in for missing evidence.
4. Prepare a separate exact-target provisioning/installation/qualification
   packet. Bind the account, image/kernel/manager and executable hashes,
   isolated network/test endpoints, signing/journal ownership, cost ceiling, run
   window, crash/resource/erasure tests and evidence retention. Present that
   packet for named external-operation approval before any cloud mutation or
   remote run.

The remaining executable gates include full legal photo/audio/video cohorts;
hard aggregate CPU/native-memory bounds and termination reserve; main-process
death and hostile helper containment; journal crash/restore/retirement; atomic
statement registration; immutable-byte recovery; late accepted writes and
erasure; and completion inside original deadlines. Proposed cgroup controls or
generous host memory do not count as passing results. A failing target remains
ineligible; there is no automatic switch to a different host or reduced product
scope.

This approval would remove the design/ownership decision blocker. Exact
installation facts and authorized target evidence remain later gates. Original
dispatch/result/completion, native journeys and integrated acceptance remain
open; version deletion, source export and the approved redesign follow in their
existing order. No claim of full alpha readiness follows from target selection.

## Approval text

> Approve `merian-prep-qualification-01` as the planned AWS EC2 `m7i.xlarge`,
> Ubuntu 24.04 amd64, `us-east-1` qualification target, with the ownership and
> no-failover recovery arrangement in this proposal. Authorize History primary
> to complete the independently and IC-1 reviewed implementation agreement and
> subsequent repository-local implementation and validation. Keep activation
> disabled and ordinary production access nil. This does not authorize spending,
> provisioning, installation, remote execution, hosted scheduling, publication,
> push, deployment, provider calls, device work or distribution; present a
> separate exact-target request before any such operation.

Approval is requested because the existing user instruction reserves the target
and ownership decision and separately named external-operation permissions. It
is not a new skill-imposed confirmation or a request to reapprove routine work.
