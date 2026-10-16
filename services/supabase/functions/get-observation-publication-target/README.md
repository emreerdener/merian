# Get observation publication target

Prepared owner-authenticated observation-wide recovery. `withEdgeHandler`
provides the verified owner; the caller supplies only
`{schema_version:1,observation_id}` within a 1 KiB body. The fixed service RPC
locks owner/deletion state and returns a non-null versioned envelope. The
handler validates that envelope before unwrapping it; empty 200/204 SDK replies
or bare null fail with 503. HTTP success returns literal JSON null for an
existing owned observation with no intake, or the original operation's exact
five-field status. Multiple legacy operations conflict; no latest-row or
selected-analysis lookup is performed. Missing, foreign and deleted observations
return opaque 404, never null. Invalid requests return 400, conflicts 409, and
uncertain or malformed responses sanitized 503. Every path is private/no-store,
with a twelve-second RPC deadline and no retry.

The occupied response is exactly
`{schema_version:1,operation_id,observation_id,analysis_id,status}`; statuses
match the unchanged exact-operation reader. The historical analysis can differ
from the currently displayed analysis. No consent, media, private reason, work
token or post ID is returned. This endpoint admits nothing, schedules nothing
and does not assert visibility. Remote null is advisory: final admission still
serializes against another device.

Clients must not synthesize a durable intent from this status: the original
consent fingerprint is absent. A local losing or uncertain request stays held
with its original UUID and consent. Explicit remote recovery can show a
different operation separately, without overwriting or acknowledging the local
one. Null after uncertainty never permits a successor. Same-ID settlement still
belongs to claimed exact delivery. Native transport and consent presentation
remain unconnected; all activation gates stay false.

See the
[target recovery contract](../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-target-recovery).
