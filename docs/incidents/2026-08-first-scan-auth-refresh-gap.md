# First-Scan Auth Refresh Gap

**Date:** 2026-08-08 local / 2026-08-09 UTC  
**Severity:** Release-blocking scan-reliability risk  
**Affected boundary:** Authenticated Edge request → session recovery → first
scan ownership  
**Repository status:** Remediated in source  
**Production status:** Open until matching-build session-expiry verification

## Summary

The supplied Supabase export contains a separate cluster of 14 rejected
`GET /auth/v1/user` validations. Every request identifies the Deno Supabase Edge
runtime as its caller, so these rows represent Edge handlers validating an
inbound user credential rather than the iOS app calling Auth directly.

The export does not contain the corresponding Edge route rows, account identity,
or response envelope. The cluster therefore cannot be attributed to one named
scan or user. It does, however, expose a deterministic client gap: Merian's
shared handler maps an expired or otherwise invalid credential to handler-owned
`401 invalid_session_token`, while the iOS recovery branch attempted SDK refresh
only for `auth_session_missing`.

For an anonymous user, the unmatched code could bypass refresh and enter Ghost
identity replacement even when the existing session still had a valid refresh
token. A first scan, its consent evidence, funding reservation, and any server
ownership all use the account UUID, so preserving that identity is the smoothest
and safest recovery.

## Sanitized Runtime Evidence

The 14 Auth validations occurred between 22:33:52.663Z and 22:34:17.531Z in
bursts of two or three. All had:

- method/path: `GET /auth/v1/user`;
- status: `403` at the Auth service;
- caller: Deno 2.1.4 / Supabase Edge Runtime 1.74.2; and
- no usable route, account, token, or scan correlation fields in the export.

No raw credential, request identifier, account identifier, or response body is
retained here.

## Root Cause

`services/supabase/functions/_shared/auth.ts` converts Auth validation failures
into a caller-safe handler response:

- an Auth “session missing” error becomes `401 auth_session_missing`; and
- every other missing/invalid user result becomes
  `401 invalid_session_token`.

Before this repair, `MerianNetworkClient.performAuthenticatedRequest` called
`SupabaseManager.refreshActiveSessionForRetry()` only when the response matched
`auth_session_missing`. The stable `invalid_session_token` path instead reached
the generic 401 branch. OAuth accounts failed closed, while anonymous accounts
could transition directly to a replacement Ghost identity.

That classification conflicted with Supabase's session model: an access JWT is
short-lived, while the current refresh token can still exchange it for a new
access/refresh pair. The pinned Supabase Swift 2.54.1 package already serializes
concurrent refresh calls through its session manager, so the missing behavior
was Merian's decision to invoke it for this stable code.

## Resolution

The foreground authenticated request boundary now treats both stable shared-auth
codes as refreshable:

1. call the SDK's session refresh once;
2. preserve the current account while it is pending;
3. reconstruct the original request so it reads the rotated access token;
4. retry exactly once; and
5. consider the existing identity-sensitive fallback only if refresh fails.

The handler's auth check precedes route domain mutation, so the refresh replay
does not duplicate a successful write. The retry retains the original request
body, idempotency key, upload-completion callback, and scan UUID.

The formerly empty 401 test now injects a non-destructive refresh seam, returns
`401 invalid_session_token` on the first handler request, succeeds on the second,
and proves one refresh plus exactly two dispatches without touching a
developer's simulator Keychain or real Supabase session.

## Required Release Verification

Do not close this incident until one matching Release/TestFlight build proves:

1. Begin a first ordinary scan under one known anonymous account and preserve
   its stable scan UUID and local media.
2. Force the next Identify handler validation to reject the access JWT while
   leaving the refresh token/session valid.
3. Observe one coalesced session refresh and one request replay; concurrent
   authenticated work must not create a refresh storm.
4. Confirm the anonymous account UUID, consent ownership, funding reservation,
   and scan UUID do not change.
5. Confirm exactly one provider dispatch and one usable saved result.
6. Repeat with a genuinely terminal anonymous session and verify local media is
   retained through the explicit replacement/approval recovery path.
7. Repeat with an OAuth account and verify an unresolved refresh never replaces
   that signed-in identity.

## Related Contracts

- [API Contracts](../backend-and-data/05-api-contracts.md)
- [Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [Error Handling](../development-guides/06-error-handling.md)
- [Core Network](../../apps/ios/Merian/Core/Network/README.md)
- [First-Scan Consent-Policy Retry Loop](./2026-08-first-scan-consent-policy-retry-loop.md)
