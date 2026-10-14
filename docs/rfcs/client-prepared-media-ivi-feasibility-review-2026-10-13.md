# IVI-1 feasibility and operational recovery review

> October 13 bounded follow-up completed: the human separately approved the
> [buffer-lifetime investigation and budget reassessment](client-prepared-media-buffer-lifetime-budget-review-2026-10-13.md).
> All three local modes passed the unchanged 96 MiB experimental target;
> loopback fetch peaked at 89.75 MiB. The prior failure remains valid. These
> results do not establish hosted fit or long-run stability; no higher budget is
> adopted. That finite investigation is finished, further experiments and
> runtime implementation remain gated, activation disabled and AWS unapproved.
> The auto-prompt remains paused.

> October 13 subsequent human decision: the accounting boundary, bounded
> per-attempt retry semantics and local feasibility exercise are approved in the
> [local feasibility record](client-prepared-media-local-feasibility-2026-10-13.md).
> It supersedes prior pending-approval and aggregate-retry-budget wording for
> those decisions only. The exercise stopped at a 122.81 MiB warm-process memory
> result against the 96 MiB target. No further experiment or runtime
> implementation follows from this record; hosted/device qualification remains
> open, activation disabled and AWS unapproved.

Status: **recommend revisions before adoption**, October 13, 2026. This review
qualifies the design-only concurrence at
`b3c8183ed54c9653481b72e15478bddd8698ea8f`; it does not adopt IVI-1 or an IVI-2
contract. The user requested review and recommendations, not implementation or
hosted testing. No experiment, schema, DTO, runtime, limit or release control is
changed. AWS remains unapproved, activation disabled, ordinary access nil, and
all push, merge, deployment and device restrictions remain.

The backend-owned control plane and incremental verifier remain sensible.
However, **all-upload physical completion, provider-internal temporary storage
bounds, and the stated resource measurements are not established**. Do not build
the schema agreement around those claims. The approved CPM policy targets stay
in place; any proposed change to their meaning needs explicit agreement.

## What the existing system actually establishes

| Claim                                                                                               | Evidence and qualification                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Backend can fix owner, intent, ordered media identities, references and original operation identity | Existing lifecycle design and local code provide the basis. The new CPM transaction and wire contract are still unimplemented; a digest is not provenance or safe decoding.                                                                                                                                        |
| Private direct PUT with conditional creation is a credible candidate                                | R2 documents presigned PUT and `If-None-Match`. Its consistency model supports authoritative uncached reads. These capabilities are not proof of this app's signer, IAM, framing or race behavior.                                                                                                                 |
| Existing code can model irreversible retirement                                                     | `mediaStorage.ts:markInitialMediaErased` writes a content-free same-key marker; `mediaVerification.ts:eraseOneInitialMediaObject` reconciles it. The source-lifecycle migration records retirement/marker confirmation. Production composition and target qualification remain absent.                             |
| Current helpers enforce CPM ingress                                                                 | **No.** `aws.ts:generatePresignedPutUrl` signs length/type but lacks the new conditional-create discipline. Generic PUT/COPY/DELETE helpers cannot establish exclusive namespace ownership. `mediaHandoffStorage.ts` has a stricter injected signer boundary but remains uninstalled and capped at the old 12 MiB. |
| URL expiry or a client timeout closes every upload                                                  | **No.** A presigned URL can be used repeatedly before expiry. The public documentation reviewed supplies no authoritative census of all in-flight uses or a per-URL join/cancel mechanism. This is an evidence gap, not a claim that no future provider facility could exist.                                      |
| Local buffering failure proves streaming fits                                                       | **No.** The retained synthetic run reached 172.59 MiB RSS. It motivates streaming; it does not qualify a different implementation or hosted runtime.                                                                                                                                                               |

Primary sources reviewed:
[R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/),
[S3 compatibility](https://developers.cloudflare.com/r2/api/s3/api/), and
[R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/).
Repository evidence is under
`services/supabase/functions/_shared/initialAnalysis/`,
`services/supabase/functions/_shared/aws.ts`, and
`services/supabase/migrations/20261011194522_prepare_initial_media_source_lifecycle.sql`.
The earlier runtime RFC already states the marker's qualification conditions in
[its late-write discussion](initial-media-handoff-runtime-2026-10-13.md).

## 1. Upload bounds: narrow the guarantee and qualify the real path

Recommend exact-key, single-part PUT with signed exact `Content-Length`,
`If-None-Match: *`, permitted content type and a nonrenewable expiry. Durable
issuance precedes capability escape. No overwrite, multipart, copy,
client-chosen key, content encoding or alternate writer may bypass that
boundary. Actual stored bytes must equal the reserved length before the object
can qualify.

That recommendation is **not yet a demonstrated size limit**. Signing a header
alone does not establish what the actual HTTP client, signer and storage service
do with omitted/conflicting lengths, chunked framing, truncated or excess
bodies, repeated URL use, or a request crossing expiry. R2's generic single-part
ceiling is approximately 5 GiB, far above CPM's 32 MiB original-photo ceiling.
R2 does not offer HTML-form presigned POST as a drop-in `content-length-range`
alternative. [R2 limits](https://developers.cloudflare.com/r2/platform/limits/),
[presigned operations](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).

Separate three quantities in the next agreement:

- **Committed application media:** enforce declared per-object length, unique
  inventory, whole-package and owner/global reservations. No oversized committed
  object is acceptable, even if a later verifier would reject it.
- **Application-owned staging/scratch:** account for all copies, interrupted
  transfers and retained generations under the existing budgets.
- **Provider-internal ingress/transient work and request cost:** do not claim
  that a reusable bearer URL bounds these to one reserved object. No such proof
  was found. Repeated failed attempts may consume service work without creating
  another committed object. A separate abuse/cost control and target evidence
  are needed; client retry limits alone cannot constrain an adversarial holder.

IVI-1 currently combines these quantities. Recommend revising that claim before
adoption. This does **not** silently redefine the approved 192 MiB intent or 53
GiB global envelope. If those budgets must bound every provider-internal byte
and request, direct presigned ingress is not presently established as feasible.
An alternate enforcement path would require a new proposal, not automatic AWS
approval or an extra server.

## 2. Reservation release: fence effects instead of joining all writers

Recommend evaluating the repository's existing
`conditional_create_permanent_same_key_marker_v1` protocol. It offers a credible
reconciliation path for **committed media**, subject to target proof:

1. The server irreversibly retires the exact binding and prevents new admission,
   capabilities and references. Surviving-version holds prevent shared-asset
   retirement; active readers/exporters/verifiers are resolved under their
   separate bounded lease rules.
2. The sole erasure authority replaces the key with an unconditional zero-byte
   `erased-v1` marker. All media writers, including already issued capabilities,
   must perform create-only PUT at that same key. Never DELETE the marker or
   recycle the key. Ordinary delete-and-check-absence would reopen a late-write
   window.
3. If storage atomically orders conditional creation against marker replacement,
   either data commits first and the marker removes it, or the marker commits
   first and data creation fails. Even a request started earlier cannot recreate
   media. This is a conditional reasoning argument, not existing hosted proof.
4. Uncached exact-key marker readback plus a current retirement claim permits an
   idempotent ledger transition releasing that object's committed-media
   reservation. Lost PUT or ledger acknowledgements use exact-key/ledger
   reconciliation; they do not mint another destination. Unknown marker status
   retains the reservation and durable cleanup work.

This substitutes **proof that no future media commit is possible** for proof
that every network request has physically ended. It cannot prove that upstream
buffers or costs have disappeared. The accounting boundary must be agreed first.

The dedicated target must exclude unconditional media writes, DELETE, COPY,
lifecycle removal, restoration/rollback and old credentials or capabilities that
can bypass the marker. A DB protocol label, fake `Map` test, or IAM change whose
propagation is not settled does not prove that exclusion. Marker replacement,
metadata preservation, atomic final visibility and race ordering need target
qualification. Existing code models these obligations; it does not install them.

Cleanup must remain runnable when admission quotas are full, resume after
process loss, and retry the same marker with bounded backoff. Retain the
approved 25-object/30-second batch, two-minute claim and two-worker ceilings as
targets; target throttling must be honored. Alert on oldest unresolved
retirement, held bytes, reconciliation failures and pending-work growth. A
storage outage may temporarily block release; elapsed time must never convert
uncertainty to success. Once storage recovers, repeated exact-key reconciliation
must drain the finite retired inventory without new uploads or manual row edits.

Permanent markers and opaque tombstones consume metadata/object-count capacity
even with zero content bytes. They require a separately approved budget,
allocation rate limit and observability before adoption. Exhaustion blocks new
allocations while preserving recovery/cleanup; it cannot justify deleting the
fence. No finite marker TTL is recommended without a separately proven bound on
all old write authority. This review does not claim indefinitely sustainable
operation under unlimited churn or propose an unmeasured numeric metadata cap.

## 3. Resource numbers: targets with an explicit measurement gate

Keep 96 MiB total memory, one second CPU and 30 seconds wall time as
**provisional qualification targets**, not measured feasibility or enforceable
JS hard caps. They were selected for headroom and bounded latency, not derived
from the failed buffered run. Supabase publishes 256 MB memory and two seconds
CPU per request; isolates can serve multiple requests. These larger platform
limits do not prove our stricter profile. A 32 MiB object alone needs over 1.07
MiB/s to finish within 30 seconds, with additional time needed for auth, ledger
and network latency.
[Supabase limits](https://supabase.com/docs/guides/functions/limits),
[CPU/isolate behavior](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits).

Before a new experiment, specify pinned runtime/build, full verifier source
graph, actual-route timing boundaries, concurrency, cold/warm runs, byte/chunk
cases, instrumentation and pass criteria. Report total worker memory, including
native fetch/hash buffers; do not subtract baseline or relabel process RSS as
isolate memory. A sampled maximum is a lower bound. Supabase's documented
shutdown memory is a snapshot; CPU metadata must be attributed to the tested
request rather than assumed to exclude other work in a reused isolate.
[Shutdown metrics](https://supabase.com/docs/guides/troubleshooting/edge-function-shutdown-reasons-explained).

First determine whether target instrumentation can establish the required peak
and CPU attribution. If it cannot, revise the measurement/acceptance definition
for explicit review instead of asserting a pass or leaving an impossible gate. A
wall timer bounds eligibility to publish a receipt; it cannot forcibly stop
synchronous hashing or prove CPU/memory safety. Object deadlines should cancel
I/O and reject late receipt commits; termination/overlap resource behavior still
needs evidence. Any numerical relaxation requires explicit approval. Streaming
has not yet passed any of these gates.

## 4. Verification retry is not repeat AI execution

Recommend replacing IVI-1's blanket no-new-verification-attempt rule with
bounded read-only retries of the **same immutable object, manifest and
authority**:

- Recover an existing receipt first. If the receipt commit outcome is unknown,
  read the original ledger state; a plain absent read is insufficient while an
  older commit can still arrive. Serialize/fence that commit before replacement.
- A settled transient GET failure can restart full hashing from byte zero. No
  new object, upload, manifest, admission, reservation, funding or provider call
  follows from that retry. Verified invalid bytes, retirement, revoked authority
  or expiry are not transient retry cases.
- Proposed initial retry policy for later approval: at most **three total hash
  attempts per object/manifest in the original intent**, including attempts with
  lost responses; persisted counting, bounded backoff, and no client reset.
  Preserve a **single aggregate budget**: one nonrenewable 30-second window from
  the first verification request, including backoff and reconciliation, and at
  most one second total CPU across all attempts. The window also ends at the
  original intent's expiry. Total worker memory remains at most 96 MiB, never
  multiplied by attempts. These are qualification targets subject to the
  measurement gate above; a fresh request must not reset their accounting.
  Unknown consumed resources are not zero: another attempt requires evidence
  that the remaining aggregate budget suffices. The three-attempt ceiling is a
  new recommendation, not an adopted limit. Longer recovery after budget
  exhaustion needs a separately reviewed policy; this proposal does not grant
  it.
- One active hash attempt holds the same aggregate resource reservation across
  retries. Its current receipt-writing claim uses compare-and-set fencing; a
  stale reader cannot publish after deletion or replacement. Fencing a DB commit
  does not terminate network/CPU work: the next attempt waits for proven
  termination or qualified bounded runtime closure of the prior reader, within
  the unchanged aggregate window. Lease replacement cannot reset the budget or
  create another resource slot. Retry exhaustion, inability to establish safe
  remaining budget, or unknown reader closure preserves the draft and recovery
  state; none starts a fresh AI operation automatically.

Unknown **AI execution** remains original-operation status/result recovery only,
with no repeat invocation or refund. A hash receipt supplies evidence to the
separate atomic admission owner and has no funding/dispatch authority. Existing
admitted operations and historical wire versions remain unchanged.

## Bounded evidence needed before schema expansion

These are proposed experiments/review gates, **not permission to run them**.

| Gate                          | Smallest decisive evidence and pass/fail rule                                                                                                                                                                                                                                                                                                                                                                                               |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| E1 ingress                    | Exact production-intended signer/client request inspection, then separately named private-target tests of exact/short/extra/missing/conflicting length, framing changes, reused capabilities and concurrent creation. No disallowed committed size, substitution or untracked destination; provider transient behavior documented separately. Failure stops this ingress candidate.                                                         |
| E2 retirement                 | First offline finite race model, then separately authorized target tests of data-before-marker, marker-before-data, in-flight data across marker, lost PUT/readback/ledger replies, repeated capability use, expiry and service recovery. Every retired key converges to a persistent marker, ledger media release happens once, and no late committed media survives. Verify all writer/lifecycle authorities, not just the tested client. |
| E3 verifier                   | Synthetic 64 KiB/12/32 MiB valid/corrupt/short/extra/stalled/chunk-boundary cases on pinned runtime; cold/warm and bounded competing requests. Full digest parity, no full buffering, correct late-commit rejection and observable resource metrics within the agreed profile. Local results cannot qualify hosted behavior.                                                                                                                |
| E4 recovery                   | Interrupted read and unknown receipt commit with deletion/reference races. Measure retry exhaustion and prior-reader termination against the single aggregate 30-second/one-second CPU/96 MiB profile, one active attempt and persisted maximum attempt count; no reset via a new request, claim or resource slot. One authoritative receipt, no resurrection or early release, and zero funding/provider effects.                          |
| E5 operational sustainability | Measure marker/ledger footprint and cleanup throughput at the proposed allocation rate, including an outage/recovery backlog. Approve a metadata/object budget and show recovery drains the bounded backlog without requiring new admission capacity. Until then, no claim of leak-free long-term operation.                                                                                                                                |

History primary remains sole implementation writer and future ledger/reference
owner. IC-1 reviews admission, funding and exact recovery; independent review
checks the proposed storage proof and evidence limits. No schema expansion
should precede agreement on the feasible storage/accounting boundary and
measurement method. Native original retention, final audio quality, G1–G4 and
F1–F4 remain open. PR116's local whole-backend hold stays active; this review
neither closes integration acceptance nor changes later version-action/redesign
sequencing.
