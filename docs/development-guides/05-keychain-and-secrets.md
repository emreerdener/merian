# Keychain and Secrets Management

This document explains what storage mechanism to use for sensitive data, API keys, and persistent identity tokens in Merian.

---

## Storage Decision Matrix

| Data type | Storage | Reason |
|---|---|---|
| Supabase JWT (access token) | Supabase GoTrue SDK (internal Keychain) | Managed automatically by the SDK |
| Supabase anonymous session | Supabase GoTrue SDK (internal Keychain) | Managed automatically by the SDK |
| RevenueCat customer ID | RevenueCat SDK (internal) | Managed automatically by the SDK |
| `SUPABASE_ANON_KEY` | `Config.xcconfig` → `MerianEnvironment.swift` | Read-only build config, not secret |
| `REVENUECAT_API_KEY` | `Config.xcconfig` → `MerianEnvironment.swift` | Read-only build config, not secret |
| `POSTHOG_API_KEY` | `Config.xcconfig` → `MerianEnvironment.swift` | Read-only build config, not secret |
| `GEMINI_API_KEY` | Supabase Edge secret only | Never in iOS bundle |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Edge secret only | Never in iOS bundle |
| `Merian_HasAuthenticatedOAuth` | `KeychainManager` (`kSecClassGenericPassword`) | Security-sensitive auth flag, migrated from `UserDefaults` on first run |
| Device IDFV (`Merian_Device_IDFV`) | `DeviceIdentityManager` (`kSecClassGenericPassword`) | Persisted across reinstalls within the same vendor group |
| `hasCompletedOnboarding` | `UserDefaults` | Non-sensitive preference |
| `lastArchiveRescueDate` | `UserDefaults` | Non-sensitive timestamp |
| `isAchievementNotificationsEnabled` | `UserDefaults` | Non-sensitive preference |
| `Merian_UnlockedSpeciesCount` | `UserDefaults` | Non-sensitive gamification counter |
| `Merian_UnlockedAchievements` | `UserDefaults` | Non-sensitive gamification set |
| User geoprivacy preference | Supabase `users` table | Server-authoritative preference |

---

## API Key Rules

**Absolute rule: no API key may appear in any `.swift` file, `Info.plist`, or committed `.xcconfig` file.**

- `GEMINI_API_KEY` — lives exclusively in Supabase Edge secrets. The iOS binary has no knowledge of this key. All Gemini calls go through the `/identify` Edge function.
- `SUPABASE_SERVICE_ROLE_KEY` — lives exclusively in Supabase Edge secrets. Never in the iOS app.
- `SUPABASE_ANON_KEY` — this is the public Supabase project key (safe to expose). It is injected via `Config.xcconfig` into `MerianEnvironment.swift` and is NOT a secret.

`MerianEnvironment.swift` reads all build-config keys from `Bundle.main.infoDictionary` at runtime, crashing with a `fatalError` if any required key is absent:

```swift
// MerianEnvironment.swift — read from xcconfig, not hardcoded
enum MerianEnvironment {
    static let supabaseUrl: String = { /* reads SUPABASE_URL from Info.plist */ }()
    static let supabaseAnonKey: String = { /* reads SUPABASE_ANON_KEY from Info.plist */ }()
    static let revenueCatApiKey: String = { /* reads REVENUECAT_API_KEY from Info.plist */ }()
    static let postHogApiKey: String = { /* reads POSTHOG_API_KEY from Info.plist */ }()
    static let telemetryAppID: String = { /* reads TELEMETRY_APP_ID from Info.plist */ }()
}
```

---

## KeychainManager

`KeychainManager.shared` is a thin wrapper over `Security.framework` for storing `Bool` values as `kSecClassGenericPassword` items.

```swift
// Accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
// Item class: kSecClassGenericPassword
// Key: kSecAttrAccount (the string key passed to set/bool/removeObject)
```

On first instantiation it migrates the legacy `UserDefaults` flag `Merian_HasAuthenticatedOAuth` to Keychain and removes it from `UserDefaults`. This migration is one-shot.

Currently stored keys:

| Key | Type | Purpose |
|---|---|---|
| `Merian_HasAuthenticatedOAuth` | `Bool` | Distinguishes OAuth-authenticated users from anonymous Ghost sessions; used by `MerianNetworkClient` to decide whether a 401 triggers re-auth or a Ghost session regeneration |

---

## Device Identity (`DeviceIdentityManager`)

`DeviceIdentityManager.shared` is a `@MainActor @Observable` singleton. `deviceId` is computed once at init via `getOrGeneratePersistentIDFV()`:

1. Attempts to load the IDFV from Keychain under the key `Merian_Device_IDFV`.
2. If not found and the Keychain is accessible, reads `UIDevice.current.identifierForVendor?.uuidString`, saves it to Keychain, and returns it.
3. If the Keychain is locked in the background (`errSecInteractionNotAllowed`), falls back to reading `identifierForVendor` directly from the OS without persisting, to avoid overwriting an existing identity.

The Keychain entry uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which means the IDFV survives app reinstall as long as another app from the same vendor group is installed. This is intentional: it preserves anonymous user identity across reinstalls for Ghost Session continuity.

The IDFV is used as the anonymous user identifier for Ghost Sessions (`signInAnonymously`), and is passed to PostHog and RevenueCat for anonymous funnel tracking.

---

## Secrets That Must Never Enter the iOS Codebase

If an AI agent generates code that includes any of the following, it must be rejected immediately:

- Any hardcoded string that looks like a Google API key (`AIza...`)
- Any hardcoded Supabase service role key (`eyJ...` with service role claims)
- Any raw database connection string
- Any SMTP or push certificate credentials

The correct pattern for all of these is an Edge Function environment variable accessed server-side only.
