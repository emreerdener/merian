# Recover observation analyses

Prepared service-authenticated completion worker. There is no deployed endpoint
or cron schedule. `orchestration_enabled` defaults false.

One invocation discovers at most ten due analyses, starts no more work after 40
seconds, and claims each separately in owner/observation lock order. Discovery
is only a hint; deleted observations and lost claims cannot authorize work. A
failing item does not stop the batch. Individual RPCs have a 12-second client
deadline and 10-second database statement timeout; an already-started item may
finish after the admission deadline. Responses contain aggregate counts only.

Only saved provider outcomes or drafts are recoverable. The worker never renews
client capabilities, quota admission, or consent; it never dispatches a
provider. Canonical output survives taxonomy failure. Taxonomy resolution adds
only a missing scientific-name identity under the parent fence, without
overwriting curated facts or publishing private prose. Draft construction must
match the stored canonical result exactly, apart from the dictionary link.
Completion shares the existing atomic append and complimentary-credit settlement
owner. Failed work is delayed 60 seconds; a crashed claim expires after 120
seconds.

Dispatched work without saved output remains ambiguous and held. No provider
retrieval/idempotency contract is qualified here, so automatic resolution of
that state is an activation limitation. Do not infer terminal failure from age.
See the
[canonical contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-child-analysis-orchestration-and-recovery).
