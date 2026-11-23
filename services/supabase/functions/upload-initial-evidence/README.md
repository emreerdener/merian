# Ordinary initial evidence upload

`POST upload-initial-evidence` accepts one artifact of an already admitted
ordinary ingestion request. Authentication supplies the owner. The route never
creates an ingestion job, reserves funding, invokes a model, finalizes an
observation, or authorizes local-original release.

The body is `application/octet-stream`: a four-byte big-endian metadata length,
closed UTF-8 JSON `{schema_version: 1, request, media_id}`, and the exact
artifact bytes. `request` is the versioned initial-retention request containing
the whole manifest and digest. The metadata ceiling is 1,044,736 bytes; the
artifact ceiling is 32 MiB, with the manifest's narrower role and cohort limits
still enforced. V7 bounds remain unchanged. Neither an object key nor a
caller-selected owner is accepted.

The existing service-only reservation proves exact owner/job/intent membership
and allocates the whole immutable graph. Upload then performs a private
conditional write, exact byte readback, and readiness acknowledgement for the
single artifact. An acknowledged retry still verifies stored bytes. Failure or
cancellation leaves the durable reservation with the existing retry/erasure
owner. There is no inferred successful completion or original cleanup.

Readback hashes each streamed chunk and verifies the exact total length without
retaining another full artifact buffer. It rejects encoded, partial, truncated,
oversized, changed and erased responses, bounds chunk counts, and cancels failed
reads. Upload still uses defensive snapshots of mutable buffers; the 32 MiB
artifact limit is not a claim of 32 MiB whole-worker memory use. Large-original
runtime memory qualification remains required before activation.

This route is source preparation, not deployed activation. Native ordinary
acceptance, the Identify continuation, History readback, and original release
must be connected and validated before enabling the workflow. The Identify
initial-evidence fence and database rollout gates remain in force.

Tests cover authentication before body consumption, framing/closed metadata,
role-specific byte bounds, exact hashes and receipt membership, partial cohort
progress, acknowledged replay, changed storage, cancellation, and private error
responses. See
[API contracts](../../../../docs/backend-and-data/05-api-contracts.md).
