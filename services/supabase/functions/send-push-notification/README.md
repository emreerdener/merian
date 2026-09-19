# `send-push-notification`

Internal service-authenticated Explore/Community push delivery endpoint. It
loads the eligible notification and devices, honors notification capability and
preference filters, and sends through APNs with bounded delivery concurrency.

`index.ts` owns configuration and bearer-token caching. `token.ts` signs the
provider JWT using the shared JOSE 6.2.12 WebCrypto implementation: ES256, the
configured Key ID and Team ID, and a one-hour expiry. Raw and escaped PEM
newlines are supported. The existing cache is valid for 55 minutes and requires
more than five minutes remaining before reuse. `delivery.ts` owns APNs request
transport and failure handling; the signing helper performs no network calls.

`token_test.ts` generates ephemeral P-256 keys, verifies signatures and claims,
checks expiry and malformed keys, and never contacts APNs. `delivery_test.ts`
separately covers the injected delivery transport. Never log provider tokens,
private keys, device tokens, or notification content. Production credential
rotation and real-device push verification remain separate release operations.
