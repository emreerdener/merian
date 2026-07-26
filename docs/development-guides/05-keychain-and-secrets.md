# Keychain and Secrets Management

This document explains what storage mechanism to use for persistent identity
tokens, app-facing client configuration, and true backend-only secrets in
Merian.

---

## Storage Decision Matrix

| Data type                           | Storage                                              | Reason                                                                                 |
| ----------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Supabase JWT (access token)         | Supabase GoTrue SDK (internal Keychain)              | Managed automatically by the SDK                                                       |
| Supabase anonymous session          | Supabase GoTrue SDK (internal Keychain)              | Managed automatically by the SDK                                                       |
| Extension cache                     | App Group `group.app.merian.shared`                  | Non-secret coordination data shared by the app, Messages extension, and Explore widget |
| RevenueCat customer ID              | RevenueCat SDK (internal)                            | Logged in with the Supabase Auth UUID; SDK-managed locally                             |
| `SUPABASE_ANON_KEY`                 | `Config.xcconfig` → `MerianEnvironment.swift`        | Read-only build config, not secret                                                     |
| `REVENUECAT_API_KEY`                | `Config.xcconfig` / `Config.local.xcconfig` → `MerianEnvironment.swift` | Read-only build config, not secret; production export should use an iOS `appl_` key     |
| `POSTHOG_API_KEY`                   | `Config.xcconfig` → `MerianEnvironment.swift`        | Read-only build config, not secret                                                     |
| `GEMINI_API_KEY`                    | Supabase Edge secret only                            | Never in iOS bundle                                                                    |
| `AI_QUOTA_IP_HASH_SECRET`           | Optional GitHub Production override synchronized to Supabase Edge | Dedicated HMAC key for rotating network quota buckets; never in clients or logs |
| `DWCA_PSEUDONYM_HMAC_KEY_V1`       | GitHub `Production` secret synchronized to Supabase Edge | Base64 32-byte-or-longer HMAC key for versioned global-export user pseudonyms |
| `REVENUECAT_WEBHOOK_SECRET`         | GitHub `Production` secret synchronized to Supabase Edge | Random webhook Authorization credential; never use the public iOS key |
| `REVENUECAT_WEBHOOK_SIGNING_SECRET` | GitHub `Production` secret synchronized to Supabase Edge | RevenueCat raw-body HMAC key; never log, commit, or expose to clients |
| `REVENUECAT_SECRET_API_KEY`         | GitHub `Production` secret synchronized to Supabase Edge | `sk_` server API credential for authoritative CustomerInfo reads; distinct from `REVENUECAT_API_KEY` |
| `R2_READ_ACCESS_KEY_ID`             | GitHub `Production` secret synchronized to Supabase Edge | Dedicated bucket-scoped read-only credential for direct-origin media verification |
| `R2_READ_SECRET_ACCESS_KEY`         | GitHub `Production` secret synchronized to Supabase Edge | Secret half of the dedicated verifier credential; never reuse upload/delete authority |
| `R2_EVENT_WEBHOOK_SECRET`           | GitHub `Production` secret synchronized to Supabase Edge | High-entropy shared secret for optional Cloudflare R2 event hints |
| `SUPABASE_SERVICE_ROLE_KEY`         | Supabase Edge secret or server-side web env only     | Never in iOS bundle or browser-exposed web config                                      |
| `Merian_HasAuthenticatedOAuth`      | `KeychainManager` (`kSecClassGenericPassword`)       | Security-sensitive auth flag, migrated from `UserDefaults` on first run                |
| `Merian_PendingGhostProfileMerge`   | `KeychainManager` (`WhenUnlockedThisDeviceOnly`)     | Versioned queue of provider-bound account-upgrade proofs; removed only after success or terminal expiry/invalidity |
| Device IDFV (`Merian_Device_IDFV`)  | `DeviceIdentityManager` (`kSecClassGenericPassword`) | Persisted across reinstalls within the same vendor group                               |
| `hasCompletedOnboarding`            | `UserDefaults`                                       | Non-sensitive preference                                                               |
| `isAchievementNotificationsEnabled` | `UserDefaults`                                       | Non-sensitive preference                                                               |
| `Merian_UnlockedSpeciesCount`       | `UserDefaults`                                       | Non-sensitive gamification counter                                                     |
| `Merian_UnlockedAchievements`       | `UserDefaults`                                       | Non-sensitive gamification set                                                         |
| `firstFieldTripAchievementProgress.v1.{accountId}` | `UserDefaults`                          | Non-sensitive account-scoped completion date and typed Field trip destination cache   |
| User geoprivacy preference          | Supabase `users` table                               | Server-authoritative preference                                                        |
| Local free-scan meter               | `UserDefaults`                                       | Advisory UX only; authoritative entitlement/quota is in Supabase                       |

---

## Deployment Environment Ownership

GitHub `Production`, Supabase Edge, the public-web Vercel project, and the
internal-admin Vercel project are separate trust boundaries. Never clone one
environment's complete variable set into another. Add a value only when the
target application's documented environment contract names it.

The backend deployment secrets commonly shown together in GitHub have these
destinations:

| GitHub `Production` variable | Deployment/runtime purpose | Copy to Vercel? |
| --- | --- | --- |
| `DWCA_PSEUDONYM_HMAC_KEY_V1` | The deploy workflow synchronizes it to Supabase Edge for global DwC-A export pseudonyms | No |
| `REVENUECAT_SECRET_API_KEY` | The deploy workflow synchronizes it to Supabase Edge for authoritative subscriber reads | No |
| `REVENUECAT_WEBHOOK_SECRET` | The deploy workflow synchronizes it to Supabase Edge for webhook Authorization | No |
| `REVENUECAT_WEBHOOK_SIGNING_SECRET` | The deploy workflow synchronizes it to Supabase Edge for raw-body signature verification | No |
| `R2_READ_ACCESS_KEY_ID` | The deploy workflow synchronizes it to Supabase Edge for signed, read-only R2-origin verification | No |
| `R2_READ_SECRET_ACCESS_KEY` | The deploy workflow synchronizes it to Supabase Edge as the verifier credential secret | No |
| `R2_EVENT_WEBHOOK_SECRET` | The deploy workflow synchronizes it to Supabase Edge when optional R2 event acceleration is enabled | No |
| `SUPABASE_ACCESS_TOKEN` | Authenticates the Supabase CLI running in GitHub Actions | No |
| `SUPABASE_DB_URL` | Preferred direct PostgreSQL connection used by migration and catalog-audit steps | No |
| `SUPABASE_DB_PASSWORD` | Used only by the alternative GitHub database connection path | No |

The public `apps/web` Vercel project has its own allowlist in
[`apps/web/.env.example`](../../apps/web/.env.example). In particular,
`SUPABASE_URL` is the HTTPS project API endpoint used by server code; it is not
`SUPABASE_DB_URL`, which is a privileged PostgreSQL connection string. The
public-web project receives `SUPABASE_SERVICE_ROLE_KEY` only as a sensitive,
server-side value for its reviewed server routes. It must never appear in a
`NEXT_PUBLIC_` variable or in the separately deployed admin project.

The `apps/admin` Vercel project receives only
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and
`NEXT_PUBLIC_ADMIN_ORIGIN`. It must not receive a service-role key, a direct
database credential, or any GitHub deployment/Edge provider secret.
`apps/admin/lib/admin-foundation.test.ts` parses the complete production
TypeScript graph, rejects privileged credential names plus computed/whole-object
`process.env` access, and allows only these public keys. The Admin Quality
workflow supplies non-secret CI placeholders; real production values exist only
in the separate admin Vercel project.

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

- `GEMINI_API_KEY` — lives exclusively in Supabase Edge secrets. The iOS binary
  has no knowledge of this key. All Gemini calls go through Supabase Edge
  inference endpoints, primarily `/identify-multimodal`; legacy `/identify`,
  `/identify-describe`, and `/audio-spec` remain server-side compatibility
  routes only. The same key powers `/share-scan-to-explore`'s dedicated
  `gemini-2.5-flash` public-audio classifier; transcripts and non-speech
  descriptions are never stored or logged. A matching service-only moderation
  attestation can approve unchanged bytes without calling Gemini; a cache miss
  still fails closed when this key is unavailable.
- `AI_QUOTA_IP_HASH_SECRET` — optional dedicated override of at least 32
  high-entropy characters. When absent, Edge code uses a built-in server-only
  Supabase secret/service-role key. In both cases it HMACs the proxy-observed
  address with a quota-specific domain and UTC-day prefix; neither the raw
  address nor key enters the database, client, analytics, or logs. A weak
  explicitly configured override fails paid-model work closed.
- `DWCA_PSEUDONYM_HMAC_KEY_V1` — required dedicated key for global Darwin Core
  export attribution pseudonyms. It is Base64 encoded and must decode to at
  least 32 random bytes. Each job pins a numeric version; rotation adds a new
  secret and advances the database default only after code can read both.
  Never replace bytes under an existing version or derive this value from
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
  `reconcile-explore-media-health` for signed direct-origin `HEAD` requests.
  The verifier fails closed when either value is absent and never falls back to
  upload, write, or delete credentials. Rotate the pair together and keep it
  out of every client and Vercel environment.
- `R2_EVENT_WEBHOOK_SECRET` — an independent random value of at least 32
  characters used to authenticate optional Cloudflare R2 event notifications
  at `ingest-r2-media-events`. Events only expedite a scheduled origin check;
  they never directly mark media missing, hide a post, or restore it.
- `SUPABASE_SERVICE_ROLE_KEY` — lives in Supabase Edge secrets or server-side
  web deployment secrets only. Never in the iOS app, never in `Config.xcconfig`,
  and never in a `NEXT_PUBLIC_` variable. Internal cron/webhook workers such as
  `refresh-species-content`, `refresh-species-model-content`,
  `refresh-merian-reference-images`, and `auto-purge-nonbio` may receive it only
  as a server-to-server
  `Authorization: Bearer ...` header from `pg_net`/Vault. The Next.js web app
  may read it only through `apps/web/lib/supabaseAdmin.ts`, which imports
  `server-only`. Public projection readers use
  `apps/web/lib/supabasePublic.ts` and cannot acquire service-role authority.
  Keep these modules separate and never re-export an admin-capable default
  client.
- `SUPABASE_ANON_KEY` — this is public client config, not a secret. It is
  injected via `Config.xcconfig` into `MerianEnvironment.swift`.
- `SUPABASE_URL`, `REVENUECAT_API_KEY`, `POSTHOG_API_KEY`, `GIDClientID`, and
  `REVERSED_CLIENT_ID` are also public client config values used by the app at
  runtime. `Config.xcconfig` may carry development defaults, while
  `Config.local.xcconfig` can override local app-facing values without being
  committed. Release archives warn if `REVENUECAT_API_KEY` is still a RevenueCat
  Test Store key, but can continue for local archive workflows. TestFlight/App
  Store export should resolve to a RevenueCat production iOS SDK key beginning
  with `appl_`; placeholder values such as the literal `appl_...` are blocked
  when supplied as a release override.

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
`Bool`, UTF-8 `String`, and raw `Data` values as
`kSecClassGenericPassword` items.

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

| Key | Type | Accessibility | Purpose |
| --- | --- | --- | --- |
| `Merian_HasAuthenticatedOAuth` | `Bool` | `AfterFirstUnlockThisDeviceOnly` | Distinguishes OAuth-authenticated users from anonymous Ghost sessions; used by `MerianNetworkClient` to decide whether a 401 triggers re-auth or Ghost regeneration |
| `Merian_PendingGhostProfileMerge` | JSON `Data` | `WhenUnlockedThisDeviceOnly` | Versioned queue containing source UUID, provider/subject, handoff UUID, 256-bit bearer secret, and server expiry for interrupted existing-account upgrades |

The merge queue is persisted and read back successfully before the app switches
away from the anonymous session. A newer handoff replaces only another handoff
for the same ghost UUID; unrelated pending upgrades remain queued. The decoder
accepts the former single-record shape and rewrites it to version 1 without
discarding the readable original if that Keychain write fails.

Completion removes one queue item only after server success or the terminal
codes `handoff_expired` and `handoff_invalid`. Network errors,
`auth_cleanup_pending`, `merge_temporarily_unavailable`, and
`handoff_forbidden` remain retryable. Sign-out cancels the in-flight task but
does not erase proofs; a task-generation token prevents an older cancelled task
from clearing the handle for a newer session.

`ThisDeviceOnly` items do not migrate through backups or device transfer. Never
copy the merge proof into `UserDefaults`, logs, analytics, crash metadata, an
App Group, iCloud Keychain, or a request URL.

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

The IDFV seeds the anonymous Ghost Session path (`signInAnonymously`) but is not
the durable billing identifier. Once Supabase returns a user, the Supabase Auth
UUID is passed to RevenueCat and PostHog; RevenueCat also receives subscriber
attributes such as auth email, public username, public display name, and account
kind for manual support lookup.

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
