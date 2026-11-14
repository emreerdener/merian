# CPM v1.77.0 compatibility: revised hosted-test packet

Status: October 14, 2026. Local compatibility qualification and independent/IC-1
review authorized. **No hosted action is authorized by this packet.** The
attended `q59d72e8dd1bcd1` approval ended at its stopped control barrier. This
packet proposes one new attended run; it never resumes either old journal.

## Exact candidate and evidence

Executable source remains commit `9c88cc72d35d925a3e4a7d7890f2ec8728d0e414`. No
verifier, driver, authentication, payload, dependency or limit changes are
needed. The approved-source package remains
`.artifacts/client-prepared-media/local-diagnostics/staged-01`:

- Package SHA-256:
  `4289f2d691c6146d1920d4c64e87643d8a73cc8ac2e5ba534c56e99271f33553`.
- Offline deployable ESZIP SHA-256:
  `7da0be7c760ef4078b98ab9670218d43cf7d6d9139836ef52fb38bd33a2752a7`.
- Original source-set SHA-256:
  `62e06f344d956a3b76406c4f2e90b5b1ed25369a001107f12b2823e715c35d42`. Its
  documentation snapshot is historical; the new review manifest distinguishes
  unchanged executable inputs from current documentation. Exact packet
  commit/review bindings live in
  `.artifacts/client-prepared-media/runtime-177-qualification/checkpoint.md`.

CLI **2.109.1** and its cached **v1.74.2 bundler** remain pinned. v1.77.0 is the
explicitly qualified execution target, not an instruction to replace the CLI's
bundler or repository pins. CLI installation rebuilds from the exact staged
tree; a local bundle hash is not attestation of uploaded bytes or hosted
infrastructure.

The new local harness runs the retained ESZIPs using the official Linux arm64
v1.77.0 image pinned by digest
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`.
Networking is disabled; no host port, credential or real media is supplied.
Mounts are read-only, with 512 MiB container/one CPU/128 MiB temporary
storage/25-second harness deadline. The user-worker cap is 256 MiB, solely local
harness isolation; this does not change the 96 MiB hosted partial-proxy stop or
approve 160 MiB.

Six checks passed: old package reproduces 503; unchanged corrected package
returns genuine wrong-key 403; missing configuration returns marked 503; a
separately labelled non-deployable synthetic-transport package rejects the wrong
key and verifies two 64 KiB controls in the same worker with digest, positive
reader/cleanup closure and valid partial V8 fields. This is startup and short
control-path compatibility. No native/RSS peak, attributed CPU, long warm reuse,
bulk, concurrency, ingress or complete product qualification follows. The local
arm64 image and matching version strings do not attest the hosted build,
architecture, platform configuration or transport behavior. Official
[v1.77.0 release](https://github.com/supabase/edge-runtime/releases/tag/v1.77.0)
documents the runtime release independently.

## Prior runs and retained credentials

The first stopped run's old 64 KiB control is reconciled using positive writer
completion and exact correlated worker Shutdown; the object remains private. The
later run passed genuine denial and two real R2 control reads, then stopped
because hosted v1.77.0 differed from locally tested v1.74.2. All three
obligations closed before the barrier. Its route, seven settings and new control
were removed; project health was `ACTIVE_HEALTHY`. Neither 32 MiB fixture was
uploaded. Preserved evidence is under `hosted-q3e225466ac7ec557` and
`hosted-q59d72e8dd1bcd1` in `.artifacts/client-prepared-media/`.

The user explicitly chose to **retain** `merian-cpm-verifier-read` and
`merian-cpm-verifier-operator`. Both remain active in the user's secure store.
Local and hosted temporary copies were removed. This supersedes automatic
end-of-test revocation in the earlier packet/operator sheet. Future setup
requires secure local re-supply and refreshed exact bucket-only scope checks; do
not read Notes or put keys in chat, source, logs or evidence. Routine cleanup
removes temporary hosted/local copies and retains those two stored credentials.
Suspected compromise or any proposed rotation/revocation requires a separately
named owner decision; retention never authorizes extra test invocations.

The old exact object
`merian-cpm-verifier-fixtures/cpm-verifier/q3e225466ac7ec557/control.bin` is
excluded from this run. Do not read, overwrite or delete it. Its deletion is
optional and still needs separately named approval; it does not block this fresh
namespace.

## Expected runtime and operator gate

For this proposed run, the expected pair is exactly:

- Deno header: `supabase-edge-runtime-1.77.0 (compatible with Deno v2.1.4)`.
- V8 header: `11.6.189.12`.
- Authentication mode remains `test-run-key-v1` with genuine handler markers.

These values are bounded runtime observations, not trusted attestation. The
driver's existing validator checks safe syntax; **the operator enforces this
exact pair at the control barrier** by inspecting all three preflight
observations. Only a genuine wrong-key denial and two verified, positively
closed controls with this pair permit the bulk-readiness attestation. Any
mismatch, malformed metadata, threshold breach or unresolved operation stops the
run without bulk uploads, expiry extension, replacement request or another
attempt. Do not silently accept a newer patch release. Runtime change revealed
later invalidates compatibility interpretation and requires
recording/cleanup/review; the unchanged driver does not automatically enforce
equality per bulk response. The operator must not claim such enforcement or
real-time detection that the launcher does not implement.

## Bounded approval requested

The
[runtime diagnostics packet](client-prepared-media-runtime-diagnostics-hosted-packet-2026-10-14.md)
and
[test-key operator sheet](client-prepared-media-test-auth-operator-sheet-2026-10-14.md)
supply the existing procedure. This packet supersedes only the prior closure
blocker, runtime expectation and automatic credential revocation, and binds the
unchanged executable candidate above. All other limits and fail-closed rules
remain.

Approval must cover one fresh attended setup/run/cleanup for candidate
`9c88cc72d` under this exact reviewed packet and its final documentation commit:

1. Existing production-alpha Supabase project `qlarqavoqhkuwzmevrmf`, only
   experimental route `cpm-verifier-characterization`; explicit narrow exception
   to the whole-backend release hold. Private R2 bucket
   `merian-cpm-verifier-fixtures`; no new infrastructure.
2. Reuse the two retained bucket-scoped credentials. Operator write key stays
   local; install only the read key pair plus fresh test
   run/key/capability/expiry through exactly seven settings: `CPM_Q_RUN`,
   `CPM_Q_OPERATOR_KEY`, `CPM_Q_CAPABILITY`, `CPM_Q_EXPIRES_AT`,
   `CPM_Q_R2_ENDPOINT`, `CPM_Q_R2_ACCESS_KEY_ID`, `CPM_Q_R2_SECRET_ACCESS_KEY`.
   Every function in the project can read those temporary settings. No ordinary
   app identity/session or privileged product key is used by the verifier.
3. Fresh opaque prefix/journal and independent test key/capability; fixed
   30-minute run including installation, followed by 15-minute cleanup. Confirm
   healthy/quiet target, no route/settings collision or concurrent deployment,
   credential scope, source/stage hashes and resource headroom before mutation.
   Resolve provider alerts by affected service and current project evidence; do
   not declare a broad banner healthy without checking its scope. An affected or
   uncertain target stops admission.
4. Conditional single-part control upload, positive writer closure, wrong-key
   case 26 then controls 1–2. Review the exact runtime pair and closure before
   serial a/b uploads and explicit readiness attestation. All three fixed
   fixtures total 67,174,400 bytes; no real user media. Never reuse old objects
   or journals.
5. At most 26 driver calls, two clients, one reader per module, no concurrent
   same-object reads, 30-second request bound. **$10 ceiling**, 256 application
   calls (192 ordinary/64 cleanup), 2 GiB transfer, 512 MiB retained local
   evidence, 20 GiB free disk floor, 96 MiB partial V8 proxy stop and 8 MiB
   growth stops. No 160 MiB or one-second CPU acceptance. The source has two
   concurrent different-object pairs and a final single read; count
   observations, not hoped-for affinity.
6. Stop on first failure/uncertainty/health alert/bound breach. Remove only the
   experiment route and seven settings, verify absence, delete only fresh-run
   objects with positive reader/writer closure, and remove local secret copies.
   Retain the two credentials in the user's secure store as directed. Unknown
   closure retains objects privately and records reconciliation; expiry or
   settings removal never proves termination. No recursive purge or bucket
   deletion.

**Local evidence storage preflight:** retained evidence is about 450.65 MiB
after this qualification. A fresh extra 64 MiB copy of all fixtures would exceed
the 512 MiB cap. Reuse the retained synthetic fixture files from
`hosted-q59d72e8dd1bcd1` only as local upload sources after independently
rechecking all exact sizes and hashes; this is not reuse of remote objects, run
identity or journal. The two prior remote bulk keys were never created. Do not
duplicate these local files, delete prior evidence, raise the cap or silently
regenerate. Reserve at least 4 MiB for the new sanitized journal/results and
verify current total plus that reserve remains under 512 MiB before setup. If
not, stop and propose a separate evidence-storage decision.

All hosted actions remain gated on a new explicit approval and current
attendance. This packet does not authorize push, PR116 merge, normal fleet
deployment, migrations, device work, product activation, AWS infrastructure,
additional credentials or schedules. History primary remains sole
writer/operator assistant; Emre remains accountable operator. Independent and
IC-1 reviewers are read-only. Original photo/audio/recovery/shared-asset gates,
actual-media requirement and later version actions/redesign remain open and
unchanged.
