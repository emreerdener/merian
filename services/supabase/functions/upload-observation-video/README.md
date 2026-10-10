# Private saved video item upload

`upload-observation-video` is an owner-authenticated POST binary endpoint for
one exact saved source clip, frame or extracted audio item. `media_enabled` and
`video_evidence_enabled` remain false. No native caller, provider dispatch,
credit action, activation or deployment is added.

`index.ts` registers the shared error boundary. `route.ts` owns authentication,
MIME/method checks and bounded streaming with a 120-second cancellation deadline
covering authentication, ingress and downstream work. `handler.ts` owns wire1
framing and reader12 admission. Database access remains in the shared
`videoEvidenceRepository.ts`, using a separately constructed service-role client
with five-second RPC deadlines and an actual 8 KiB response cap; the wrapper's
generic client is not used for video RPCs.

The shared upload coordinator verifies bytes before reserving the entire saved
inventory, then conditionally writes only the target object and awaits
readiness. Already-ready targets skip writes, including partial cohorts and
expired replay. Completion revalidates authoritative SQL fences. A lost response
remains uncertain and never starts another provider invocation or changes
media/object identity. No caller-selected owner, object, expiry or completion
timestamp is accepted. No standalone allocation endpoint or legacy audio/photo
fallback is introduced.

See the
[wire contract](../../../../docs/backend-and-data/05-api-contracts.md#private-video-item-upload-route).
Handler and route tests cover closed framing, authentication, owner-derived RPC
arguments, bounded ingress, cancellation and ready replay. Hosted runtime,
storage/CDN/erasure and device qualification remain separate.
