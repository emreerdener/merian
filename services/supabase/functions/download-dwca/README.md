# DwC-A Download Authorization

`download-dwca` is the public bearer-capability boundary for completed Darwin
Core Archive downloads. It accepts only:

```text
GET /functions/v1/download-dwca?token={43-character-base64url-token}
```

The export worker emails the application URL, never a long-lived Cloudflare R2
signature. The database indexes the capability by SHA-256 hash in
`internal.export_download_grants`; the token itself is generated from 32 random
bytes and is not logged by application code.

Every request:

1. validates the exact URL shape and hashes the token;
2. applies a distributed five-minute IP-hash rate limit;
3. transactionally checks that the grant is live and the job is completed;
4. revalidates the complete immutable source membership against current
   deletion, ownership, taxonomy, protection, and privacy state; and
5. returns a no-store `303` to a read-only R2 signature valid for at most 30
   seconds.

A failed privacy fence revokes the grant and durably enqueues archive deletion.
Expired grants enter the same cleanup outbox even when nobody follows the link.
Unknown and malformed capabilities are indistinguishable `404` responses;
revoked/expired grants return `410`; provider or database outages fail closed
with `503`. The narrow post-email/pre-completion interval returns `425` without
revoking a valid in-progress grant.

The optional `DWCA_DOWNLOAD_IP_HASH_SECRET` may provide a dedicated versioned
HMAC secret for address hashing. If absent, the shared server-only key boundary
is domain-separated for this purpose. Do not use a public/publishable key.

The endpoint has `verify_jwt = false` because the random capability is its
credential. It never accepts an `Authorization` header as proof of export
ownership and never exposes R2 write credentials.
