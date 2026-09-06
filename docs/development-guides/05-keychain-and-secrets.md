# Keychain and Secrets Management

This document explains what storage mechanism to use for persistent identity
tokens, app-facing client configuration, and true backend-only secrets in
Merian.

---

## Storage Decision Matrix

| Data type                                                | Storage                                                                                             | Reason                                                                                                                                                                                                                                                                |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supabase JWT (access token)                              | Supabase GoTrue SDK (internal Keychain)                                                             | Managed automatically by the SDK                                                                                                                                                                                                                                      |
| Supabase anonymous session                               | Supabase GoTrue SDK (internal Keychain)                                                             | Managed automatically by the SDK                                                                                                                                                                                                                                      |
| Extension cache                                          | App Group `group.app.merian.shared`                                                                 | Non-secret coordination data shared by the app, Messages extension, and Explore widget                                                                                                                                                                                |
| RevenueCat customer ID                                   | RevenueCat SDK (internal)                                                                           | Stable mode uses the server-issued purchase-principal ID; legacy mode uses the uppercase Supabase Auth UUID. Neither is persisted by the app as authority                                                                                                             |
| `SUPABASE_ANON_KEY`                                      | `Config.xcconfig` → `MerianEnvironment.swift`                                                       | Read-only build config, not secret                                                                                                                                                                                                                                    |
| `REVENUECAT_API_KEY`                                     | `Config.xcconfig` / `Config.local.xcconfig` → `MerianEnvironment.swift`                             | Read-only build config, not secret; production export should use an iOS `appl_` key                                                                                                                                                                                   |
| `POSTHOG_API_KEY`                                        | `Config.xcconfig` → `MerianEnvironment.swift`                                                       | Read-only build config, not secret                                                                                                                                                                                                                                    |
| `GEMINI_PAID_API_KEY`                                    | Supabase Edge secret; must be rotated from the owner-confirmed billing-enabled Google Cloud project | Never in iOS bundle; current billing/DPA evidence is unverified                                                                                                                                                                                                       |
| `AI_QUOTA_IP_HASH_SECRET`                                | Optional GitHub Production override synchronized to Supabase Edge                                   | Dedicated HMAC key for rotating network quota buckets; never in clients or logs                                                                                                                                                                                       |
| `DWCA_PSEUDONYM_HMAC_KEY_V1`                             | GitHub `Production` secret synchronized to Supabase Edge                                            | Base64 32-byte-or-longer HMAC key for versioned global-export user pseudonyms                                                                                                                                                                                         |
| `REVENUECAT_WEBHOOK_SECRET`                              | GitHub `Production` secret synchronized to Supabase Edge                                            | Random webhook Authorization credential; never use the public iOS key                                                                                                                                                                                                 |
| `REVENUECAT_WEBHOOK_SIGNING_SECRET`                      | GitHub `Production` secret synchronized to Supabase Edge                                            | RevenueCat raw-body HMAC key; never log, commit, or expose to clients                                                                                                                                                                                                 |
| `REVENUECAT_SECRET_API_KEY`                              | GitHub `Production` secret synchronized to Supabase Edge                                            | `sk_` server API credential for authoritative CustomerInfo reads; distinct from `REVENUECAT_API_KEY`                                                                                                                                                                  |
| `R2_READ_ACCESS_KEY_ID`                                  | GitHub `Production` secret synchronized to Supabase Edge                                            | Dedicated bucket-scoped read-only credential for direct-origin media verification                                                                                                                                                                                     |
| `R2_READ_SECRET_ACCESS_KEY`                              | GitHub `Production` secret synchronized to Supabase Edge                                            | Secret half of the dedicated verifier credential; never reuse upload/delete authority                                                                                                                                                                                 |
| `R2_EVENT_WEBHOOK_SECRET`                                | GitHub `Production` secret synchronized to Supabase Edge                                            | High-entropy shared secret for optional Cloudflare R2 event hints                                                                                                                                                                                                     |
| `SUPABASE_SERVER_API_KEY` / `SUPABASE_SECRET_KEYS`       | Supabase Edge or server-side web env only                                                           | Explicit or hosted JSON-dictionary current privileged key sources; never in iOS or browser-exposed config                                                                                                                                                             |
| `MERIAN_SUPABASE_SERVER_API_KEY`                         | Production-deploy-synchronized Supabase Edge secret                                                 | Non-reserved copy of the exact revealed active server key; same standard transport, never a custom request header                                                                                                                                                     |
| `SUPABASE_SECRET_KEY`                                    | Local/manual Deno server env only                                                                   | Singular current-key fallback; not supported by public web and not a replacement for the hosted plural dictionary                                                                                                                                                     |
| `SUPABASE_PUBLISHABLE_KEYS`                              | Supabase Edge server env                                                                            | Hosted JSON dictionary for user-scoped project clients; its keys are public but its shape is server runtime config                                                                                                                                                    |
| `SUPABASE_SERVICE_ROLE_KEY`                              | Supabase Edge secret, reviewed Vault reaper copy, or server-side web env only                       | Legacy service-role JWT migration fallback; never in iOS bundle or browser-exposed web config                                                                                                                                                                         |
| `Merian_HasAuthenticatedOAuth`                           | `KeychainManager` (`kSecClassGenericPassword`)                                                      | Security-sensitive auth flag, migrated from `UserDefaults` on first run                                                                                                                                                                                               |
| `Merian_GhostModeUserID_v1`                              | `KeychainManager` (`kSecClassGenericPassword`)                                                      | Retired presentation-only logout marker; upgraded clients delete it during startup and never use it to shape account UI                                                                                                                                               |
| `Merian_PendingGhostProfileMerge`                        | `GhostProfileMergeStore` via injected `KeychainManager` (`WhenUnlockedThisDeviceOnly`)              | Versioned queue of provider-bound account-upgrade proofs; removed only after success or terminal expiry/invalidity                                                                                                                                                    |
| `Merian_PendingSignOutPurchaseHandoff_v1`                | `PurchaseIdentityHandoffStore` via injected `KeychainManager` (`WhenUnlockedThisDeviceOnly`)        | One-use sign-out purchase proof; written and read back before local sign-out, then retained until destination receipt/server verification completes                                                                                                                   |
| `Merian_PurchasePrincipalInstallationCapability_v1`      | `KeychainManager` (`WhenUnlockedThisDeviceOnly`)                                                    | Random 256-bit device capability for resolving the same server-owned stable purchase principal across local Auth rotation; Postgres stores only SHA-256                                                                                                               |
| `Merian_PurchasePrincipalBindingIntentGeneration_v1`     | `KeychainManager` (`WhenUnlockedThisDeviceOnly`)                                                    | Positive monotonic ordinary-resolver intent; advanced/read-verified before network I/O so an older Auth request cannot overwrite a newer server binding                                                                                                               |
| `Merian_PurchasePrincipalStableActivationFingerprint_v1` | `KeychainManager` (`WhenUnlockedThisDeviceOnly`)                                                    | Monotonic lowercase SHA-256 fingerprint of the local capability after first stable activation; prevents later legacy or missing-route identity fallback                                                                                                               |
| `Merian_PendingPurchasePrincipalAuthRotation_v1`         | `PurchaseIdentityHandoffStore` via injected `KeychainManager` (`WhenUnlockedThisDeviceOnly`)        | Protocol-3 write-ahead journal containing a raw one-use rotation secret and exact continuity metadata; paid mutations fail closed until verified claim or source cancellation removes it                                                                              |
| `Merian_AccountDeletionRecoveryCapability_v1`            | `KeychainManager` (`WhenUnlockedThisDeviceOnly`)                                                    | Protocol-v2 JSON envelope with distinct random 256-bit recovery/acknowledgement authorities; also decodes legacy raw 256-bit data. Edge stores only domain-separated hashes; iOS verifies envelope creation and removal around its identity-free durable phase marker |
| `Merian_AnalyticsRevocationIntent_v1`                    | `KeychainManager` (`AfterFirstUnlockThisDeviceOnly`)                                                | Versioned write-ahead journal of exact analytics revocation events; keeps capture off until the atomic ledger write is verified                                                                                                                                       |
| Consent ledger                                           | File-protected Application Support JSON                                                             | Atomically replaced and byte-verified append-only adult/Terms/Gemini/PostHog evidence; migrates the legacy `UserDefaults` copy                                                                                                                                        |
| Device IDFV (`Merian_Device_IDFV`)                       | `DeviceIdentityManager` (`kSecClassGenericPassword`)                                                | Persisted across reinstalls within the same vendor group                                                                                                                                                                                                              |
| `hasCompletedOnboarding`                                 | `UserDefaults`                                                                                      | Non-sensitive preference                                                                                                                                                                                                                                              |
| `isAchievementNotificationsEnabled`                      | `UserDefaults`                                                                                      | Non-sensitive preference                                                                                                                                                                                                                                              |
| `Merian_UnlockedSpeciesCount`                            | `UserDefaults`                                                                                      | Non-sensitive, account-derived gamification counter; removed during accepted account deletion                                                                                                                                                                         |
| `Merian_HasFireflyBadge`                                 | `UserDefaults`                                                                                      | Non-sensitive, account-derived local badge state; removed during accepted account deletion                                                                                                                                                                            |
| `Merian_UnlockedAchievements`                            | `UserDefaults`                                                                                      | Non-sensitive, account-derived gamification set; removed during accepted account deletion                                                                                                                                                                             |
| `firstFieldTripAchievementProgress.v1.{accountId}`       | `UserDefaults`                                                                                      | Non-sensitive account-scoped completion date and typed Field trip destination cache; removed during accepted account deletion                                                                                                                                         |
| User geoprivacy preference                               | Supabase `users` table                                                                              | Server-authoritative preference                                                                                                                                                                                                                                       |
| Local free-scan meter                                    | `UserDefaults`                                                                                      | Advisory UX only; authoritative entitlement/quota is in Supabase                                                                                                                                                                                                      |

---

## Deployment Environment Ownership

GitHub `Production`, Supabase Edge, the public-web Vercel project, and the
internal-admin Vercel project are separate trust boundaries. Never clone one
environment's complete variable set into another. Add a value only when the
target application's documented environment contract names it.

The backend deployment secrets commonly shown together in GitHub have these
destinations:

| GitHub `Production` variable        | Deployment/runtime purpose                                                                                                                    | Copy to Vercel? |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `DWCA_PSEUDONYM_HMAC_KEY_V1`        | The deploy workflow synchronizes it to Supabase Edge for global DwC-A export pseudonyms                                                       | No              |
| `REVENUECAT_SECRET_API_KEY`         | The deploy workflow synchronizes it to Supabase Edge for authoritative subscriber reads                                                       | No              |
| `REVENUECAT_WEBHOOK_SECRET`         | The deploy workflow synchronizes it to Supabase Edge for webhook Authorization                                                                | No              |
| `REVENUECAT_WEBHOOK_SIGNING_SECRET` | The deploy workflow synchronizes it to Supabase Edge for raw-body signature verification                                                      | No              |
| `R2_READ_ACCESS_KEY_ID`             | The deploy workflow synchronizes it to Supabase Edge for signed, read-only R2-origin verification                                             | No              |
| `R2_READ_SECRET_ACCESS_KEY`         | The deploy workflow synchronizes it to Supabase Edge as the verifier credential secret                                                        | No              |
| `R2_EVENT_WEBHOOK_SECRET`           | The deploy workflow synchronizes it to Supabase Edge when optional R2 event acceleration is enabled                                           | No              |
| `SUPABASE_ACCESS_TOKEN`             | Authenticates deployment tooling and lets independent health monitors resolve a production server API key through the Supabase Management API | No              |
| `SUPABASE_DB_URL`                   | Preferred direct PostgreSQL connection used by migration and catalog-audit steps                                                              | No              |
| `SUPABASE_DB_PASSWORD`              | Used only by the alternative GitHub database connection path                                                                                  | No              |

The public `apps/web` Vercel project has its own allowlist in
[`apps/web/.env.example`](../../apps/web/.env.example). In particular,
`SUPABASE_URL` is the HTTPS project API endpoint used by server code; it is not
`SUPABASE_DB_URL`, which is a privileged PostgreSQL connection string. The
public-web project receives a current opaque key as the sensitive, server-side
`SUPABASE_SERVER_API_KEY` for its reviewed server routes. A legacy
`SUPABASE_SERVICE_ROLE_KEY` is supported only during migration. Neither may
appear in a `NEXT_PUBLIC_` variable or in the separately deployed admin project.
The web resolver rejects publishable keys, anon/user JWTs, malformed JWTs, and
malformed platform dictionaries before constructing a client.

The `apps/admin` Vercel project receives only `NEXT_PUBLIC_SUPABASE_URL`,
`NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_ADMIN_ORIGIN`. It must not
receive a service-role key, a direct database credential, or any GitHub
deployment/Edge provider secret. `apps/admin/lib/admin-foundation.test.ts`
parses the complete production TypeScript graph, rejects privileged credential
names plus computed/whole-object `process.env` access, and allows only these
public keys. The Admin Quality workflow supplies non-secret CI placeholders;
real production values exist only in the separate admin Vercel project.

Removing or changing a Vercel environment variable takes effect only in a new
deployment. Preview deployments that need functional backend access must use
separate staging credentials; do not reuse production server secrets merely to
make previews work.

---

## API Key Rules

Merian uses two different categories of keys/configuration:

- **Public client config**: values the iOS app needs at runtime. These are not
  true secrets because they ship in the client bundle and can be extracted by a
  motivated user.
- **Backend-only secrets**: values that would grant admin, server, provider, or
  signing authority if exposed. These must never ship in the app.

**Absolute rule: no true backend secret may appear in any `.swift` file,
`Info.plist`, iOS `.xcconfig` file, client component, or `NEXT_PUBLIC_` web
environment variable.**

- `GEMINI_PAID_API_KEY` — must come from the approved billing-enabled Google
  Cloud project and live exclusively in Supabase Edge secrets. The variable name
  is not evidence: billing and DPA status remain unverified until the Cloud
  owner archives confirmation, rotates the key, synchronizes it, smoke-tests it,
  and revokes the prior key. The iOS binary has no knowledge of this key. All
  Gemini calls go through Supabase Edge inference endpoints, primarily
  `/identify-multimodal`; legacy `/identify`, `/identify-describe`, and
  `/audio-spec` remain server-side compatibility routes only. The same key
  powers `/share-scan-to-explore`'s dedicated `gemini-2.5-flash` public-audio
  classifier; transcripts and non-speech descriptions are never stored or
  logged. A matching service-only moderation attestation can approve unchanged
  bytes without calling Gemini; a cache miss still fails closed when this key is
  unavailable.
- `AI_QUOTA_IP_HASH_SECRET` — optional dedicated override of at least 32
  high-entropy characters. When absent, Edge code uses a built-in server-only
  Supabase secret/service-role key. In both cases it HMACs the proxy-observed
  address with a quota-specific domain and UTC-day prefix; neither the raw
  address nor key enters the database, client, analytics, or logs. A weak
  explicitly configured override fails paid-model work closed.
- `DWCA_PSEUDONYM_HMAC_KEY_V1` — required dedicated key for global Darwin Core
  export attribution pseudonyms. It is Base64 encoded and must decode to at
  least 32 random bytes. Each job pins a numeric version; rotation adds a new
  secret and advances the database default only after code can read both. Never
  replace bytes under an existing version or derive this value from
  `SUPABASE_JWT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, or a provider key.
- `REVENUECAT_WEBHOOK_SECRET` — at least 32 random characters configured as the
  secret portion of RevenueCat's `Authorization: Bearer <value>` header and as a
  GitHub `Production` environment secret. The deployment workflow synchronizes
  it to Supabase; the Edge Function compares the complete header in constant
  time.
- `REVENUECAT_WEBHOOK_SIGNING_SECRET` — the secret shown by RevenueCat when HMAC
  signing is enabled. It authenticates the exact raw webhook body with a bounded
  timestamp replay window. Rotation invalidates the old RevenueCat signing
  secret immediately, so rotation is a supervised dashboard + GitHub deploy
  operation.
- `REVENUECAT_SECRET_API_KEY` — a RevenueCat secret server API key beginning
  with `sk_`, used only to read authoritative CustomerInfo after a verified
  webhook. It is not the app-facing `REVENUECAT_API_KEY`; never place a server
  key in an `.xcconfig`, app bundle, Test Store configuration, or support log.
- `R2_READ_ACCESS_KEY_ID` / `R2_READ_SECRET_ACCESS_KEY` — a required,
  bucket-scoped read-only S3 credential used only by
  `reconcile-explore-media-health` for signed direct-origin `HEAD` requests. The
  verifier fails closed when either value is absent and never falls back to
  upload, write, or delete credentials. Rotate the pair together and keep it out
  of every client and Vercel environment.
- `R2_EVENT_WEBHOOK_SECRET` — an independent random value of at least 32
  characters used to authenticate optional Cloudflare R2 event notifications at
  `ingest-r2-media-events`. Events only expedite a scheduled origin check; they
  never directly mark media missing, hide a post, or restore it.
- Supabase server API keys — current `SUPABASE_SECRET_KEYS` /
  `SUPABASE_SERVER_API_KEY` values, the deploy-synchronized non-reserved
  `MERIAN_SUPABASE_SERVER_API_KEY` Edge fallback, the singular
  `SUPABASE_SECRET_KEY` local/manual Deno fallback, and the migration-only
  `SUPABASE_SERVICE_ROLE_KEY` fallback live in Supabase Edge secrets, reviewed
  Vault cron values, or approved server-side environments only. The public web
  supports the explicit, plural, and legacy sources but deliberately does not
  support the synchronized Edge fallback or singular Deno fallback. Never put
  any server key in the iOS app, `Config.xcconfig`, or a `NEXT_PUBLIC_`
  variable.

  Hosted `SUPABASE_SECRET_KEYS` and `SUPABASE_PUBLISHABLE_KEYS` values are JSON
  objects such as `{"default":"<complete key>"}`. A raw key, JSON string, array,
  empty/truncated entry, mixed key class, or manually duplicated platform value
  is malformed. Do not infer an alternate format from a credential's observed
  length. The singular `SUPABASE_SECRET_KEY` is a separate local/manual source,
  not a permissible encoding for the plural variable.

  The production deploy retrieves the selected active key through the
  reveal-explicit Management API request, masks it, and refreshes
  `MERIAN_SUPABASE_SERVER_API_KEY` before deploying Functions. This copy is a
  controlled workaround for runtime provisioning lag; it does not authorize a
  custom header and must not be manually renamed to a reserved `SUPABASE_*`
  secret. The workflow verifies the stored secret's SHA-256 digest against the
  exact selected key before Function rollout without printing the key or digest.
  Complete a deploy during key overlap before revoking the old key.

  Current explicit keys must be platform-shaped: `sb_secret_`, followed by a
  URL-safe opaque suffix of at least 20 characters. A legacy fallback must be an
  HS256 JWT whose role is exactly `service_role` and whose base64url signature
  is complete. Placing a publishable, anon, user, truncated placeholder, or
  malformed value in an individual explicit, synchronized, singular, or legacy
  source never makes that value a candidate. Inbound sources are classified
  independently: a malformed source cannot veto an exact key from another valid
  source, while an unmatched request still fails as invalid configuration.
  Outbound priority remains strict, so a malformed configured scalar encountered
  at its priority point fails instead of silently falling through. Internal
  cron/webhook workers such as `refresh-species-content`,
  `refresh-species-model-content`, `refresh-merian-reference-images`, and
  `auto-purge-nonbio` may receive one only through the shared key-format-aware
  `pg_net`/Vault header policy. An opaque key uses the standard `apikey` header
  only; a legacy JWT uses `apikey` plus Bearer Authorization. No custom server
  credential header is recognized. The Next.js web app may read its supported
  sources only through `apps/web/lib/supabaseAdmin.ts`, which imports
  `server-only`. Public projection readers use `apps/web/lib/supabasePublic.ts`
  and cannot acquire service-role authority. Keep these modules separate and
  never re-export an admin-capable default client.

  Credential diagnostics must not expose or derive a prefix, suffix, length,
  partial value, accepted candidate, or failed internal response body. Report
  only stable reason codes, endpoint, and HTTP status. Capability probes,
  successful empty reads, and RLS-filtered responses are never authorization
  evidence.

  API-key transport and database authorization are separate boundaries. A legacy
  service-role JWT may populate `auth.role()` when used through its supported
  Bearer path. A modern opaque `sb_secret_...` value belongs in `apikey`; the
  gateway/PostgREST maps it to the `service_role` database role, which
  privileged routines verify through PostgREST's protected standard `role`
  setting. SQL must never inspect or compare the secret itself, and no
  server-key format belongs in iOS. See Supabase's
  [API-key guide](https://supabase.com/docs/guides/getting-started/api-keys) and
  PostgREST's
  [transaction-scoped role settings](https://postgrest.org/en/stable/references/transactions.html).

  Account deletion has two independently resolved server-key paths. The database
  reaper reads its value from Vault; the GitHub health monitor resolves its
  value through the Management API. Both use the same transport rule after
  migration `20260727013416_future_proof_server_key_boundaries.sql`: opaque
  `sb_secret_...` values belong only in `apikey`, while legacy service-role JWTs
  use both `apikey` and Bearer Authorization. A present but blank Vault value
  wins over the legacy app-setting fallback and makes configuration health
  critical. Update or delete a blank Vault row; do not expect fallback. Rotate a
  Vault key and the corresponding project key together. Supabase's current key
  formats and legacy-key transition are documented in
  [Understanding API keys](https://supabase.com/docs/guides/getting-started/api-keys).
  The complete affected-surface checklist and production exit criteria are in
  the
  [July 2026 server-key incident report](../incidents/2026-07-server-key-authorization-mismatch.md).
  The current operational source of truth is the
  [server credential and database release safety contract](../backend-and-data/13-server-credentials-and-database-release-safety.md).
- `SUPABASE_ANON_KEY` — this historical build-setting name is public client
  config, not a secret. Configure it with the current `sb_publishable_…` value;
  a legacy anon JWT is supported only during overlap. It is injected via
  `Config.xcconfig` into `MerianEnvironment.swift`.
- `SUPABASE_URL`, `REVENUECAT_API_KEY`, `POSTHOG_API_KEY`, `GIDClientID`, and
  `REVERSED_CLIENT_ID` are also public client config values used by the app at
  runtime. `Config.xcconfig` may carry development defaults, while
  `Config.local.xcconfig` can override local app-facing values without being
  committed. Local development and unsigned validation archives may use a
  RevenueCat Test Store key. The sole distributable path, Xcode Organizer,
  requires the Release configuration to resolve to a production iOS SDK key
  beginning with `appl_`; Test Store and placeholder values are blocked. Apple
  account and distribution-signing credentials stay in Xcode and Keychain, not
  in an app-facing `.xcconfig` file or GitHub Actions.

That means committed client config is acceptable for values in the second group,
while the first group must stay server-side only.

`MerianEnvironment.swift` reads all build-config keys from
`Bundle.main.infoDictionary` at runtime and returns typed configuration
diagnostics if a key is absent. Missing optional analytics/payment keys skip SDK
setup. Missing or invalid Supabase config blocks outbound endpoint construction
with `MerianError.invalidURL` while still allowing the app to boot into recovery
UI.

```swift
// MerianEnvironment.swift — read from xcconfig, not hardcoded
enum MerianEnvironment {
    static let configuration = load()
    static var configurationIssues: [ConfigurationIssue] { configuration.issues }
    static var isSupabaseConfigured: Bool { configuration.hasSupabaseConfiguration }
}
```

### Debug simulator production guard

The tracked client configuration currently resolves to the production Supabase
project. On a Debug simulator, `MerianEnvironment` therefore emits:

```text
Environment configuration degraded: Debug simulator is using production Supabase...
```

This is an intentional warning, not a block. Supabase Auth and normal network
reads/writes continue, and a fresh install or cleared session can create a real
anonymous production user. Use a local or staging `SUPABASE_URL` plus matching
client key in ignored `Config.local.xcconfig` for routine simulator work.

For a deliberate production smoke test, preserve the existing session when
possible and add this environment variable to the Xcode Run action for that run:

```text
MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR=1
```

The override suppresses only the diagnostic. It does not change the endpoint,
permissions, RLS, or cleanup obligations. Remove it after the smoke test and
never use a service-role/secret key as the matching client key.

---

## KeychainManager

`KeychainManager.shared` is a thin wrapper over `Security.framework` for storing
`Bool`, UTF-8 `String`, and raw `Data` values as `kSecClassGenericPassword`
items.

```swift
// Default accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
// Sensitive foreground-only proof:
//   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
// Item class: kSecClassGenericPassword
// Key: kSecAttrAccount (the string key passed to set/read/removeObject)
```

On first instantiation it migrates the legacy `UserDefaults` flag
`Merian_HasAuthenticatedOAuth` to Keychain and removes it from `UserDefaults`.
This migration is one-shot.

Currently stored keys:

| Key                                                      | Type                                               | Accessibility                    | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------------------------- | -------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Merian_HasAuthenticatedOAuth`                           | `Bool`                                             | `AfterFirstUnlockThisDeviceOnly` | Distinguishes OAuth-authenticated users from anonymous Ghost sessions; only a stable missing/invalid-session response plus failed refresh may use it when deciding whether authoritative Ghost regeneration is allowed                                                                                                                                                                                                         |
| `Merian_PendingGhostProfileMerge`                        | JSON `Data`                                        | `WhenUnlockedThisDeviceOnly`     | Versioned queue containing source UUID, provider/subject, handoff UUID, 256-bit bearer secret, and server expiry for interrupted existing-account upgrades                                                                                                                                                                                                                                                                     |
| `Merian_PendingSignOutPurchaseHandoff_v1`                | JSON `Data`                                        | `WhenUnlockedThisDeviceOnly`     | Legacy-mode one-use proof that fences receipt transfer from a linked UUID customer to the exact fresh anonymous UUID customer until server verification completes                                                                                                                                                                                                                                                              |
| `Merian_PurchasePrincipalInstallationCapability_v1`      | 32-byte `Data`                                     | `WhenUnlockedThisDeviceOnly`     | Stable-mode possession capability. The app verifies each write, sends its base64url form only to the authenticated resolver, and never persists the returned provider ID as authority                                                                                                                                                                                                                                          |
| `Merian_PurchasePrincipalBindingIntentGeneration_v1`     | canonical positive decimal `Data`                  | `WhenUnlockedThisDeviceOnly`     | Monotonic Auth-binding intent paired with the capability. It is advanced/read-verified before each ordinary resolver request and must already exist after stable activation; missing or malformed state fails closed                                                                                                                                                                                                           |
| `Merian_PurchasePrincipalStableActivationFingerprint_v1` | lowercase SHA-256 `Data`                           | `WhenUnlockedThisDeviceOnly`     | Monotonic evidence that the exact local capability has activated stable mode; it is not a provider-ID cache and is never sent as identity authority                                                                                                                                                                                                                                                                            |
| `Merian_PendingPurchasePrincipalAuthRotation_v1`         | JSON `Data`                                        | `WhenUnlockedThisDeviceOnly`     | Protocol-3 stable-mode journal containing `preparing`/`prepared` state, rotation UUID, raw 256-bit rotation secret, source Auth UUID, expected principal/provider IDs, binding generation, capability fingerprint, local start time, and the server expiry once prepared. The draft is written/read-verified before the source-authenticated prepare call; the prepared receipt is written/read-verified before local sign-out |
| `Merian_AccountDeletionRecoveryCapability_v1`            | Protocol-v2 JSON `Data`; legacy raw 32-byte `Data` | `WhenUnlockedThisDeviceOnly`     | One deletion-only envelope containing distinct recovery and acknowledgement authorities, generated and read-after-write verified before network suspension. Edge stores only domain-separated SHA-256 hashes. Accepted deletion retires it only after verified local cleanup and acknowledgement; definitive uncommitted v2 intent may retire it without erasing local data.                                                   |
| `Merian_AnalyticsRevocationIntent_v1`                    | JSON `Data`                                        | `AfterFirstUnlockThisDeviceOnly` | Versioned journal containing exact immutable PostHog revocation events that have not yet crossed the verified primary-ledger boundary                                                                                                                                                                                                                                                                                          |

`Core/Security/PurchaseIdentity/Stores/` owns all five purchase-identity rows
through the narrow `PurchasePrincipalSecureStore` boundary.
`PurchasePrincipalCapabilityStore` owns capability creation and retrieval;
`PurchasePrincipalSecureStateStore` owns stable activation and binding-intent
generation; and `PurchaseIdentityHandoffStore` is the sole codec and
persistence-policy owner for the two purchase-continuity journals. Their live
composition receives `KeychainManager` from `SupabaseManager`; no store resolves
a singleton. They validate before writes and after reads, select the exact keys
and accessibility, and verify written bytes. Invalid activation fingerprints are
rejected unless they have the exact 64-character lowercase hexadecimal SHA-256
shape, before the secure store is called. The journal store additionally
preserves explicit camel-case JSON fields, accepts bounded fractional PostgreSQL
and whole-second RFC 3339 timestamps through cached formatters, and performs
verified removal. Auth/server/provider phase order remains in Core Network Auth
and `SupabaseManager`.

`Core/Security/GhostProfileMerge/Stores/GhostProfileMergeStore.swift` is the
sole codec and persistence-policy owner for the ghost-profile merge queue. Its
live dependencies receive `KeychainManager` from `SupabaseManager`; the store
itself resolves no singleton. It preserves explicit camel-case JSON field names,
validates evidence before writes and after reads, selects the established key
and device-only accessibility, verifies written bytes, and performs verified
removal. Validation covers UUIDs, the provider allowlist, the provider subject's
exact UTF-16/control-character bounds, the base64url capability shape, and both
accepted server timestamp formats. It does not use the device clock to classify
expiry.

The merge queue is persisted and read back successfully before the app switches
away from the anonymous session. `GhostProfileMergePolicy` makes a newer handoff
replace only another handoff for the same ghost UUID; unrelated pending upgrades
remain queued. The store accepts the former single-record shape and rewrites it
to version 1 without discarding the readable original if that Keychain write
fails.

Completion removes one queue item only after server success or the terminal
codes `handoff_expired` and `handoff_invalid`. Network errors,
`auth_cleanup_pending`, `merge_temporarily_unavailable`, and `handoff_forbidden`
remain retryable. Sign-out cancels the in-flight task but does not erase proofs;
a task-generation token prevents an older cancelled task from clearing the
handle for a newer session. `GhostProfileMergeWorkflow` checks cancellation
before the first server effect and between server completion, purchase
synchronization, local-evidence synchronization, and final proof removal.

`ThisDeviceOnly` items do not migrate through backups or device transfer. Never
copy the merge proof into `UserDefaults`, logs, analytics, crash metadata, an
App Group, iCloud Keychain, or a request URL.

### Consent ledger durability

`DurableConsentLedgerStore` keeps the complete consent ledger at
`Application Support/Naturebook/Consent/ledger-v1.json`. Every save uses an
atomic replacement, applies complete-until-first-authentication file protection,
reads the result back, and compares the exact bytes. A one-time migration writes
and verifies this file before removing `UserDefaultsKeys.legalConsentLedger`, so
an older stale grant cannot become the fallback authority.

Analytics withdrawal uses two independent boundaries. `ConsentManager` closes
capture in memory first and requests one repository transition.
`ConsentLedgerRepository` writes the exact revocation event to
`Merian_AnalyticsRevocationIntent_v1` before replacing the main ledger through
`ConsentLedgerStore`. The Keychain payload is a journal, not a single slot:
simultaneous offline actions for different accounts remain distinct. A failed
main write leaves the journal in place across restart; repository recovery
appends the same IDs, text, versions, and timestamps to the ledger and only then
verifies journal removal. If both writes fail, the current process remains off
and the Settings surface reports that the withdrawal still needs durable
storage. The repository does not publish or notify observers about a candidate
ledger until the store has verified its durable bytes.

---

## Device Identity (`DeviceIdentityManager`)

`DeviceIdentityManager.shared` is a `@MainActor @Observable` singleton.
`deviceId` is computed once at init via `getOrGeneratePersistentIDFV()`:

1. Attempts to load the IDFV from Keychain under the key `Merian_Device_IDFV`.
2. If not found and the Keychain is accessible, reads
   `UIDevice.current.identifierForVendor?.uuidString`, saves it to Keychain, and
   returns it.
3. If the Keychain is locked in the background (`errSecInteractionNotAllowed`),
   falls back to reading `identifierForVendor` directly from the OS without
   persisting, to avoid overwriting an existing identity.

The Keychain entry uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
which means the IDFV survives app reinstall as long as another app from the same
vendor group is installed. This is intentional: it preserves anonymous user
identity across reinstalls for Ghost Session continuity.

The IDFV seeds the anonymous session path (`signInAnonymously`) but is not a
billing identifier. In stable mode, a separate random installation capability
resolves one server-owned purchase principal. The server response—not the IDFV,
capability, Auth UUID, or a cached provider ID—is the authority for the current
RevenueCat link. The same readable capability resolves the same principal after
ordinary local Auth rotation. The app sends no account email, username, display
name, avatar, or Auth UUID attribute to that shared provider customer. PostHog
continues to follow its own analytics identity and consent contract.

Older builds could store the linked Supabase UUID in `Merian_GhostModeUserID_v1`
to mask an authenticated session as anonymous in the UI. That presentation-only
flow is retired. Supporting builds delete the marker during `SupabaseManager`
startup and never consult it for account presentation. In stable mode,
user-facing **Sign out** uses `Merian_PendingPurchasePrincipalAuthRotation_v1`
as a two-write journal around a server reservation:

1. While the exact linked source session is still live, iOS generates a rotation
   UUID and 256-bit secret, persists and read-verifies a `preparing` journal,
   and sends `prepare_signout_rotation`. Postgres receives only the secret and
   installation-capability hashes.
2. iOS validates the returned principal, provider ID, binding generation, and
   expiry against the journal, persists and read-verifies the `prepared` form,
   and only then closes the source session.
3. One newly created anonymous session submits the same rotation ID and secret
   to `claim_signout_rotation`. This claim, not ordinary purchase-principal
   resolution, authorizes the destination binding.
4. iOS validates the atomic claim receipt, serially links the unchanged
   RevenueCat customer, requires `EntitlementManager.beginSession(...)` to
   return `true`, and revalidates task cancellation, the exact anonymous
   manager-published user, nonexpired SDK session, captured Auth generation, and
   transition context before verifying journal removal last. No stable sign-out
   step calls RevenueCat receipt sync or a provider customer-transfer API.

If local sign-out fails or the exact source is restored first, that source sends
`cancel_signout_rotation` with the same journal proof and clears the journal
only after the server confirms `cancelled` or `expired`. Cancellation may create
a tombstone when the `preparing` request reached neither the server nor the
device response boundary. A different permanent session, an old anonymous
session, an expired claim, a malformed journal, or a temporarily unreadable
Keychain keeps purchase, restore, redeem, provider linking, and ordinary
principal resolution closed. A readable pre-protocol-3 client-only value at the
same key can be retired only by its exact restored source and can never
authorize a destination.

The journal is bearer-sensitive because it contains the raw rotation secret.
Never copy it or any field from it into `UserDefaults`, logs, analytics, crash
metadata, an App Group, iCloud Keychain, or a request URL. While it exists, the
resolver requires the exact lowercase SHA-256 fingerprint of the local 32-byte
installation capability and disables capability creation. An absent or replaced
capability is rejected before any server binding or RevenueCat identity call, so
partial secure-storage loss cannot strand access on a newly created principal.

The first successful stable response separately writes and verifies
`Merian_PurchasePrincipalStableActivationFingerprint_v1`. That activation
fingerprint—not the pending rotation journal—is retained across later sign-out,
account deletion, and rollout rollback. Once present, neither an endpoint `404`
nor a later `mode: legacy` response is accepted for that capability. The journal
does persist the expected provider ID as a response-continuity assertion, but it
never selects that ID or makes it local identity authority.

Account deletion uses a separate atomic protocol-v2 envelope at the
compatibility-named `Merian_AccountDeletionRecoveryCapability_v1` key. iOS first
records `capability_preparation_pending`, then generates two distinct 256-bit
values, JSON-encodes them as recovery and acknowledgement capabilities, persists
the envelope once, and read-after-write verifies the exact bytes before the
first network suspension. Its intended path registers both values through the
non-destructive prepare operation, records `capability_prepared_pending`, and
only then records `capability_intake_pending` before destructive commit. Prepare
sends both values; commit and public recovery send only the recovery value;
post-cleanup acknowledgement sends only the acknowledgement value. Neither is
interchangeable: Edge applies distinct protocol-v2 recovery and acknowledgement
hash domains, also separating both from the legacy v1 hash namespace. Neither is
placed in `UserDefaults`, URLs, logs, analytics, crash metadata, App Groups,
backups, or server plaintext storage. Once the server receipt is known, the
local state advances through cleanup and capability-retirement phases. Keychain
deletion is read-after-delete verified before the durable marker is removed. For
legacy v1, unknown proofs and ambiguous transport outcomes remain fail-closed; a
matched-expired proof is the only non-receipt result that authorizes
conservative local erasure. For v2, `not_committed` or an unknown proof
authorizes proof-only retirement because destructive commit cannot run without
the server preparation. If another device committed first, the database converts
every preparation into a receipt and recovery returns pending/completed instead.
The device acknowledges with the distinct second proof before retiring the
envelope; expiry blocks inspection, not post-cleanup acknowledgement. When
authenticated intake is definitively rejected with
`409 purchase_continuity_pending`, iOS first persists
`capability_rejection_retirement_pending`, then read-after-delete verifies the
unused proof is gone, and removes the marker last. Recovery from that phase is
non-destructive: it cannot sign out or purge local data. This capability cannot
select, restore, or authenticate an account and is never reused for sign-in or
purchase identity.

The deletion path checks task cancellation before its first recovery marker. The
legacy branch checks again after its intake marker; the v2 branch checks before
preparation, after its non-destructive response and before the prepared/intake
marker pair, and after that pair before destructive commit. It never rolls back
a durable marker or capability because of cancellation. Recovery owns evidence
already written, and the cancelled task starts no later destructive effect.

The checked-in four-field v2 prepare response is decoded by a dedicated
non-destructive native receipt. The handler and native tests consume the same
identity-free fixture, while accepted deletion and recovery receipts keep their
required provider-disposition field. The
[Core Network preparation contract and integration checklist](../../apps/ios/Merian/Core/Network/README.md#preparation-receipt-contract)
separate that source-level evidence from authorized real-session testing.

In legacy mode, the same UX uses the one-use proof in
`Merian_PendingSignOutPurchaseHandoff_v1`. The server stores only its SHA-256
secret hash; the raw verifier remains on the device and in authenticated handoff
requests. The client removes the proof only after the fresh anonymous Supabase
UUID is the exact linked RevenueCat custom ID, StoreKit receipt sync, server
destination verification/projection, and a current entitlement read. Each
suspended phase and the removal boundary revalidate task cancellation, the exact
anonymous manager-published user, nonexpired SDK session, captured Auth
generation, and transition context. A retry without a transition owner becomes
stale when another Auth transition opens. A restored source may cancel only an
unbound proof.

The installation capability is `ThisDeviceOnly`: restoring a backup, moving to
another device, or a true Keychain loss must not let sign-in claim the previous
principal. The new installation resolves a new principal and uses explicit App
Store restore for StoreKit ownership. Capability revocation is terminal and
requires a reviewed recovery flow; the client must never silently generate a
replacement to bypass it.

---

## Shared Extension Storage

Merian uses `group.app.merian.shared` for non-secret extension coordination:

- Explore widget snapshots
- Messages scan share cache (`message-scan-share-cache.json`,
  `MessageScanThumbnails/`, `MessageScanAttachments/`)

Do not put provider secrets, service-role keys, raw private notes dumps, or
SwiftData stores in the App Group. The App Group is for small, explicit handoff
artifacts whose schema is owned by shared Swift structs.

---

## Secrets That Must Never Enter the iOS Codebase

If an AI agent generates code that includes any of the following, it must be
rejected immediately:

- Any hardcoded string that looks like a Google API key (`AIza...`)
- Any hardcoded Supabase service role key (`eyJ...` with service role claims)
- Any raw database connection string
- Any SMTP or push certificate credentials

The correct pattern for all of these is an Edge Function environment variable
accessed server-side only.
