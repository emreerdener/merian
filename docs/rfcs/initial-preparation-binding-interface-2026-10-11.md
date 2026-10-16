# IC-1 preparation identity and retained WAV derivation

Status: accepted inactive interface, October 11, 2026, following local profile
checkpoint `07aa63f80`. Initial-engine and independent read-only reviewers
accepted the immediate reference scope before implementation. History primary
owns writes. This document specifies the next bounded dependency within S0, not
a new product slice.

## Follow-up ordering contract

The
[durable pre-admission preparation contract](initial-pre-admission-preparation-2026-10-11.md)
records the coordinated correction to the future admission and
retained-derivation ordering below. It requires durable original/prepared bytes
and a preparation outcome before funding, then exact M1/M2 handoff without a
second transform. The accepted finite reference implementation and its
qualification remain unchanged. The coordinated follow-up supersedes the future
process-local handoff and retained retransformation proposal below. Executable
schema and transport acceptance remain separate; the sections below preserve the
earlier proposal.

## Separate identity from permission

The accepted `validated-wav-darwin-arm64-v1` profile is local synthetic evidence
for one exact executable. It is not an Edge runtime selector or production
loader. Its 262,144-byte synthetic request envelope is smaller than initial
media ingress. The local qualification cannot attest full-size inputs, hosted
isolation, provider construction or every initial format.

The next increment defines a finite immutable preparation-profile reference and
its canonical digest. It does not change `prepareInitialAdmission`, existing
admission RPCs/decoders, the M1/M2 v1 manifests, saved configuration, or any
live route. No new database operation or runtime installer belongs to this first
reference increment. The local profile remains explicitly ineligible for Edge
admission/execution. Unknown profiles/platforms have no fallback.

The reference must bind all inference-affecting preparation identity:

- Profile ID, protocol version, qualification scope and target platform.
- Exact historical archive SHA256, revision and configuration-assets digest.
- New bootstrap and validator path, prior commit, regular blob identity, SHA256
  and byte count, separate from the historical archive inventory.
- Artifact SHA256 and byte count; semantic validator ID
  `initial-wav-structure-v1`; transform semantic ID `initial_audio_v1`.
- Exact build-policy and Deno/esbuild/provenance identities already pinned in
  the finite local registry. No version string alone is sufficient.
- Fixed target rate 16,000 and the explicit required fallback boolean supplied
  per item; it must equal the original admitted clip-companion semantics.

`scripts/initial-preparation/registry.json` remains the source of truth for
local artifact tuples. A closed reference projection must derive from a
validated, registered entry, never copy an arbitrary caller manifest or use
current checkout source. The fixed semantic/protocol/scope fields belong to the
finite profile implementation, not to caller input. Reference construction must
reject null registrations and the historical feasibility profile, which lacks
the new validator. Preserve the existing historical registry row and artifacts.

The local reference has exactly these top-level fields: `version: 1`,
`profile_id: "validated-wav-darwin-arm64-v1"`, `scope: "local_synthetic_only"`,
`platform: "darwin-arm64"`, `protocol_version: 2`,
`validator_id: "initial-wav-structure-v1"`, `transform_id: "initial_audio_v1"`,
`options: {target_sample_rate: 16000, fallback_rule: "clip_index_not_null"}`,
and `registry_entry` containing the complete validated registered tuple. The
options describe the fixed rule; each eventual admission/derivation binds its
actual original boolean separately. No digest field is embedded in this object.

Encode recursively sorted JSON object keys, preserve array order, compact
separators, no ASCII escaping, no trailing newline, and only the closed schema's
ASCII strings, integers and booleans. Hash the UTF-8 bytes prefixed by
`merian.initial-analysis.preparation-profile.v1` plus one LF. The constructor
accepts only the finite profile ID and reads the registry authority itself; a
decoder compares a bounded candidate's canonical encoding against that exact
expected reference, rejecting duplicate JSON keys, extra fields, altered types,
array reordering or changed tuple values. It does not accept caller-selected
registry paths. Local reference tests must include a fixed canonical/digest
vector and each identity mutation. The first implementation is a pure helper
beside the existing local harness, with no database/Edge imports or I/O beyond
reading the finite checked-in registry. Edge eligibility always returns false
for this reference. No purported eligibility field is trusted from input. A
reference is public code identity; source/result/media digests and operation
identities remain private. A reference digest alone is neither storage proof,
execution authority nor a qualified runtime capability.

## Admission ordering and version boundary

Current admission already binds the expected source and prepared output tuples;
M1 allocation and M2 verification follow admission. Do not create a dependency
cycle requiring a future retained derivation receipt before original admission.

The later coordinated fresh-alpha cutover must use a **v2 admission binding and
v2 configuration snapshot**. The snapshot adds an immutable preparation-profile
reference/digest alongside original provider/configuration/funding identity. The
v2 admission response exposes that digest to the internal repository. The
provider asset catalog and new preparation-source inventories remain separately
measured inputs; their composition receives the new configuration digest. Do not
rewrite the archived v1 catalog or change its digest to include new files.

At fresh admission the trusted composition resolves the exact approved profile
and derives expected output from its copied original bytes under that profile.
Resolving, reading, copying and transforming media happen outside every SQL
transaction and lock. The atomic admission/funding transaction receives only
already-derived bounded identities and the selected profile/configuration
reference; it performs no media I/O or transformation. It then freezes
source/output identities, transform options and preparation identity atomically
with the existing admission/funding transaction. Admission is still not
permission to invoke a provider. A runtime-ineligible profile must hold before
fresh admission or funding work; the local Darwin profile cannot become eligible
through a client flag, registry presence or a successful local receipt. A
separately qualified hosted/runtime profile is required first.

Existing inactive v1 records are not upgraded or relabelled. Exact v1 recovery
may return the original binding without gaining v2 execution authority. New v2
recovery reads the original saved profile and configuration without consulting
new defaults or recomputing media. Unsupported versions fail closed. This is
operation recovery for the candidate, not older-scan compatibility work.

## Retained derivation after M2

M2 v1 continues to attest byte identity and signature plausibility only. A later
separate write-once private derivation receipt references the exact saved v2
admission/configuration/profile and original M1 manifest/M2 verification. It
must not add meaning or fields to the existing M2 v1 receipt.

For each WAV item the trusted owner must read the original permanent retained
source object through the saved backend generation, with bounded direct uncached
streaming and erasure-marker rejection. Before asynchronous execution, it owns a
private exact-length copy, checks the source digest/count, and prevents callers
from retaining mutable aliases. Validation and transform consume that verified
copy; no mutable upload URL, caller path, current checkout implementation or
second source fetch may replace it between verification and execution.

The exact qualified runtime artifact and options are resolved from the saved
profile. Its output digest/count must equal the original admitted prepared tuple
and the verified retained prepared role. A mismatch holds/conflicts; it cannot
rewrite original admission, replace prepared media, select a new profile or
allocate another funding/provider attempt. Video-companion fallback stays an
explicit original input, not a retry policy. Other media in a cohort require
separately qualified profiles; WAV success cannot authorize a mixed cohort.

The future receipt binds owner/scan/submission, configuration/profile digest,
original media manifest/backend, item index and source/prepared object
identities, source/output digest/count, exact artifact/validator identity and
options. It erases with the private original submission on cancellation, scan
deletion and account detachment, including before history enrollment. Permanent
erasure metadata retains no private content digest. Identical settlement may
replay only after live ownership/deletion checks; conflicting settlement
rejects. Late completion cannot recreate erased evidence.

The durable claim, settlement and exact-recovery operations require their own
closed reviewed contract before database or transport implementation. They must
reuse IC-1/M1/M2 lock order and original cancellation/retirement fences, perform
I/O outside database locks, preserve the original deadline, and exclude ordinary
retirement while valid work/receipts are in use. An uncertain execution or
settlement cannot trigger another invocation: recover only the original status,
outcome or receipt; missing evidence holds. No refund or provider authorization
is implied. This reference increment creates none of those operations.

## Evidence and acceptance

| Boundary               | Owner                                  | Pass condition                                                                                                                                              |
| ---------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Finite reference       | History primary                        | Exact validated registered tuple; canonical digest vectors; every identity/option mutation rejects; unknown/null/historical identities reject               |
| Runtime eligibility    | History primary; initial-engine review | Local Darwin profile always ineligible for Edge admission/execution; no default/latest selection or caller override                                         |
| Admission cutover      | Coordinated database/repository owners | New v2 schema/configuration/response with atomic funding/input/profile binding, exact retry/recovery and cross-version denial; unchanged v1 identities      |
| Retained derivation    | History primary; initial-engine review | Exact original retained copy, artifact and options; output equals original prepared tuple; bounded malformed/failure/race cases; write-once erasing receipt |
| Remaining S0           | Coordinated owners                     | Other formats, permanent dispatch fence, original result/completion, all-route/worker integration and final candidate CI                                    |
| External qualification | User and separately authorized owners  | Installed/device/hosted behavior and runtime resource bounds; no inference from local synthetic tests                                                       |

Only the first two rows belong to the immediate reference increment. All later
rows remain required, with exact service schemas and migration order reviewed
before their implementation. Ordinary access stays nil, backend selection null
and activation false. No push, deployment, hosted scheduling, device
installation or distribution is authorized by this contract.
