# review-scan-identification

Authenticated owner decisions for **Mark as incorrect**, Undo, and explicit
acceptance after rejection. The immutable AI answer remains evidence. A
rejection means the identification is unresolved; it does not assert a
replacement species, submit to community, open a support ticket, or authorize
model training.

`index.ts` authenticates through `withEdgeHandler`, looks up the owned scan,
checks revisions, verifies named acceptances, and calls the atomic service-only
RPC. `contract.ts` owns exact payload validation. `db.ts` owns database access.
The native owner is `IdentificationReviewSyncService`, backed by V54 optional
review storage and account-bound `OfflineJobRecord` intents.

## Contract

Send `scan_id`, `expected_revision`, `operation_id`, `action`, and
`expected_species_review_revision`. UUIDs are lowercase; the AI-review revision
is 0–999,999,998. The species-review revision is required for explicit-primary
records and null for legacy records.

- `reject`: no replacement name required. Sets `ai_rejected` and records the
  original scan/name. Existing AI confirmation becomes unreviewed; manual
  overrides and resolved community identifications cannot be rejected here.
- `undo`: restores the original AI suggestion as unreviewed. It cannot accept a
  reanalysis proposal.
- `confirm_primary`: independently verifies the saved species-level AI name.
- `confirm_name`: additionally requires bounded `scientific_name`; the name is
  input, not taxonomy proof.
- `carry`: the owner's explicit replacement handoff additionally supplies
  `source_scan_id` and `source_revision`. Both observations must belong to the
  caller, the source must still be unresolved at that revision, and the target
  must have no review revision. The target becomes `awaiting_acceptance` with
  the original source provenance. This operation transfers rejection only; it
  provides no evidence that either observation depicts any species.

The response contains `schema_version: 1`, `scan_id`, `review`, nullable
`species_review`, and nullable canonical `confirmed_species_id`. `review` has
exactly `version`, `revision`, `state`, `origin_scan_id`,
`origin_identification`, `operation_id`, `operation_digest`, and `community`.
The state is `clear`, `ai_rejected`, or `awaiting_acceptance`. The bounded
`community` projection is null unless a trusted consensus transaction resolved
this rejection. It carries the request, rank, names and nullable species ID.
Genus resolutions never earn species credit. Withdrawing or reversing that
consensus restores the unresolved obligation.

## Durability and privacy

The RPC locks the scan generation, checks owner/tombstone state, compares the
expected revision, and commits the review plus matching owner-job backup. Older
saved scans receive an authoritative ledger snapshot on their first review. An
exact committed retry returns its receipt before quota or GBIF work. Reusing an
operation with a different action or stale revision returns
`409 identification_review_revision_conflict`.

The native outbox persists intent and job together. A failed predecessor cannot
be overtaken. Conflict/permanent-denial reconciliation fetches current owned
state and discards dependent intent instead of rebasing it. Transient failures
retain bounded retry scheduling. Reanalysis keeps the source until the carry
receipt is durable; accepting the proposal is a separate operation.

Raw review history is not selectable by anonymous or authenticated users from
`scans`, including public observations. `get_owned_scan_ai_reviews` derives the
owner from `auth.uid()` and accepts at most 100 IDs. Its current review fields
come from the same snapshot. Public consumers use effective identification,
which has no species while unresolved. Tombstones/deletion clear job backups.

Protocol 6 is required to read affected decisions, including community results.
Deploy the migration and route before a native build using this contract. These
source changes and local checks do not authorize deployment.

A non-biological reanalysis result remains a separate saved result; it does not
retire the original rejected observation or carry an acceptance obligation into
the non-biological screen. Broad taxon proposals offer community help instead of
species-only acceptance controls.

## Verification

- Deno parser/handler tests cover strict requests, owner binding, bounded names,
  conflict handling, and retries avoiding duplicate external verification.
- `tests/identification_rejection.sql` covers actual-role privacy, durable
  receipts, replacement proposals, reader compatibility, and deletion.
- `AIIdentificationReviewTests` and `MigrationPlanTests` cover local intent,
  immutable evidence, replacement staging, and V53→V54 stores.

See the canonical
[API contract](../../../../docs/backend-and-data/05-api-contracts.md) and
[schema contract](../../../../docs/backend-and-data/04-database-schema.md).
