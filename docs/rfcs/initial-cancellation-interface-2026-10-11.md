# IC-1 cancellation addendum C1

Status: proposed exact cancellation contract, October 11, 2026. This additive
agreement preserves acknowledged IC-1 revision 2 as a historical record. For
cancellation responses, C1 takes precedence over revision 2’s original two-value
union; all other IC-1 requirements remain in force. It defines the first
prepared cancellation response, version 1, before any installed consumer or
activation. Implementation and executable acceptance remain separate.

## Fixed boundary and precedence

`cancel_initial_analysis(owner, scan)` is a fixed service-only operation. The
trusted adapter derives the owner from verified authority; a saved owner ID is
not authentication. No ordinary native endpoint is installed by this addendum.
The closed success envelope is:

```json
{ "version": 1, "outcome": "cancelled", "dispatch": "dispatch_prevented" }
```

`dispatch` has exactly three values:

- `dispatch_prevented`: a durable fresh pending witness, the closed generic
  execution namespace and exact original accounting proof establish primary
  authorization never occurred. Only this path may release unused original
  funding, atomically with cancellation.
- `dispatch_already_authorized`: a durable positive original authorization
  witness exists. Cancellation prevents resurrection but never refunds or
  authorizes another invocation.
- `dispatch_outcome_unknown`: historical authorization cannot be proved either
  way, including missing or contradictory evidence. Cancellation confirms only
  the delivery/resurrection fence. Funding remains unchanged; timeout, expired
  lease or absence of a result never grants refund or invocation authority.

Precedence under owner-first locks is live owner and cross-owner/deletion
checks, saved scan/completion too-late denial, same-owner exact cancellation
receipt replay, then fresh cancellation eligibility. A late cancellation never
implicitly deletes an already saved scan. Same-owner saved/completed operations
return `initial_analysis_already_complete` without mutation; foreign or
ambiguous ownership returns generic owner unavailable without private details.
Explicit operation/scan deletion returns deleted and cannot recreate recovery
data. A lost or malformed response is an unknown write outcome until exact
recovery; it never proves rollback or dispatch permission.

## Cancellation and stronger deletion

Cancellation may retain one private immutable operational receipt containing
only owner UUID, operation/scan UUID and dispatch classification. It exists only
for same-owner lost-acknowledgement recovery after private submission erasure.
It contains no timestamp, text, content-derived digest, funding or result
reference. It is not a scientific record and cannot appear in public or generic
history readers. Account erasure deletes it through its owner foreign key;
identity merge must hold/reject a source account with any cancellation receipt.
It must neither reparent nor silently erase that receipt; register the explicit
merge-reference preserve policy and test that denial.

This exception applies only to operation cancellation. Subsequent explicit
operation/scan deletion erases the private cancellation receipt too. Recovery
then returns authorization-safe deleted/unavailable, not the erased receipt.
Only an ownerless permanent logical UUID and lifecycle classification survive.
Cancellation writes that terminal lifecycle fence and erases the submission
chain without inserting the ordinary scan-deletion tombstone or invoking its
fanout. Explicit deletion owns that tombstone and erases both private chains.
The two operations cannot accidentally delete/recreate one another's receipt.

## State, proof and namespace

The immutable namespace fence remains unchanged. A separate content-free
lifecycle row is inserted pending only by fresh admission in its original
transaction. There is no backfill or inferred execution authority for existing
prepared admissions. All lifecycle operations use the same logical row and owner
→ ingestion advisory → existing scan/history serialization. Terminal
cancellation cannot reset or be rebound. Future dispatch must consume that same
pending witness before original quota commit and provider I/O. No usable grant
or callable pending-to-authorized transition is introduced by cancellation.

Fresh pre-admission cancellation is first-writer-wins ownership of the global
operation UUID. It requires the existing lifecycle gate and a verified caller;
under the advisory it rejects any conflicting scan/history, initial binding,
analysis source/intent/result, ingestion job/intent, quota request/original ID,
invocation, complimentary identity or permanent historical marker. Foreign or
ambiguous occupancy yields generic denial and no caller receipt. Current absence
cannot prove a never-used legacy ID: cancellation therefore records unknown,
allocates no funding and permanently denies future admission. Existing owned
cancellation and exact replay remain available after gate closure.

Generic begin, claim, intent recording, completion, failure and recovery owners
reject every prepared operation UUID after serialization, including pending
operations. Response finalization delegates to the fenced canonical finalizer.
Raw scan/job/intent identity writes reject terminal lifecycle states under the
existing owner → ingestion advisory boundary; live private completion remains
possible. UUID spelling aliases share that boundary and cannot evade occupancy
checks. Generic batch replay excludes every permanent prepared UUID from both
claim and over-budget settlement candidates. That immutable fence precedes any
visible prepared work; admission and fresh cancellation cannot claim an existing
generic job/intent. Contradictory generic work defeats refund proof and remains
a held recovery concern, never dispatch authority.

Refund requires locked fresh pending state plus immutable submission/admission
identity and an exact original reserved quota: same owner, request and original
scan, operation, attempt 1, original funding snapshot and complimentary
association; never committed, failed or refunded; no
invocation/result/completion or generic ingestion job/intent. The current locked
lease is used only for the original settlement helper. Contradictory/missing
proof produces unknown, not inferred non-execution.

The supported expanded order is owner → ingestion advisory → existing
scan/history → lifecycle/private binding → quota → daily/user/IP counters →
complimentary usage → reentrant owner epoch update. The complimentary helper
cannot update a user inside that user's DELETE trigger. Supported account
detachment handles pre-row cancellation before scan detachment and user DELETE.
Saved/completed rows use the existing explicit account erasure owner instead.

Already-authorized, lock-safe raw erasure marks conservative terminal state and
erases private evidence without invoking settlement. Preserve existing raw-user
detachment-required denials wherever funded history fanout could update the
deleting tuple. Missing proof alone must not prevent otherwise safe privacy
erasure; raw DML does not become a supported account API. For successful
`dispatch_prevented` cancellation, state transition, original settlement,
minimal receipt and private erasure are one transaction. Any settlement failure
rolls back all of them. Raw conservative erasure performs no settlement and
creates or preserves no private cancellation receipt.

## Acceptance and limits

History primary owns writes; the initial-engine owner and independent read-only
reviewer must acknowledge this exact contract and then independently review the
candidate implementation/evidence. The bounded matrix is retained in
`.artifacts/initial-analysis-cancellation/design.md`. Tests must cover both
admission/cancellation and erasure race orders, exact retry, cross-owner denial,
old/missing/corrupt proof, completed precedence, shared accounting contention,
rollback, permanent-state guards and actual API-role privileges.

S0 is still incomplete. Native durable cancellation delivery, exact media,
original dispatch/result/completion, route/worker cutover, installed and hosted
qualification remain separate rows. Activation stays false and ordinary access
nil. This addendum authorizes no push, merge, deployment, scheduling,
installation, activation or distribution.
