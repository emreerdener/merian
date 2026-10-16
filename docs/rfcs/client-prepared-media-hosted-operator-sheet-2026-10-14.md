# CPM characterization: exact future operator sheet

> Superseded October 14 by the
> [test-only authentication revision](client-prepared-media-test-auth-hosted-packet-2026-10-14.md).
> This original JWT-based candidate and its approval remain historical. No
> hosted mutation or test occurred. Use the revised candidate only after new
> approval.

Status: prepared locally October 14, 2026; **not execution authorization**. This
sheet is part of the
[hosted-test approval packet](client-prepared-media-runtime-packaging-and-hosted-packet-2026-10-14.md).
Emre is the accountable operator. History primary may execute only separately
named approved operations. Independent/IC-1 reviewers remain read-only.

## Candidate and preconditions

Use the local checkpoint and source manifest in
`.artifacts/client-prepared-media/runtime-packaging/`. The only deployable tree
is `staged-06`, package digest
`d3841f1471f1cebad46ded3f95abc16fb196357098cf9c3f8efa90ae9e6661c0`. The offline
ESZIP digest is
`dbb594bd6e7b6e196b1972e9e0e7fa9d426f0b13cd479314c352fde526202c94` (8,425,366
bytes). This is offline packaging evidence; the pinned CLI rebuilds from the
verified tree during installation. Do not claim that the CLI-uploaded ESZIP has
this digest unless independently observed. Any source, dependency,
packaging-method or tool-pin change requires re-review before upload.

Before starting, the human approval must name the existing production-alpha
project `qlarqavoqhkuwzmevrmf`, route `cpm-verifier-characterization`, R2 bucket
`merian-cpm-verifier-fixtures`, this exact candidate, the attended window, $10
incremental ceiling, shared-project secret exposure and the full rollback scope
below. It must explicitly permit the one-route exception to the existing
whole-backend release hold. No PR116 push/merge or normal fleet deploy is
implied.

Read-only preflight after approval confirms the account, project and bucket;
private access; exact two bucket-only credential roles; absence of the test
route and all seven `CPM_Q_*` names; space for seven new secrets; no concurrent
planned deployment; healthy app baseline; and independent control-plane access
for route removal/token revocation. Stop on any collision or uncertainty. Do not
reveal credential values or use an ordinary app credential. No additional
project, server, bucket, user, permission, plan or paid add-on is created.

Reserve one fresh opaque run alias, one random capability, an already-valid
operator JWT with enough lifetime, and one absolute expiry at most 30 minutes
from installation/start. Installation consumes that same window; do not extend
it or refresh credentials mid-run. If it cannot fit, stop and return for another
approval instead of silently changing the run. Retain a local, sanitized action
ledger with attempt counts and outcomes. Never log Auth bodies, tokens, private
settings or request headers. The two credentials already exist by user report;
no secret discovery or rotation is included.

## Install only the experimental route

CLI pin: Supabase 2.109.1. Cached local Docker bundler: Edge Runtime v1.74.2,
image ID
`sha256:a82676277615aee03c4f288cbbbf68dedb5ba8693073e567ab8dbfdd11ba5d45`.
Revalidate the source manifest and run `stage.py --verify` before mutations. Do
not regenerate into or alter retained `staged-06` evidence.

The following are future commands, not commands already executed. Run from the
repository root. `CPM_Q_SECRET_FILE` is an operator-created private temporary
file outside source/artifacts, mode 0600, with **exactly** the seven names in
the packet. Its values are supplied securely; never print the file. Remove it
after use. Existing project public-key settings are reused, never overwritten.

```sh
SUPABASE_TELEMETRY_DISABLED=1 supabase secrets set \
  --project-ref qlarqavoqhkuwzmevrmf --env-file "$CPM_Q_SECRET_FILE"
SUPABASE_TELEMETRY_DISABLED=1 supabase functions deploy \
  cpm-verifier-characterization \
  --project-ref qlarqavoqhkuwzmevrmf \
  --workdir .artifacts/client-prepared-media/runtime-packaging/staged-06 \
  --jobs 1
```

No `--use-api`, `--prune`, omitted function name, generic deploy script,
migration, CI dispatch, debug tracing or automatic command retry. A
failed/unknown install stops; inspect status through the control plane, never
invoke the handler to probe it outside the 26-call budget. Platform
control-plane retries, if any, are not verifier calls; they do not authorize
repeating a failed operator command. Confirm deployed route/config version
through available metadata only. If the CLI cannot use the reviewed
bundler/package, stop without switching methods.

All functions in the existing project can read experiment secrets. Only the R2
**read-only bucket credential** is installed. The write/cleanup credential stays
with the operator. This exposure is an explicit approval condition, not an
isolation property supplied by the test route.

## Synthetic fixture creation and single-part upload

After approval, materialize exactly the three deterministic files defined in
`services/supabase/tests/cpm_verifier_characterization/policy.ts` and
`test_support.ts:fixtureResponse`. Each 65,536-byte block is filled with
`(seed + blockIndex) % 251`. Write exclusive new local files incrementally;
close and fsync them, then independently hash and match `policy.ts` before any
upload. Sizes: control 65,536 bytes, a/b each 33,554,432 bytes; total 67,174,400
bytes. No real photos, audio, video or personal data. Files and retained bundle
artifacts count within the 512 MiB local cap. No whole-package buffering is
needed.

Use the installed AWS CLI 2.34.8 only as an R2 S3 protocol client; this grants
no AWS infrastructure access. The operator process receives the R2 write
credential in standard AWS credential environment names and the exact R2
endpoint in `CPM_Q_R2_ENDPOINT`, privately. Clear any ambient session
token/profile and supply explicit credentials so no AWS credential source is
consulted. Disable metadata discovery and automatic retries. Use
`s3api put-object`, never `s3 cp` or resumable/multipart upload. Both
Cloudflare's
[conditional PutObject contract](https://developers.cloudflare.com/r2/api/s3/api/)
and the
[CLI option](https://docs.aws.amazon.com/cli/latest/reference/s3api/put-object.html)
support `If-None-Match: *`; the condition prevents replacement of an existing
committed object, not completion of an unknown in-flight writer.

For each of the three approved files, set nonsecret local `CPM_Q_ASSET_FILE`,
`CPM_Q_ASSET_NAME` and `CPM_Q_ASSET_BYTES` to its exact path/name/size from the
fixed manifest. Do not loop with retries or accept arbitrary keys.

```sh
AWS_EC2_METADATA_DISABLED=true AWS_MAX_ATTEMPTS=1 AWS_RETRY_MODE=standard \
  AWS_PAGER='' aws s3api put-object \
  --endpoint-url "$CPM_Q_R2_ENDPOINT" --region auto \
  --bucket merian-cpm-verifier-fixtures \
  --key "cpm-verifier/$CPM_Q_RUN/$CPM_Q_ASSET_NAME" \
  --body "$CPM_Q_ASSET_FILE" --content-length "$CPM_Q_ASSET_BYTES" \
  --if-none-match '*' --cli-connect-timeout 5 --cli-read-timeout 30 \
  --no-cli-pager
```

Only one upload process runs at a time. A positive successful response, exited
process and no other writer are required before attesting closure. Do not infer
closure from HEAD, listing, timeout, process loss or token expiry. A 412, lost
response, timeout or unclear outcome stops this experiment; no retry/replacement
key. Read-only reconciliation may inspect the original object's status within
the reserved ledger; it does not authorize new writes or proving a missing
writer ended. This finite attended test is not product ingress qualification.

## One driver run and operator readiness barrier

1. Confirm the run prefix is empty without listing unrelated objects. Upload and
   positively close **control only**.
2. Securely supply the operator process with `CPM_Q_RUN`, `CPM_Q_CAPABILITY`,
   `CPM_Q_EXPIRES_AT`, `CPM_Q_OPERATOR_BEARER` and the existing public project
   key (`SUPABASE_PUBLISHABLE_KEYS` or `SUPABASE_ANON_KEY`). No R2 write/read
   credential is needed in this process. From the repo root, run once:

```sh
deno run --cached-only --frozen --no-prompt \
  --config services/supabase/functions/deno.json \
  --allow-env=CPM_Q_RUN,CPM_Q_CAPABILITY,CPM_Q_EXPIRES_AT,CPM_Q_OPERATOR_BEARER,SUPABASE_PUBLISHABLE_KEYS,SUPABASE_ANON_KEY \
  --allow-net=qlarqavoqhkuwzmevrmf.supabase.co:443 \
  --allow-read=".artifacts/client-prepared-media/hosted-$CPM_Q_RUN" \
  --allow-write=".artifacts/client-prepared-media/hosted-$CPM_Q_RUN" \
  services/supabase/tests/cpm_verifier_characterization/runtime/run.ts \
  --approved-hosted-run
```

3. Case 26 runs first and must return the genuine handler-marked 403; gateway
   refusal stops before reads. Cases 1–2 then read control. At the pause,
   inspect `preflight.json` (two closed control Acks and runtime versions). Stop
   on invalid fields, threshold breach, unexpected versions or unhealthy
   application state.
4. Upload/close a and b serially. Write the exact `bulk-ready.json` shape from
   the
   [runtime README](../../services/supabase/tests/cpm_verifier_characterization/runtime/README.md)
   only after all three digests/sizes and positive writer closure match. It is
   an operator attestation. The driver refuses bulk if the remaining timed
   schedule cannot fit before original expiry. Do not restart the journal or
   extend expiry.
5. Observe the fixed warm cohorts and two different-object concurrent pairs,
   followed by the remaining single reader. There are at most 26 calls total,
   including preflight, two clients and one reader per observed module. No extra
   warm-up, affinity forcing, replacement request, or hidden retry. If real
   routing does not supply the intended same-isolate cohort, report it as
   unobserved.

The driver reserves 178 ordinary calls including 48 setup/observation allowance;
64 are held for cleanup, within the 256-call cap. The operator ledger must
account for setup/upload/control-plane/observation attempts within those
reservations. Limit observation to available bounded summaries; no raw logs
containing session or personal data. Media transfer stays within 2 GiB; local
evidence within 512 MiB; keep 20 GiB disk headroom. The run is at most 30
minutes including readiness, followed by at most 15 minutes of cleanup. No 160
MiB threshold, one-second CPU target, total/native-memory proof or product-limit
change.

## Independent stop and cleanup

Stop new driver work immediately on the packet's failure/unknown/health/budget
conditions. Preserve the journal and unresolved operations. Remove the test
route using the separately available control plane; this command has no need for
the experiment handler to respond:

```sh
SUPABASE_TELEMETRY_DISABLED=1 supabase functions delete \
  cpm-verifier-characterization --project-ref qlarqavoqhkuwzmevrmf
```

Revoke the experiment read credential through the operator's Cloudflare token
control. Remove only the seven names (never bulk-clear project secrets):

```sh
SUPABASE_TELEMETRY_DISABLED=1 supabase secrets unset \
  CPM_Q_RUN CPM_Q_OPERATOR_ID CPM_Q_CAPABILITY CPM_Q_EXPIRES_AT \
  CPM_Q_R2_ENDPOINT CPM_Q_R2_ACCESS_KEY_ID CPM_Q_R2_SECRET_ACCESS_KEY \
  --project-ref qlarqavoqhkuwzmevrmf
```

With positively closed readers/writers, delete only the three recorded run keys
using the operator credential and `s3api delete-object`, same endpoint/bucket,
retry-disabled environment and timeouts as above. No recursive/prefix purge.
Then revoke that write/cleanup credential. Confirm route absence, seven-name
absence and object outcomes through bounded metadata requests; do not infer
successful cleanup from a failed command. Preserve the empty private bucket.
Revocation/route removal blocks future access but does not prove current reads
or writes stopped. Unknown closure retains objects privately, revokes
credentials, records obligations and requires reconciliation review within 24
hours; further mutation after the 15-minute cleanup allowance requires
separately named approval. No indefinite polling, new experiment, blind TTL
deletion or funding/provider operation follows an unknown outcome.
