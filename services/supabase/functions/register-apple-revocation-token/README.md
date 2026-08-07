# `register-apple-revocation-token`

Authenticated iOS endpoint for the server half of Sign in with Apple. The app
submits Apple's short-lived authorization code and identity token immediately
after Supabase installs the permanent Apple session. The endpoint:

1. checks a client-generated registration UUID before consuming the one-use
   code;
2. verifies the presented Apple identity token;
3. exchanges the code at Apple's `/auth/token` endpoint with a freshly signed
   ES256 client secret;
4. verifies the returned identity token and requires the same Apple subject;
5. atomically binds that subject to the active Supabase Auth identity and stores
   the refresh token encrypted in Supabase Vault; and
6. writes a 24-hour idempotency receipt so a lost HTTP response can be retried
   without attempting a second code exchange.

If Apple issues a refresh token but the Vault transaction reports failure, the
endpoint first rechecks the token-free receipt to reconcile a committed
transaction whose response was lost. An absent or unreadable receipt triggers
Apple's `/auth/revoke` as fail-closed compensation. It never logs the
authorization code, identity token, refresh token, client secret, or Apple
response body.

Required hosted Edge secrets:

- `APPLE_SIGN_IN_TEAM_ID`
- `APPLE_SIGN_IN_KEY_ID`
- `APPLE_SIGN_IN_PRIVATE_KEY` (the Sign in with Apple `.p8` private key; raw
  newlines or escaped `\n` are accepted)

The native App ID is deliberately pinned to `app.merian.Merian`, matching
`services/supabase/config.toml`. Rotate the Apple key by updating all three Edge
secrets before retiring the previous key in Apple Developer.

Only the service-role client can call the registration/Vault RPCs. Direct table
access is denied even to API `service_role`; the authenticated caller is bound
by `withEdgeHandler`, Apple subject verification, and the private SQL identity
check.

The complete deletion state machine, legacy fallback, key-rotation procedure,
and production exit gate are normative in the
[Sign in with Apple account-deletion contract](../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).
