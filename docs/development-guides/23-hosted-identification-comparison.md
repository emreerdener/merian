# Hosted identification comparison

The manual **Compare identification providers** workflow runs the existing
Gemini Pro and Naturebook OpenAI photo/text profiles against the same six images
and two descriptions. It makes at most sixteen first attempts. Production
identification routing stays Gemini; this workflow does not deploy Supabase or
the app. Existing benchmarks remain unchanged.

The
[27 September comparison](../rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
completed all sixteen attempts. This remains the operator procedure for its
fixed baseline pair, not a pending run or an arbitrary optimization runner. The
[current optimization plan](../rfcs/identification-optimization-preserving-results-2026-09-27.md)
starts with offline analysis of existing evidence. A new hypothesis needs
reviewed profile and workflow support, a new bounded plan and applicable run
authorization; changing a bundle or experiment ID cannot repurpose this
completed comparison. Existing secret configuration does not authorize another
run.

The owner accepted public test materials on 27 September 2026. Use the existing
R2 `merian` bucket under `benchmarks/identification/`. This procedure owns the
hosted execution boundary; the
[matched-comparison plan](../rfcs/identification-gemini-openai-matched-comparison-2026-09-27.md)
owns the selected cases and interpretation, and the
[evaluator guide](../../services/supabase/scripts/identification_evaluation/README.md)
owns the underlying measurement and accounting contracts.

## GitHub configuration

Use `emreerdener/merian` → environment **Production**:

| Setting                                               | Purpose                                                                                |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `GEMINI_PAID_API_KEY` secret                          | Existing paid Gemini key                                                               |
| `NATUREBOOK_OPENAI_API_KEY` secret                    | Existing Naturebook OpenAI key; mapped to `OPENAI_EVALUATION_API_KEY` in this workflow |
| `R2_ACCOUNT_ID` variable or secret                    | Cloudflare account containing `merian`; exactly 32 lowercase hexadecimal characters    |
| `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` secrets | Authenticated object read/write access to `merian` for claims and summaries            |

Reuse existing suitable storage credentials where available. The read-only
`R2_READ_*` pair cannot create claims. Standard R2 Object Read/Write credentials
are bucket-scoped and can also delete objects; the prefix and
GET/conditional-PUT restriction here is enforced by the reviewed wrapper, not a
claim about the token's permissions. Prefer dedicated comparison credentials if
already available, and do not rotate application credentials for this
comparison. The wrapper fixes the bucket to `merian`, offers no
list/delete/settings operation, and assigns provider and storage keys to
separate steps. The unrelated Agent Quality `OPENAI_API_KEY` is never used.

GitHub retains the keys. No developer-machine key entry or readback is needed
for this path. The local launcher remains available for separately prepared
local runs.

## Prepare the public bundle

Use a clean reviewed revision that can be dispatched as the current `main`
commit. Keep the original private packet outside Git. Prepare a reviewed
`hosted_identification_spec_v1` record following
[`HostedSpec`](../../services/supabase/scripts/identification_evaluation/hosted.ts):

- One stable experiment ID; exact source identity, corpus/taxonomy digests and
  existing order seed.
- A concrete execution window of at most two hours, within the corpus retention
  date, and an approved total budget with per-provider allocations. The wrapper
  supports at most $100; the existing full-context reservations must fit each
  allocation. A proposed budget does not authorize paid execution.
- The two fixed provider profiles, their current fingerprints and reviewed
  pricing cards. Pricing must be no more than seven days old at preflight.
- Explicit paid-service and exact-input permission for each provider, review
  dates covering the window, truthful shared/dedicated-project status and opaque
  terms/data-use/region/retention review references. The GitHub environment
  secrets identify the approved application projects. References are public-safe
  aliases; do not include actual account configuration in the spec.
- Public-release approval and applicable source/license attribution for the
  selected materials. Account files, credential reviews, local paths and logs
  are not part of the export.

For the prepared September comparison, the proposed reservation ceiling is $66
($23 Gemini and $43 OpenAI), not an expected invoice. Confirm the concrete
allocation when dispatching. Do not extend a completed or uncertain run's window
or regenerate its ID to get another attempt.

After caching the frozen dependency graph, export with network and environment
access denied. The following paths are examples to replace with the reviewed
packet/spec and a new output file outside Git:

```bash
evaluation_packet=/absolute/private/packet
evaluation_spec=/absolute/private/hosted-spec.json
evaluation_output=/absolute/private/public-bundle.json
deno run --frozen --cached-only --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_packet,$evaluation_spec,$evaluation_output" \
  --allow-write="$evaluation_output" --allow-run=git \
  services/supabase/scripts/host_identification_comparison.ts \
  export "$evaluation_packet" "$evaluation_spec" "$evaluation_output"
```

The exporter reads only the corpus, taxonomy, reviewed spec and six enumerated
images. It checks the exact eight-case photo/text shape, input hashes, image
containers, profile fingerprints and public-release declaration. It creates a
new JSON file containing inline image bytes, preserving provider inputs. It does
not upload anything. Its output gives the file's SHA-256, byte count,
sixteen-call cap and budget. Review the selected public file, then upload it to
`merian/benchmarks/identification/bundles/<sha256>.json` using the approved R2
upload path. Preserve the original corpus retention date for public copies.

The workflow downloads only the corresponding fixed `media.merian.app` URL,
without credentials or redirects, with a 24 MiB limit. It verifies the complete
bundle hash before parsing, then checks every asset hash and stages new local
files with private permissions outside the checkout. It cannot import an
archive, follow an arbitrary asset URL, overwrite an existing packet or accept
path traversal. Public read access does not permit public writes or dispatch.

## Preflight and execution

1. Select **Compare identification providers** on `main`. Supply the exact
   candidate SHA and reviewed bundle SHA-256. Leave `operation: preflight` and
   budget `0` for a no-request check. It verifies public inputs, source,
   profiles, pricing age and reservations without reading any provider or
   storage credential. Its summary says `preflight_passed`; actual credential
   binding remains unchecked. It creates no remote claim and makes no provider
   request.
2. After the complete packet and budget are approved, dispatch `compare` with
   those same hashes and the approved maximum budget. Complete Supabase
   candidate validation must pass before this job starts; allow for validation
   time when selecting the short window. Only after candidate validation does
   this operation bind each provider key to a private readiness fingerprint in
   its own network-denied step, create the live controller plan and perform
   complete controller preflight without network access.
3. The job creates `benchmarks/identification/claims/<experiment-id>.json`
   through one signed R2 `PUT` with `If-None-Match: *`, then verifies
   authenticated origin readback. Only confirmed creation admits paid execution.
   Existing claims, transport uncertainty or readback failure stop the job.
   There are no storage retries or claim-deletion paths.
4. Gemini executes first, then OpenAI, with one provider key and one provider
   host allowed per process. The existing controller owns per-call claims,
   budgets, usage, model matching and global stops. A zero process exit is not
   enough: the wrapper requires the completed run ID and no controller stop
   before advancing to the next provider.
5. A network-denied step regenerates the public summary from validated
   normalized records. The job uploads only `identification-public/summary.json`
   as an Actions artifact and, after verifying claim ownership, stores an
   immutable copy at
   `benchmarks/identification/results/<experiment-id>/<run>-<attempt>.json`. It
   never publishes the packet directory, readiness records, full manifests,
   account files or unfiltered diagnostics.

## Interruption and results

The remote claim is permanent evidence that this allocation was admitted; it
must not be removed to retry a run. A rerun of the job or a fresh dispatch of
the same experiment cannot acquire it, even after the original runner
disappears. Changing a bundle digest does not change the claim key. Any new
comparison requires a separately reviewed experiment and budget; no automatic
retry, resume, provider failover or replacement experiment exists.

If a job fails after claiming, preserve its partial summary. A missing or torn
controller report leaves the entire allocation unresolved. Hard cancellation can
prevent summary publication altogether; in that case the remote claim still
blocks replay and the maximum allocation remains unresolved. Public Actions
artifacts are a convenience copy, not the duplicate-execution guard.

A complete summary means the sixteen assigned attempts completed under the
controller. It does not qualify a production provider change. The report keeps
provisional taxonomy, missing measurements and uncontrolled caching explicit.
Read the per-case and per-modality results before deciding on further work.

## Implementation and checks

- [`hosted.ts`](../../services/supabase/scripts/identification_evaluation/hosted.ts)
  owns the strict public bundle, private readiness binding, experiment
  preparation and generated report projection.
- [`hostedStorage.ts`](../../services/supabase/scripts/identification_evaluation/hostedStorage.ts)
  owns fixed-origin downloads and signed conditional R2 writes/readback.
- [`host_identification_comparison.ts`](../../services/supabase/scripts/host_identification_comparison.ts)
  and
  [`run_hosted_identification.sh`](../../services/supabase/scripts/run_hosted_identification.sh)
  own the CLI and per-step permissions.
- [The workflow](../../.github/workflows/identification-provider-comparison.yml)
  owns manual dispatch, exact-main validation, Production environment and secret
  mappings.

Run `make test-supabase-tooling` and
`deno fmt --check services/supabase/functions services/supabase/scripts`. The
isolated evaluator suite covers byte-preserving export/hydration and preflight;
standard tooling covers conditional-write races, ambiguous storage outcomes and
workflow credential boundaries. These checks make no paid requests.

R2 conditional writes and public-bucket behavior were checked against
[Cloudflare's S3 compatibility reference](https://developers.cloudflare.com/r2/api/s3/api/)
and
[public-bucket guide](https://developers.cloudflare.com/r2/buckets/public-buckets/).
