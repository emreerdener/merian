# Proposed original-preparation target composition

> October 13 subsequent human approval: proceed with the reviewed CPM-1 policy
> targets, bounded local feasibility preparation and PR116 whole-backend source
> hold under the
> [approved local plan](client-prepared-media-approved-local-plan-2026-10-13.md).
> Earlier pending-approval wording below is historical for that decision.
> Runtime schema/audio/reference agreement and candidate qualification remain
> open; hosted/device/push/merge/deployment restrictions remain unchanged. AWS
> is unapproved and activation disabled. The hold is a local source change only.

> October 13 evaluation update: the user authorized drafting and reviewing the
> [CPM-1 client-prepared media amendment](client-prepared-media-amendment-2026-10-13.md)
> before any AWS decision. It proposes a distinct fresh-submission version; it
> does not weaken or reinterpret this document’s existing server-prepared or
> historical contracts. Adoption and implementation remain pending. AWS is
> unapproved, activation disabled, and all external-operation restrictions
> remain. Revision 3 records the user-required G1–G4 acceptance gates:
> original-byte retention, final audio plus signal/quality evidence, concrete
> storage limits, and end-to-end recovery/shared-asset deletion. Specification
> closure and candidate proof remain separate and open; missing numeric budgets
> or feasibility decisions block implementation, not merely release.

Status: October 13, 2026, review proposal only. This follows the accepted local
owner checkpoint `b3864361dd5c8b4d921650891ca1926a798d9bb0` and the
[caller inventory](initial-media-structure-attestation-2026-10-13.md). No target
is installed or qualified, and no implementation handoff, grant, schema, profile
selection or external operation follows from this proposal. History primary
remains sole writer under IC-1. Activation remains disabled and ordinary access
nil. The existing Darwin fixture remains Edge-ineligible.

## Pending concrete target decision

The user requested a concrete recommendation after the reviewed checkpoint. See
[target and ownership approval proposal](initial-preparation-target-approval-2026-10-13.md)
for the proposed AWS qualification VM, ownership and recovery arrangement. It is
pending user approval; no installed target or execution authority is recorded.
The reviewed design and historical evidence below remain unchanged.

## Reviewed design boundary

Independent review and IC-1 final bounded design concurrence are complete for
candidate `5a63a8a1343121b077221befceef3ee6318edfc4ffa1e6c335d075eb140ba71c`.
Exact decisions are retained in
`.artifacts/initial-media-structure/target-design-v4-reviews.json`. This accepts
the proposed consuming direction, not a target, changed product limits or an
implementation-ready schema/API. All earlier review findings and corrections
remain in the candidate-specific evidence directory.

The next concrete implementation agreement depends on naming the actual target
and its installation/worker ownership. It must jointly settle private
statement/registration/recovery schemas and vectors, effective caller/privilege/
lock inventory, generated consumers, and cross-host journal restore/failover.
Neither journal loss/restoration nor moving to another supervisor/installation
can recreate fresh launch authority. Native functional profile/source-plan
compatibility needs its distinct agreement. Do not fabricate placeholder SQL
while those target-specific decisions are unresolved.

No actual Linux target or target-use authorization is recorded. Installation and
qualification execution require separately named authorization; exact build,
sandbox/resource/death and storage evidence remains missing. Existing pending
environment answers are preserved without repeating questions. At this boundary,
stop implementation advancement pending that concrete target decision rather
than rerun the accepted local WAV/SQL evidence or invent another adapter.
Further read-only contract/source clarification remains possible when new target
information arrives. The original roadmap and deletion/export/redesign
follow-ups remain incomplete and in their approved order.

## Concrete candidate and decision

Propose a dedicated **Linux x86-64, GNU ABI preparation worker**, outside the
hosted Edge execution sandbox. Trusted Deno 2.9.4 orchestration calls the
existing preparation owner; an OS service manager owns isolated, credential-free
decoder processes. This is a proposed qualification target, not a configured
host or a claim that existing Edge eligibility accepts it. No infrastructure is
provisioned.

The candidate decoder composition is:

- The existing archived WAV parser/`processWavBuffer` closure, rebuilt for the
  proposed Linux Deno tuple without modifying saved historical identities.
- FFmpeg 9.0.2 native libraries for JPEG/PNG/WebP validation and bounded MP4
  demux/decode using an explicit H.264/HEVC and AAC/PCM allowlist. No automatic
  protocol, decoder, hardware acceleration or external-library discovery.
- libheif 1.23.6 with libde265 1.1.3 for HEVC-backed HEIC/HEIF, built without
  runtime plugins. Other HEIF codecs are not silently accepted.

These are proposed release baselines, **not a pinned executable closure**.
Compiler, libc, enabled components, transitive libraries, source/signature
hashes, final executable digests and reproducible build provenance remain to be
resolved for a named target. Releases are documented by
[FFmpeg](https://ffmpeg.org/download.html),
[libheif](https://github.com/strukturag/libheif/releases/tag/v1.23.6) and
[libde265](https://github.com/strukturag/libde265/releases/tag/v1.1.3). Their
release existence supplies no Merian compatibility or security acceptance.

Source-level decision: this is a plausible isolation composition, but **cannot
replace any current saved preparation profile**. Current profile runtime
metadata names a Deno engine and one artifact; it does not yet establish a
transitive native bundle or trustworthy video extraction. Do not disguise native
children as the qualified Darwin artifact, broaden an existing digest's meaning,
or populate eligibility rows. A reviewed bundle/protocol proposal must precede
any justified codec/SQL delta. Unsupported source encodings require a qualified
profile or blocked fresh admission; video remains required product scope, not an
optional feature removed to qualify a smaller candidate.

## Trust and dependency mapping

| Component                 | Proposed authority and ownership                                                                                                                                                                                  | Existing boundary and missing evidence                                                                                                                                 |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Trusted orchestration     | One worker per original intent; frozen own-data context, no caller URLs or executable names. Only this component can request fixed service operations.                                                            | `runInitialPreparation` remains the lifecycle owner and sole fresh-grant call site. Transport's five operations remain closed; no new issuer.                          |
| Source/storage broker     | Separately restricted trusted component resolves saved opaque IDs and backend generation. Holds original-preparation signing capability; never passes it to a decoder.                                            | `readSource` and identity/readback dependencies require a concrete preparation namespace adapter. M1/handoff signing ownership is not reused as a substitute.          |
| Structural inspector      | Credential-free process with private exact source snapshot, bounded input/output, no network or writable executable path. Reads container headers/structure only.                                                 | `inspectSource` runs before grant. It must not decode or invoke the combined WAV transform. Header parsing is hostile work and consumes its own bounded phase.         |
| Granted decoder/transform | Immutable allowlisted executables, no service credentials, signed URLs, host filesystem, network, dynamic plugins or child-selected commands. Full cohort runs only after one positively received original grant. | The existing `runtime` callback snapshots and reads the same verified bytes. Native decoding and expansion occur here once, never as preflight followed by repetition. |
| Output validator/retainer | Trusted orchestration validates the complete ordered response, snapshots output, computes tuples, registers destinations, then uses conditional storage plus direct readback.                                     | Existing manifest/resolved/outcome chain owns durable identity. Native output and process exit alone do not establish retention.                                       |
| OS lifecycle owner        | Service manager outside the per-operation cgroup owns termination even when the Deno coordinator dies. No automatic operation restart.                                                                            | Parent-death, group-empty, reap, deadline and cleanup evidence is absent on this candidate target.                                                                     |

The source broker must finish the exact-length read and hash comparison before
handing a private snapshot to inspection and transform. No decoder may refetch
from storage; any shared-memory or descriptor transport needs immutable/sealed
input semantics and exact-length ownership verification. Output protocols must
reject extra/missing ordinals, unexpected media, fallback, options, identity,
trailing frames and partial/truncated success. No raw media or process
diagnostics enter logs or review artifacts.

## Process death and durable output

The current `KnownOutput` and `reconciliations` WeakMap in
`preparationExecution.ts` preserve bytes only within the surviving process.
Neither that token nor a SQL manifest makes lost bytes recoverable. The proposed
minimum uses the **existing registered destinations** as durable byte storage;
it does not invent an unregistered spool or a second output namespace.

1. Before grant, only verified original sources exist. Lost issue
   acknowledgement is recovery-needed, with no decoder invocation. A replacement
   never obtains execution authority from status.
2. After the fresh transform finishes, the trusted owner accepts only the
   complete bounded cohort, validated identity/provenance and clean process
   completion. The output is still volatile. Compute and validate its exact
   manifest; call the existing registration operation before any output PUT.
3. Resolve registration uncertainty through original status. A surviving worker
   can reconcile the identical known manifest; a replacement with no bytes
   cannot construct them from source media. Registration binds destination IDs
   and tuple identities, not successful physical writes.
4. Conditionally create each registered destination, then directly read and
   compare the full expected bytes. For identity outputs, verify the original
   immutable source object. An uncertain PUT allows only read/reconciliation of
   that destination. Do not overwrite conflicts, generate a new object ID, or
   blindly repeat an uncertain write.
5. Only when **all** ordered outputs are durably present and verified, and the
   original trusted execution identity/provenance is durably recoverable, can a
   replacement finish outcome reconciliation without transformation. A
   storage-only digest or untrusted decoder report is insufficient. The current
   generic receipt fields bind identity but do not yet persist target process
   provenance; that gap blocks target implementation acceptance.
6. Original outcome settlement is immutable. Lost settlement response recovers
   the original saved outcome. Existing live receipt replay is distinct from
   permission to write new output or settle after a deadline.

| Crash point                                                           | Permitted recovery                                                                                                                                          |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Issued, before complete validated output                              | Original status only; no transform retry or refund.                                                                                                         |
| Complete output in RAM, before durable registration                   | Surviving known-output token may settle within its original deadlines. After process loss, hold.                                                            |
| Manifest registered, some destination bytes missing                   | Surviving worker with exact bytes may use only positively authorized storage reconciliation. Replacement cannot regenerate missing transformed bytes; hold. |
| Every destination exists, execution provenance missing or conflicting | Hold; receipt shape and hashes cannot manufacture provenance.                                                                                               |
| Complete registered bytes and trusted execution evidence survive      | Replacement validates original live scope, exact registered identities and all bytes, then reconciles outcome only within original authority/deadlines.     |
| Outcome already committed                                             | Read exact original outcome under live ownership/erasure checks; no new execution.                                                                          |

A durable recovery entry point must remain separate from the fresh runtime path.
It must not deserialize a stored grant into execution authority or accept an
arbitrary replacement-worker output manifest. Its consuming provenance format
needs review with the concrete executable bundle; no new fields or SQL objects
are approved here. A lost complete output can remain permanently unrecoverable
for this operation. Availability is not a reason to execute it again.

Retirement marks all registered sources/destinations before private evidence
cascade. Conditional create is not an erasure fence: already issued write
capabilities may arrive late. The broker must recheck the original terminal
fence before signing, limit capability lifetime to the original deadline and
retain cleanup ownership through the final possible late write. Repeated cleanup
reconciles those fixed destinations only; it must not make them reusable.
Physical deletion need not finish before expiry, but logical retirement must
survive expiry/process loss. No scheduled hosted cleanup is installed here.

## Resource and lifetime feasibility

The proposed OS mechanism is unified Linux cgroup v2 with no child delegation,
no realtime scheduling privilege, no escape to another cgroup and no huge-page
allocation. Aggregate coordinator/inspector/decoder accounting is required;
separate child ceilings cannot substitute for the whole-operation envelope.
`memory.max` bounds accounted memory with documented temporary overshoot;
`memory.swap.max=0` prevents swap allowance. `cpu.max` limits CPU bandwidth per
period, not cumulative CPU milliseconds. `pids.max` and cgroup-wide killing
bound descendants; populated-state observation does not itself reap zombies.
These distinctions come from the
[Linux controller contract](https://docs.kernel.org/admin-guide/cgroup-v2.html).

Use a service-manager-owned operation lifetime with `Restart=no`, bounded
startup/stop, `KillMode=control-group` and an absolute remaining-runtime budget.
The manager must observe main-process death and stop descendants, then verify
absence/reaping before accepting completion. `RuntimeMaxSec` and startup/stop
limits must cover different service phases; timeout extension and notification
access from untrusted children are forbidden. See the authoritative
[service lifecycle](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.service.xml)
and
[termination](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.kill.xml)
contracts. This design is not evidence that a particular kernel/manager provides
a hard real-time kill deadline. An unkillable or unobserved process means
unknown execution and no acceptance.

Cumulative profile `cpu_ms` needs a qualified enforcement design including
scheduler periods and stop overshoot; RSS sampling and `cpu.max` alone fail it.
`heap_bytes` cannot silently become V8 old-space or decoder-only RSS. Whole
operation native allocations, frame surfaces, compressed snapshots, output
copies and broker buffers must fit the accepted interpretation. FFmpeg's
`max_alloc` limits a single allocation, not aggregate heap; allowlisted
protocols and disabled network components are additional restrictions, not OS
isolation. See [FFmpeg options](https://ffmpeg.org/ffmpeg.html) and
[protocol selection](https://ffmpeg.org/ffmpeg-protocols.html).

The generic source-plan maxima are not an admissible profile cohort. In
`mediaPreparationProfile.ts`, video profiles permit only raw-video, video-frame
and optionally one video-audio role; photo/recording roles cannot be mixed into
them. Legal maximum byte envelopes, before stricter saved profile limits, are:

| Profile family          | Maximum role cohort                                               | Compressed source bytes |
| ----------------------- | ----------------------------------------------------------------- | ----------------------- |
| Photo plus audio        | Five photos totaling 5 MiB plus two 2,700,000-byte recordings     | 10,642,880              |
| Video frames            | One 12,582,912-byte clip plus five supplied frames totaling 5 MiB | 17,825,792              |
| Video frames plus audio | The preceding cohort plus one 2,700,000-byte companion WAV        | 20,525,792              |

All are below the profile schema's 20,971,520-byte aggregate ceiling. The
hypothetical eight-source/23,225,792-byte combination is blocked by both role
compatibility and that ceiling; it is not a target sizing envelope or an
accepted fixture. Supporting it would require a separately reviewed product,
schema and profile expansion. No such expansion is proposed. Decoded expansion,
output and overlapping copies still need their own bounds. Local 64,044-byte WAV
execution cannot qualify these complete legal cohorts.

Let `E` be original expiry, `N` current server time, `W` saved qualified cohort
preparation wall time and `H` saved handoff total. Existing qualified SQL issue
requires `N + W + 45,000 + H < E`; it sets execution to `N + W + 5,000`,
registration to `N + W + 10,000`, and outcome to `N + W + 45,000`. `E` is at
most original creation plus 300,000ms, never renewed. The runtime also uses its
conservative local budget checks and subtracts transport elapsed time.

Therefore source reads, structural inspection and source settlement must finish
before that issue inequality is evaluated. `W` must include every granted cohort
item, decoding, verification, response framing and process cleanup; registration
has its fixed subsequent window; output PUT/readback and outcome settlement use
only their original windows. Handoff/funding cannot borrow from expired
preparation time. These are admission equations, **not measured tail budgets**.
No numeric target profile is proposed until the complete cohort fits both these
equations and enforceable CPU/memory semantics. Tight observed local transfer
margins remain observed results, not proof of target headroom.

## Modality feasibility and saved compatibility

| Source                         | Proposed consuming policy                                                                                                                                                                     | Unresolved acceptance                                                                                                                                                                                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WAV recording                  | Reuse exact archived structural and audio transform semantics on the verified private bytes, with Linux executable provenance.                                                                | Full 2.7 MB inputs, two-source/cohort load, hard budgets and target output equality. The Darwin executable identity cannot be reused.                                                                                      |
| JPEG/PNG/WebP photo            | Decode fully under the granted sandbox to validate format and expansion; preserve original bytes for `identity_v1`. Focus is existing bounded metadata, not permission to recrop or reencode. | Dimensions, pixel/plane/frame count, color/orientation and malformed/animated-file policy must be fixed in a concrete decoder profile. MIME/signature is insufficient.                                                     |
| HEIC/HEIF photo                | Isolated libheif/libde265 closure; preserve original identity bytes. Reject unavailable codec/unsupported multi-image semantics before any admission.                                         | Complete container item/grid/auxiliary-image policy, expansion limits, provider compatibility and finite dependency closure. Proposed HEVC support does not cover every HEIF encoding.                                     |
| Raw MP4                        | Validate declared track structure before grant; full bounded decoding after grant for accepted codecs. Retain original raw clip; current raw-video output remains null.                       | Duration/frame expansion, track/timebase/PTS, edits, orientation/color and audio layout policy. Container plausibility does not qualify decoding.                                                                          |
| Video frames and companion WAV | Retain current supplied objects and indices as saved facts. Do not claim their bytes were extracted by this proposed decoder.                                                                 | `video_frame_v1` integers do not define timestamp selection or deterministic encoding; supplied `video_audio` is not trusted extraction. Neither equality nor perceptual similarity can infer a missing extraction recipe. |

For new raw-clip derivation, the consuming recipe must bind original clip,
selected tracks, rational timebase and presentation timestamps, deterministic
frame order, orientation/color/crop and exact audio extraction/resampling. That
requires a separately reviewed compatibility contract if existing saved schemas
cannot express it. Do not silently reinterpret existing `video_frame_v1` or
replace companion bytes. Historical/admitted records retain exact recovery; new
requests needing unqualified derivation remain blocked with media retained. This
proposal does not enable video publication/review.

## Proposed consuming agreement, revision 2

The following decisions close the local design questions for independent/IC-1
review. They are proposed requirements, not edits to effective schemas or an
installation agreement. Failure to prove any requirement rejects the target; no
partial modality qualification enables ordinary access.

### Trusted evidence and ordering

The proposed trusted attester is the **per-installation preparation
supervisor**, a measured host component outside decoder namespaces. It owns
process creation, immutable input descriptors, bundle resolution, output
verification and lifecycle observations. Its installation-bound signing key is
inaccessible to decoders and the unprivileged coordinator. The existing trusted
backend validates its signature against the exact saved installation's
public-key identity, original scope and deadlines. This is proposed authority
requiring an installation/key contract; generic service-role access or
decoder-provided JSON is not an attester. No key is created or logged in this
work.

The supervisor's success statement must bind the original assignment/source
receipt/grant digests, immutable bundle and sandbox-policy digests, complete
ordered consumed input and produced output tuples/options, fresh invocation
identity, measured start/finish, clean exit, bounded response completion,
aggregate resource counters and termination/reap evidence. It signs only after
validating all output and observing required process completion. It must not
sign a success report supplied by the decoder without these observations.
Resource numbers do not prove the sandbox policy worked; target qualification of
that policy and its fixed enforcement margin is separately mandatory.

Proposed durable ordering is **one atomic private registration** of the exact
output manifest, resolved destination IDs and verified supervisor statement,
before any external output PUT. Existing registration already owns the manifest
and destinations; the new fact is authenticated execution provenance. It needs a
versioned private contract and explicit migration/SQL-parity review because
current registration has no such field. This proposal approves no field names,
new table, caller or migration. Existing historical receipts keep their original
version and recovery semantics; they never acquire new provenance by inference.

A positive registration response permits only the existing fixed destinations.
Unknown registration recovers original status. The surviving worker may
reconcile identical registration with exact bytes; after its death, absent
registration means hold. A registered statement with missing output bytes still
means hold for a replacement. If registration and all bytes survive, a
replacement verifies the authenticated statement, original
installation/source/grant bindings, exact manifest/resolved mapping, live scope
and direct complete byte reads. It may settle the outcome only within the
original remaining deadline. It has no fresh-execution capability, signing key
or authority to change a tuple.

After registration/write/outcome deadlines, recovery is **read-only** for
existing proof and bytes: return an already committed live outcome, or retain
recovery-needed/terminal status. Do not introduce a success outcome after its
fresh-settlement deadline, even if every object is found later. Cleanup may
continue against retired fixed IDs; it cannot restore admission or funding.

### Supervisor launch admission and signed statement

Choose **durable consume-before-launch plus a non-reconnectable original
coordinator channel**. A signed SQL grant, matching digest, status response or
retained statement is never itself a launch credential. The service manager
starts one measured coordinator with one private socketpair to the supervisor;
no public socket accepts arbitrary grant payloads. Before SQL issue, the
supervisor durably binds a single reservation to the original owner/scan,
assignment/profile/installation digest and that channel's random invocation ID.
Capacity reservation is not execution permission. A second channel for that
operation, including after restart, cannot take over a grant-bearing
reservation.

Only the original coordinator's direct positively received issue response may
cross that channel. Supervisor validates the full immutable grant and receipt
against the reserved scope, current original deadlines and saved installed
bundle. It atomically records **consumed** in its protected durable journal,
flushes the record and containing storage metadata, then launches the cohort.
Duplicate messages find consumed and are rejected; no acknowledgement, PID or
child result can reset it. The journal stores only bounded identity/control
metadata, no media, bearer credentials or raw responses. Its invocation ID is
correlation, not a replayable capability. The permanent consumed fence is keyed
also by original logical operation, so a new grant ID cannot bypass it.

A supervisor restart must consult this journal before accepting any operation;
unknown/corrupt/unavailable journal state disables fresh launch. A prepared
reservation whose original channel was lost is abandoned/held, not reattached.
The SQL owner remains the sole issuer; the journal only narrows local execution
and cannot authorize a grant absent from SQL. These durable launch/retirement
records require target filesystem crash-consistency evidence. They do not add a
second funding/analysis lifecycle or supply execution authority to replacement
workers.

| Launch failure                              | Required behavior                                                                                                                |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Original SQL reply lost before channel send | Supervisor never launches from recovered status; operation holds.                                                                |
| Journal consume write uncertain             | No launch until the original process positively proves that exact durable consume; if it dies or loses the channel, hold.        |
| Consume durable, crash before spawn         | Slot remains consumed; zero-run operation holds forever under that identity.                                                     |
| Spawn happens, launch acknowledgement lost  | Original invocation may finish; caller cannot send another launch. Recover only original result/statement/status.                |
| Coordinator dies after spawn                | Manager stops its operation unit; supervisor must not sign success without completed cohort observations. No replacement launch. |
| Supervisor/manager restart or journal loss  | No reattachment or execution replay. Unknown state holds; surviving original terminal proof may be recovered read-only.          |

The supervisor signs **after every inspector/decoder/transform child has exited,
its complete bounded output is validated, and those children are reaped with no
remaining untrusted descendants**. The trusted coordinator/retainer remains
alive to register provenance and write/read back output. Requiring its exit
before registration would be circular. Final unit/coordinator/retainer
termination and buffer disposal are later cleanup facts, not falsely included in
the earlier success statement. Resource counters in that statement end at cohort
completion; later retention/registration resources remain enforced by the
operation unit and are not retroactively claimed as measured by the earlier
statement. Inspection observations bind the same source snapshots; structural
inspection is never launch authority for transformation.

Proposed statement format is closed canonical JSON using the repository's
`initialCanonicalText` rules and bounded safe integers/decimal strings, with
explicit version, original invocation/scope/grant/receipt identities, bundle and
sandbox identities, ordered input/output/options and cohort terminal/resource
facts. Unknown/duplicate fields, duplicate JSON keys, noncanonical numbers,
ambiguous ordinals and trailing bytes reject before signature acceptance. The
signature is Ed25519 over UTF-8 domain
`merian.initial-preparation.target-statement.v1` followed by one newline and
canonical statement bytes; encode the 64-byte signature as canonical unpadded
base64url. Public keys are exact 32-byte values resolved only from the saved
installation's immutable key identity, never from a caller-supplied key or
mutable latest-key lookup. Revocation blocks fresh acceptance; historical
statement recovery still requires its original live-scope/erasure policy and
must not authorize execution. Key rotation needs a new installation identity,
not rewriting saved operations.

The proposed version mapping is a new private registration/status/outcome
contract carrying this closed statement plus installation-key reference, bound
atomically to the original output registration; the profile/bundle contract must
name the corresponding verifier and sandbox. Existing versions remain unchanged
and cannot claim this statement. Exact schema field allocation, canonical
vectors, private privilege/lock inventory and generated consumers belong
together in a later independently reviewed implementation agreement. No
public/native DTO, new key or SQL migration is created by this specification.

### OS isolation, main process and admission capacity

Propose one systemd `Type=exec`, `ExitType=main`, `Restart=no` service per
original operation. The executable main PID is the trusted operation
coordinator; all its helpers are descendants in that unit. Main-PID exit must
transition the unit to stop and kill remaining descendants via
`KillMode=control-group`. Do not use `RemainAfterExit`, daemonizing wrappers,
notify-based timeout extension or an independently surviving decoder scope. A
host manager/supervisor outside the unit observes unit termination and reaps
adopted children. Manager failure or missing terminal observations cannot yield
a signed success.

For the proposed Linux image, require mount, PID, IPC, UTS and network
namespaces for untrusted processes; empty network namespace; no host sockets;
distinct operation UID; dropped capability bounding/ambient sets;
`no_new_privs`; read-only measured bundle; empty read-only root except bounded
private scratch; no host home, secrets, proc environment of other processes or
service-manager socket. Bind only sealed immutable source descriptors and
bounded result/control pipes. Mark every other inherited descriptor
close-on-exec. Output buffers and scratch are capped independently of compressed
inputs; core dumps and raw diagnostic logging are disabled. This is a sandbox
specification, not proof that cgroups alone provide it.

A default-deny seccomp policy permits only the measured loader, memory,
clock/signal and descriptor I/O operations needed by each closure. Deny network
socket creation/connect, ptrace, mount/setns/unshare, bpf, perf, module loading,
keyring and privilege/scheduler changes. Restrict clone to necessary threads; no
arbitrary exec, subprocess discovery or executable writable memory unless
explicitly justified for the Deno runtime in its separate sandbox. Native
libraries receive no Deno run/FFI permission. The exact syscall policy must be
retained with the executable closure and qualified on the named kernel; a prose
allowlist is not an installed seccomp program.

Proposed capacity policy: one active operation per worker slot, no queued grant,
and no concurrent decode of different cohort items. Reserve the whole slot,
source/output buffer envelope and broker capacity before issue; release only
after terminal process observations and byte ownership transfer. Structural
inspection has a 30,000ms full-cohort deadline, inclusive of source reads and
settlement, and separate resource accounting; budget failure before issue holds.
An unavailable slot rejects/holds before grant, with no deadline renewal.

All per-operation broker buffers, source snapshots, metadata and decoder memory
count inside the aggregate limit, including buffers owned by a restricted helper
outside the decoder namespace. The shared manager's bounded fixed overhead and
maximum number of worker slots require a separate host capacity reservation; it
cannot hide unbounded per-operation buffers. No decoder can migrate tasks or
modify cgroup controllers. CPU enforcement must cover all these charged helpers.

Proposed qualification ceilings are 1 GiB accounted operation memory (swap
zero), 60,000ms cumulative CPU and 60,000ms granted cohort wall time. These are
candidate ceilings, not accepted profile values: scheduler/kill overshoot must
fit a separately measured reserve below them, and native allocations must
satisfy the agreed `heap_bytes` interpretation. Current per-role resource sums
must also fit the schema and aggregate. Failure to fit forbids installation; it
does not raise a saved limit. Startup, hashing, framing and cleanup consume
these windows.

The proposed bundle manifest is closed and canonical: platform/ABI and runtime,
ordered regular-file paths with length/SHA256/mode, exact loader/shared-library
closure and search paths, compiler/linker flags and source/signature provenance,
entry points and fixed argv/environment, and digests of the sandbox policy,
media recipe and qualification vectors. Reject symlinks, writable executable
files, undeclared loads/plugins and mutable package resolution. The installation
binds a domain-separated digest of this entire manifest; each launch verifies it
before consuming authority. Actual file hashes cannot be invented before a
retained build. Existing artifact fields cannot silently change from one Deno
artifact to this native closure; a versioned private bundle consumer is
required.

Proposed sandbox-policy manifest binds namespace/capability/descriptor/seccomp
rules, kernel/controller/service-manager compatibility, aggregate and child
limits, main-PID/termination configuration, fixed concurrency and every buffer
owner. For each qualified resource ceiling `B`, accepted work must stop at
`B - R`, where `R` covers measured worst-case scheduling, controller-period,
termination, reap and final-copy overhead under the qualified host load. A
missing/nonfinite reserve, scope-excluded broker allocation or overshoot beyond
`B` fails qualification. No sampled maximum may be called a hard reserve. A
candidate cumulative-CPU limiter must combine kernel bandwidth control with
bounded supervisor enforcement and prove the complete accounting interval;
without such proof the proposed 60,000ms profile is unqualified. The exact
syscall program and binary closure are required build outputs, not assumed from
these design requirements.

### Late writes and retirement

The proposed storage broker uses conditional single-object PUT only, no
multipart uploads and no untracked upload session. Before any request it records
the original registered destination as in flight under the permanent operation
fence, with the backend's finite request-body and completion deadline if one
exists. Local timeout or signed-URL expiry does not prove remote abort: an
accepted request might commit later. Unknown completion remains in flight until
the backend provides an authoritative terminal commit/abort result or a
qualified hard upper completion bound has elapsed and reconciliation completes.

Cancellation/expiry marks the fence retired before deleting private evidence,
revokes new signing, and continuously reconciles/deletes any late object at the
same registered key. Cleanup bookkeeping may become quiescent only after all
issued capabilities have expired, all accepted/in-flight writes have a proven
terminal state or elapsed qualified completion bound, and final bounded direct
reads/deletes confirm absence. The permanent content-free retirement fence never
clears. If this storage backend supplies no such completion guarantee, retain
the tombstone and continuing cleanup obligation indefinitely; do not claim
finite physical-erasure completion or qualify that backend for a finite erasure
SLA. This is a concrete acceptance condition for the proposed adapter, not a
request to exercise hosted storage.

### Proposed media acceptance and derivation

Fresh proposed profiles have the following explicit policy. These limits are
design choices to test against native capture requirements and the exact decoder
closure; they do not silently change current saved inputs. Inputs beyond them
remain retained and blocked until a compatible profile or explicit remediation
is available. No clipping, dropping extra images/tracks or text-only fallback.

- Still images: exactly one presentation image, at most 8,388,608 pixels, each
  axis at most 8,192, at most four output planes/channels at 16 bits per sample,
  at most 64 MiB decoded presentation storage. Reject animation, image
  sequences, multiple primary presentations, unsupported auxiliary/depth/gain
  maps and nonidentity container crops. A tiled HEIF grid is one presentation
  only if aggregate decoded tiles and composed surface fit the same bounded
  envelope. JPEG/PNG/WebP preserve identity bytes. Orientation is retained
  metadata for identity output; no undeclared rotation or color conversion is
  applied.
- MP4: exactly one non-encrypted H.264 or HEVC video track, optionally one AAC
  or PCM audio track, no alternate/external tracks, fragmentation or edit list.
  Duration greater than zero and at most 30 seconds; at most 1,800 decoded
  frames; at most 3,840 by 2,160 per frame; 8/10-bit 4:2:0 only. Reject missing,
  duplicate or nonmonotonic presentation timestamps, unsupported color/HDR
  metadata, matrices other than orthogonal rotation, and unknown layouts.
- Audio: at most two channels, at most 48 kHz for proposed extracted PCM, at
  most 30 seconds, signed 16-bit little-endian output; then the exact archived
  `initial_audio_v1` transform and explicit short-context policy. Standalone WAV
  continues the archived parser/transform's accepted format checks and 2.7 MB
  source ceiling; it is not silently converted to the extracted-audio policy.

Proposed **new derivation recipe**, never retrofitted onto `video_frame_v1`:
select the sole video track; use its integer PTS and rational timebase. Let `P0`
be its first presented PTS and `D` the greatest accepted frame-end timestamp
minus `P0`, using strictly positive sample duration in that track's rational
timebase. Missing/ambiguous durations or discontinuities reject; do not
substitute container duration. Normalize video timestamps by `P0`. For each
rational target `(2k+1)D/10`, `k=0..4`, choose the first presented frame at or
after the target; if none exists choose the last presented frame. Iterate
targets in order, append a frame only on its first selected original sample
index, and collapse repeated indices without renumbering their original
identity. This produces one to five distinct outputs, with separate contiguous
output ordinals; no interpolation, duplicate images or synthetic padding.
Duplicate PTS are rejected by the track policy before selection.

Apply the single orthogonal display rotation, no crop, fixed SDR BT.709 matrix
and transfer interpretation, and full-range RGB8 PNG encoding. Require explicit
supported SDR color metadata; do not guess missing metadata or tone-map HDR.
Propose Paeth row filter, zlib compression level 6, single-threaded encoding, no
ancillary metadata other than the fixed color identification, and pinned integer
conversion/rounding behavior. The recipe records track, timebase, original
PTS/sample index, rotation, color and encoder options with each exact output
digest. The retained library/toolchain closure and golden vectors must establish
byte determinism; specifying options alone does not do so.

If audio exists, convert its PTS and duration exactly to the common rational
presentation timeline. Require its first presented time to equal `P0` exactly;
reject nonzero offsets, edit compensation, gaps, discontinuities or coverage
shorter than `D` rather than inventing silence. Decode over `[P0,P0+D)`,
normalize by `P0`, preserve mono/stereo channel order, and convert to 48 kHz
PCM16 WAV. Propose libswresample engine `swr`, filter size 32, phase shift 10,
`linear_interp=0`, `exact_rational=1`, cutoff 0.97, Kaiser filter with beta 9,
internal sample format planar double, no dither, no async timestamp compensation
and one thread, using the explicitly named
[resampler controls](https://ffmpeg.org/ffmpeg-resampler.html). Retain exactly
`floor(D*48000)` interleaved output frames, reject insufficient decoded
coverage, and write a canonical PCM WAV header with no ancillary metadata. Then
run the archived transform at the saved target rate with its explicit
short-context option. No audio track yields no companion; a supplied companion
is never treated as this generated output. Generated frames and WAV must fit the
same 5 MiB aggregate image and 2.7 MB audio limits; oversized results hold
without lower-quality retry. Raw clip export remains original bytes.

This new recipe needs a distinct source-plan/derivation version and consuming
native agreement because current schemas require supplied frame/audio sources
and lack this recipe. The explicit encoding/resampling choices above must be
bound into the retained native bundle and checked for support, not replaced by
library defaults. Until that contract exists, existing supplied frames/audio
keep their saved identities and cannot be advertised as trusted raw-clip
extraction. Compatibility tests must cover both versions and prohibit automatic
rewriting of queued drafts.

### Current native compatibility findings

Read-only source evidence is retained in
`.artifacts/initial-media-structure/target-native-compatibility-v1.json` (15
unchanged source files, no native build or device claim). For stills,
`CameraSessionController.capturePhoto` requests maximum supported photo
dimensions and optional depth. `CaptureScanStillMediaPreparer` and
`ImagePreparationPolicy` derive 1,024/768 inference and 2,048 display images,
square-cropped and WebP/JPEG encoded by `ImageCropProcessor`. This does not
establish the proposed 8-megapixel/8,192-axis identity-byte policy. A native
capture-to-retained-raw handoff must explicitly distinguish originals from these
derivatives; neither may silently substitute for the other.

Video recording's `CameraVideoRecordingService` applies caller duration and
`ScanMediaPayloadPolicy`'s 12 MiB bound, available rotation and automatic
stabilization. Playback compression uses AVFoundation presets and can fall back
to original bytes. Neither proves the proposed 30-second/4K/SDR/no-edit-list
policy. Those hypotheses need compatibility approval with a new profile/version.

Read-only tracing of the current checkout finds a **different** video recipe.
`CaptureScanVideoFrameSamplingPolicy` in
`apps/ios/Merian/Features/Capture/Scan/Models/CaptureScanMediaModels.swift` uses
normalized sampling positions 10% through 90% (numerically the same five
midpoints for five samples), but does not bind exact PTS/sample identities or
require all extractions to succeed.
`CaptureScanVideoMediaPreparer.prepareFrames` applies the preferred track
transform, caps generation at 2,048 pixels, crops square and encodes WebP/JPEG;
`ImagePreparationPolicy`/`ImageCropProcessor` subsequently downscale and
crop/reencode. These are not the proposed no-crop PNG bytes, even when their
sampling targets coincide.

`CaptureScanVideoAudioExtractor` selects the first audio track and produces mono
44.1 kHz PCM16 WAV; extraction is optional and failure may yield no companion.
That does not implement the proposed strict common timeline, 48 kHz mono/stereo
recipe or fail-closed track policy. AVFoundation capture/export presets are not
source-level proof of the proposed codec, chroma, SDR, timestamp/edit-list or
expansion constraints. Do not call the proposed limits accepted native product
limits or remove currently supported media based on this document.

The proposed recipe therefore cannot be deployed as a transparent validator for
existing supplied frame/audio objects. It needs a separately versioned
functional native/source-plan handoff before fresh use; old queued drafts must
keep their saved operations and require explicit remediation when not yet
admitted. Historical admitted recovery remains exact. This functional
compatibility requirement is separate from the capture-tools visual refactor,
whose ownership and pending final approval do not change.

### Required facts and qualification cases

| Requirement                               | Existing field/owner                                                           | Proposed new fact or target proof                                                                                       |
| ----------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Original identity/options/deadlines       | Candidate, assignment, source receipt, grant, manifest, resolved/outcome chain | None merely for choosing a host.                                                                                        |
| Whole executable closure                  | Profile artifact/identity and installation digests                             | Finite native bundle, toolchain/syscall/sandbox policy manifest; versioned interpretation before schema implementation. |
| Who actually executed and retained output | Current immutable registration and destination owners                          | Authenticated supervisor statement atomically bound to registration; process provenance is not a decoder assertion.     |
| Replacement recovery                      | Existing status and immutable outcome; process-local known-output token        | Explicit provenance-aware durable recovery adapter, unable to call runtime; no new execution lifecycle.                 |
| Hard resource and death controls          | Declared role/cohort limits only                                               | Effective target controller/sandbox settings, all-helper accounting, main-PID death and bounded shutdown evidence.      |
| Raw video derivation                      | Current supplied clip/frame/audio indices                                      | Distinct versioned recipe, track/PTS/rotation/color/audio bindings and native handoff; preserve old records.            |
| Terminal storage cleanup                  | Existing registered IDs and permanent erasure fences                           | Backend in-flight completion semantics and retained late-write obligations; no expiry-only proof.                       |

| Future qualification case                                        | Required observation; never a retry instruction                                                                       |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Crash before/after issue response                                | Issued fence survives; zero invocation after uncertain issue; no regrant.                                             |
| Death during inspection versus transform                         | Inspection cannot transform; granted cohort starts once; manager kills/reaps all helpers and missing proof holds.     |
| Death before/after atomic provenance registration                | No partial authoritative registration; absent or conflicting statement cannot settle.                                 |
| Crash after one of several PUTs                                  | Exact IDs and partial byte state survive; missing transformed bytes cannot be recreated.                              |
| Every byte survives, outcome acknowledgement lost                | Authenticated original statement and direct complete reads permit only original settlement/replay as deadlines allow. |
| Recovery after original outcome deadline                         | Already committed live outcome may replay; no new outcome or write.                                                   |
| Main PID SIGKILL, fork escape, memory/CPU pressure               | Manager remains owner; isolation/aggregate bounds and termination reserve hold, or candidate fails.                   |
| Upload begins before URL expiry and commits after retirement     | Fixed key stays tombstoned and deletion reconciles; no premature cleanup retirement.                                  |
| Profile maxima, animation/grid/track bombs, malformed timestamps | Full legal cohort fits all bounds or fails closed without reduced-quality retry or partial admission.                 |
| New recipe versus old supplied companions                        | Exact bytes/options and version ownership remain distinct; no synthetic provenance for old inputs.                    |

## Qualification boundary and next decision

The local design identifies a candidate and rejects its use with current saved
qualification. Remaining evidence is concrete: exact Linux image/kernel/service
manager and executable/toolchain closure, decoder compatibility and full ingress
vectors, enforceable CPU/native-memory and abrupt-parent-death results, the
original-preparation signer/immutability/erasure contract, recoverable execution
provenance and crash-point tests, and full-cohort/tail timing inside the
existing lifetime. A receipt-format change alone cannot satisfy these rows.

Independent and IC-1 review must decide whether this composition is the next
feasible direction and which local contract work remains before implementation.
No generic environment-variable question or duplicate local WAV/SQL test run is
needed. A named target and separately named authorization are required for any
installation or target/hosted execution; this document is the reviewable
proposal for that later decision, not that authorization. Keep existing device
questions and results, capture visual ownership and the paused hardening
automation intact. No push, deployment, scheduling, activation, provider call or
refund is authorized.
