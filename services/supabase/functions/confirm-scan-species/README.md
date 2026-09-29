# confirm-scan-species

Prepared authenticated review endpoint for the reserved explicit-primary result
contract. Current model profiles do not produce that contract and the native app
has no caller yet. This checkpoint does not activate a model or change
confidence.

`POST /confirm-scan-species` uses `withEdgeHandler` authentication and derives
the owner from the verified session. `verify_jwt = false` does not make the
route public. `index.ts` orchestrates; `db.ts` owns queries and the service-only
atomic RPC; `contract.ts` owns strict request/receipt validation.

## Request and response

Send exactly `scan_id` (lowercase UUID), `expected_revision` (integer
0–2,147,483,646), and `action`:

- `confirm_primary`: verify the saved species-level primary name. A genus,
  family, unresolved or non-biological primary cannot be confirmed as a species.
- `confirm_name`: additionally send `scientific_name`, a selection of up to 160
  UTF-16 units. It is normalized input, never proof. UUIDs, taxonomy and owner
  fields supplied by a client are rejected.
- `clear`: no name, proof or external lookup; creates a newer authoritative
  null.

The response has `schema_version: 1`, the exact `scan_id`, and `review`. That
version-1 envelope carries `revision`, nullable `identity`, and the four
existing review fields. A non-null identity has exactly `version: 1`,
`species_id`, bounded `scientific_name`, `common_name: null`, and the positive
`gbif_taxon_key`. Its UUID and name come from the verified dictionary row,
including when an accepted-name change reuses an older saved name. The review
envelope is bounded to 8 KiB; the identity is bounded to 4 KiB. Typed overrides
retain the legacy `user_overridden` plus `user_confirmed_identification: false`
tuple; confirming the primary uses `ai_confirmed` plus true. Identity authority
is independent of those flags.

No original AI label, rank, score, explanation or provenance is rewritten. A
verified taxonomy selection does not establish that the observation depicts that
species and is not a calibration of model confidence.

## Proof, concurrency and recovery

Owner lookup and obvious revision conflicts stop before external work.
Confirmation uses the existing non-AI admission counters (6/user/minute,
60/user/day, 120 globally/minute) before a fresh bounded GBIF verification,
including dictionary hits and retries. Accepted synonyms require the verified
accepted SPECIES record. The shared verifier permits at most two reads, each
bounded to 6 seconds/64 KiB, with cancellation. There is no model call or scan
allowance debit. Clear requires neither admission nor GBIF availability.

`apply_verified_scan_species_review` is service-only, fixes `search_path`,
checks the caller role and serializes with finalization/recovery/deletion using
their scan-generation advisory lock, followed by scan and owner-job row locks.
It requires a matching original primary/provenance and exact review backup.
Expected revision advances once. A retry from exactly one revision earlier
succeeds only if its entire desired identity/action/selection is already saved;
a different or older mutation receives `409 species_review_revision_conflict`.
Refresh and reconcile; do not automatically retry it with a newer revision.

The scan stores identity and revision; the ingestion job stores the complete
`confirmed_species_review` envelope. Old review/community changes invalidate
both the identity and legacy FK and advance revision while retaining review
intent. The existing recovery RPC's insert trigger restores all four fields from
the exact server backup, or clears them when no backup exists. Client recovery
JSON cannot assert authority or resurrect an earlier selection. Account merge
keeps the envelope owner-bound; deletion/owner removal clears it.

All responses are private/no-store. Missing and foreign scans share 404. Invalid
inputs return 400, unsupported legacy observations and revision conflicts 409,
unverified species 422, bounded admission 429, and unavailable verification 503.
Unexpected integrity failures return generic errors without provider bodies or
observation text. Names and receipts must not enter logs or benchmark artifacts.

## Integration and release boundary

Migration `20260929170458_prepare_verified_scan_species_review.sql` precedes
endpoint deployment. The deployment workflow's critical authenticated-route
smoke requires an unauthenticated POST to reach this route's own 401 handler;
the generic OPTIONS probe alone is insufficient. Native
acknowledgement/history/clear merging into reserved V53 storage and
shared/public/export consumers remain separate checkpoints in the
[primary-resolution plan](../../../../docs/rfcs/identification-primary-resolution-contract-2026-09-29.md).
Native capability remains 4 until all consumers are complete. No model producer,
provider assignment, confidence threshold or consent behavior changes here.

Validation covers strict HTTP/auth/cancellation cases, actual database roles,
legacy review compatibility, identity replacement/clear, stale and simultaneous
mutations, missing-row recovery, account merge and privacy cleanup. Follow the
[backend gates](../../README.md) and existing exact-SHA release procedure;
source implementation and passing local tests do not constitute deployment.
