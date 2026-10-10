# Erase observation evidence

Prepared service-authenticated POST worker for the private history outbox.
`private_evidence_erasure_enabled` defaults false and independently gates new
retirement and claims. No scheduler or activation is included. Configured source
participates in normal future main deployment planning; runtime-off is not a
deployment exclusion. This worker is separate from public-copy erasure.

One invocation retires at most one expired unbound cohort (up to five receipts)
or one legacy receipt, retaining the immutable cohort descriptor and expiry. It
then claims at most one due opaque object, writes a permanent empty marker using
dedicated private-history write credentials, verifies HEAD, and settles the
original token. The outbox survives private history deletion. Caller bodies and
keys are never used as authority. Only service authentication can reach the
service-only database facades.

The 90-second shared request deadline includes twelve-second RPCs. The original
60-second claim is never renewed; the effective deadline is capped by its exact
returned expiry and the local claim-start clock. PUT and HEAD share 25 seconds
and begin only with 38 seconds remaining, leaving twelve seconds plus a margin
for completion. Parent cancellation reaches both storage requests. The worker
never DELETEs the object: the permanent marker blocks delayed conditional
uploads. A missing object alone is not erasure evidence.

Responses contain only `retired` (0–5), `claimed`, `marked`, and `acknowledged`
(0–1 each), and are no-store. `marked` means the origin marker was verified;
`acknowledged` means SQL accepted a success or failure report. Failed marking
may therefore return `marked=0, acknowledged=1` and remains retryable. Unknown
writes or acknowledgements are never retried inside the request; claim expiry
and the durable registry retain recovery. Existing-token settlement remains
available after the gate closes. No owner, object key, raw error, inference or
credit information is returned or logged.

Activation requires separately authorized recurring draining and backlog/oldest
age monitoring, real private-bucket policy and credential verification, and
storage race qualification. Local fake transport tests do not prove hosted
storage or CDN behavior. See the
[canonical contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-private-evidence-cleanup-rpcs).
