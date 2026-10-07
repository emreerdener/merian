# Observation analysis wire values

`ObservationEvidenceUpload` owns the private reanalysis upload frame and strict
receipt decoder. Durable capture supplies observation, child-analysis and media
IDs plus immutable bytes. This value never creates an identity or owns retry,
selection, quota, enrollment or persistence.

The frame matches the
[private upload contract](../../../../../../../docs/backend-and-data/05-api-contracts.md#private-reanalysis-photo-upload):
uint32 big-endian metadata length, sorted-key UTF-8 metadata, then raw photo
bytes in order. Validation permits 1–5 JPEG/PNG images and 5 MiB aggregate,
rejects ID aliases and unsupported media, and computes SHA-256 on owned bytes.
Endpoint preparation uses the existing cancellable inference-preparation task
owner off the main actor; no base64 payload is produced.

The schema-1 response is bounded to 4 KiB at decoding and must have exact keys,
matching parent/child identities and one exact V2-shaped reference per submitted
photo in original order. Byte count rejects JSON booleans, and every digest must
match the prepared bytes. No decoder invents a manifest wrapper, URL, object ID,
post or visibility. Reference encoding preserves `kind: "image"` for later V2
admission. Existing publication/status decoder limits remain unchanged.

The endpoint uses a fixed authenticated facade bridge with the initiating owner,
a 130-second client timeout, no automatic ambiguous transport retry and no 401
session refresh. Dispatcher admission and post-await account-lease checks remain
the shared owners. Prepared values are not durable jobs: native capture/queue
integration must persist exact identity and media before invoking this endpoint.

`ObservationReanalysisRequest` prepares immutable protocol-8 photo admission
bytes for `analyze-observation`. It requires distinct observation, child and
source analysis IDs, 1–5 exact image references, ordered description items and
an explicit processor expectation. That expectation must come from the dedicated
owner-bound reanalysis recipient preflight, never a locally selected provider.
The request validates both Unicode-scalar and UTF-16 description limits and
rejects unsupported content instead of dropping it. Description-only protocol-7
admission is a separate contract and is not represented by this type.

The native request fingerprint is SHA-256 of the complete input except
`request_digest`, encoded as sorted-key UTF-8 JSON without escaped slashes.
Identity strings are lowercase; array order and text are preserved. The golden
fixture includes non-ASCII text, a slash and an emoji. Restoring saved bytes
checks exact keys, limits and the fingerprint, then retains those original bytes
for replay. This fingerprint is a native persistence convention; the server
independently compares the entire admitted input. It is neither proof of
uploaded evidence nor permission to run a provider. No capture producer, queue
delivery or analysis dispatch is activated by these value types.

`ObservationAnalysisReceipt` decodes only the four-field, 4 KiB execution
acknowledgment. It accepts the five defined execution states and binds the
response to the original parent/child IDs. Even `complete` carries no result or
selection authority: the durable caller must recover the immutable child through
owner history before committing local queue completion.

`ObservationReanalysisPreflightRequest` encodes only parent/source/child and
protocol 3/6/8 claims. Its exact eight-field 4-KiB response decoder rejects
foreign identities, unknown keys, boolean minima and ambiguous recovery states.
Recovery requires null recipient/minima and cannot construct fresh admission.
Capability 6 is understood without weakening the original native preflight
format. Shared consent authorization validates the expected account both before
the RPC and after suspension, then revalidates local consent and queue ownership
before each authorized use. This read does not promise ready media or funding.

The prepared `analyzeObservation` endpoint transmits those exact saved bytes
through the same private account-bound transport as evidence upload. Its closed
route chooses JSON rather than the upload frame's binary content type. A current
`IdentificationDispatchAuthorization` must match the saved processor, including
on replay; `recoveryOnly` cannot authorize a potentially not-yet-dispatched
admission. Both automatic retry and 401 refresh are disabled, and the durable
caller owns all reconciliation and current-account checks around persistence.

`manifest` and `decodeEvidence` are shared with the local offline draft so its
ordered evidence obeys the same limits without assigning a placeholder provider.
Extracting this validation changes neither the wire format nor its canonical
request digest; the existing Unicode/order fingerprint fixture remains the
compatibility check.

## Separate immutable audio wire

`ObservationAudioEvidenceUpload` prepares the fixed wire-1 audio frame using
`ObservationAudioContainer` and SHA-256 off the main actor. Its receipt decoder
accepts exactly one matching manifest-3 audio descriptor, with no storage or
provider fields. The fixed audio endpoint preserves expected-owner leases and
caller claim checks around preparation, Auth and response; automatic transient,
401 and route replay are disabled. It does not reuse the photo upload parser.

`ObservationAudioReanalysisRequest` separately prepares input 3, entitlement 3,
identification 6 and history 9 with the fixed `google_gemini` processor. Reader
10 is a result/action compatibility version, not this input's history protocol.
The existing strict audio manifest decoder owns description/scalar/UTF-16 limits
and descriptor validation. The request additionally rejects media equal to the
source, verifies the native canonical SHA-256, and retains exact saved bytes.
Current consent and server funding remain required; this value does not grant
either. Schema-2 photo request parsing and saved replay remain unchanged.

`ObservationAudioEvidenceUploadTests` covers binary framing, exact receipt
association, malformed WAV rejection before I/O, account/claim fences and
retry-free failures. `ObservationAudioReanalysisRequestTests` covers saved
order/text/bytes, strict versions/processor, aliased identities, Unicode bounds,
digest corruption and cross-generation refusal. These are wire-boundary tests;
durable audio preparation, execution, private restore and UI remain pending.
