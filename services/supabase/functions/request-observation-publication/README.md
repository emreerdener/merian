# Request observation publication

Prepared authenticated durable intake. `index.ts` derives the owner from the
verified user and the quota-address hash from the shared server HMAC boundary.
`handler.ts` freezes exact ordered consent and admits only a validated receipt;
`db.ts` owns the single service RPC with a twelve-second deadline and no retry.
`analysisHistory/publicationOperation.ts` owns strict request/receipt parsing.

HTTP 202 `accepted` means the immutable request is durably saved. It does not
mean moderation completed, photos became public or a worker was scheduled. Exact
retries recover the same receipt and original hash under owner/deletion fences;
changed consent conflicts. Eight new operations per owner per rolling 24 hours
bound intake independently of provider/scan credits. No external work is
performed. `publication_operation_enabled` defaults false. Native durable
delivery and service worker owners are prepared behind closed activation gates;
ordinary native UI admission remains disconnected. The route participates in
normal main deployment planning, without authorizing merge, deployment or
activation.

See the
[canonical intake contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-authenticated-publication-operation-intake)
for payload, errors, deletion and remaining worker requirements.
