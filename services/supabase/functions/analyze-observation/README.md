# Analyze observation

Prepared authenticated child-analysis orchestration. `withEdgeHandler` supplies
the verified owner; the server computes the existing quota IP HMAC. The strict
V1 description / V2 private-photo admission body freezes the actual client
protocol and processor claims. No caller-supplied owner, model, provider, object
key, or URL is accepted. Photos must meet the existing provider limit of five
JPEG/PNG images and 5 MiB combined, plus 32,000 UTF-16 code units of description
context, before admission. HEIC remains valid stored history but is rejected for
execution before any hold; transcoding is not implicit.

The response is exactly
`{schema_version:1, observation_id, analysis_id, state}`, with 200 for
`complete`/`failed_terminal`, otherwise 202. It is private/no-store. Clients
retry the same immutable input and analysis ID after transport failure, then
retrieve completed results through the owner history reader. A fresh analysis ID
requests another analysis. Completion appends; it never selects.

Immutable request-identity conflicts during admission return HTTP 409 with
`analysis_history_operation_conflict`. The caller must recover the original
request; retrying conflicting input is not a transient recovery strategy. Later
worker-claim conflicts remain sanitized 503 responses because replay can recover
saved work after a claim expires. Internal database diagnostics remain private
in both cases.

The service-only RPCs retain all quota tokens, claims, evidence receipts, saved
provider outcomes, and funding receipts internally. Received canonical output is
saved before taxonomy resolution. A 120-second work claim serializes preparation
and completion; the SQL dispatch decision separately prevents repeated
inference. Private photos are downloaded with bounded length, content type, and
SHA-256 verification, and their bytes are sent directly to the admitted
provider.

SQL dispatch is the external-processing authorization point. It checks current
owner/deletion fencing, consent, pinned evidence, and completion gates. The
provider call follows immediately. Deletion after that authorization cannot
reliably retract in-flight external processing, but blocks every late result,
replay, and private delivery. A live worker whose dispatch acknowledgement fails
can prove it has not entered `invoke()` and request claim-fenced cancellation. A
crash or expired claim supplies no such proof: ambiguous executions stay held,
are never automatically redispatched, and are excluded from completion recovery.

All rollout gates remain false. No endpoint deployment, enrollment, provider
execution, private bucket provisioning, or activation is authorized by this
source change. See the
[canonical contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-child-analysis-orchestration-and-recovery)
and [recovery worker](../recover-observation-analyses/README.md).
