# Original preparation adapter: concrete local protocol agreement, revision 3

Baseline: runtime `41823294`, dependency correction `e0893e26`. Independent and
IC-1 review accepted this bounded implementation agreement at proposal SHA
`253b0821390b48397492dc3cb2f8a59b048e2569ed10bedf9d24af441267f4e9`. Earlier
proposal v1/v2 decisions are historical. Exact-source launch reviews are clear
and local executable qualification passes. Final independent and IC-1 evidence
review is required before the local checkpoint commit; its decisions and exact
commit identity belong in `owner-final-reviews.json` and
`owner-local-checkpoint.json` alongside the evidence below. No registry or
production eligibility change follows. The original dependency is recorded in
the
[media-validation inventory](initial-media-structure-attestation-2026-10-13.md).

## Scope and fixed fixture authority

The composition is a local synthetic qualification fixture under
`scripts/initial-preparation`, not an installed runtime adapter. The existing
`runInitialPreparation` remains the operation owner. Extend its private runtime
argument with independently canonical-cloned original `grant` and
`source_verification`, deeply frozen before entering the dependency. Keep source
bytes accessible only through its defensive `read(ordinal)`. No public DTO, SQL
receipt, migration, live route, installation or provider capability changes. The
callback is still called solely at the existing fresh-grant site. JSON
possession is not execution authority.

No existing media-lifecycle fixture or saved profile exactly maps to the real
artifact. Create a new explicitly synthetic test vector, never modify/relabel an
existing saved profile. The fixed test profile is `local_validated_wav_fixture`
version 1, `identify-multimodal`, `multimodal_audio_v1`, Deno 2.9.4,
`darwin_arm64`, ABI `local_synthetic_only`, protocol 2. Its artifact is the
registered 16,647-byte
`cf2df93f4bdcdea853ae7d9c0e1432149cec470270880ca87dcb3b43f51a2f64` from
`validated-wav-darwin-arm64-v1`. Registry entries and local preparation
reference remain unchanged and always Edge-ineligible.

The test identities are derived, not arbitrary placeholders: `source` is SHA256
of the fixed registry entry's canonical bytes; `validator` is its existing
validator SHA256; `transform` is SHA256 of canonical ordered registry input
records for the six existing transform modules; `configuration` is the original
registry configuration digest. The fixture qualification references the existing
validated artifact receipt, existing harness digest and bootstrap source anchor;
new integration evidence separately binds the changed coordinator/harness
source. These are local test references, never a claim that a production profile
has passed qualification. Review the actual generated vector and all digest
domains with the implementation before any process run.

Exactly one `recording` rule accepts `audio/wav`, `initial_audio_v1`, target
16000, preservation false, clip/frame indices null, max count/max sources 1.
Source limit is 192,000 bytes, output limit 192,000 bytes and wall limit
15,000ms. Required numeric CPU/heap fields are frozen declared fixture inputs
(15,000ms, 268,435,456 bytes), **not enforced hard-resource guarantees**.
Evidence must say `resource_status: sampled_local_only` and explicitly leave
CPU/native heap qualification open. No installer, production selector or SQL
test installs this fixture. Ordinary/profile-selected execution is rejected
before issue.

A fixed synthetic 32kHz PCM16 mono WAV with 32,000 frames and amplitude 8192 is
constructed independently by the trusted parent and Deno fixture. Scan, owner,
original object, grant and output IDs are fixed synthetic IDs. Source, profile
and assignment/source receipt digests are independently verified by both sides.
Tests with malformed/mutated inputs are separate fixed cases; no command-line
operation input or arbitrary caller data reaches this fixture.

Before `runInitialPreparation` can reach issue, the fixture composition checks
exact test identity/profile, source mapping/order/options, actual byte count,
canonical base64 length <=256,000 and unchanged inner request <=262,144 bytes.
It also verifies the pinned structural validator and uses that structural-only
function for `inspectSource`. It never calls the combined executable pre-grant.
The parent verifies executable/toolchain/input availability before starting the
fixture. Oversize, mixed, unknown or ordinary tuples cannot issue a local grant.

## Closed pipe exchange

Use inherited anonymous stdin/stdout pipes only. No socket, listening server,
URL, path selector, reconnect, ambient lookup or filesystem mailbox. The Python
harness owns both coordinator and transform child lifetimes; neither child can
spawn another process. Do not duplicate `artifact.py.run` in a second loop.
Extend that existing bounded selector owner with an optional fixed two-child
exchange mode, used only by this fixture. Existing standalone callers retain
their current EOF/input semantics. This is **one non-reentrant selector loop**,
not a callback recursively invoking `run`. Trusted composition supplies the
verified immutable transform command/input paths before coordinator spawn. The
child cannot supply an executable/command or cause further children.

The same selector registers coordinator and transform pipes with distinct child
and stream identities. A complete authorized execution frame consumes the slot
and starts the one transform through the same existing spawn/setup/cleanup
owner. While the transform runs or exits, every selector tick continues draining
both children's stdout/stderr under separate caps, detecting a second
coordinator frame, checking abort/EOF/parent deadlines, and sampling RSS for
both process groups with the same bounded `ps` call. Per-child input offsets and
output buffers are separate and never recursively reused. The coordinator may
emit no frame after its execute frame until the validated response is written;
any second frame, output excess or coordinator RSS violation kills both groups.
Neither process group may exceed the existing sampled 256MiB ceiling; aggregate
RSS is also recorded without calling it a hard memory cap.

Transform exit triggers nonblocking `poll`/pipe draining and group kill/reap
progress serviced by this same loop, while coordinator controls remain active.
There is no blocking nested `wait(5)` with an active unchecked sibling. After
both groups are killed, bounded terminal waits may use only the single remaining
absolute cleanup budget. All partial spawn/setup failures enter one cleanup
owner for both children. No worker thread, background reaper or unsupervised
process loop is added.

The coordinator emits exactly one compact canonical JSON line for execution:

```
{"version":1,"kind":"execute","scan_id":"<fixed>","assignment_digest":"<sha256>","grant_id":"<fixed>","source_digest":"<sha256>","profile_digest":"<sha256>","ordinal":0,"request":{"version":2,"operation":"validated_wav16k","base64":"<canonical>","preserve_source_when_trimmed_too_short":false}}
```

All outer fields must exactly match the independently constructed original
fixture grant/source/profile before any transform spawn. Frame limit 280,000
bytes including LF; no duplicate keys, whitespace variants, extra/missing/null
fields, BOM or alternate encodings. The inner request is emitted with the
artifact's existing four-field order and no LF, without outer correlation
fields. Verify the decoded bytes against the trusted source count/digest, not
only JSON.

The harness exchange starts `unused`, transitions atomically to `consumed`
before spawning, and remains consumed for every return, exception, timeout,
cancellation and broken pipe. Duplicate/concurrent/second frames are fatal;
there is no reset/reconnect path. One fixture process owns one operation. Replay
cases execute the same owner's original status/outcome path and emit no
execution frame. A fresh fixture case has a distinct synthetic operation; it is
not a retry of an unknown case.

Success response has exactly `version:1`, `kind:"prepared"`, the same
`grant_id`, `source_digest`, `ordinal:0`, and `answer` containing the unchanged
nine-field artifact response (version, operation, preservation, input count/SHA,
output count/SHA, base64, complete). Stage response has exactly `version:1`,
`kind:"rejected"`, `grant_id`, `source_digest`, `ordinal:0`, and
`stage:"validation"|"transform"`. No arbitrary stderr/error text crosses the
bridge. Any harness/unknown failure closes the response pipe instead of emitting
successful rejection. Response cap 300,000 bytes including LF. Both sides check
complete canonical spelling and all input/output counts/digests, then return
exactly one fresh non-null output copy to the existing owner. No partial array,
extra output, null, alternate ordinal or source identity alias is accepted.

The coordinator emits one bounded final scalar summary only after owner return.
Execution frames/raw media/process stdout are never retained as evidence; keep
only case ID, fixed correlation digests, counts, stage classification, outcome,
timing and cleanup facts. The harness must redact captured raw process output
before publishing either success or failure evidence.

## Deadlines, cancellation and cleanup

Cross-process timestamps are never compared. The parent records its own
monotonic anchor **before coordinator spawn**. The fixed synthetic server grant
has execution slack greater than the declared 15s owner runtime window; status
and grant responses remain validated by the real owner. A process scenario
cannot choose a timeout. The parent grants no more than 15s total from its
earlier anchor, which conservatively precedes the owner's runtime window.

Use one inclusive parent timeline: active coordinator/transform work, response
validation and delivery stop by anchor+9s; both groups must be killed/reaped and
confirmed absent by anchor+14s; cache inventory/validation and final scalar
evidence framing must finish by anchor+15s. A transform may start only if it has
positive remaining time before anchor+9s. There is one shared 5s cleanup
reserve, not two serial 5s waits. Any stage exceeding its deadline fails the
case; a return without confirmed group disappearance never qualifies. The
existing standalone single-child path retains its existing semantics and must be
regression tested after the shared loop change.

Immutable source/tool/artifact verification and fixed command construction are
bounded preflight **before** the parent anchor. The measured tree is then locked
for both child lifetimes. Artifact/command bytes cannot be selected or changed
by pipe input. The parent anchor covers spawn, request handling, all RSS probes,
transform work, response checks/delivery, both cleanup phases, bounded cache
inventory/validation and final framing. Every phase checks the same absolute
deadline before and after its bounded operations. Inventory still rejects more
than 128 visited entries, 32 files or 16MiB; do not reset a deadline after reap.
If post-run cache work is late, retain failure evidence without a successful
qualification claim. Local timing is measured qualification, not a hard OS
resource guarantee.

Coordinator exit/EOF, duplicate/flood output, abort, loss of the response pipe,
parent cancellation or active deadline violation immediately closes admission
and signals both groups for cleanup. No late result is delivered to a finished
coordinator. SIGINT/SIGTERM use the same cleanup owner. Uncatchable termination
of the supervising Python harness itself is **not qualified by this local
fixture**; OS-backed parent-death/resource isolation remains a target-runtime
prerequisite. Do not claim local tests establish that guarantee.

Reverify actual regular executable/artifact bytes immediately before spawn,
using fixed owner paths and non-writable measured source trees. Keep replacement
environment, no network/capabilities/imports, private caches, bounded output,
RSS sampling and process-group cleanup. No new process command is provided by
the coordinator. Both existing standalone artifact profiles require executable
regression if their shared process owner changes.

## Negative outcomes and durable chain

Artifact exit 2 is expected structural rejection only with the exact existing
validation diagnostic and empty stdout; exit 3 likewise means known transform
rejection. Preserve that distinction only in synthetic test evidence. The
adapter throws a closed local error to `runInitialPreparation`, whose existing
catch returns `recovery_needed/original_status_required`. It does not create a
terminal receipt, held-success, unused refund or another grant. Malformed
output, all other exits, timeout, cancellation, ambiguous transport and process
failure also require original recovery; none is downgraded to a known negative
outcome.

Successful bytes use the existing original manifest, destination registration,
readback, immutable outcome and settlement-only reconciliation. No schema is
needed merely to qualify this synthetic chain. The evidence establishes trusted
local process composition, not independently durable SQL process attestation.
Provider dispatch remains blocked on full S0; later resource/installed evidence
cannot retroactively relabel this test profile or historical operation.

## Implementation and acceptance boundary

History primary owns all writes. After this agreement closes, implement the
minimal private runtime argument change, fixed local fixture/codec and bounded
existing-process-owner extension, then independent/IC-1 source review **before**
actual executable qualification. Portable owner/bridge tests may run first.
Review exact source closure, fixed commands, cleanup and profile vector before
launch. No source edits during build/execution.

Test fresh once; issued/outcome replay and lost grant reply zero calls; pregrant
structure rejection zero transforms; source/descriptor mutation; wrong identity,
profile, artifact, options, ordinal; missing/extra/malformed/late output;
timeout/cancel/EOF/duplicate; coordinator flood, second frame and RSS violation
while the transform is active; deadline exhaustion during post-reap cache
checks; registration/settlement loss and known-output-only reconciliation.
Preserve original failed evidence. Full affected gates at the coherent
implementation milestone, with shared-checkout limitations explicit. No repeat
unchanged SQL family just for this local protocol change.

Activation disabled, ordinary access nil. No push, install, provider, hosted
mutation, scheduling, device run or distribution. Full photo/audio/video
resource and consuming-byte qualification, original dispatch/result/completion,
native and integrated acceptance remain open before approved version
actions/redesign.

## Local implementation evidence — October 13, 2026

Exact prelaunch source candidate `owner-source-candidate-v1.json` SHA256
`a5032c5fe25b3456e71256d20cb3a6442e1f98a023f3fda231be7920744bdbc7` records 20
owned files and 27 coordinator closure inputs. Independent and IC-1 review
cleared that exact candidate before any executable launch. IC-1's complete-grant
finding was corrected before this snapshot: all four fixed grant times and the
entire fixed source receipt are independently constructed and canonical-compared
before pipe I/O; four altered-timing tests prove zero pipe calls. Source
remained unchanged during all executable runs.

Evidence resides in `.artifacts/initial-media-structure/`:

- `owner-executable-v1/owner-qualification-6981a5125202b3977013b228b0ceb19b78e745af4b9f37138dae7e7c85dd544d.json`
  proves one original synthetic 64,044-byte source transformed to a 32,044-byte
  prepared WAV through the real owner and pinned executable, followed by
  original outcome replay without another execution frame. The independently
  calculated outcome digest is
  `d67945c1fba3aff7d3ec1712c74858f208bbab479e92439dd08d9e1f76b0dfe9`. Supervised
  elapsed time was 2,231ms. Both direct children exited zero, were reaped, and
  their process groups were confirmed absent. Sampled coordinator and transform
  peaks were 67,403,776 and 46,301,184 bytes; aggregate sampled peak was
  112,787,456 bytes. These are one-run observations, not hard limits or
  tail-latency qualification.
- Historical regression receipt
  `12e77442b7ca05fe053eb44c35f07c0d0888db4f9e68e41c5290ff8210ddbfce` and
  validated-WAV regression receipt
  `eea84708834da373abb5c65699b6b28f03d10c3a6b6d18df4a664d0b01878ec3` are in
  `owner-historical-regression-v1/` and `owner-validated-regression-v1/`. Each
  reproduced two builds of its unchanged registered artifact and passed its
  existing executable and process-control cases.
  `owner-executable-results-v1.json` indexes all three receipts.
- `owner-portable-gate-v2.log` passes the complete portable preparation target,
  including 20 bridge tests, 5 bootstrap tests, 7 parent-protocol tests and 10
  mocked dual-process tests. Lost replies, expected stage rejections, malformed
  output, altered inputs and failure controls here use simulated replies or
  processes; they are not additional real owner executions. Existing owner tests
  pass 24 cases. Portable target coverage is local Make coverage, not a newly
  installed CI gate.
- `owner-prelaunch-gates-v1.json` records recursive formatting/lint, 1,205 Edge
  TypeScript checks, DTO and Markdown gates. Full Edge validation passed 3,404
  tests / 598 steps with 532 database-dependent cases ignored. It qualifies the
  recorded shared checkout, not an isolated commit tree or a fresh SQL run.
  Prior runtime-family SQL evidence remains unchanged. Earlier failed command
  attempts and withdrawn-candidate evidence are preserved.

The fixture's five service operations and retained-byte store are synthetic
in-memory dependencies. The run proves actual local artifact composition and
original owner/replay behavior; it is not durable SQL execution attestation,
installed signer/backend qualification or native/device acceptance. Target
CPU/native-memory enforcement, abrupt supervisor death, complete photo/video
structure and derivation, and final consuming-byte integration remain open.
Later work must resolve the concrete target contract before claiming S0 or
opening provider dispatch. No retry of an uncertain original operation is
permitted by the qualification tooling.
