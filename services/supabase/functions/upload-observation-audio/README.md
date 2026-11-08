# Prepared private audio upload

Owner-authenticated binary WAV ingress for immutable audio cohorts. Both
`media_enabled` and `prepared_audio_evidence_enabled` remain false. This
endpoint does not admit inference, choose a provider, consume quota or enable
native UI.

`route.ts` owns authentication and the shared 120-second bounded streaming
deadline. `handler.ts` owns the closed binary frame, exact WAV verification and
server SHA-256 before reservation. `db.ts` calls only the two service-only audio
cohort RPCs with 12-second abortable bounds and no retries. Private storage uses
the existing conditional write, HEAD and permanent erasure-marker checks. Ready
replay still validates the original unexpired tuple through completion. Writes
abort before the final twelve-second completion-attempt window. SQL expiry
remains authoritative; an accepted PUT can survive cancellation or failed
completion until independent erasure. No completion guarantee or renewed expiry
is implied.

The separate wire-1 frame and bounded descriptor-only response are specified in
the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#private-reanalysis-audio-upload).
Never widen the existing photo endpoint or generic evidence parser to accept
this payload. Original media/object identity and five-minute expiry survive
retry; unknown replies grant no replacement or execution authority.

Handler and route tests cover byte ownership, validation-before-I/O, strict
receipts, expiry, cancellation, authentication and fixed RPC routing. Real
provider/storage/device qualification and coordinated input-3/result-4/reader-10
execution remain separate. No deployment or scheduling is enabled here.
