# resolve-purchase-principal

JWT-authenticated, additive purchase-identity resolver. A caller supplies only a
256-bit installation capability, protocol version, and device-monotonic binding
intent. The Edge function derives the current Auth user from the verified JWT,
hashes the capability, and asks service-only database routines to create or
rebind one stable RevenueCat purchase principal.

The binding intent is advanced and verified in device-only Keychain storage
before network I/O. Postgres accepts it only when newer than the last intent for
that capability, and completion must match it exactly. This prevents an older
Auth request that finishes late from rebinding the principal over a newer
session.

The client cannot nominate an Auth UUID, purchase-principal UUID, or RevenueCat
App User ID. Existing customers are adopted in place when safe; otherwise the
server creates an opaque `MERIAN_PP_…` provider ID. StoreKit-backed state is
projected through the active binding. RevenueCat promotional state is imported
to the fixed account-grant owner and does not move during sign-out or account
switching.

An active account-deletion job rejects both database resolution phases. Cleanup
uses the same principal-first lock order, detaches the deleting Auth binding,
erases account-owned grants, and permanently freezes compatibility promotion
import. The non-identifying StoreKit principal survives for the same
installation; a later account cannot inherit the deleted account's provider
promotion.

RevenueCat retains historical non-renewing purchases after refund. First
adoption therefore enables detached `pro_week` inference only when the current
Supabase Pro projection has the exact same finite expiry; completion repeats the
comparison while holding the user row lock. Active principals return and reuse
their durable pass-policy flag. Only signed webhook purchase evidence can later
enable it directly. A transfer destination can inherit an enabled flag only from
its resolved stable source after its authoritative snapshot contains an active
App Store pass; destination history, ordinary resolver reads, and reconciliation
reads cannot enable it.

The rollout configuration returns `mode: legacy` for new or pending capabilities
until operators explicitly enable the stable lane after schema, webhook,
reconciliation, iOS, and provider sandbox gates pass. An already active
capability remains stable and rebindable if rollout returns to legacy; rollback
cannot rotate its provider identity. A below-minimum active client fails closed
with `purchase_principal_client_upgrade_required`. The legacy
`/transfer-signout-purchases` protocol remains unchanged for old clients. After
the first stable response, iOS stores a verified device-only fingerprint of the
exact installation capability. That monotonic evidence is not a provider ID
cache, but it makes any later endpoint `404` or `mode: legacy` response fail
closed instead of re-entering compatibility mode.

The installation capability is stored only in device-only Keychain storage on
iOS and only as SHA-256 in Postgres. Responses and logs must never include the
capability, its hash, provider payloads, or user identity.
