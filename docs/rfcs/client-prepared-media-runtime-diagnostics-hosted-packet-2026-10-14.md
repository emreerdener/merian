# CPM runtime compatibility correction: revised hosted-test packet

Status: October 14, 2026. Local diagnostics, packaged-runtime tests, correction
and independent/IC-1 review are authorized. **No hosted action is authorized by
this revision.** Approval of the previous candidate was consumed by its stopped
attempt. The exact new commit and review bindings belong to
`.artifacts/client-prepared-media/local-diagnostics/checkpoint.md`.

## Demonstrated defect and scope

The pinned cached Edge Runtime v1.74.2 reports its Deno version as
`supabase-edge-runtime-1.74.2 (compatible with Deno v2.1.4)`. Candidate
`16c8cb64c` rejected spaces and parentheses during worker construction and again
in driver metadata validation. The original ESZIP returns an empty 503 in an
actual offline user worker. The corrected deployable ESZIP returns the expected
handler-marked 403 to a wrong test key. Missing configuration still returns 503,
now with a fixed `x-cpm-startup-error: initialization_failed` marker.

The shared `validRuntimeVersion` accepts only 1–80 ASCII characters, starting
with an alphanumeric character; remaining characters are alphanumeric, period,
plus, underscore, parentheses, space or hyphen. CR/LF, other control characters,
non-ASCII and oversized values remain rejected. Metadata remains required; no
authentication, expiry, media, memory or recovery check is bypassed.

The transport records at most one fixed-shape diagnostic per attempt: fixed case
number, response-received/transport-failed stage, numeric status or null, and
booleans for expected auth-mode, version validity, handler and startup markers.
Driver failures additionally retain a fixed
delivery/response-timing/denial-status/ denial-body/acknowledgement stage. No
arbitrary exception text, URL, header value, request/response body or secret is
retained. Validated bounded runtime versions continue in the existing runtime
evidence. These are observations, not bundle attestation or proof of remote
termination. A diagnostic failure still stops; it does not authorize another
request. Request/Ack bodies and product DTOs are unchanged; only the
experimental driver consumes the new evidence fields.

Local tests include denied environment/network unit tests, staging provenance,
and actual pinned user-worker execution with Docker networking disabled. The
actual candidate is tested for rejection/startup. A separately identified
**test-only** ESZIP replaces outbound fetch with deterministic synthetic control
bytes and verifies two successful controls in one reused module; it is never
eligible for deployment. No real R2/TLS, gateway, long warm cohort, concurrency,
total-memory or CPU qualification follows. Local container caps are test safety
controls, not new product limits. The harness follows the pinned runtime's
[user-worker example](https://github.com/supabase/edge-runtime/blob/v1.74.2/examples/main/index.ts).

## Prior attempt and credential correction

The prior attended run `q3e225466ac7ec557` attempted only the deliberately wrong
key check (case 26). It stopped with `delivery_or_verification_failed`,
retaining no qualifying denial or runtime metadata. Its precise hosted cause is
unknown; the local reproduction establishes a real defect, not retrospective
proof of what the hosted gateway returned. Its journal and failed evidence are
preserved.

The test route and seven temporary settings were removed and absence confirmed.
The user corrected the earlier revocation confirmation: **both R2 credentials
remain active in their secure store**. Local private copies were removed. No
credentials were read or used in this local investigation. Reuse of those same
two bucket-scoped credentials is proposed below, subject to refreshed read-only
scope checks and explicit new approval; it is not authority to use them now.

The private synthetic 64 KiB object
`merian-cpm-verifier-fixtures/cpm-verifier/q3e225466ac7ec557/control.bin`
remains under an unresolved case-26 closure obligation. Review is due October 15
at 11:14 a.m. America/Chicago. Local reproduction, expiry, settings removal and
key status do not close that obligation. Do not read, overwrite or delete that
object as part of a new run. Resolve the old closure obligation before
scheduling a new hosted test; if available metadata cannot establish closure,
return an explicit revised reconciliation proposal rather than silently infer
it. Any separately approved deletion must name that exact object and its closure
basis. Auto-prompts remain paused; this document does not schedule a review.

## Exact approval requested after review

The
[prior test-auth packet](client-prepared-media-test-auth-hosted-packet-2026-10-14.md)
and
[operator sheet](client-prepared-media-test-auth-operator-sheet-2026-10-14.md)
remain the base procedure, with only these explicit changes:

1. **Candidate:** use the new reviewed commit, source manifest and
   `local-diagnostics/staged-01` package, never the old stage or the synthetic
   transport package. Hash-check before mutation. Use pinned CLI 2.109.1 and
   cached Edge Runtime v1.74.2 with the existing offline packaging procedure.
2. **Targets:** the existing alpha Supabase project `qlarqavoqhkuwzmevrmf`, only
   route `cpm-verifier-characterization`, and private R2 bucket
   `merian-cpm-verifier-fixtures`. Refresh account, bucket-private settings,
   exact credential scope, project health, collisions, space and concurrent
   deployment observations. No separate project, bucket or AWS worker.
3. **Credentials/settings:** explicitly approve reuse of
   `merian-cpm-verifier-read` (Object Read only, this bucket) and
   `merian-cpm-verifier-operator` (Object Read & Write, this bucket). Obtain
   them through a private local file, never chat or evidence. Operator
   credentials remain local; only the read pair enters the shared project.
   Generate new independent test key/capability, new opaque run and original
   30-minute expiry. Install only `CPM_Q_RUN`, `CPM_Q_OPERATOR_KEY`,
   `CPM_Q_CAPABILITY`, `CPM_Q_EXPIRES_AT`, `CPM_Q_R2_ENDPOINT`,
   `CPM_Q_R2_ACCESS_KEY_ID`, `CPM_Q_R2_SECRET_ACCESS_KEY`. Every function in the
   project can read these temporary settings. No ordinary credential or product
   user/session is used.
4. **Execution:** exactly one new attended 26-case driver/journal, with case 26
   first. Positively close the new 64 KiB control upload, then require genuine
   denied-key and two valid-control evidence before uploading the two 32 MiB
   fixtures and attesting readiness. Never reuse the old namespace or journal.
   No replacement request or retry after an uncertain or failed response.
5. **Bounds:** retain the $10 ceiling, 30-minute run plus 15-minute cleanup, 256
   application calls (192 ordinary/64 cleanup), 2 GiB transfer, two clients, one
   reader per module and no same-object concurrent reads, 30-second request
   bound, 512 MiB local evidence and 20 GiB disk floor. Retain the 96 MiB
   partial V8 proxy and 8 MiB growth stop rules. Diagnostics add no HTTP calls.
   Posted billing may lag; reservations are not measured usage. No 160 MiB
   adoption.
6. **Cleanup:** stop on first failure, remove only the experiment route and
   seven temporary settings, verify absence, delete only new run objects with
   positive reader/writer closure, then revoke both temporary experiment
   credentials and remove local secret copies. This packet explicitly requests
   revocation at the end of the new attempt; retention beyond that needs an
   explicit amended decision. Unknown closure retains objects privately and
   records a 24-hour reconciliation review; deletion is never inferred from
   expiry/revocation. No bucket deletion, recursive purge or ordinary
   application mutation.

Approval must name the exact new candidate, shared-project settings exposure,
credential reuse and end-of-test revocation, attended window, $10 ceiling and
setup/run/cleanup scope. A new route deploy still requires the explicit narrow
exception to the whole-backend release hold. No push, PR116 merge/fleet deploy,
migration, device installation, activation or AWS infrastructure is included.

History primary is sole writer/operator assistant; Emre is accountable operator;
independent and IC-1 review remain read-only. Original photo/audio/recovery/
shared-asset acceptance, media-required scope and version-actions then redesign
sequencing remain open and unchanged. This fixes a representative verifier
startup defect, not the complete CPM architecture. No further implementation or
hosted action is implied by a passing review.
