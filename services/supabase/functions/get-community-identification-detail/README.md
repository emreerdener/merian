# get-community-identification-detail

Authenticated Community request detail. `withEdgeHandler` derives the viewer
from the verified JWT; its service client invokes the service-only invoker RPC.
The request accepts a bounded `request_id`, never a caller-selected viewer or
provider. SQL owns visibility, taxonomy suggestions and ordering; shared helpers
add public author identity, Pro badges and public media.

Apply `20260927004054_qualify_identification_metrics_by_provenance.sql` before
this producer. `ai_confidence_qualified` is a required non-null boolean derived
from immutable execution metadata. Historical absence retains Gemini behavior.
Unknown profiles return null suggestion scores in their recorded order. The
runtime guard rejects missing/non-boolean qualification, unsupported score
exposure and full provenance. No provider configuration is projected publicly.

The current native consumer shows **AI suggestion** for false, preserving review
without unsupported score or model-tier claims. Legacy native omission support
does not authorize alternate-provider activation; older public readers need a
compatible minimum app version or equivalent exclusion first. See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#get-community-identification-detail).
