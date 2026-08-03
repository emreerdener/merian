# Security and Reliability Remediation — 2026-08-03

This record joins five repository fixes that share one release boundary:
collection ownership, staging-upload size enforcement, offline complimentary
funding admission, redirect construction, and taxonomy cursor checkpointing.
It records what is implemented, where the normative contracts live, and what
must be proven before production promotion. It does not supersede the linked
canonical documents.

## Status

The repository contains the forward migrations, Edge changes, iOS protocol-3
behavior, redirect helpers, taxonomy checkpoint correction, and regression
tests. Repository-corrected and production-verified are separate states:

- applying a migration does not activate complimentary mode or require protocol
  3;
- exact-header upload signing must not be enabled before the compatible iOS
  build is deployed;
- no source-only or mocked test substitutes for fresh-catalog PostgreSQL,
  deployed R2, hosted iOS, admin, or public-web evidence; and
- foreign collection IDs and unavailable scan memberships remain skippable by
  design so stale offline state cannot block unrelated synchronization.

## Remediation matrix

| Area | Repository contract | Fail-closed boundary | Compatibility |
| --- | --- | --- | --- |
| Collection sync | `upsert_owned_collections` atomically admits only new or same-owner collection IDs; `insert_owned_collection_scans` joins both parents to the authenticated owner | RPC errors stop membership work; a trigger rejects cross-owner parents; `service_role` can update only `name` and `created_at` directly | Foreign IDs and missing/foreign scans are logged and skipped |
| Staging upload | Every manifest member declares a positive exact `sizeBytes`; each signed response declares required `Content-Type` and decimal `Content-Length` | Both headers and `host` are signed; iOS re-stats immediately before PUT and re-signs changed files | Legacy `fileNames`, missing sizes, arrays, and other old shapes intentionally return `400 size_bytes_required` |
| Complimentary admission | A stable scan/account funding reservation is claimed synchronously before file writes or foreground inference and persisted in the scan job | Verified server availability is reduced by unresolved local blockers; uncertainty under-admits; 402 invalidates local proof | Protocol-2 remains accepted only during the dual-mode rollout; protocol-3 is required at atomic cutover |
| Redirects | Admin callbacks derive from validated `NEXT_PUBLIC_ADMIN_ORIGIN`; web aliases derive from fixed `CANONICAL_ORIGIN` | Absolute, protocol-relative, backslash, recursively encoded separator, and hostile Host inputs cannot select an origin | Valid local paths retain pathname, query, and hash; web aliases retain pathname and query |
| Taxonomy import | Every successfully fetched page checkpoints its raw-page `nextOffset`, even when all rows normalize out | Fetch failure leaves the failed page uncheckpointed; dry runs simulate movement without writes | Stop only at GBIF `endOfRecords`, a raw empty page, or requested `page_count` |

## Collection ownership boundary

`sync-collections` resolves the caller from the verified JWT and passes that UUID
as `p_user_id`; ownership is never accepted from collection JSON. One
`INSERT ... ON CONFLICT ... DO UPDATE` statement updates `name` and `created_at`
only when the existing row has the same owner. Its accepted/rejected result is
the sole input to membership hydration and delta calculation. A concurrent UUID
collision therefore remains foreign-owned rather than being reparented.

Membership insertion is independently owner-scoped. The RPC joins the requested
collection and scan to `p_user_id`, while the invoker trigger enforces equal
parent owners for direct service and authenticated writes. Existing mismatches
are removed by the forward migration. Authenticated RLS separates own-parent
select/delete from own-collection-plus-own-scan insert; membership updates are
unsupported. Both RPCs use empty search paths and explicit `service_role`-only
execute grants.

Normative details:

- [collection API contract](./05-api-contracts.md#deno-sync-collections-edge-node)
- [database schema and privileges](./04-database-schema.md#collections-and-collection_scans)
- [route README](../../services/supabase/functions/sync-collections/README.md)

## Exact-size staging uploads

The manifest size is a signing input, not trusted evidence that the object was
uploaded. The Edge signer validates per-kind and aggregate budgets before
issuing a URL. SigV4 covers `content-length;content-type;host`, and each response
item repeats the two caller-supplied headers under `requiredHeaders`. Every iOS
data, file, repair, restore, and background PUT applies that map. A
`ScanUploadItem` retains the signing-time size; a final file stat mismatch
invalidates the URL before task creation. A post-upload HEAD check remains the
authoritative verification that R2 stored the declared number of bytes.

Normative details:

- [staging API contract](./05-api-contracts.md#deno-generate-upload-urls-edge-node)
- [background upload architecture](../system-architecture/07-background-inference-body-safe.md)
- [cross-language manifest](../contracts/media-staging-upload-manifest.json)
- [signer README](../../services/supabase/functions/generate-upload-urls/README.md)

## Serialized complimentary funding

Boolean entitlement properties are presentation hints. Admission is the
idempotent `ScanFundingReservation` transaction on `@MainActor`, keyed by stable
scan ID and active account. Its source is one of paid Pro, locally reserved
complimentary Pro, immediate Flash, or deferred Flash with earlier blocker scan
IDs. Only exactly one image, one standalone audio clip, or one description—and
never video—is eligible for Flash.

The job metadata object may contain `inference_generation` and
`funding_reservation` simultaneously. Each owner removes only its property. A
proven pre-dispatch local failure first durably removes the reservation and
writes `funding_reservation_released: true`; only after that save succeeds may
memory state and the advisory Flash token be released. This marker prevents a
relaunch from restoring an intentionally released pre-protocol-3 job as an
unknown complimentary blocker. A manual retry of released work performs a new
synchronous funding claim from the persisted capture timeline.

On each scheduler pass, one bulk owner-scoped status lookup reads blocker
`complimentary_state`. Deferred work remains blocked under uncertainty.
`held`/`consumed` blockers safely select immediate Flash; `released` or absent
terminal state requires an authoritative entitlement refresh and
reclassification. A terminal `consumed` status also remains a blocker until a
subsequent successful entitlement read proves the local balance snapshot
includes settlement. A newly paid account promotes deferred work to paid Pro.
Successful response handling uses both `plan_used` and `credit_consumed`; a
`pro_complimentary` result with `credit_consumed: false` releases the local
assumption, such as when paid access won before settlement.

Normative details:

- [complimentary Pro contract](./18-complimentary-pro-scans.md)
- [offline pipeline](./01-offline-sync-pipeline.md)
- [iOS security README](../../apps/ios/Merian/Core/Security/README.md)
- [bulk funding-state contract](../../services/supabase/functions/check-scan-status/README.md)

## Redirect origin safety

The admin callback validates that `NEXT_PUBLIC_ADMIN_ORIGIN` is an HTTP(S)
origin with no credentials, path, query, or fragment. Its `next` helper accepts
only a single-leading-slash local path after bounded recursive decoding, then
copies pathname, search, and hash onto the configured origin. It never derives
the destination from `request.url`, `Host`, or forwarding headers.

The public web alias helper starts from `CANONICAL_ORIGIN`, then assigns
`pathname` and `search` separately. It never resolves attacker-controlled path
text as a URL, so `//evil.example`, slash/backslash variants, and Host-header
input cannot replace the canonical origin.

Normative details:

- [admin security architecture](./10-internal-admin.md)
- [admin operations](./11-internal-admin-operations.md)
- [public-brand host contract](../system-architecture/08-public-brand-compatibility.md)

## Taxonomy checkpoint safety

A successful raw page is processed in this order: normalize, upsert any
remaining taxa, then checkpoint the raw page's `nextOffset` regardless of
normalized count. The cursor therefore describes fetched GBIF progress rather
than inserted-row count. Coverage refresh runs once after the worker only when
at least one row was imported. The final page checkpoint already owns the page
summary; there is no redundant end-of-run cursor write.

Normative details:

- [taxonomy worker contract](../../services/supabase/functions/sync-community-taxonomy-index/README.md)
- [import checklist](./07-community-taxonomy-import-checklist.md)
- [taxonomy API contract](./05-api-contracts.md#deno-sync-community-taxonomy-index-edge-node-internal-import-worker)

## Ordered rollout

1. Promote the collection and protocol-3-compatible schema migrations while
   complimentary mode remains legacy and required protocol remains 2 or 0 as
   appropriate.
2. Deploy dual-mode Edge behavior that accepts supported protocols 2–3. The
   collection and taxonomy corrections are independently deployable.
3. Deploy the iOS build that applies response-declared upload headers and uses
   funding reservations. Verify it through TestFlight before changing either
   server compatibility boundary.
4. Enable exact-header signing and legacy upload rejection. Verify exact PUT,
   wrong-size and wrong-MIME rejection, and stored R2 object size.
5. Atomically select complimentary mode and require protocol 3. If production
   never activated protocol 2, use the owner script's direct legacy-0 to
   protocol-3 cutover; otherwise transition only after the fixed build is
   verified.

Rollback must preserve forward schema, ownership triggers, private ledgers, and
audit history. Hold promotion or repair forward when a compatible application
version is unavailable; do not reopen unsafe clients or broad table grants to
restore traffic.

The executable command sequence and production smokes are canonical in the
[Supabase deployment runbook](./06-supabase-deployment-runbook.md#security-and-reliability-remediation-rollout).

## Required evidence and monitoring

Before production sign-off, prove:

- foreign and concurrent-collision collection IDs remain unchanged while
  unrelated IDs sync; cross-owner membership writes fail through RPC, direct
  service access, and authenticated RLS; Ghost merge still reparents through its
  reviewed function;
- missing/legacy upload manifests fail, exact signed PUT succeeds, wrong length
  or MIME fails, HEAD equals the declared size, and file mutation re-signs;
- one local remaining credit admits one complimentary reservation, relaunch
  restores ordering, released and consumed settlement paths refresh safely,
  mixed/video work is rejected, paid reclassification works, ambiguous outcomes
  remain reserved, and obsolete clients receive 426 only after cutover;
- redirect test matrices cover query/hash preservation, absolute and
  protocol-relative forms, slash/backslash and encoded variants, and hostile
  Host headers; and
- normalized-empty raw taxonomy pages checkpoint and continue, later failures
  resume after that checkpoint, dry runs write nothing, and all-empty runs skip
  coverage refresh.

Monitor rejected collection IDs, R2 signature failures, oldest deferred-funding
age, 402 and 426 rates, and fetched taxonomy pages with zero normalized rows.
Pause the affected rollout boundary when any signal rises unexpectedly; never
clear it by mutating ownership, reservations, or cursor state without proving
the underlying event.
