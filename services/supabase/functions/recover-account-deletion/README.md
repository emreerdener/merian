# Account Deletion Recovery

`recover-account-deletion` is the public, capability-authenticated continuation
for a deletion that `/safe-delete` already authorized or for a protocol-v2
preparation that may not have reached commit. It exists because the account's
Supabase Auth identity may be removed before the initiating device receives the
HTTP receipt. It cannot initiate deletion and accepts no account, job, provider,
or purchase identity.

The request is an exact object:

```json
{
  "operation": "recover",
  "recovery_capability": "43-character-base64url-device-proof"
}
```

`operation` is `recover` or `acknowledge`. iOS generates 32 random bytes,
persists them with `whenUnlockedThisDeviceOnly`, verifies the Keychain write,
and sends the base64url value only over TLS. Edge validates the bounded body and
hashes the proof with SHA-256. PostgreSQL stores only that hash in
`internal.account_deletion_recovery_capabilities`.

Protocol v2 uses two domain-separated 32-byte proofs. Recovery accepts
`protocol_version: 2` with `recovery_capability`; acknowledgement accepts the
same version with `acknowledgement_capability`. A non-destructive preparation
must exist before authenticated commit can run. Still-live uncommitted recovery
returns `not_committed` and retires the preparation without changing Auth or
local data.

The service-only `recover_account_deletion(text,boolean)` RPC derives the
existing job exclusively from the hash. A successful response contains only
`pending|completed`, the manual-provider-revocation boolean, capability expiry,
and acknowledgement state. It never returns an identity. A wrong proof is a
bounded `404 account_deletion_recovery_invalid`; dependency failure is a
retryable `503 account_deletion_recovery_unavailable`.

Capabilities expire after 180 days for normal inspection. An expired hash is
retained until acknowledgement and returns the distinctive bounded
`410 account_deletion_recovery_expired`. Because that response can only follow a
server-side hash match, iOS may conservatively finish the already-requested
local sign-out and erasure and show the manual Apple notice. The same expired
proof remains valid for the post-cleanup `acknowledge` operation; only after
that durable receipt may iOS retire its proof. An unknown legacy-v1 `404` never
authorizes local cleanup or marker removal: an earlier authenticated request may
still be committing after an ambiguous transport failure. An unknown v2 proof
also cannot authorize cleanup, but it definitively permits unused proof/intent
retirement because destructive commit requires a prior server preparation.

Preparation expiry is not capability expiry. Expired v2 preparation hashes are
first moved to the permanent private, identity-free
`internal.account_deletion_expired_preparation_proofs` ledger and can never be
reused or promoted into a 180-day capability. A proof expired without any
deletion returns `not_committed`; a proof retired while another device's commit
won returns bounded `410 account_deletion_recovery_preparation_expired`. That
distinct response is non-authorizing, so iOS retains its fail-closed barrier for
operator/retry resolution instead of erasing local data. Only the positive match
to an actual committed capability may return
`account_deletion_recovery_expired`.

iOS acknowledges only after verified local Auth sign-out and SwiftData purge. It
then persists a retirement marker, removes the Keychain proof with verified
deletion, and clears the marker last. A crash at any boundary repeats the same
operation. The hash remains as a permanent idempotency receipt because the
acknowledgement response can itself be lost. Issue is capped at eight total
hashes per deletion job, including acknowledged receipts, so acknowledgement
cannot bypass the storage bound.

Authorization and observability are fail-closed:

- the Edge route needs only the publishable `apikey`; it does not consume a
  cached user bearer token;
- all four database RPCs are `service_role`-only, call
  `internal.require_service_role()`, and private table access is revoked;
- responses are `private, no-store`, logs contain no proof, hash, account, job,
  or raw error; and
- `get_account_deletion_recovery_health()` contributes aggregate active,
  acknowledged, expired, age, and per-job-cardinality state to the independent
  account-deletion monitor.

Deploy the migration and this route before distributing an iOS build that sends
`recovery_capability`. Old clients continue to send an empty `/safe-delete` body
and receive the legacy response shape. Never remove the compatibility path until
the old-client support window closes.

Executable coverage lives in `handler_test.ts`,
`../safe-delete/protocol_test.ts`, `../safe-delete/db_recovery_test.ts`,
`../_tests/accountDeletionMigrationContract.test.ts`, and
`../../tests/account_deletion_security.sql`.

On iOS, `Core/Network/Endpoints/MerianNetworkClient+AccountDeletion.swift` owns
the public legacy/v2 recovery and acknowledgement calls. A fixed-route bridge
delegates to the existing private capability-only transport; pure receipt and
timestamp validation do not own Keychain retirement or local cleanup. See the
[native ownership and verification matrix](../../../../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-verification)
for the mirrored suites and separate real-session evidence requirement.

The checked-in v2 prepare handler currently omits
`manual_provider_revocation_required`, which the shared native receipt requires.
That incompatibility prevents iOS from reaching normal commit even though this
recovery route's v2 contract is implemented. See the matrix's
[known preparation-receipt mismatch](../../../../apps/ios/Merian/Core/Network/README.md#known-preparation-receipt-mismatch)
before treating separate native/backend test results as end-to-end evidence.
