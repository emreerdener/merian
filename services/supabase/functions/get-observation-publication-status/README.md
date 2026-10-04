# Get observation publication status

Prepared owner-authenticated POST reader for one durable publication operation.
`withEdgeHandler` validates the user; no caller-supplied owner is accepted. The
service client invokes `read_owned_observation_publication_status` with the
verified owner, observation and exact saved operation ID. The RPC enforces owner
and deletion fences. This reader neither advances work nor admits a new intent.

The bounded request is exactly `{schema_version:1,observation_id,operation_id}`
with lowercase UUIDs and a 1 KiB HTTP body limit. The response is exactly
`{schema_version:1,operation_id,observation_id,analysis_id,status}`. States are
`accepted`, `processing`, `photos_approved`, `needs_action` and `admitted`.
Extra or malformed server fields fail closed with 503. Notes, media, reasons,
provider decisions, cleanup keys, work tokens and post IDs remain private.

`admitted` records historical admission; it does not assert current visibility,
identification authority or species eligibility. `needs_action` intentionally
provides no private moderation reason. Clients must recover this same operation
instead of looking up a latest scan or invoking legacy sharing as a fallback.

Every response, including preflight, authentication, method and body errors,
carries `Cache-Control: private, no-store`. Invalid requests receive 400;
missing, foreign and deleted operations share the same opaque 404. Known
operation/revision conflicts return 409; transport or invalid server responses
return a sanitized 503. The RPC has a twelve-second client deadline and no
internal retry. The native durable delivery owner recovers this status before
exact admission, keeps acknowledged operations status-only, and fences every
response by the expected account and persisted claim. Ordinary UI delivery,
deployment and activation remain separate. See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-operation-status).
