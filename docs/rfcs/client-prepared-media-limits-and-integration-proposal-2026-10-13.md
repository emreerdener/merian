# CPM-1 proposed media limits and PR116 integration checkpoint

Status: October 13, 2026. **Proposal for approval; not adopted or implemented.**
The user approved the acceptance-gate intent and requested concrete defaults,
feasibility boundaries and a separate PR116 integration recommendation. This
supplements [CPM-1 revision 3](client-prepared-media-amendment-2026-10-13.md),
not an executable profile or authorization to implement it. G1–G4 remain open.
AWS is unapproved; activation and ordinary production access remain disabled.
Push, merge, deployment, provider calls and device operations remain restricted.

## Recommendation and decision scope

Use the existing native queue/repository, Supabase authority and prepared
private R2 history-media architecture. Retain exact selected originals
separately from frozen AI inputs and previews, with server-owned references
across versions. Do not add an AWS execution worker. This still requires
functional changes and qualification: the private history bucket/credentials are
a prepared contract, not evidence that the required hosted target is provisioned
or qualified.

Recommend the numeric policy below for a new CPM-1 version. Approving it would
choose a proposed product/storage envelope, not attest to feasibility, adopt
reduced derivation assurance implicitly, authorize implementation or provision a
target. Resource failures keep the design open; raising limits or reducing
supported media then requires an explicit revised decision. Older saved
operations retain their original profile and recovery meanings.

## Original bytes, location and retention

- **Camera photo:** the exact encoded bytes returned by `captureImage()` before
  crop, orientation rendering, resizing or compression. Preserve the embedded
  metadata too; rewriting it would produce a derivative with another identity.
- **Library photo:** the exact file representation delivered by the existing
  picker's `ImageFileWrapper`. Record that representation's type and origin.
  This is not a promise to recover the unedited Photos master, RAW companion or
  Live Photo video. If the selected representation includes Photos edits, those
  selected bytes are the retained source. Do not label a rendered derivative
  created by Merian as the original.
- **Audio/video:** preserve the selected/captured source file as its own role.
  Canonical WAV, boosted/trimmed audio, sampled video frames and a recompressed
  playback clip have separate identities whenever bytes differ. A playback file
  cannot replace an available camera source merely to save space. No new format,
  duration or video publication support is implied.

On iOS, add account-scoped package ownership under the existing durable
Documents-backed media/file-store boundary; use an opaque package directory, not
`tmp`, a purgeable cache, SwiftData blobs or a Photos reference. Use protected
files and the existing account lease, with hashes/manifest and atomic durable
commit before draft clear. Temporary acquisition copies can be removed only
after that commit or an explicit discard of their sole draft owner. The exact
protection class and background-transfer compatibility require F1 below.

For synced accounts, retain originals and submitted evidence in the **private
history R2 bucket** behind the existing authenticated backend, with private
Supabase reference/receipt metadata. No public CDN or generic public scan-media
bucket fallback. The authenticated backend verifies all owned byte identities;
only the frozen AI cohort goes to the provider. Originals may contain sensitive
metadata and must not automatically enter provider requests or publication. The
privacy/consent contract must explicitly cover private original retention. A
local-only or unsynced library keeps its only owned copy on device.

Recommended lifetimes:

| State                                      | Retention and release                                                                                                                                                                                                                                                                       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unsubmitted local draft                    | Keep until explicit discard or successful durable package commit. No age-based loss of originals or supporting text.                                                                                                                                                                        |
| Queued, interrupted or uncertain operation | Keep its exact package and recovery identity. Unknown create/PUT/admission/provider outcomes hold immediately for original reconciliation. Seven days is only a maximum horizon for otherwise-authorized known-safe transfer work, never a deletion TTL or permission to retry uncertainty. |
| Completed live version                     | Keep original and frozen AI evidence while any live version or operation requires it; no 30-day source expiry. An ancestor's deletion does not erase descendants' source.                                                                                                                   |
| Local copy with verified cloud retention   | Evict only a redundant local copy under an explicit cache policy, after exact server durable-retention acknowledgement and no local leases. Offline source reuse then needs a download. Never evict the only copy or assume a result receipt proves source retention.                       |
| Server unadmitted staging                  | Nonrenewable 30-minute admission deadline. Retire fixed destinations at expiry/cancellation; admission and new writes cease. Existing writes/cleanup liabilities survive expiry until positively reconciled.                                                                                |
| Unreferenced, retired bytes                | Eligible for cleanup immediately after reference/lease and writer-terminal proofs. Target first cleanup within 15 minutes of eligibility; backlog alert at 24 hours. Neither value proves erasure or permits releasing unknown liability.                                                   |

The seven-day local horizon never renews a server intent, upload ticket or
provider grant. At its end, offer status recovery first; resume only under still
valid original authority, or explicit remediation after positive serialized
terminal/unused proof. Discard releases only resources proven safe to release. A
30-minute expiry can stop writes much earlier; no seven-day automatic upload
right exists.

No storage-system lifecycle rule may expire live originals or the permanent
content-free erasure markers. Account/scan deletion follows existing privacy
precedence, revokes delivery and retires the relevant owners; physical cleanup
remains durable even if delayed. Sign-out, account switch and uninstall follow
existing user-visible library rules rather than an invented cross-account cache.

## Proposed numeric profile

MiB means 1,048,576 bytes; audio's 2,700,000-byte ceiling stays decimal. All
byte counts include file headers. These are **new policy proposals**, not claims
about current app/backend compatibility. Retain at most two physical selected
sources, existing five-image/two-audio/one-video input ceilings and current
supported combinations. Role references do not add a new capture modality or
source slot.

| Item                      |                                                         Recommended maximum | Tradeoff / status                                                                                                                                                                                                             |
| ------------------------- | --------------------------------------------------------------------------: | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Original still            |                 33,554,432 bytes (32 MiB) each; two originals, 64 MiB total | Ample room beyond current derivatives. Not guaranteed to cover every Photos import; large RAW/panoramas need explicit refusal, not silent conversion. F1 must test representative camera/picker formats.                      |
| Original still dimensions |                                      64 million pixels, primary still image | Proposed decode-work eligibility ceiling, not proof of safe decoding. Preserve existing accepted still formats only; RAW/animated/multi-resource expansion requires a separate decision. Bounded ImageIO behavior remains F1. |
| Original video            |                        12,582,912 bytes (12 MiB), existing capture duration | Preserve the current byte ceiling. A different playback copy may use up to another 12 MiB and counts separately. No raw-to-playback relabelling.                                                                              |
| Original audio            |                                      2,700,000 bytes per asset, at most two | Existing supported source envelope; an imported source needing more is blocked explicitly. Final audio is additional unless exact bytes actually share a compatible role.                                                     |
| Frozen AI images          |                             5,242,880 bytes (5 MiB) aggregate; at most five | Preserve native aggregate image ceiling. Originals never enter the image provider cohort just because they fit the source limit.                                                                                              |
| Frozen AI audio           |                                           2,700,000 bytes each; at most two | Preserve supported audio envelope; all required DSP before freeze. G2 recipe/quality agreement still required.                                                                                                                |
| Preview/display stills    |                                   8 MiB aggregate; at most five, 4 MiB each | A new closed preview budget. Optional preview failure cannot change original or submitted evidence silently.                                                                                                                  |
| Manifest/context envelope |              1 MiB; at most 24 distinct file objects and 32 role references | Includes existing text limits, not permission to expand supporting text. Bound parser/object overhead.                                                                                                                        |
| Whole package             |                              100,663,296 bytes (96 MiB), including metadata | Sum distinct physical files, plus exact ordered role references. Both originals and final evidence count; hashes alone do not deduplicate. Old 25 MiB soft queue and 28,625,792-byte backend profiles are not reused.         |
| Local pending packages    | Four including the preparing draft; 384 MiB aggregate durable package bytes | Prevent unlimited offline backlog. Unknown operations retain their slot; the 192 MiB temporary pool below is separate. Existing live-library media consumes actual free space.                                                |

Examples with no assumed sharing: two 32 MiB photos, 5 MiB AI images, 8 MiB
previews and 1 MiB metadata total **78 MiB**. One 32 MiB photo, 12 MiB video
source, 12 MiB playback, 5 MiB AI images, 8 MiB previews, two 2,700,000-byte
audio files and 1 MiB metadata total **75.15 MiB**. The 96 MiB cap covers these
conservative legal-role envelopes without reducing current two-source behavior.
It is a ceiling, not preallocation or a target upload size. Every independent
per-role cap also applies; unused package allowance cannot enlarge an asset.

### Peak disk and transfer accounting

Recommend **192 MiB additional temporary disk across the app's CPM work**, split
into 96 MiB acquisition/atomic-commit copy allowance, 64 MiB serial preparation
scratch, and 32 MiB transfer/export staging. One active preparation and one
active file transfer; export shares the transfer staging slot. URLSession-owned
upload copies, failed attempt remnants and restart leftovers count, including
files temporarily outside the final package directory. Prefer atomic same-volume
ownership transfer; do not assume hard links or clones consume no capacity.

With a maximum 96 MiB new durable package, incremental worst-case allocation is
**288 MiB**, in addition to already allocated drafts, queued files and retained
history. Preserve **256 MiB free after outstanding reservations**: a fresh
worst-case admission requires 544 MiB available before new allocation, or the
actual missing-byte reservation plus that reserve when files already exist.
Count existing allocations once; count every real duplicate. Recheck during
copy/encode and fail closed if free capacity is unknown. This deliberately
replaces CPM's use of the existing 100 MiB reserve/25 MiB soft estimate, and
will block sooner on low-storage devices. F2 must prove the accounting, not
merely show a successful capture. No other version's required files may be
pruned.

Retries reuse immutable package files, identity and fixed destinations. They get
no new disk allowance. Reconcile an unknown PUT before another write; a known
failed transfer may retry the same destination only while the original intent is
live and a new write cannot race the old one. No re-preparation or inference
retry is inferred. Use single-part object writes for this profile, not an
unbounded multipart scratch/retry inventory. A rejected oversized import keeps
its original in Photos/provider storage and its draft selection/error/text; if
its temporary representation cannot be retained within the budget, say that
reselection is required rather than promising a durable copy that does not
exist.

### Server storage and verification

Recommend two pending intents per owner and 16 globally for an inactive alpha
qualification profile. Reserve **192 MiB per intent** for one 96 MiB staging
package and one retained copy during handoff; at most 384 MiB per owner and 3
GiB globally for this pending pool. A separately allocated third copy is not
free: prohibit it unless already represented in that reservation. Physical
coalescing only reduces charged bytes after immutable identity and ownership are
proven. Old versions continue under their own accounting.

Recommend **5 GiB retained private CPM media per account and 50 GiB globally**
for the first alpha profile, plus the separate pending pool above. These are
storage safety caps, not paid entitlements or a new billing policy. Reserve
prospective retained bytes before accepting an intent, even while charging its
pending physical copies; convert that retained reservation atomically at
completion. Count a shared object once physically, but retain all references. At
a cap, stop new CPM admission without deleting history; allow status, deletion
and required cleanup. Alert at 80 percent; cap increases are a reviewed policy
change. This bounds worst-case private media to 53 GiB for this profile,
excluding existing non-CPM storage and separately bounded database metadata.

Use per-object bounded verification on the existing backend, not one 96 MiB
base64 request or server media decoding. Proposed target: 1 MiB read chunks, one
object at a time, no more than 96 MiB total worker memory, 1 second CPU and 30
seconds wall time per 32 MiB verification request. The full package receipt is
an atomic aggregation of verified immutable objects; no partial cohort may
admit. These are F3 feasibility targets, not established performance. Supabase
currently documents a 256 MB memory limit and 2 seconds CPU per request; local
byte hashing alone cannot qualify its hosted envelope.
[Supabase limits](https://supabase.com/docs/guides/functions/limits).

The proposed 30-minute unfunded staging deadline belongs exclusively to a **new
versioned CPM-1 clock**. It does not extend the existing preparation intent's
fixed 300 seconds or reuse an older grant. The next closed agreement must relate
frozen assignment/consent validity, staging, admission and all downstream phase
deadlines; expired or revoked authority still blocks admission. Until that
agreement is adopted, these numbers grant no existing path additional authority.

Write authorization expires no later than the original 30-minute intent
deadline; use at most ten-minute tickets and a five-minute client transfer
timeout per object. Any ticket refresh before expiry binds the same original
object/generation and cannot revive or extend the intent. It requires positive
old-write status, not a blind retry after a timeout. No new ticket after
retirement. Ticket expiry alone is not a proof of terminated writes; R2's
presigned URL guidance provides an authorization expiry, not our required
late-write closure proof.
[R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/).
The upload boundary must enforce the declared byte ceiling and conditional
immutable destination before accepting unbounded storage, not merely reject a
large body during later verification. Signed MIME alone is insufficient. F4 must
prove oversized/repeated writes cannot exceed the reserved object inventory or
replace verified bytes; until then the storage cap is a proposed bound, not a
guarantee supplied by presigning.

Keep unknown-write liability reserved, even beyond the work horizon. F4 must
establish conditional-write/late-completion behavior on the named target before
hosted acceptance. Do not add a worker or promise a cleanup TTL to conceal this
unknown. Status and cleanup remain available after admission expiry.

## Limit failures and authoritative ownership

Show the exceeded asset/package/storage limit and preserve supporting text,
source selection and any already-owned draft bytes. Offer explicit removal,
replacement, freeing device space, later retry or authorized status recovery.
Never downsize, strip metadata, substitute a thumbnail, drop companion audio,
split into separately charged requests, or replace an admitted package silently.
Full original retention is a deliberate storage/privacy tradeoff; an optional
converted replacement would be a separate explicit user selection, with its own
source identity. Existing historical missing originals remain unavailable. No
text-only fallback.

History primary is the sole implementation writer for native persistence and
backend reference/cleanup changes. Supabase transactions own the private
reference ledger, capacity reservations, live-owner checks and irreversible
retirement. IC-1 reviews identity/funding/dispatch/caller-lock integration;
independent review checks the complete candidate. The native actor owns local
file leases and crash recovery, not server erasure authorization.

Acquire shared-source holds before child preparation/commit depends on them;
transfer holds into admitted/history references atomically. A version deletion
releases only its references. The server's existing private erasure/outbox owner
must erase only zero-reference, zero-lease retired objects and retain fixed-ID
late-upload cleanup duties. Cleanup-token expiry never makes a retired object
acquirable again. After the last live reference, unresolved writes/reads/exports
still prevent premature release. Account erasure revokes access first and
retires every applicable owner; it does not leave contentful provenance behind.

Recommended cleaner work unit: 25 object identities or 30 seconds, whichever
comes first, with a two-minute claim and at most two concurrent cleaner workers.
Retain backlog reservations; capacity exhaustion stops admission, not cleanup.
This proposes execution bounds only. **No hosted cleanup schedule is
authorized.** The numeric claim does not establish a hard late-writer completion
bound or create provider/funding authority. Actual effective SQL callers, lock
order and cross-version schema remain the next closed agreement.

## Small feasibility checks, separately authorized

The product choices above can be approved now as targets. Physical compatibility
and enforcement remain assumptions until these finite checks pass. Prepare a
single evidence packet; no production-code implementation or operational test is
authorized by this proposal. Maximum proposed effort: two engineering days, zero
AI calls and zero AWS resources; stop and report the failing bound rather than
repeatedly expanding the exercise.

| Check                       | Bounded work and pass/fail                                                                                                                                                                                                                                                                                                                | Operator / remaining authority                                                                                                                               |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| F1 originals and protection | Twelve synthetic/consented camera/picker cases spanning supported formats, edits, orientation, cloud-unavailable, 32 MiB/one-byte-over and pixel bounds. Exact acquired-to-owned hashes, preserved draft on failure, no unsupported master claim; successful background reopen under the chosen file-protection policy.                   | History prepares harness; user runs device cases only after named device authorization. No library browsing or installation now.                             |
| F2 disk/restart             | Six maximum-cohort/low-storage scenarios, each with three interruption points (acquisition, commit, upload). Instrument all app/OS copies and crash remnants. Peak stays within reserved 288 MiB increment and free reserve; one-byte-over/unknown capacity denies new work; restart never doubles allowances or loses owned draft bytes. | Local harness and user device execution need their explicitly bounded approval; local measurement is not device qualification.                               |
| F3 existing backend fit     | Twelve synthetic object checks at small/12/32 MiB sizes and corrupt/boundary cases. Prove same generation/full hash, request-level CPU/memory/wall ceilings and atomic aggregate denial. No decode/provider call. Failure blocks 32 MiB adoption into an executable profile.                                                              | First offline measurement; hosted proof later needs named nonproduction target/read-write authorization. Do not dispatch production deployment to obtain it. |
| F4 sharing/late writes      | Eight deterministic race schedules: both acquire/delete orders, both admit/expire orders, lost PUT acknowledgement, late PUT after retirement, cleaner crash, lease expiry/reacquisition attempt. Zero resurrection, missing surviving sources, unaccounted bytes or extra AI grants.                                                     | Disposable local model first, then separately authorized private R2 integration. Neither mock nor local success proves remote write termination.             |

The final feasibility packet must name exact candidate, target, fixtures,
measurement method, observed maxima, failures and limits. Audio signal and
identification-quality qualification still follow G2 separately; these storage
checks cannot qualify audio or complete A0–A21. A failure is a concrete design
input for a revised recommendation, not implicit permission for AWS.

## PR116: merge effects and bounded integration recommendation

Read-only GitHub inspection found
[PR116](https://github.com/emreerdener/merian/pull/116) open and draft, remote
head `87893226850031506eb008fcd26752701c5dd456`, base
`167dbacb03b5fc3b0cc70cc9d04d3c74b21552fe` on `main`: 266 commits, 1,071 changed
files, 58 migrations, Supabase configuration and deployment workflow changes.
Local reviewed checkpoint `70b75279f9b7b55ec8dc3e3f9ce48915d602f95c` is 51
commits ahead, cumulatively 1,327 changed paths and 83 migrations against that
base. Neither the published PR nor the entire dirty checkout is the new
proposal's integration candidate. Existing exact-push approval still blocks
publishing the newer history. PR115 must remain untouched.

**Merging the current PR is potentially a production deployment.** Its
[deployment workflow](https://github.com/emreerdener/merian/blob/87893226850031506eb008fcd26752701c5dd456/.github/workflows/deploy.yml)
runs on `main` pushes. Candidate validation and source-scope/hold checks precede
an automatic `Production` job; YAML expects no required environment reviewers.
The source scope compares with the last successful production deployment, not
just the final PR commit. The
[hold manifest](https://github.com/emreerdener/merian/blob/87893226850031506eb008fcd26752701c5dd456/services/supabase/release-holds.json)
has only the existing inactive Field Chat hold, not a history deployment hold.
The human no-deploy instruction and disabled feature flags are not machine
gates.

If all release checks permit it, the workflow can predeploy compatibility
functions, apply pending migrations (`db push --dry-run` then real `db push`),
synchronize secrets, deploy the selected Edge fleet and run production smokes,
including reconciliation calls. Both `config.toml` and `deploy.yml` are
full-fleet selection paths in `planAffectedFunctions`; the remote-head tree has
124 direct Edge entrypoints. That inventory is not an exact future deployment
plan: the actual merged SHA, prior deployed SHA and target migration state must
be bound. It is unsafe to assume only new history endpoints would deploy. Manual
dispatch forces deployment scope/full-fleet planning and is prohibited.

Local workflow review finds iOS/web/admin build/test validation, not permission
for TestFlight or site publication. Live repository/environment settings,
external GitHub-app hosting hooks, last deployed SHA and production migration
ledger were not verified. The local `gh` CLI is unavailable; no credentials or
hosted data were accessed. These unknowns block claiming that a merge has zero
external effects. The dirty local deployment-workflow edit is unrelated and not
included in the published PR snapshot or this proposal.

Recommend a **source-integration checkpoint**, separate from CPM-1
implementation, full feature acceptance, backend rollout, activation and later
redesign:

1. Keep PR116 draft. Recommend the committed history work through
   `70b75279f9b7b55ec8dc3e3f9ce48915d602f95c` as the integration cut, plus this
   proposal's documentation and a later separately authorized, implemented and
   reviewed release-hold delta. Exclude the 115 unrelated working-tree paths,
   further CPM-1 implementation and the later redesign. Inventory published
   versus unpublished commits and their required checks; the 51 local commits do
   not inherit the remote PR body's old validation claim. Freeze the resulting
   integration SHA, base and migration/function manifest before any separate
   exact-push/merge approval. This is a bounded source cut, not a declaration
   that its full integration gates already pass. Do not publish it now.
2. Propose adding a distinct active source hold,
   `identification_history_integration_hold`, with `scope: supabase_production`,
   owner “History release owner”, and explicit release-exit criteria. The
   existing manifest parser supports additional unique hold IDs; retain the
   existing Field Chat entry unchanged. Any active hold makes
   `deploy_allowed=false` before entering the Production mutation job. Prove
   automatic and manual-dispatch paths both deny mutation for the exact
   candidate, including the full undeployed range. **This hold is not added by
   this proposal.**
3. Accept the tradeoff explicitly: this source hold stops the entire Supabase
   production job, including unrelated backend releases, until removed through a
   separately authorized release decision. It does not stop existing running
   jobs or external hosting hooks. Before a later merge, read-only verification
   must show no older production mutation job can cross this boundary; an
   existing running job is a blocker requiring its own decision. If a global
   hold is unacceptable, keep PR116 unmerged and validate its branch. Do not
   weaken scope detection or selectively omit migrations to simulate safety.
4. Require exact-candidate affected-surface validation and independent review:
   complete migration/catalog/privilege and Edge/DTO gates, native compilation
   and relevant persistence/recovery regression gates, affected web/admin and CI
   contracts, plus ordinary DI access nil and every activation gate disabled.
   Preserve prior failures and rerun only changed/invalidated gates. A
   feature-wide device/provider/storage qualification may remain open for this
   source-only checkpoint, explicitly recorded; no new real user path is
   installed or activated. Amend the integration checklist with that distinction
   before seeking a merge decision.
5. Before separately requesting exact push/merge authorization, verify live
   protected-branch/environment settings, queued/running release jobs and
   external auto-deploy integrations; pin a verified no-mutation hold and the
   intended merged-tree behavior. No merge or workflow dispatch is authorized
   now. After any future authorized merge, inspect that candidate validation ran
   and production mutation was skipped/held; do not interpret green CI as a
   release request.

Hold-exit criteria must cover a separate exact-SHA/target backend release
approval, reviewed full undeployed migration/function/secret plan, compatibility
and rollback/forward-repair evidence, and required release qualification.
Removing it is a backend deployment decision even if feature gates stay false.
Source integration does not close CPM-1 G1–G4, the alpha matrix, initial-engine
hardening or Field Trip. Individual-version actions and the
Identification/History/menu redesign keep their existing later sequence.

## Approval choices to carry forward

The recommended defaults are 32 MiB originals, 96 MiB packages, 192 MiB shared
temporary allowance with 256 MiB free reserve, four local pending packages, and
the bounded server capacity/lifetime profile above. Approve or revise these as
product targets, including rejection of oversized imports and indefinite
live-version retention. Approve the definition of picker-delivered original
rather than an unedited Photos master, and decide whether the future PR116
whole-backend hold is acceptable. Those choices still need the closed schema,
audio/reference agreement and successful feasibility evidence before
implementation authority is requested. Nothing here grants external operation,
AWS or activation approval.
