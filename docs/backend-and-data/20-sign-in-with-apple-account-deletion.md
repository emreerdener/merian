# Sign in with Apple Account-Deletion Revocation

**Status:** Apple credential capture and provider revocation were implemented in
source on 2026-08-06. The protocol-v2 preparation producer/consumer contract was
aligned in source on 2026-09-03 through an operation-specific native receipt and
a shared Deno/Swift fixture. Production promotion remains gated on authorized
real-session verification, hosted secrets, fresh-catalog replay, an Apple
staging smoke, and an enforceable minimum-supported-build gate or an independent
server-delivered manual-revocation fallback for older iOS binaries.

This is the normative engineering and rollout contract for revoking Sign in with
Apple authorization during Naturebook account deletion. It implements the
server-side token handling described by
[Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
and Apple's
[token revocation endpoint](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).
It complements, but does not replace, the
[scientific-observation retention contract](./17-scientific-observation-retention.md).

## Required outcome

For every new or returning Apple authorization completed by the supporting iOS
build, Naturebook must obtain a server-held Apple refresh token. An account
deletion with that credential cannot delete Supabase Auth until Apple accepts
the revocation and the database transaction destroys the stored credential.

Accounts authorized before this capability have no recoverable server token.
Their deletion must still proceed. The deletion receipt identifies that legacy
condition, and iOS persists Apple's manual revocation instructions before local
sign-out so the notice survives relaunch and foreground transitions. Apple's
customer-facing manual path is documented at
[How to use Sign in with Apple](https://support.apple.com/en-us/102571).

No authorization code, identity token, refresh token, Apple client secret, or
Apple response body may enter application logs, telemetry, a public table, or a
client deletion receipt.

Deletion acceptance must also survive termination after the server commits but
before iOS receives the receipt. Supporting builds bind a separate random
deletion-recovery proof during authenticated intake. That proof carries no Apple
or account identity and cannot initiate deletion by itself.

## Authorization capture

1. `ASAuthorizationAppleIDCredential` must contain both `identityToken` and
   `authorizationCode`. Missing either value fails the sign-in attempt.
2. iOS installs the Supabase Apple session, then immediately calls the
   authenticated `register-apple-revocation-token` function with both Apple
   values and one client-generated registration UUID.
3. The function checks the registration UUID before consuming the one-use code,
   verifies the presented identity token against Apple's JWKS, and pins issuer,
   audience, and algorithm.
4. The function signs a fresh five-minute ES256 Apple client secret and
   exchanges the code at `/auth/token`. It verifies the returned identity token
   and requires the same Apple subject as the presented token.
5. `store_apple_revocation_credential(...)` locks the permanent Auth user,
   rejects active deletion, and requires the verified Apple subject to match
   that user's `auth.identities` row. It creates or updates the refresh token in
   [Supabase Vault](https://supabase.com/docs/guides/database/vault) and writes
   the idempotency receipt in the same database transaction.
6. A lost HTTP response can repeat the exact registration UUID without a second
   code exchange. Receipts contain no token and are pruned after 24 hours.

If exchange succeeds but Vault persistence returns an error, the function first
rechecks the token-free registration receipt. A committed receipt resolves a
lost database response without revoking a credential that is already durable. If
the receipt is absent or cannot be read, the function attempts `/auth/revoke` as
fail-closed compensation. iOS clears the newly installed local session on any
registration failure and requires the user to start a fresh Apple authorization.
A new Apple sign-in is not presented as complete unless the server can later
revoke its authorization.

The app also observes Apple's credential-revoked notification. It revalidates
the active provider-specific Apple subject with `getCredentialState`, discards a
stale callback if the signed-in Apple identity changed, and clears the local
session unless Apple authoritatively reports `.authorized`.

## Durable deletion stage

Migration `20260806203700_durable_apple_provider_revocation.sql` adds a provider
substage to `internal.account_deletion_jobs` without weakening the existing
`pending → storage_pending → auth_pending → completed` state machine.

`request_account_deletion(user_id)` locks the Auth user and records exactly one
provider disposition:

| Condition at intake                            | `provider_revocation_status` | Deletion receipt                              |
| ---------------------------------------------- | ---------------------------- | --------------------------------------------- |
| Vault credential exists                        | `pending`                    | `manual_provider_revocation_required = false` |
| Apple identity exists but no credential exists | `manual_required`            | `manual_provider_revocation_required = true`  |
| No Apple credential or identity exists         | `not_required`               | `manual_provider_revocation_required = false` |

After delayed R2 verification advances the job to `auth_pending`, the worker
performs this order:

1. read the Vault refresh token only through the active job and UUID claim;
2. call Apple's `/auth/revoke` with `token_type_hint=refresh_token`;
3. accept only Apple's HTTP `200` idempotent success;
4. transactionally delete the private token mapping, registration receipts, and
   Vault secret, then mark the provider stage `completed`;
5. call Supabase Auth Admin deletion; and
6. commit terminal account-deletion completion.

Provider timeout, configuration, decoding, or non-200 failures release the claim
with bounded backoff and retain both the Supabase Auth identity and Vault
credential. A restrictive foreign key from the credential row to `auth.users`
hard-fences direct Auth deletion, while `finish_account_deletion_attempt(...)`
independently rejects terminal completion if provider work or a credential
remains. A lost provider-success response is safe because Apple documents HTTP
`200` for both newly revoked and previously invalid tokens; the next claimed
attempt repeats revocation before advancing.

`manual_required` is a resolved server disposition, not a claim that Apple was
revoked automatically. It permits privacy deletion to finish while preserving
the manual-instruction bit in the response. The updated iOS client stores that
bit before sign-out and keeps showing **Finish Sign in with Apple Cleanup**
until the user explicitly confirms that they removed Naturebook in Apple
settings.

### Client crash recovery

Migration `20260813053000_add_account_deletion_recovery_capabilities.sql` keeps
the legacy one-proof contract. Migration
`20260813142638_prepare_account_deletion_recovery_v2.sql` adds the supporting
two-stage protocol: iOS atomically persists distinct recovery and
acknowledgement proofs, authenticated prepare records only their SHA-256 hashes
without creating a deletion job, and later authenticated commit requires that
preparation. Recovery and acknowledgement use distinct protocol-v2 hash domains,
separate from legacy v1. Forward repair
`20260813162506_reject_expired_account_deletion_preparation_promotion.sql` locks
and converts only still-live device preparations. Expired proof hashes move
first to a permanent identity-free ledger and can never be reused or promoted
into 180-day recovery capabilities. A deletion-job insert records expired proofs
as committed before retiring them, so a second device cannot misclassify its
stale proof as unknown after deletion has started. Forward migration
`20260813190637_serialize_account_deletion_preparation_pruning.sql` gives the
bounded pruner the same Auth-user-first row-lock order and skips locked
accounts, closing the reciprocal cleanup-first race without making a batch wait
behind active deletion or recovery.

After Auth is gone, `/recover-account-deletion` uses only the proof to return
the already-recorded manual Apple disposition and pending/completed state. It
does not reauthenticate the deleted account or accept a user, Apple subject,
job, or provider identifier. iOS must persist the manual notice before local
sign-out, purge, and proof retirement. It acknowledges only after local cleanup
succeeds and only with the independent acknowledgement proof. A legacy unknown
proof leaves cleanup blocked because intake may still be committing. A v2
`not_committed` or genuinely unknown proof retires only the unused local intent
because commit cannot run without a server preparation. After that definitive
cancellation, the transition owner retires the unused proof, adopts only the
same unexpired cached Supabase session while the durable barrier remains, then
clears the barrier before republishing that exact UUID and anonymous/account
kind or reopening ordinary account work. An expired preparation retired during a
different device's commit returns the distinct non-authorizing
`account_deletion_recovery_preparation_expired` response and keeps cleanup
blocked. Only a retained committed capability matched after its 180-day window
returns `account_deletion_recovery_expired` and authorizes conservative local
cleanup while forcing the manual Apple notice. This acknowledgement never claims
automatic Apple-provider revocation.

The non-destructive v2 preparation response is decoded through the dedicated
`AccountDeletionPreparationReceipt`, which contains its exact four fields and no
provider disposition. Accepted deletion and public recovery retain the stricter
`AccountDeletionReceipt` with a required `manual_provider_revocation_required`
field. The handler test and native DTO/decoder suites consume one identity-free
fixture; the
[native preparation contract and integration checklist](../../apps/ios/Merian/Core/Network/README.md#preparation-receipt-contract)
separate that source-level proof from authorized real-session execution.

## Private data and authorization boundary

- `internal.apple_sign_in_revocation_credentials` maps one Auth user to one
  Vault secret UUID. It has RLS enabled, no Data API privileges, and an
  `ON DELETE RESTRICT` Auth foreign key.
- `internal.apple_sign_in_credential_registrations` contains only registration
  UUIDs, user UUIDs, and timestamps. It has RLS enabled and no direct API
  privileges.
- `apple_revocation_registration_exists`, `store_apple_revocation_credential`,
  `get_account_deletion_provider_token`, and
  `complete_account_deletion_provider_revocation` are service-role-only, in-body
  authorized, empty-search-path routines on the privileged-routine allowlist.
- The authenticated Edge handler derives the caller from the verified JWT. No
  caller can nominate another user or read a stored token.
- `internal.account_deletion_recovery_capabilities` stores only a unique SHA-256
  proof hash, deletion-job reference, expiry, and recovery/acknowledgement
  times. Direct access is revoked. Its issue, recover, and health routines are
  service-only and no public response contains a user or Apple identity.
- `internal.account_deletion_expired_preparation_proofs` permanently stores only
  an expired proof hash, its recovery/acknowledgement kind, expiry, record time,
  and whether deletion had committed. Direct access is revoked; it contains no
  user, job, Apple, device, provider, or purchase identity and never authorizes
  deletion by itself.

## Hosted configuration

The production GitHub `Production` environment must provide:

- `APPLE_SIGN_IN_TEAM_ID`
- `APPLE_SIGN_IN_KEY_ID`
- `APPLE_SIGN_IN_PRIVATE_KEY` — the PKCS#8 `.p8` key, with either raw newlines
  or escaped `\n`

The deployment workflow validates all three before database mutation and
synchronizes them as Edge Function secrets before deploying the affected
functions. The native Apple client ID is pinned to `app.merian.Merian`, matching
the iOS bundle and `services/supabase/config.toml`.

Key rotation is one release operation: provision a new Apple key, update the
three GitHub secrets, run the production deployment so Edge receives the new
values, complete exchange and revoke smokes, and only then retire the prior key
in Apple Developer. Do not commit the `.p8` file or reuse a generated Apple
client-secret JWT as `APPLE_SIGN_IN_PRIVATE_KEY`.

## Rollout and production exit gate

The migration and these runtime consumers form one release unit:

- `register-apple-revocation-token`
- `safe-delete`
- `recover-account-deletion`
- `reconcile-account-deletions`
- iOS `SupabaseManager`, `MerianNetworkClient`,
  `AccountDeletionRecoveryCapability`, the Settings
  `AccountDeletionDependencies`, `DeleteAccountViewModel`, and
  `DeleteAccountSheet` presentation path, and the app-root manual notice

The production workflow applies migrations before Edge bundles. The prior worker
rejects the new `provider_revocation_pending` cleanup result, so a stored
credential cannot fall through to Auth deletion during that short interval. Do
not intentionally exercise account deletion until the affected bundles are
deployed and the post-deploy checks pass.

Repository completion is not production completion. The source-level preparation
contract is aligned, but promotion still requires all of the following on one
immutable release SHA:

- exact Supabase CLI `2.109.1` fresh-catalog migration replay and the complete
  account-deletion pgTAP fixture;
- focused Apple exchange/revocation, registration-handler, deletion-worker,
  migration, and source-order tests;
- complete Supabase tooling, formatting, lint, and isolated function graphs;
- hosted Apple secrets synchronized without printing values;
- a real non-production Apple sign-in showing one credential mapping and one
  Vault secret, followed by account deletion that records provider completion,
  removes both secret records, and only then removes Auth;
- a forced transient revoke failure proving Auth and the Vault secret remain
  retryable;
- a legacy Apple fixture proving the deletion response sets
  `manual_provider_revocation_required`, the notice survives sign-out and
  relaunch, and the Apple support/settings path opens;
- physical-device termination at each recovery boundary: before authenticated
  intake, after server commit with a dropped response, after local Auth
  sign-out, after SwiftData purge, after recovery acknowledgement, and after
  Keychain removal. Each relaunch must converge with the same proof without
  restoring an account or losing the manual-provider disposition;
- public recovery with no cached Auth session, using publishable `apikey` plus
  the proof only, as well as wrong-proof and matched-expired fixtures that prove
  fail-closed versus conservative-terminal behavior;
- a physical-device credential-revocation notification smoke proving the app
  queries the active provider-specific Apple subject and clears the matching
  local session when Apple no longer reports `.authorized`, while exact-SHA
  source coverage retains the stale-identity callback fence; and
- an enforceable minimum-supported-build gate or an independent server-delivered
  manual-revocation fallback for older iOS binaries. Older installed binaries
  cannot display a response field or notice they do not implement. Merely
  publishing or distributing the supporting build therefore does not complete
  the legacy-account rollout.

As of 2026-08-06, this repository contains neither an enforced minimum iOS build
gate nor an independent server-delivered fallback for a deletion started by an
older binary. Product promotion is blocked until one of those controls is
implemented and verified. A version gate must preserve a clear, usable path to
in-app account deletion after update; a server fallback must durably deliver
Apple's manual-removal instructions without depending on a response field that
the old client ignores.

The existing account-deletion health monitor includes provider stalls inside
`auth_pending_count`; retry failures contribute to `failed_job_count` and the
bounded `last_error_code` used by restricted logs. Operators repair Apple
configuration or availability and let claim-fenced retries resume. They must
never delete Auth manually, edit provider status, copy a Vault token, or mark a
provider attempt successful from an Apple error response.

## Verification map

- `_shared/appleSignIn_test.ts`: form encoding, identity-subject binding,
  terminal exchange errors, idempotent revoke success, and response-body
  redaction.
- `register-apple-revocation-token/handler_test.ts`: idempotent lookup,
  exchange-before-store ordering, lost-response receipt reconciliation, and
  compensating revocation.
- `_tests/safeDelete.test.ts`: provider-before-Auth ordering, retry retention,
  and legacy manual disposition.
- `_tests/accountDeletionCoverage.test.ts`: source, iOS, workflow, config, and
  executable-fixture ordering.
- `_tests/accountDeletionMigrationContract.test.ts`: Vault schema, Auth and
  terminal fences, recovery hash ledger, ACLs, allowlist, permanent replay,
  health, and secret destruction before state commit.
- `safe-delete/protocol_test.ts`, `safe-delete/db_recovery_test.ts`, and
  `recover-account-deletion/handler_test.ts`: exact proof wire contract,
  server-side hashing, account-free recovery, stable errors, and no-store
  response behavior.
- `tests/account_deletion_security.sql`: live catalog intake, Vault read,
  provider completion, secret removal, legacy disposition, Auth fencing, retry,
  terminal completion, expired-preparation retirement, and a two-device commit
  proving an expired proof never becomes a committed recovery capability.
- Core Network's `AccountDeletionEndpointTests`,
  `AccountDeletionRecoveryEndpointTests`, and
  `AccountDeletionRecoveryTransportTests`: isolated legacy/v2 wire mapping,
  strict receipt handling, public-only recovery headers, retries, bounds, and
  cancellation. `AccountDeletionAPIModelsTests`,
  `AccountDeletionRecoveryValidationTests`, and
  `AccountDeletionResponseDecoderTests` cover exact DTOs and fixed-clock
  phase/status/expiry rules; `AccountDeletionBoundaryTests` guards private
  transport, owner forwarding, and test ownership. See the
  [native verification matrix](../../apps/ios/Merian/Core/Network/README.md#account-deletion-and-recovery-verification)
  for the accepted-owner integration evidence boundary and manual checklist.
  Their preparation tests consume the same exact four-field fixture as the Deno
  handler test and also prove it cannot decode as an accepted receipt.
- `SupabaseManagerTests`, `MerianNetworkClientTests`, and `AppDIContainerTests`:
  bounded registration retry, shared Auth refresh policy, subject-bound
  credential-state handling, durable notice persistence, exact
  prepare/owner/marker/commit ordering, pre-commit owner/marker
  short-circuiting, stale post-commit owner classification, recovery phase
  order, ambiguous-response retention, and terminal capability retirement.
- `AccountDeletionRecoveryCapabilityTests`: secure randomness, Keychain
  accessibility, write verification, reuse, and verified deletion.
