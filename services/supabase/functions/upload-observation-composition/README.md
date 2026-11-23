# Private composition item upload

Prepared owner-authenticated `POST upload-observation-composition` handles one
exact artifact from a complete immutable shared-toolbar composition. It does not
admit inference, charge credits, create a successor or activate History. SQL
composition gates remain closed; no native caller is connected yet.

`route.ts` owns authentication, bounded binary ingress and the shared 120-second
deadline. `handler.ts` owns wire1 framing and reader14. Shared
`compositionUpload.ts` verifies original bytes before allocation, reuses private
conditional `writeOnce`, and awaits readiness for the exact object. The shared
`compositionEvidenceRepository.ts` uses five-second RPCs with a 16 KiB response
cap. `compositionVerification.ts` is also the provider materialization verifier;
video source/frame/audio retain their existing validators and identity graph.

Already-ready targets replay without rewriting bytes; an expired unready target
cannot extend its allocation. Complete receipt membership, object identifiers,
expiry and existing readiness remain unchanged. A lost response or cancellation
never triggers an in-request retry. All responses are private/no-store. Original
photo/audio/video endpoint contracts are unchanged.

See the canonical
[wire and lifecycle contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-composition-item-upload).
Tests cover all artifact roles, owner/reader binding, auth/framing/stream
limits, conditional PUT/HEAD, erasure markers, lost completion, immutable replay
and cancellation using synthetic fixtures. They make no hosted calls and do not
qualify mixed inference or the app's final submit/resume path.
