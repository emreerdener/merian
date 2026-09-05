# Profile Shell

`Shell/` is the thin container around Profile's sibling product areas. It owns
how those areas enter the app and fit together; it does not own their domain
logic.

## Why “Shell”

The name describes a boundary that wraps feature content with shared navigation
and composition. `ProfileView` supplies the close chrome, horizontal
Profile/Settings pager, segmented tab selection, and Profile-only toolbar. The
content inside that shell remains owned by `UserProfile/` and `Settings/`.

## Dependency composition

`ProfileView` is also the composition point for Settings dependencies that need
environment-owned state. It builds the account-fenced geoprivacy adapter from
the active `SupabaseManager` and the expedition-mode reconciliation action from
the environment `HardwareOrchestrator`, then injects both into
`SettingsTabView`. Settings subareas with live side effects construct their
narrow default dependencies at their own state-owner boundary.

The Shell must not absorb Profile tab loading, Settings interaction state,
endpoint calls, SwiftData queries, RevenueCat actions, or account-deletion
policy, sequencing, and live orchestration. Product-area Services and ViewModels
retain feature effects; `Core/Network/Auth/` owns deterministic deletion
decisions and ordering, while `SupabaseManager` assembles the live effects.
