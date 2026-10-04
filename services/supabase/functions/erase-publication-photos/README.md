# Erase publication photos

Prepared service-authenticated worker. `publication_erasure_enabled` defaults
false and blocks new external claims; finishing an existing claim remains
available. No cron schedule is included. A future main-branch merge participates
in the normal deployment workflow, so this runtime gate is not a deployment
exclusion. POST accepts no operation parameters. The registry chooses at most
one due unbound or revoked public-photo object. User JWTs and caller-nominated
object keys cannot authorize this endpoint. Internal copy recovery can use the
same handler with a targeted service-only claim after failed completion.

The worker writes a permanent empty marker and verifies its HEAD through
`PublicHistoryPhotoStorage.erase`, then acknowledges the exact claim token. It
never deletes the key, reads private history, dispatches inference or charges
credits. Failed writes release the claim for retry; lost acknowledgements or
crashes recover when the two-minute claim expires. SQL excludes valid bound
publications and never extends staging deadlines.

Responses contain only `claimed`, `marked` and `acknowledged` counts, each zero
or one. `marked` means the origin marker was verified; `acknowledged` means SQL
accepted the success or failure report. A failed marker can therefore return
`claimed=1, marked=0, acknowledged=1` and remains retryable. RPCs have
twelve-second client deadlines and ten-second SQL timeouts; storage uses the
existing bounded R2 adapter. One invocation handles one object without an
internal retry loop.

After qualification, keep the separate cleanup gate enabled when
history/publication admission gates close. Activation requires dedicated
public-storage credentials, scheduled draining/monitoring, and verified
namespace cache bypass. An origin marker does not prove CDN erasure. See the
[canonical worker contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-public-photo-erasure-worker).
