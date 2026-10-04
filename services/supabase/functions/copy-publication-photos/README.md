# Copy publication photos

Prepared service-authenticated POST worker for one durable, previously moderated
publication operation. No caller-selected operation, source, note, URL or object
key is accepted. Responses contain only `claimed`, `published` and
`needs_action` counts with `Cache-Control: no-store`. `published` includes
recovered historical admission and does not assert current visibility or
identification authority.

The database adapter strictly validates bounded hints, the exact ordered settled
cohort, original work token and expiry. Durable copy finalization precedes the
controller: existing publication skips all cleanup; a nonnull note requires
separate moderation and never reaches copying; expired original staging yields
only exact registry cleanup targets. Other eligible work enters the shared
controller, which verifies the full cohort before writing, preserves original
keys/expiry, binds the exact cohort and recovers publication before cleanup
after an uncertain binding reply. Transport or authority failures remain
recoverable.

The request lasts at most 135 seconds. Work and cleanup stop at 123 seconds,
leaving 12 seconds for best-effort original lease release. The 110-second copy
controller starts only with at least 122 seconds of request budget remaining;
slow setup releases work without starting I/O. Every RPC has its own 12-second
cap within the parent deadline. The original 120-second claim expiry is never
renewed locally. Erasure claims, marker PUT/HEAD and acknowledgement carry the
same parent cancellation. Interrupted cleanup remains durable in the registry.

## Activation prerequisites

All SQL rollout gates remain false. This endpoint is not scheduled or deployed.
Before enabling copying, separately authorize and verify recurring invocation of
`erase-publication-photos`, due-backlog/oldest-age monitoring and public CDN
cache bypass. Terminal expiry settlement deletes copy work, so failed immediate
erasure has **no copy-work retry path**: the permanent registry and independent
erasure worker must recover it. Without verified recurring erasure and
monitoring, publication copying must remain disabled. A successful best-effort
cleanup test alone does not satisfy this prerequisite.

CPU, process-memory and CDN qualification remain required. The 32 MiB cap covers
retained source input, not peak heap. Owner/native remediation delivery remains
separate. No deployment, scheduling, activation or TestFlight is authorized by
this source change. See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-service-publication-copy-worker).
