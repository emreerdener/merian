# Guest library identity transitions

Guest A persists across launches. Linking a new Apple or Google account retains
A's identity; signing into an existing account transfers A through the existing
provider-bound merge protocol. A completed sign-out clears the local private
library and creates guest B. Cross-device restoration requires signing into the
same permanent account. Guest-only device transfer and recovery through backups
are not promised.

## Ownership and completion inventory

The first implementation drains source-owned work before identity replacement.
`LibraryMutationInventory` reads a fresh SwiftData context after Auth closes
producer admission and drains active account-work leases. Unknown, failed,
needs-attention, unreadable, and unacknowledged states fail closed. A count of
runnable jobs is never evidence that cleanup is safe.

| Operation                                    | Producer and durable owner                                                                                           | Required acknowledgment and recovery evidence                                                                                                                            | Resolution                                                            |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| Capture, originals, derived media, ingestion | CaptureAdmission; `OfflineQueuedScan`, ingestion job and upload generation                                           | Local queue retirement after authoritative result persistence; upload acceptance alone is insufficient. Stable scan ID, media references and generation survive retries. | Existing queue retry, media repair and separately confirmed deletion  |
| Scan deletion                                | ScanRepository; account/origin-bound `PendingCloudDeletionTask` and deletion job                                     | Explicit decoded deletion success; ambiguous responses retain the same intent. Matching private-detail jobs retire only after this acknowledgment.                       | Existing deletion retry; protected history remains held               |
| Collections and membership                   | CollectionMutationService; durable collection job, dirty revision and tombstones                                     | Successful desired-state snapshot plus revision check; tombstones must be acknowledged before local removal                                                              | Open the affected library/collection; retry synchronization           |
| Notes, tags, Favorites                       | FieldNotesRepository, UserTagsDependencies, CollectionsDependencies; immutable `library-details:` OfflineJob payload | Owner-authorized RPC success with operation UUID and immutable payload receipt; local value must match an acknowledged payload before cleanup                            | Review the item; correct invalid values; retry the retained operation |
| Identification reviews                       | IdentificationReviewSyncService; owner-bound review payload                                                          | Accepted server review revision and durable reconciliation; a conflict/needs-attention job still blocks replacement                                                      | Existing review retry/reconciliation and affected Insight             |
| Species preferred names                      | SpeciesPreferredNameRepository; account-bound rows and deletion dates                                                | Exact server-read or acknowledged-upsert values, plus acknowledged deletion dates; a later generic sync timestamp does not acknowledge an edit made during the request   | Review the name; force preferred-name synchronization                 |
| Field-trip progress                          | ActiveOfflineQueuedScanGoalHint and existing progress replay owner                                                   | Server progress acknowledgment and durable hint retirement                                                                                                               | Existing progress replay                                              |
| Legacy bridge-only notes                     | FieldNotesStore                                                                                                      | Must be represented and acknowledged by the library; an empty runnable queue does not permit removal                                                                     | Review/restore the affected scan before retrying the transition       |

Stable record and operation IDs define duplicates. Separate captures of the same
subject remain separate scans. Existing resource-specific merge conflict rules
remain authoritative.

Local cleanup and source retirement have different meanings. Sign-out retains
the outgoing server account. Merge retires its profile and later its Auth shell.
The current ingestion protocol does not prove independent continuation across
that retirement, so merge rejects nonterminal source jobs and resumable intents
without a terminal matching job. Source processing must finish first. Prepared
analysis history/evidence with explicit source ownership also blocks merge until
its transfer contract exists; it is never silently stranded.

The merge transaction locks both public profiles. All supported ingestion
admission/recovery entrypoints lock and verify the public owner before taking a
scan lock. A stale source request waking after retirement receives
`scan_ingestion_owner_unavailable`; an Auth foreign key alone does not supply
this fence. The older interrupted-ingestion repair protocol remains available
for historical receipts, not as the completion boundary for new merges.

## Sign-out recovery states

`LibrarySignOutJournalStore` is device-only, verified Keychain storage. Purchase
preparation remains owned by the existing purchase journals. The library journal
is written before local session removal and retained through purchase
completion.

| Journal state        | Recovery behavior                                                                                                                                              |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No commitment        | Cancellation or failed inventory preserves source session and library. Prepared purchase reservations use their existing recovery path.                        |
| `committed`          | Repeat verified SDK local sign-out, including when the in-memory session is already nil. Require successful SDK acknowledgment and nil published/SDK sessions. |
| `sourceCleared`      | Keep private presentation covered; purge local models, preferences, derived projections and media-recovery mappings. Retry any failed cleanup.                 |
| `libraryCleared`     | Reuse an already persisted distinct anonymous SDK session, or create the replacement guest. No outgoing library is visible.                                    |
| `destinationCreated` | Require the exact recorded anonymous destination before and after purchase continuity completion. Never create another guest to repair purchase failure.       |
| Journal removed      | Show the new guest's empty private library and reopen ordinary work.                                                                                           |

**Finishing sign out** covers private content and capture throughout committed
recovery. Retry resumes the journal. Before commitment, **Cancel** cancels only
the request; it never cancels pending library changes. **Keep syncing** returns
to ordinary synchronization. The user starts and confirms sign-out again
afterward.

Anonymous creation has a protocol limitation: if Auth creates B but its response
is lost before the SDK or journal records B, this client cannot discover B's
identity. A later retry may create another server anonymous user. Exact recorded
local transitions are recoverable; zero additional server guests is not
promised.

## Transfer, restoration and session recovery

OAuth completion reports `completed`, `pending`, or `needsAttention`
independently of authentication. The destination is pinned in each merge proof
before remote completion. Invalid/expired proofs remain as needs-attention
recovery evidence; expiration never means that the library transferred. The
needs-attention screen offers support contact without deleting that evidence.
Pending transfers block unrelated identity replacement. One recovery admission
is allowed before destination authentication: the SDK session must still be the
anonymous source, and every retained handoff must match that source and the
requested OAuth provider, have no destination, and have no needs-attention flag.
That same-provider continuation can finish the recorded merge preparation; it
does not permit a different provider/source, a destination-bound handoff, or an
attention-marked proof to start another identity change. Once authenticated as
the destination, only the recorded transfer recovery may proceed.

The current local library is an unpartitioned projection. After destination
authentication, unresolved transfer is covered by **Signed in; finishing library
transfer**, and local library mutations are closed. Merge and public-author
recovery may use a separate, verified destination lease; ordinary library
workers cannot read or relabel the source cache. Full destination-library
activity during a pending transfer still requires a separate local projection
and is not enabled by this implementation. After authoritative server
completion, acknowledged local detail receipts rebind to the destination, source
preference caches retire, and the proof is removed last. A durable library-owner
marker also prevents a missing or unrelated restored session from reading or
overwriting that projection. Recovery requires the original identity; anonymous
bootstrap cannot replace a nonempty local library whose session is missing.
Ownership is reevaluated after the local store opens. An old Keychain marker can
be cleared only when that store is proven empty, never when the store is
unavailable or unreadable. One clean, empty built-in Favorites collection is
first-launch scaffolding; custom collections and pending deletions remain
library state. On upgrades, retained merge proofs identify the source of an
otherwise unmarked library: destination credentials cannot establish ownership
until the server acknowledges transfer.

Restoration tracks account and generation separately from authentication. Every
scan page and collection page must succeed; quarantined records, failed pages
and stale completions cannot report complete. Notes and Favorites are hydrated
through an owner-only bounded RPC. Pending local detail operations take
precedence over a remote snapshot. Media availability remains a separate
per-item result. The UI reports restoration completion without claiming that
pending mutations or missing media are resolved.

Legacy preference-only notes on an existing scan are staged with the source
identity before transition. Merely finding the scan ID locally does not
acknowledge those notes; its exact persisted value and durable operation must
match. A completed restored detail baseline makes the model authoritative over
its legacy note bridge, including an explicitly cleared note. A pending or
completed client tag-only operation with nil notes does not establish that the
bridge was migrated; those notes are imported into a subsequent immutable
operation before the drain can finish. Import preserves the latest immutable
operation's other fields; a stale read projection cannot manufacture an older
replacement edit. When pending intent repairs a stale projection, its local
notes, tags and favorite state are reconciled as well, so the final inventory
can prove exact acknowledgment. Stale bridge values cannot resurrect a remote
clear or indefinitely block an otherwise acknowledged library. Missing-scan and
unacknowledged legacy notes remain held for review. Both paged and targeted
restoration must durably stage legacy details before fetching a cloud snapshot;
a failed preparation save stops restoration instead of accepting an empty
baseline over local work. Targeted preparation reads only that scan and its
operations.

The detail drain re-reads durable work after every batch so an edit arriving
during a request does not lose its coalesced wake-up. If the local
acknowledgment save fails, the in-memory job also remains pending; retry uses
the same immutable operation ID. A five-second in-process fallback schedules the
retry even when another durable write is unavailable. It shares the earliest
wake with other queues and is cleared only after exact-owner admission succeeds;
the pending operation remains the restart recovery evidence. A late response
cannot acknowledge a cancelled/deleted job or an operation whose account lease
is no longer current.

Legacy server collections whose names collide with reserved `Favorites` (case-
and diacritic-insensitively) retain their IDs and memberships under
`<original label> (restored <collection UUID>)`. This adaptation is sent to the
server by the next ordinary collection sync; an older client can reintroduce the
original name, which is adapted again. If an earlier scan restoration used that
colliding row for private favorite state, only memberships backed by a
private-detail snapshot or edit are moved to the local Favorites folder.
Ordinary legacy collection membership alone never creates a private favorite.

**Review pending changes** opens affected items/library recovery and exposes
existing scan retries and synchronization. It does not silently discard
permanent failures. Deletion/discard continues through the existing separate
confirmation.

## Private detail API

`set_owned_scan_library_details(p_scan_id uuid, p_operation_id uuid,
p_field_notes text, p_is_favorite boolean, p_custom_tags text[])`
requires the current owner, a live untombstoned scan, bounded values and an
immutable operation UUID. Nil notes are sent explicitly. Repeating an accepted
operation is a no-op; reusing the UUID with another payload is rejected. Newer
operations may supersede an earlier accepted value; retrying the earlier
operation never overwrites them. This guarantee applies to replay of the same
operation ID. Distinct operations from different devices follow server arrival
order; there is no cross-device revision/CAS or client-time last-edit-wins
promise, including for older clients using the legacy tags endpoint.

`get_owned_scan_library_details(p_scan_ids uuid[])` accepts at most 100 IDs and
returns owned live rows with `scan_id`, `owner_id`, nullable `field_notes`, and
`is_favorite`. Missing or malformed restoration results keep restoration
pending.

Notes and Favorites live in internal scan-linked tables without direct API-role
access. They follow the scan's ownership during merge and cascade on actual scan
deletion. Tags retain their pre-existing public projection; this change does not
alter public-content visibility. Private media signing, previously issued URL
expiry, purchase continuity and abandoned-guest retention remain separate
contracts. No automatic guest deletion or new media revocation promise is added.

## Validation and rollout

The
[test ownership matrix](../development-guides/08-testing-strategy.md#guest-library-transition-validation)
names the native, SQL and concurrency suites. The
[triage guide](../development-guides/04-logging-and-debugging.md#guest-library-transition-triage)
owns supported recovery actions. Candidate-specific pass counts remain in their
dated verification records; source coverage does not prove deployed behavior.

Native tests cover interrupted sign-out, lost local journal writes, purchase
retry, exact destination matching, unreadable journals, the anonymous response
loss limitation, mutation acknowledgment and partial/stale restoration status.
SQL fixtures cover private access, tombstones, operation conflicts, old-response
retries, source-work refusal, stale source admission and private-detail
transfer. The two-connection retirement test observes ingestion waiting on
merge, then verifies refusal after the profile commits its retirement.
Historical repair coverage explicitly seeds an older interrupted receipt after
proving new merge admission rejects that state.

Run the full migration replay, every SQL catalog, complete Deno task, recursive
Edge type/format checks, generated DTO/project checks and relevant native
suites. Physical Apple/Google sign-in, two-device library restoration, purchase
handoff, and issued-media URL expiry/revocation checks require device/hosted
verification; local synthetic evidence does not substitute for them.

Ship the migrations and merge function before a client requiring private-detail
RPCs. This document authorizes no deployment, hosted mutation, retention change,
TestFlight distribution or external publication. Follow the existing exact-SHA
release controls under a separately authorized operation and target.
