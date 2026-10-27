# Initial photo CPM content declaration v1

Status: October 27, 2026. The pure inactive content-codec design was reviewed by
Engine in turn 01a17f2c-63d1-7750-b6f8-21c4eb4e7345. The local implementation
candidate is `initialAnalysis/cpmPhotoContent.ts`, with the closed executable
`cpm-photo-content-schema-v1.json` as its field authority. Source review cleared
this pure-codec scope. Ten focused tests and the full Edge suite passed (3416
tests / 598 steps, with 532 tests explicitly ignored). Recursive type,
format/lint, config/dependency and documentation checks passed. Tooling coverage
completed across retained runs: 521 standard tests, 157 isolated evaluator
tests, 20 and 21 DTO tests, one archive test and 21 shell tests. The original
tooling commands remain failed: a stale V59 recovery guide was corrected to the
existing V66 implementation, and a synthetic PTY test required terminal access.
Its five-scenario rerun and all remaining shell tests passed without repeating
the completed suites. This is shared-checkout validation, not isolated-source,
native parity or runtime acceptance. No live owner or route imports it; no SQL,
Swift DTO or provider adapter is installed. This closes only the
content-declaration slice, not the complete CPM admission contract.
Server-preparation M1/M2 and historical recovery remain unchanged.

## Existing inputs and actual gaps

`SharedMediaNativeReceivingIntent.Prepared.observationID` is the initial server
scan/logical operation ID. Its operationID is local receiving, queueID is local
job correlation, bindingID is local consumer identity and generation is the
native inference fence. They are not alternate server inference identities. The
frozen cohort supplies ordered derivative intents, exact supporting bytes,
original identity and recipe. Readback supplies AI bytes only. The existing
initialAnalysis source assignment expects server-preparation proof and cannot
consume these as equivalent evidence.

The native supporting value stores an ordered contexts array and separate photo
presentation. It does not store an interleaved photo/text chronology or frozen
language/location/client inference options. ObservationContext.serialized()
trims text; the new mapping must not call it after freeze. Capture product and
provider composition must not silently invent chronology or fetch current UI
options to fill missing values. This is a concrete consuming-contract issue, not
permission for another queue or funding owner.

## Content-only v1 encoding

Use contract `client_prepared_media_v1`, content schema version 1 and photo
profile `P1-L1`. This slice admits one or two photos, optional exact text and no
client inference overrides. It does not declare audio/video unsupported by the
product: those remain later required profiles and cannot fall back to legacy
fresh admission. No endpoint, SQL signature, active route or eligibility is
allocated by this content codec.

Reuse initialAnalysis/canonical.ts sorted ASCII-key JSON, safe integers, exact
Unicode scalar strings, duplicate/extra/missing field rejection and the 1 MiB
serialized metadata ceiling. Use a separate SHA-256 domain:
`merian.initial-analysis.cpm-photo-content.v1\n` followed by exact canonical
UTF-8 bytes. Do not change legacy canonical domains or label this digest
verified.

Closed top-level fields:

| Field            | Proposed content                                  |
| ---------------- | ------------------------------------------------- |
| contract         | literal client_prepared_media_v1                  |
| version          | integer 1                                         |
| kind             | literal initial_photo                             |
| resource_profile | literal P1-L1                                     |
| scan_id          | lowercase canonical UUID from saved observationID |
| package_id       | lowercase canonical UUID from frozen packageID    |
| photos           | ordered array of 1–2 photo records                |
| contexts         | ordered array of 0–64 exact submitted contexts    |

Each photo has ordinal (0-based consecutive), source, ai, display and recipe.
Each role has logical reference_id, byte_count, sha256 and
declared_content_type. Logical IDs map to original.reference.referenceID /
intent.ai.referenceID / intent.display.referenceID; no server object ID or
generation is present. Association is explicit by containment; equal hashes
never deduplicate or reorder entries. Logical reference IDs are distinct across
these initial selected photos; physical sharing is a server reference decision,
never a hash-based client decision. All logical role IDs are distinct; the
current native recipe always creates separate roles. No source-version identity
is fabricated for initial capture. Reanalysis gets a separately reviewed
discriminator/shape with its exact selected source version.

Declared content type is a bounded nonempty scalar string, at most 128 UTF-8
bytes. A syntactically valid declaration is not a supported input profile or
proof of MIME/framing. Actual eligible original formats, AI/display JPEG rules,
byte-verifier build and provider compatibility remain explicit server profile
requirements; a codec cannot silently accept a format for execution.

Recipe is client provenance only: format (nativeStillImageV1 or
nativeCameraStillV1), is_pro, crop_display_size_bits (nullable), quarter_turns,
scale_bits, offset_x_bits, offset_y_bits, camera_vertical_center_bits
(nullable). Floating values use exactly 16 lowercase hex digits of their IEEE754
binary64 bit pattern. This preserves frozen finite values, including signed
zero, without a second decimal normalization changing their identity. Validate
the same finite/range/null combinations as SharedMediaNativePreparationRecipe.
Never serialize the enclosing native derivative/preparation blob: it includes
local file tokens, filesystem proofs and owner identifiers irrelevant to wire
permission. A later consuming builder must use the exact saved recipe only.

Each context has text_utf8_base64, canonical padded RFC4648 of exact strict
UTF-8 bytes. This avoids silently losing native-accepted NUL or altering Unicode
normalization through legacy scalar-string restrictions. Decode before applying
native-equivalent limits: 8192 scalars and 16384 UTF-16 units each; 32000 total
UTF-16 units; at most 64 entries. Preserve empty and whitespace-only entries and
order. Do not trim, combine, infer text/photo interleaving or take current
notes. The provider compositor must explicitly agree how the two ordered arrays
are serialized before consuming this manifest; this codec alone makes no
chronology claim. The serialized 1 MiB ceiling still includes base64 expansion.

Per-role limits match P1-L1: original 32 MiB each/64MiB cohort, AI 5 MiB cohort,
display 4 MiB each/8MiB cohort. Counts are positive safe integers, hashes
lowercase 64 hex, UUIDs canonical. Six objects maximum for this photo-only
slice. Total role bytes plus serialized metadata must remain within 96 MiB; no
limit changes. The codec neither buffers media nor qualifies decoder/worker
memory.

## Separate authority and consuming owner

The server recomputes the content digest from the closed declaration. A future
binding, separately versioned/domain-separated, combines authenticated owner,
scan, original unfunded intent identity, immutable assignment, content digest,
fixed logical-role-to-object/generation mapping, approved types, authority
revision and original deadline. No owner ID/URL/storage key/expiry/provider or
funding selection comes from this client content. Content never contains this
binding or receipt, preventing circular digests.

Complete byte verification must consume owned immutable original/AI/display
objects, full length/hash and bounded admissibility proof under the original
intent. It yields byte verification, not server transformation. Existing
initialAnalysis admission/accounting then atomically consumes the complete
new-branch proof; no M1/M2 placeholder and no dispatch from replay. Unknown
create/upload/verification/admission/provider outcomes recover exact saved
identity; no reminting, auto reupload, repeat AI, refund inference or deadline
renewal. The 30-minute intent and existing IVI-1 bounded authority clocks remain
policy; this slice does not implement or qualify their enforcement.

Original upload must use a narrow capability under the existing native original
owner/receiving locks with before/after-await and final physical/identity seals.
One bounded transfer at a time, at most 32 MiB original staging, included in 192
MiB temporary accounting. No all-originals Data array or broadened AI
projection. The future lifetime includes URLSession copies and uncertain
transfer cleanup; until that is proved, there is no upload adapter or server
receipt claim.

Completion preserves initial result and immutable evidence via existing owners;
explicit history enrollment remains a later action under IC-1 section 6. A
consumer-kind flip cannot replace the atomic native successor proof.

## Implementation boundary and remaining agreement

The pure, inactive content schema/validator under initialAnalysis has golden
vectors for one/two photos, exact text (including NUL/non-BMP/whitespace),
bit-pattern recipes, bounds, order, multiplicity, unknown fields/versions and
private-field rejection. A Swift mapping is a separate compiled checkpoint
consuming the saved native values; no new runtime state, route, SQL or provider
authority follows from codec tests.

Before any adapter can consume it: agree native/server text composition and
explicit option absence; close allocation/verification/admission/recovery
versioned fields, exact clocks/caller/lock/retirement ownership and response
semantics; prove original-transfer lifetime; preserve original funding rules.
Hosted feasibility, device and installed UI, full initial-photo result/history,
reanalysis, audio/video, RUX and final acceptance remain open. This proposal
does not claim that the complete CPM admission contract is closed.

## Revision 2 review clarification

Physical original asset IDs may be shared behind distinct logical references.
Use reference_id, not asset_id, as the role identifier; preserve both ordered
occurrences even when their physical native asset or hashes match. The native
builder still compares exact saved asset generations locally; this content
projection supplies no remote physical-sharing authority. Strict UTF-8 decode
must preserve a leading BOM (TextDecoder ignoreBOM:true) and reject invalid or
noncanonical base64. Independent synthetic text/bit vectors are retained in
photo-cpm-encoding-vectors01.json. They are encoding examples, not test passes.

## Exact mapping and qualification boundary

Photo ordinal comes from frozen cohort entry position. Acquisition ordinal, UUID
sorting and presentation-array order are not substitutes. Context order is
independent. Recipe bits are the unsigned binary64 pattern, most-significant hex
digit first, never native memory byte order. is_pro is provenance only. The
digest validates and snapshots canonical text synchronously before awaiting
SHA-256; it retains no caller-mutable object through that await. An unverified
content digest is not a server-issued verification receipt or dispatch grant.

The executable Deno schema is the field authority. The future Swift mapper must
prove parity using these exact golden/denial vectors and compile against saved
native values before consumption. No Identify DTO generator block changes
because no public Identify shape changes. The web and admin surfaces have no
producer or consumer of this private declaration. Allocation/verification and
recovery schemas remain separately unimplemented; a passing pure codec cannot
install an adapter or bypass their review and qualification.
