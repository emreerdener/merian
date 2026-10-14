# CPM-1 incremental verification and ingress contract

Status: **draft revision IVI-1 for independent and IC-1 review**, October 13,
2026. The human authorized drafting this agreement after checkpoint
`f00b0f48369306e218b50b2ce031a5bf9f913414`. This document proposes a new
fresh-submission boundary within the already approved
[CPM limits](client-prepared-media-limits-and-integration-proposal-2026-10-13.md).
It does not authorize runtime implementation, another feasibility run, target
provisioning or release. AWS remains unapproved, activation disabled and
ordinary access nil. All existing push, merge, deployment, hosted and device
restrictions remain. History primary is sole writer; reviewers have read-only
ownership.

## Decision and evidence

Recommend a backend-owned control plane, a qualified single-part private-storage
upload path, and serial incremental SHA-256 verification of immutable objects.
Media bodies must not pass through JSON, base64, whole-body buffering or media
decoders in the verifier. Retained originals, frozen AI inputs and previews keep
separate role identities. Only the frozen AI cohort may later reach the
provider. Client-provided video frames remain submitted evidence with claimed
lineage, not proof of faithful extraction. A hash proves bytes, not safe
decoding, truthful provenance or identification quality.

The approved offline reuse experiment observed 180,977,664 bytes (172.59 MiB)
RSS against the 96 MiB target. Its 12 expected length/hash outcomes passed, but
`readInitialStream` retains chunk copies and aggregates a complete buffer;
`initialMediaHash` hashes that buffer. Evidence is retained under
`.artifacts/client-prepared-media/approved-plan/`. It is failed buffered-reuse
feasibility, not a hosted measurement or permission to enlarge the budget.

The existing `mediaHandoffStorage.ts:snapshotRole` rejects objects above 12 MiB;
`mediaBinding.ts` has different package limits. These functions and all admitted
snapshots retain their existing meaning. IVI-1 must not be implemented by
raising old constants, relabelling old receipts or adding a fallback to the old
route.

## Version and authority boundary

IVI-1 names the design revision, not a deployed API. Reserve distinct version
identifiers for the future CPM manifest, resource profile, verification receipt
and upload authority. Exact wire keys, canonical encoder/golden vectors,
generated DTO ownership and SQL callable signatures must be closed in the next
schema agreement before implementation. Unknown versions fail closed. Existing
admitted operations recover through their original version and operation ID.
Local queued no-media requests remain drafts requiring explicit remediation;
unknown admission first recovers status. There is no new text-only path.

The new manifest freezes, before remote admission:

| Semantic value                                                    | Owner and binding                                                                                                                                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Package/operation identity and manifest digest                    | Durable native identity, accepted once by server; changed input under the same identity conflicts. Server assigns storage identities.                                                |
| Ordered sources, roles and exact supporting descriptions          | Native frozen package; server validates closed structure and supported combinations. Original, AI and preview roles cannot silently substitute for one another.                      |
| Per-object byte length, SHA-256, media type, role references      | Expected claims only until the backend reads the entire exact stored object. Equality of client hashes does not authorize sharing.                                                   |
| Recipe/version and AI cohort order                                | Final post-processing bytes only. Audio recipe, signal and quality acceptance remains G2; IVI-1 does not attest equivalence.                                                         |
| Principal, intent, generation, reservation and authority revision | Server-derived; clients cannot choose another owner, storage key, host or authoritative expiry.                                                                                      |
| Verification result                                               | Server record bound to manifest, object identity/generation, measured length/full digest, verifier profile/build and authority revision. Not a bearer upload or dispatch credential. |

No media verification result grants funding, provider dispatch, refund, version
selection or completion. Fresh admission still atomically validates the whole
cohort and creates the original operation through its reviewed lifecycle owner.
A client receipt, storage ETag or PUT success response cannot replace that
owner.

## Limits: preserve the approved envelope

The approved profile remains authoritative for all per-role and retention
limits. The verifier's largest single object is a 32 MiB original still; video
stays 12 MiB, audio 2,700,000 bytes each, AI images 5 MiB aggregate, and preview
stills 4 MiB each/8 MiB aggregate. At most two physical sources, 24 distinct
objects, 32 role references and 1 MiB exact serialized manifest/context are
allowed. The whole package, including that metadata, remains at most 96 MiB.
Every role ceiling also applies; sharing uses one qualified physical object
identity and all required references, never a client hash as deduplication
authority.

Use the existing bounded JSON classes: up to 1 MiB for the closed manifest and
16 KiB for scalar object-verification/status requests. No arbitrary URLs or
embedded media. Actual byte counting precedes JSON decoding; reject duplicate
keys, unsupported fields, invalid types, counts and unsafe numeric arithmetic.
Exact wire constraints remain a schema-closure gate, not an implemented codec.

Worker targets remain **96 MiB total memory, one second CPU and 30 seconds wall
per object verification**, with at most 1 MiB application read chunks and one
active object per worker. Include runtime, imported code, TLS, stream buffers,
hash state, headers, error paths and response encoding. A worker must refuse
concurrent verifier work before opening another body; a DB object lease alone
cannot bound multiple objects sharing one worker. Do not enqueue unbounded
waiting requests or use background tasks for required success work.

The 192 MiB server pending reservation per intent still covers at most one 96
MiB staging package plus one retained copy. Two pending intents per owner, 16
globally, 5 GiB retained per owner and 50 GiB retained globally remain intact.
Unknown writes keep their capacity liability. No additional proxy spool,
multipart parts, retry copy or third object inventory may be assumed free.
Native 192 MiB temporary pool, 288 MiB maximum incremental allocation, 256 MiB
free reserve and four pending packages are unchanged. Device qualification must
include OS transfer copies and restart leftovers; this backend draft does not
qualify those limits.

## Ingress: qualify before accepting media bytes

The recommended first candidate is direct single-part PUT to the prepared
private R2 storage boundary, authorized by the existing backend. This selects a
candidate to review, not an assertion that current presigning enforces IVI-1. No
AWS worker, new proxy service or multipart upload is added.

Before issuing a write capability, the server must atomically reserve the exact
object inventory, retained capacity and owner references, freeze the manifest,
and assign a never-reused opaque destination/generation. The capability binds
one authenticated owner intent, exact method/destination, declared length,
expected identity, approved metadata and original expiry. It cannot grant list,
copy, overwrite, delete or arbitrary-prefix access. The all-writer inventory
must include signers, privileged service clients, generic storage helpers,
imports, repair tools, cleanup, lifecycle rules and external integrations.

Inventory reservation is not sufficient issuance evidence. Before any signed
capability can leave the backend, durably commit its opaque issuance identity,
object/generation, method/destination, exact limits, expiry and authority
revision. Serialize issuance with retirement. Persist a conservative
may-have-issued state before the signer/response boundary; a crash, missing
response or unknown issuance commit retains that possible writer and its
liability. Never reconstruct an unrecorded capability, return one after an
unknown issuance commit, or infer non-issuance from missing client
acknowledgement. Refreshes are additional tracked capabilities for the same
fixed object, not overwrites of the prior issuance record. Store only the
minimum private issuance metadata, never a signed URL or credential in logs or
evidence.

Required target proofs, all still open:

1. **Length enforcement at the write boundary.** A signed exact content length
   and the receiving service's actual framing must reject missing, conflicting,
   forged, compressed, chunked or oversized bodies before committing storage
   beyond the reserved object bound. Content-Type is not a length limit. A
   subsequent GET rejecting an oversized object is too late. Provider-internal
   temporary storage and billing behavior must be identified; if it cannot be
   bounded by the approved reservation, this candidate fails G3/F4.
2. **Conditional immutable create.** Enforce create-if-absent for every writer,
   bound into the signature/policy, with no unconditional PUT, copy or delete-
   then-recreate bypass. Concurrent/replayed capabilities cannot replace bytes.
   The same destination is never reassigned to a fresh operation or generation.
3. **Closure of old writers.** Capability expiry, client abort, a missing HEAD,
   a precondition failure or a successful DELETE alone does not prove no request
   can still finish. Record all issued capabilities and possible writers; prove
   terminal outcome for them before cleanup settlement or capacity release.
   Targeted erasure of retired bytes remains available while that outcome is
   unknown, under the fixed-ID cleanup authority below. Reusable presigned
   capabilities are not assumed single-use. Unknown closure leaves the intent
   held and the bytes charged, even after its staging deadline.
4. **Atomic final visibility.** Prove that a full GET resolves one finalized,
   immutable object generation and cannot expose a partially uploaded or mutable
   body. Otherwise sequence verification after positive writer-terminal and
   final-generation proof. A short/mismatched read while finality is unknown
   remains unresolved, not a known invalid package. Do not retire or clean up
   solely because that read disagreed. Final object visibility does not prove
   every other issued capability or possible late writer is closed; those
   liabilities remain separately tracked.
5. **Private target identity.** A named nonproduction bucket/account, credential
   principal, allowed operations/prefixes, authoritative clocks, read
   consistency and original-object identity mapping must be reviewed. No public
   bucket/CDN, client-selected URL, redirect or fallback endpoint is permitted.

Cloudflare documents conditional PUT support and separately lacks S3 Object
Lock. Neither fact proves our all-writer policy or late-upload closure. These
are required target tests, not guarantees inherited from S3 naming.
[R2 compatibility reference](https://developers.cloudflare.com/r2/api/s3/api/).

If direct PUT cannot meet any of these requirements on the existing target,
report the failed condition and stop ingress implementation. Do not silently
switch to an Edge proxy: its transport buffering, CPU/memory, write concurrency
and temporary storage need a separately reviewed design within the same limits.
Do not increase limits, weaken immutable retention or infer AWS approval.

## Incremental verifier algorithm

The verifier accepts only an opaque object/intent reference and original
verification operation identity, never caller-provided bytes or a replacement
URL. Authenticate with the existing verified caller boundary; resolve private
metadata and capacity from server authority. A privileged service key alone is
not the authorization decision. No user may read another owner's status or probe
whether a digest exists elsewhere.

1. Claim one verifier lease for the exact object/generation/manifest, while the
   original intent and required owner/reference holds remain valid. Persist an
   operation identity and immutable deadline before I/O. Deny retired, erased,
   changed, unsupported or already-conflicting input. Return a saved exact
   verification outcome on idempotent recovery.
2. Resolve the allowlisted target from trusted server configuration. Perform one
   full GET only after the qualified atomic-final-visibility contract or
   positive writer-terminal/final-generation proof establishes its finality. If
   finality cannot be established, stop at original status reconciliation,
   retaining liability. Read the fixed immutable generation; use target
   generation or conditional validators only as concurrency guards. Reject
   redirects, partial content, content transformation and inconsistent metadata.
   ETags are not SHA-256 proof. HEAD may help preflight but never substitutes
   for reading.
3. Maintain a running safe-integer byte count and one incremental SHA-256 state.
   Before hashing each nonempty chunk, check deadline, cancellation, chunk size
   and `chunkLength <= expectedLength - count`. Reject excess immediately;
   consume until EOF to detect an extra byte after the declared length. Do not
   retain prior chunks, concatenate, tee, clone, base64-encode, decompress,
   decode media or call `arrayBuffer()`/`blob()` on the full body.
4. Process at most 4,096 delivered chunks and 32 consecutive empty chunks, as
   bounded transport-work guards; reject pathological fragmentation instead of
   extending the deadline. Read chunks must be at most 1 MiB before application
   retention. Splitting an already allocated oversized chunk does not prove the
   worker bound. Actual fetch/runtime buffering and cold/warm memory remain a
   qualification obligation. No unbounded async prefetch or parallel hashing.
5. At EOF require exact expected length and full SHA-256 equality. No prefix,
   sampled or per-chunk digest list may replace the full byte-stream digest.
   Compare byte-identical independent vectors across chunk partitions. Release
   reader/hash state on every path; cancellation acknowledgement is bounded and
   never evidence that a remote write stopped.
6. Commit the immutable receipt only through a serialized compare-and-set on the
   original lease, manifest, generation and current owner/retirement state.
   Re-check authoritative expiry at commit. A late completion after
   cancellation, expiry, erasure or lease supersession cannot publish a usable
   receipt. A lost commit response remains unknown and permits original status
   recovery only.

Preferred primitive for evaluation is incremental SHA-256 via Deno's
`node:crypto` `createHash().update().digest()` API. Its documented incremental
interface makes it a candidate; it does not establish the pinned Supabase Edge
build's compatibility or memory/CPU behavior.
[Deno crypto reference](https://docs.deno.com/api/node/crypto/). Resolve it
through the repository's reviewed dependency/import boundary. Pin the
runtime/compiler and source graph in the verifier profile. Do not add a runtime
URL import, custom cryptographic implementation, worker thread or alternate hash
fallback. If this primitive fails qualification, review a replacement before
use.

Measure total process/worker peak and per-request CPU in the actual target.
Sampled RSS is a lower bound; baseline subtraction cannot turn total memory into
an incremental-memory claim. Cold and warm requests, malformed streams and
concurrent attempts must fit. If the target cannot expose sufficient CPU/peak
metrics, mark those gates unresolved rather than substituting a JS wall timer. A
JS timeout cannot preempt synchronous hashing or prove the one-second CPU limit.
The monotonic wall deadline covers auth, claim, finality checks, GET, hashing
and receipt commit; check it at I/O and chunk boundaries without resetting it on
progress. Supabase's published platform limits are larger than this profile and
do not qualify our stricter targets.
[Supabase limits](https://supabase.com/docs/guides/functions/limits).

## Clocks, recovery and reference ownership

The new intent's admission deadline is nonrenewable at 30 minutes. A ticket is
at most ten minutes and never outlives that deadline; the native transfer wait
is at most five minutes. The verifier's absolute operation deadline is at most
30 seconds from request start and never beyond the intent/authority deadline.
Server authority uses its trusted clock; local waits use monotonic elapsed time.
No client timestamp creates authority. The seven-day native work horizon never
extends tickets, consent, assignments or admission. Old 300-second preparation
contracts are unchanged. Exact cross-phase clocks and effective caller/lock
signatures remain required in the schema agreement.

| Condition                                                      | Allowed action and retained liability                                                                                                                                                                                                                                                                                                     |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PUT outcome unknown, including timeout/restart                 | Recover the same fixed object operation; no second PUT, fresh key, recipe change or released reservation. A matching stored object may be read for reconciliation; finality proof is required before a usable verification receipt. This does not prove every writer is closed.                                                           |
| PUT positively terminal and unused                             | Same-destination retry only under live original authority, with old-writer closure and no race. Refresh cannot extend the intent or enlarge inventory.                                                                                                                                                                                    |
| Hash/length mismatch or unsupported representation             | Refuse package admission and retain the local draft. Classify a byte mismatch as known invalid only with finalized immutable-generation proof; otherwise retain unknown status and liability. Retire known-invalid inventory under its cleanup owner, without equating retirement to writer closure. No automatic conversion/replacement. |
| Verification read fails before receipt commit                  | Record known failure only when its lease/commit outcome is settled. No automatic new verification attempt/deadline is inferred; status recovery remains available. A future retry/remediation policy needs explicit schema closure.                                                                                                       |
| Receipt commit unknown                                         | Query exact original operation outcome; do not acquire a new lease or publish a substitute receipt until authority is resolved.                                                                                                                                                                                                           |
| Intent expires, parent version is deleted or account is erased | Serialize retirement/reference decisions with admission; revoke new access. Preserve surviving-version references and unresolved physical liabilities. Never revive the retired generation.                                                                                                                                               |
| Provider execution unknown, at any later phase                 | Only original-operation status/result recovery and reconciliation. Media verification or cleanup never authorizes another invocation or refund.                                                                                                                                                                                           |

Supabase owns the authoritative reference/reservation ledger. Acquire child
source holds before preparation depends on an existing original. Atomic
admission must require every frozen object receipt, all live source holds, exact
ordering, consent/assignment validity and a complete package within limits. No
partial cohort admits, even when all AI inputs are present but an original is
absent. Receipt creation cannot race deletion to reacquire a retired object.
Transfer holds to admitted/history references atomically; delete a version by
releasing only its references. Native file leases guard local bytes but never
authorize server erasure or spending a second retained reservation.

Distinguish **physical erasure attempts** from **terminal cleanup settlement**.
After irrevocable retirement and zero surviving references/read/export/verifier
leases, the existing token-authorized erasure/outbox owner may delete present
bytes and reconcile the fixed destination even while writer closure is unknown.
It must keep the permanent opaque fixed-ID tombstone and full outstanding
capacity liability. Late arrivals are removed by the same durable cleanup
authority; a retry/renewed cleanup claim cannot rebind the object or authorize a
new upload. Unknown DELETE outcomes require reconciliation, not an assertion of
absence. Cleanup remains available when admission or storage capacity is held.

Only positive closure of every possible writer **plus** terminal
absence/readback proof permits cleanup completion and capacity release. No TTL,
failed HEAD, expired lease/claim, or first successful DELETE establishes those
facts. Never reuse the destination or restore its binding after expiry. Account
erasure also removes contentful manifests/hashes under existing privacy
precedence, keeping only the minimum opaque non-content cleanup/fence identity.
Retention limits must not expire the sole original of a surviving version.

## Acceptance and ownership matrix

Every row is **specified for review, unimplemented and unqualified**. Source
review does not close G1–G4 or F1–F4. No experiments run for this draft.

| Gate                      | Measurable pass condition                                                                                                                                                                                                                                          | Evidence and owner                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| IVI-V version isolation   | Old admitted replay vectors unchanged; old object/package limits unchanged; new version rejects missing media and unknown schema; changed manifest conflicts.                                                                                                      | History owns codec/DTO mapping plan; IC-1 reviews admission compatibility.                                                                                   |
| IVI-H hash correctness    | Same full SHA-256 for independent known vectors under multiple chunk boundaries; corrupt/short/extra byte, absent body and transformed body rejected; no full-buffer retention.                                                                                    | Future finite local harness, source/dependency audit; independent reviewer.                                                                                  |
| IVI-R resource bound      | Each approved 64 KiB/12/32 MiB boundary case and errors fit total 96 MiB, CPU 1s, wall 30s; oversized chunks, stalled streams, cold/warm reuse and concurrent attempts cannot bypass guards.                                                                       | New separately agreed F3 experiment packet, then named hosted target metrics; not the failed reuse run relabelled.                                           |
| IVI-I ingress bound       | Exact-length and conditional-create constraints cannot be bypassed; issuance crashes leave a tracked possible writer; only final immutable generations produce receipts; oversized/replayed/concurrent writes stay within reserved inventory and cannot overwrite. | Named private target, full credential/writer inventory, F4 integration evidence. Fake storage is insufficient.                                               |
| IVI-L late-writer closure | Lost acknowledgements and retirement during PUT retain liability; unknown-writer → delete → late-write → repeat-delete removes retired bytes without early cleanup settlement, capacity release or resurrection.                                                   | Target-specific closure proof and all eight F4 schedules plus issuance-crash and partial-visibility negative cases in the next separately authorized packet. |
| IVI-A atomic aggregate    | Missing/stale receipt, omitted original, reordered cohort, expiry/revocation and concurrent deletion all deny admission; exact replay recovers the original operation without funding twice.                                                                       | Future closed transaction/lock matrix and disposable DB tests; IC-1 concurrence before implementation.                                                       |
| IVI-S sharing and erasure | Both acquire/delete orders preserve every surviving version's original; expired leases cannot reopen retired objects; account erasure leaves no contentful provenance.                                                                                             | Reference schema/caller agreement, recovery and erasure race evidence.                                                                                       |
| IVI-N native and audio    | Exact originals durably owned before draft clear; final audio frozen after all DSP; interruption/restart/low disk preserves draft and original identity within approved budgets; G2 quality evidence passes.                                                       | Separate G1/G2/F1/F2 native and audio work, device runs owned by user. Not satisfied by backend hashing.                                                     |

Before any implementation: independent review and IC-1 must acknowledge the
exact draft; the wire/schema/reference/clock/lock and audio agreements must
close; a bounded follow-up feasibility packet must be explicitly authorized; and
the selected ingress must demonstrate a credible, testable path to its bounds.
Hosted/device proof needs separately named targets and operations. No review
concurrence grants those permissions.

Before acceptance: actual exact-source candidate tests, complete affected
surface gates and the required target/device evidence must pass. The previous
aggregate tooling failure remains historical evidence; its successful isolated
terminal retry is not a green aggregate. This documentation checkpoint does not
repeat those suites or claim PR116 integration readiness. The local production
hold remains active and unpublished; source integration, feature activation and
later deletion/export/redesign remain separately sequenced.
