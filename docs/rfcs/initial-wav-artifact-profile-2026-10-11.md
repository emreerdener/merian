# Local initial WAV validation and transform profile

Status: proposed finite profile, October 11, 2026. This extends the accepted
[WAV structural contract](initial-wav-validation-interface-2026-10-11.md) and
[local artifact experiment](initial-preparation-artifact-interface-2026-10-11.md).
It does not qualify or install initial admission, provider execution or a hosted
worker. History primary is sole writer; initial-engine and independent reviewers
accept the exact boundary and evidence before advancement.

## Identity and preserved inputs

Introduce the explicitly enumerated local profile
`validated-wav-darwin-arm64-v1`. Keep the historical
`wav-feasibility-darwin-arm64-v1` registry entry, bootstrap and accepted archive
unchanged. Unknown identities remain rejected; no arbitrary entrypoint, archive,
latest-source selection or general plugin execution is added.

The new artifact combines the historical archive's exact transform members with
new separately committed regular Git blobs for the validator and adapter. Pin
path, prior commit, blob identity, SHA256 and byte count for each new member.
The validator baseline is `b7e0c7962dcc38b2bece7f283b4ec08123d71957`; the new
source anchor additionally exports a typed structural rejection so unexpected
exceptions cannot pass as expected denials. Its exact new commit/hash is pinned
only after source review. Commit the adapter before writing its registry anchor;
the registration/evidence commit cannot reference itself. Disable Git
replacement objects and reject symlinks, missing objects and changed bytes. The
receipt binds both inventories separately and includes their selected tuple and
harness identity.

Reuse reviewed process, sandbox, private cache, output, deadline, resource,
cleanup and receipt machinery through an explicit finite profile extension. Do
not duplicate a second harness or broaden source selection. Preserve the old
profile's checks and requalify that path if shared machinery changes. Exact
`deno info` graph inventory must match the new allowlist; graph membership does
not prove that type-only imports execute. Bind actual emitted artifact bytes
separately. No change to `configuration-assets-v1.json`, its retained archive,
saved initial admission identities or live `prepareInitialAdmission` belongs to
this checkpoint.

## Local protocol and copy boundary

The new bootstrap is `scripts/initial-preparation/wav-validation-bootstrap.ts`.
Its synthetic JSON protocol is closed:

```json
{
  "version": 2,
  "operation": "validated_wav16k",
  "base64": "<canonical base64 synthetic WAV>",
  "preserve_source_when_trimmed_too_short": false
}
```

Keep the local experiment's existing maximum stdin envelope of 262,144 bytes,
base64 limit of 256,000 characters and parent process input/output bounds. These
are intentionally smaller than initial ingress limits; local synthetic
qualification must not claim full-size ingress or hard native-memory coverage.
Require the request to equal compact `JSON.stringify` spelling with the four
keys in the order shown above, no leading/trailing whitespace or BOM. This
rejects duplicate names, alternate number/string spellings and extra fields;
non-object values and prototype-shaped extra members reject. The displayed
pretty-printed example shows the schema, not accepted wire whitespace. Require
canonical base64 by decode plus re-encode equality, including padding/pad bits.
The fallback field is a required boolean and appears unchanged in successful
output. The output has exactly these keys in this compact JSON order, followed
by one LF: `version` (integer 2), `operation` (literal `validated_wav16k`),
`preserve_source_when_trimmed_too_short` (the request boolean), `input_bytes`
(positive bounded integer), `input_sha256` (lowercase 64 hex), `output_bytes`
(positive bounded integer), `output_sha256` (lowercase 64 hex), `base64`
(canonical output bytes), `complete` (literal true). The parent checks every
field, digest and independently expected output. No raw input or internal error
is logged outside the bounded synthetic protocol.

The adapter synchronously checks the supplied view's raw cap and non-shared
backing, copies exactly that view, validates the private copy, then transforms
that same copy to 16 kHz with the explicit fallback option. Its transform
function is a trusted static dependency, never JSON-selected; an injected spy in
unit tests proves it is not called on invalid structure and receives the private
exact copy on success. There is no await between copying, validation and
transformation. Only the bootstrap owns output hashing/serialization.

Rejected protocol produces no stdout and exit 1. Only the exported
`InitialWavStructureError` (or explicit source-cap/backing denial before
allocation) maps to structural rejection. Rejected structure produces no stdout,
exit 2, and this closed stderr diagnostic:

```json
{
  "version": 2,
  "status": "rejected",
  "stage": "validation",
  "transform_started": false
}
```

Only the existing typed `WavProcessingBudgetError` or exact existing minimum
duration Error may map to a transform denial. The historical transform has no
typed minimum-duration error: require the exact Error constructor and its known
message; a TypeError/subclass with the same message remains unexpected. No
structural denial is classified by message. A structurally accepted input
rejected by the existing transformation budget or minimum duration produces the
equivalent `stage: "transform"`, `transform_started: true`, exit 3 diagnostic.
Do not include the input, error message or stack in these diagnostics. Distinct
stage evidence and spy tests prove validation-before-transform; eventual generic
process failure is not sufficient. Unexpected runtime/process failure is not
structural acceptance or a successful negative test.

## Acceptance and remaining boundaries

| Row                                             | Owner                                  | Concrete pass condition                                                                                                                                                                     |
| ----------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source anchor                                   | History primary; independent review    | Prior committed exact adapter/validator blobs; closed protocol, stage, subarray/copy tests pass; docs and source hashes recorded                                                            |
| Compatibility                                   | History primary; initial-engine review | PCM16 and float32 mono/multichannel synthetic inputs preserve exact existing transform output and options; short sound fails without fallback but retains the original source with fallback |
| Rejection ordering                              | History primary; independent review    | Malformed RIFF/framing/nonfinite input never calls the transform spy; executable rejection has exact exit/stage/output, without parent timeout/limit masquerading as rejection              |
| Executable identity                             | History primary; independent re-review | Exact resolved graph; two fresh offline builds byte-identical; new registered digest/count and exact receipt; historical profile still passes after shared changes                          |
| Resource/lifecycle controls                     | History primary                        | Existing permission/cache/deadline/output/cancel/reaping/RSS gates pass; no native-memory hard-bound claim; 20 GiB floor preserved                                                          |
| Initial integration and candidate qualification | Coordinated owners                     | Open: same-copy retained-byte/admission integration, other formats, S0, native and installed/hosted acceptance, final exact-head CI                                                         |

Source tests use current checkout modules only as a local development gate; they
do not qualify the later artifact. Executable acceptance uses pinned old archive
members plus pinned new blobs. The local copy test does not prove later
retained-object loading, admission binding, device recovery or provider
behavior. Production stays disabled. Publishing, deployment, installation and
activation remain separately unauthorized.
