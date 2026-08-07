# Sign in with Apple Account-Deletion Revocation

**Status (source implemented; production evidence pending, 2026-08-07):**
automatic Apple token revocation and the independent legacy fallback are both
implemented in repository source. A successful Resend send response now records
only `accepted`; it cannot remove the restrictive Auth fence. The dedicated
signature-verified webhook and database reducer make Auth deletion reachable
only after a matching `email.delivered` event. This closes the client-version
dependency in source. Production promotion remains blocked on the immutable-SHA
candidate, hosted configuration, real private-relay delivery,
oldest-supported-binary smoke, and zero-unverifiable evidence gates below.

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
Their deletion must still proceed through an authoritative legacy control. The
deletion receipt identifies that condition, and supporting iOS builds persist
Apple's manual revocation instructions before local sign-out. That notice is
defense-in-depth: the server independently sends the same instructions to the
account's confirmed Auth email and retains Auth until Resend confirms delivery.
Older binaries do not need to understand the deletion response for this control
to work. If hosted delivery confirmation cannot be validated, production must
instead enforce another guaranteed control, such as a minimum-build/update
gate, before legacy deletion. Apple's customer-facing manual path is documented
at
[How to use Sign in with Apple](https://support.apple.com/en-us/102571).

No authorization code, identity token, refresh token, Apple client secret, or
Apple response body may enter application logs, telemetry, a public table, or a
client deletion receipt.

## Dispatch-versus-delivery authority

`manualRevocationEmail.ts` records the provider email ID after
Resend returns a successful `POST /emails` response. That proves only that the
API request succeeded and Resend will attempt delivery—the `email.sent`
boundary—not that the recipient's mail server accepted the message. Resend
reports that later outcome separately as
[`email.delivered`](https://resend.com/docs/webhooks/emails/delivered), and can
instead report `email.delivery_delayed`, `email.bounced`, `email.failed`, or
`email.suppressed` through its
[webhook event types](https://resend.com/docs/webhooks/event-types).

The worker now calls
`record_account_deletion_manual_revocation_acceptance(...)`. That routine binds
the provider email ID to a pre-created attempt and normally advances the job to
`accepted`; it keeps `internal.apple_manual_revocation_delivery_requirements`
and releases the worker claim. The legacy
`complete_account_deletion_manual_revocation_delivery(...)` RPC remains only as
a migration-first compatibility fence and always rejects acceptance as
completion. The signed webhook calls
`record_account_deletion_manual_revocation_event(...)`; only its matching
`email.delivered` transition deletes the requirement and records `delivered`.

No release evidence may describe a successful send response or provider email
ID as delivered. Historical completed legacy jobs without a recoverable signed
delivery event are backfilled as `unverifiable` for release-owner and counsel
review; they must never be relabeled delivered.

## Delivery-confirmed implementation invariants

The migration, worker, and signature-authenticated webhook satisfy these
requirements:

1. Before dispatch, the database creates one durable attempt with an opaque
   attempt identifier and a stable per-attempt idempotency key. The send request
   carries that opaque identifier as a bounded
   [Resend email tag](https://resend.com/docs/dashboard/emails/tags); it contains
   no user or recipient value.
2. A successful send response binds the bounded provider email ID to that exact
   attempt and advances it only to `accepted`/`delivery_pending`. It keeps the
   restrictive Auth row and does not authorize terminal deletion.
3. A dedicated Resend webhook route verifies the Svix signature over the raw
   request body before parsing or mutation. `svix-id` is the provider event
   idempotency key. Invalid, stale, or unsigned events fail closed.
4. The webhook correlates by the opaque attempt tag and provider email ID, not
   by recipient address. It persists only bounded event metadata needed for
   replay and reduction; it never logs or copies the recipient, subject,
   headers, or provider body.
5. Webhook reduction is idempotent and safe for Resend's documented
   [at-least-once and out-of-order delivery](https://resend.com/docs/webhooks/introduction).
   A valid event can arrive before the send response commits. The event journal
   must retain that bounded event against the pre-created attempt and reduce it
   only after the same provider email ID is bound. Duplicate events cannot
   repeat state transitions, and an event for an old or unknown attempt cannot
   release the current job.
6. Only a valid `email.delivered` event for the current attempt and provider
   email ID may transactionally mark the attempt `delivered`, remove the
   restrictive Auth row, and make Auth deletion reachable.
   `email.delivery_delayed` remains
   pending. `email.bounced`, `email.failed`, and `email.suppressed` keep Auth
   fenced and enter bounded retry or operator review; none is completion.
7. Each retry uses the stable idempotency key for that attempt. Creating a new
   attempt after a terminal provider failure requires a new attempt identifier
   and cannot reuse an old delivery event as authority.
8. The rollout classifies active legacy jobs with Auth still present as
   `pending` and creates the restrictive guard. Historical legacy jobs whose
   Auth address was already erased without recoverable signed delivery evidence
   become `unverifiable`, not `delivered`.

Resend webhooks are a delivery signal from the configured provider, not proof
that the person read or completed Apple's manual-removal steps. The product and
legal copy must retain that distinction.

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
substage to `internal.account_deletion_jobs`. Migration
`20260807034322_deliver_legacy_apple_revocation_instructions.sql` adds a
delivery-confirmed substage without weakening the existing
`pending → storage_pending → auth_pending → completed` state machine.
The durable fields are `provider_revocation_status` and
`manual_revocation_delivery_status`; the latter can be `pending`, `accepted`,
`delivery_delayed`, `retry_required`, `delivered`, `unverifiable`, or
`not_required`. Active unresolved legacy jobs own one private
`internal.apple_manual_revocation_delivery_requirements` row whose restrictive
foreign key prevents Auth deletion until a signed, current-attempt
`email.delivered` event commits. PII-free attempt and event tables retain the
minimum correlation evidence needed for replay, retry, and finalization.

`request_account_deletion(user_id)` locks the Auth user and records exactly one
provider disposition:

| Condition at intake                            | Provider status   | Delivery status | Deletion receipt                              |
| ---------------------------------------------- | ----------------- | --------------- | --------------------------------------------- |
| Vault credential exists                        | `pending`         | `not_required`  | `manual_provider_revocation_required = false` |
| Apple identity exists but no credential exists | `manual_required` | `pending`       | `manual_provider_revocation_required = true`  |
| No Apple credential or identity exists         | `not_required`    | `not_required`  | `manual_provider_revocation_required = false` |

After delayed R2 verification advances the job to `auth_pending`, a job with a
Vault credential performs this order:

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

`manual_required` is a resolved provider disposition, not a claim that Apple
was revoked automatically. For that branch, source performs:

1. `prepare_account_deletion_manual_revocation_delivery(...)` creates or resumes
   one `prepared` attempt and transiently reads the confirmed Auth email under
   the active UUID claim. The address is never copied into durable delivery
   state.
2. The worker sends the fixed message with idempotency key
   `account-deletion-manual-apple/{attempt_token}` and the PII-free
   `purpose=apple_manual_revocation` and `attempt_id={attempt_token}` tags.
3. `record_account_deletion_manual_revocation_acceptance(...)` binds the
   provider email ID. Unless a matching delivered event won the race and is
   already journaled, it records `accepted` or `delivery_delayed`, clears the
   claim, and leaves Auth fenced.
4. `resend-account-deletion-webhook` verifies the Svix signature against the
   exact bounded raw body, parses only supported tagged events, and calls the
   event journal/reducer with `svix-id`, attempt token, provider email ID, event
   type, and provider timestamp.
5. Only a matching `email.delivered` event marks both attempt and job
   `delivered`, records reduction, and deletes the restrictive row in one
   transaction. The next reaper claim revalidates that attempt and event before
   Auth deletion.

Resend, network, response-decoding, missing-address, and acceptance-persistence
failures retain the prepared attempt and Auth for idempotent retry. An accepted
attempt without a delivery event waits. `email.delivery_delayed` waits;
`email.bounced`, `email.failed`, and `email.suppressed` mark the attempt
`retry_required`, keep the fence, and permit a new attempt with a new token.
Unknown, conflicting, duplicate, or superseded events cannot release Auth. The
supporting iOS notice remains customer-visible defense-in-depth; the server
control does not depend on the initiating binary or deletion response arriving.

Resend retains idempotency keys for 24 hours. Normal claim retries begin after
one minute and remain within that window; a dispatch or delivery still ambiguous
near the provider window is an operational alert, not authority to bypass the
Auth fence or edit delivery state. The fixed key and byte-stable message payload
must remain unchanged for one attempt during that window. A replacement attempt
after a terminal provider event needs a distinct, durable attempt key.

## Private data and authorization boundary

- `internal.apple_sign_in_revocation_credentials` maps one Auth user to one
  Vault secret UUID. It has RLS enabled, no Data API privileges, and an
  `ON DELETE RESTRICT` Auth foreign key.
- `internal.apple_sign_in_credential_registrations` contains only registration
  UUIDs, user UUIDs, and timestamps. It has RLS enabled and no direct API
  privileges.
- `internal.apple_manual_revocation_delivery_requirements` contains only the
  active Auth user and deletion-job UUIDs. It has RLS enabled, no Data API
  privileges, and an `ON DELETE RESTRICT` Auth foreign key. Source removes it
  only on a signed `email.delivered` event for the current attempt and provider
  email ID. The Ghost-profile merge manifest classifies this foreign key as
  `preserve`, so an active source-side deletion fence aborts a merge before any
  profile mutation instead of transferring deletion authority to the permanent
  destination identity.
- `internal.apple_manual_revocation_delivery_attempts` and
  `internal.apple_manual_revocation_delivery_events` contain no recipient,
  sender, subject, headers, or raw payload. They have RLS enabled and no direct
  Data API privileges, including for `service_role`.
- `apple_revocation_registration_exists`, `store_apple_revocation_credential`,
  `get_account_deletion_provider_token`, and
  `complete_account_deletion_provider_revocation` are service-role-only, in-body
  authorized, empty-search-path routines on the privileged-routine allowlist.
- `prepare_account_deletion_manual_revocation_delivery`,
  `record_account_deletion_manual_revocation_acceptance`, and
  `record_account_deletion_manual_revocation_event` are service-role-only,
  empty-search-path allowlist entries with in-body service-role checks. The
  first two are claim-fenced. The old recipient/completion RPCs remain
  service-role-only fail-closed rollout fences.
- The aggregate health boundary exposes only bounded, identity-free pending,
  accepted, delayed, retry-required, delivered, and unverifiable counts.
- The registration Edge handler derives the caller from its verified JWT. The
  Resend route has `verify_jwt = false` because the provider cannot present one;
  it authenticates the exact request bytes with the endpoint-specific Svix
  secret before parsing or mutation. Neither route lets a caller nominate
  another user or read stored credentials.

## Hosted configuration

The production GitHub `Production` environment must provide:

- `APPLE_SIGN_IN_TEAM_ID`
- `APPLE_SIGN_IN_KEY_ID`
- `APPLE_SIGN_IN_PRIVATE_KEY` — the PKCS#8 `.p8` key, with either raw newlines
  or escaped `\n`
- `RESEND_API_KEY`
- `ACCOUNT_DELETION_FROM_EMAIL` — a verified Naturebook sender identity, for
  example `Naturebook Privacy <privacy@naturebook.earth>`
- `RESEND_WEBHOOK_SIGNING_SECRET` — the endpoint-specific `whsec_` Svix signing
  secret; its Base64 key material must decode to 16–128 bytes

Use a Resend sending-only key restricted to the verified Naturebook domain. The
deployment workflow validates and synchronizes all six values without printing
them. Register exactly
`https://<project-ref>.supabase.co/functions/v1/resend-account-deletion-webhook`
in Resend, subscribe only to `email.delivered`, `email.delivery_delayed`,
`email.bounced`, `email.failed`, and `email.suppressed`, then copy that
endpoint's `whsec_` secret into the GitHub environment. The visible sender
domain, Resend return-path domain (for example `send.naturebook.earth`), and
exact From address must also be registered as Apple private-relay email sources
and tested with a real Hide My Email address; ordinary Resend domain
verification alone is insufficient. The native Apple client ID is pinned to
`app.merian.Merian`, matching the iOS bundle and
`services/supabase/config.toml`.

Key rotation is one release operation: provision a new Apple key, update the
three GitHub secrets, run the production deployment so Edge receives the new
values, complete exchange and revoke smokes, and only then retire the prior key
in Apple Developer. Do not commit the `.p8` file or reuse a generated Apple
client-secret JWT as `APPLE_SIGN_IN_PRIVATE_KEY`.

## Rollout and production exit gate

The source release unit contains:

- `register-apple-revocation-token`
- `safe-delete`
- `reconcile-account-deletions`
- `resend-account-deletion-webhook`
- migrations `20260806203700` and `20260807034322`
- iOS `SupabaseManager`, `MerianNetworkClient`, `DeleteAccountSheet`, and the
  app-root manual notice

The source unit is complete but not production-proven. The webhook's
`config.toml` entry uses `verify_jwt = false` because Resend cannot send a
Supabase JWT; exact-raw-body signature verification is the first handler
boundary.

The production workflow applies migrations before Edge bundles. Migration
`20260807034322` is compatible with the old worker by making its recipient RPC
fail before dispatch and its completion RPC reject acceptance as authority.
That migration-first interval therefore retains Auth. The workflow then
synchronizes the webhook secret and deploys the signed consumer and updated
worker. Do not intentionally exercise account deletion until all affected
bundles, the exact webhook subscription, and the post-deploy checks pass.

The repository migration file is the candidate's final forward migration. If
any environment received an earlier draft outside the authoritative GitHub
workflow, stop: compare hosted migration history and catalog state, then create
a new reconciliation migration. Never mutate an already-applied production
migration to force history to match.

Repository completion is not production completion. Promotion requires all of
the following on one immutable release SHA:

- exact Supabase CLI `2.109.1` fresh-catalog migration replay and the complete
  account-deletion pgTAP fixture;
- focused Apple exchange/revocation, registration-handler, deletion-worker,
  forward-migration, signed-webhook, and source-order tests;
- complete Supabase tooling, formatting, lint, and isolated function graphs;
- hosted Apple, Resend send, and webhook-signing secrets synchronized without
  printing values;
- a real non-production Apple sign-in showing one credential mapping and one
  Vault secret, followed by account deletion that records provider completion,
  removes both secret records, and only then removes Auth;
- a forced transient revoke failure proving Auth and the Vault secret remain
  retryable;
- a legacy Apple fixture proving the deletion response sets
  `manual_provider_revocation_required`, the supporting-client notice survives
  sign-out and relaunch, and an idempotent server email is accepted for the
  confirmed Auth address while Auth remains fenced;
- signed webhook fixtures proving duplicate and out-of-order events are
  idempotent, an event arriving before send-response persistence is not lost,
  unknown or superseded email IDs cannot release Auth,
  `email.delivery_delayed` remains pending, and `email.bounced`, `email.failed`,
  and `email.suppressed` retain Auth for retry or review;
- a signed `email.delivered` fixture proving delivery completion and restrictive
  row removal commit together before Auth deletion becomes reachable;
- a real Hide My Email staging fixture proving the configured sender reaches
  Apple's private relay and links only to Apple's official account-management
  and support pages;
- a physical-device credential-revocation notification smoke proving the app
  queries the active provider-specific Apple subject and clears the matching
  local session when Apple no longer reports `.authorized`, while exact-SHA
  source coverage retains the stale-identity callback fence; and
- a legacy deletion initiated from the oldest supported pre-field binary,
  proving a signed provider delivery event—not merely send acceptance—releases
  Auth even though that client ignores `manual_provider_revocation_required`
  and loses or discards the response.

The repository uses independent server-confirmed delivery rather than a
minimum-build deletion gate, so the initiating client version is no longer the
authority in source. Promotion remains blocked until the candidate records zero
unverifiable rows, signed
`email.delivered` evidence, a real Apple private-relay delivery, and the
older-binary smoke on one immutable candidate SHA. If that control cannot be
completed, a minimum-build/update gate or another counsel-approved guaranteed
path must ship instead. A nonzero unverifiable count means a legacy deletion
erased the only usable Auth address without recoverable delivery evidence; it
requires release-owner and counsel review and must never be relabeled delivered.

The account-deletion health monitor includes provider and delivery stalls inside
`auth_pending_count`; exposes identity-free pending, accepted, delayed,
retry-required, delivered, and unverifiable counts; and includes failures in
`failed_job_count`. Delayed and retry-required states warn; any unverifiable row
is critical. Operators repair Apple, Resend, sender-domain, or private-relay
configuration and let claim-fenced retries resume. They must never delete Auth
manually, edit provider/delivery status, copy a Vault token, or forge provider
acceptance or delivery.

## Verification map

- `_shared/appleSignIn_test.ts`: form encoding, identity-subject binding,
  terminal exchange errors, idempotent revoke success, and response-body
  redaction.
- `register-apple-revocation-token/handler_test.ts`: idempotent lookup,
  exchange-before-store ordering, lost-response receipt reconciliation, and
  compensating revocation.
- `safe-delete/manualRevocationEmail_test.ts`: idempotency, bounded transport,
  official instruction content, secret failure, and ambiguous dispatch retry.
  These tests deliberately treat send acceptance as non-authoritative.
- `_tests/safeDelete.test.ts`: provider-before-Auth ordering, delivery waiting,
  out-of-order delivered-event recovery, terminal retry, failure retention, and
  the legacy manual disposition.
- `resend-account-deletion-webhook/*_test.ts`: published Svix signature vector,
  exact-byte and timestamp rejection, bounded tagged protocol parsing,
  database-outcome propagation, retryable persistence failure, and PII-free
  correlation.
- `_tests/accountDeletionCoverage.test.ts`: source, iOS, workflow, config, and
  executable-fixture ordering.
- `_tests/accountDeletionMigrationContract.test.ts`: Vault, attempt/event
  schema, compatibility fences, Auth and terminal fences, ACLs, allowlist, and
  ordered delivery-confirmed state commits.
- `tests/account_deletion_security.sql`: live catalog intake, Vault read,
  provider completion, secret removal, old-worker rejection, prepared legacy
  attempts, restrictive Auth rejection, out-of-order delayed reduction,
  acceptance with Auth retained, terminal retry, replay/conflict handling,
  signed delivery completion, and terminal Auth completion.
- `SupabaseManagerTests`, `MerianNetworkClientTests`, and `AppDIContainerTests`:
  bounded registration retry, strict deletion receipt, subject-bound
  credential-state handling, and durable notice persistence.
