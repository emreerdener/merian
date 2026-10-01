# OpenAI confidence prompt activation — 30 September 2026

Status: source activation prepared; exact-SHA production deployment pending.
Target: Supabase production `qlarqavoqhkuwzmevrmf` through the existing GitHub
`Production` workflow. The owner explicitly requested this activation after
reporting a newly released iOS build and a fresh device identification. No iOS
archive/upload, new benchmark, threshold change or other provider activation is
included in this release.

## Change and authority

`openaiPhoto.ts` now selects `openai_identify_vision_confidence_v1` for the
existing database-admitted `openai_photo_v1` binding. Production applies the
unchanged observed-traits improvements and the assessed confidence rules. The
prescribed 70–88% range and conflicting confidence anchors are removed from both
instructions and schema descriptions. The rules are shared with the assessment
through the pure `openaiConfidenceRules.ts` module; evaluation authority never
becomes production authority.

Model `gpt-6-sol`, low reasoning, high image detail, output ceiling 8,192,
moderation, timeouts, explanation format and response fields are unchanged.
Gemini and historical evaluation profiles retain their requests. Completed
replays and historical restoration preserve original scores and provenance.
`openai_unqualified_v1` and all native 0.95/0.60 display mappings remain in
force. An existing 83% score therefore stays Possible; the release changes
instructions for new requests and does not guarantee a higher score for any one
photograph.

The owner reports that the new reader has been released and used on a device.
Its exact installed version/build, historical-restoration exercise and revised
fixture were not independently captured in this activation turn. The owner then
explicitly directed immediate beta production activation. This record reports
that authorization and evidence limit without inventing device verification or
claiming completion of the earlier full reader-evidence checklist. Older readers
may show Needs review for the revised prompt. No additional iOS build is
created.

## Validation and request preservation

- Offline reconstruction verified all **200 frozen request and settings
  digests** against the original assessment manifest and the production builder.
  Provider requests: **zero**; private packet and existing attempts unchanged.
- Focused adapter/profile/provenance tests: **22 passed**, plus the production
  composition test using the exact CI environment allowlist and no network.
- Independent read-only contract review found no activation, historical replay,
  decoder or evaluator-isolation blocker.
- Complete backend suite: **2,232 passed**, 343 steps, zero failures and 11
  existing ignored tests.
- Complete Supabase tooling gate passed, including isolated evaluation tests,
  deployment/scope regressions and local credential-transport tests with zero
  API calls. Edge DTO and captured-media contract checks passed.
- Recursive formatting, lint, function configuration and dependency-graph checks
  passed. The identification entrypoint type check, generated deployment
  identity check and changed-Markdown formatting check passed.
- Exact GitHub deployment evidence remains pending. Local checks do not
  establish production activation.

The
[completed assessment](../rfcs/identification-openai-confidence-results-2026-09-30.md)
selected no new cutoff. This release preserves that decision and does not claim
population accuracy or calibrated individual percentages.

## Release and recovery

Commit and push the reviewed source to `main`; the existing workflow validates
the exact SHA in a disposable database before the protected Production job.
Retain its function deployment and post-deploy authorization smoke evidence. No
migration, catalog assignment or new credential is needed for this switch.

Recovery is a reviewed forward source change restoring the previous
observed-traits prompt selector and request transformation, followed by the same
validated Production workflow. Keep the confidence reader, saved results,
historical provenance and evaluation journals. Never retry completed scans or
rewrite scores during rollback. No rollback has been performed.

Monitor the deployment and its built-in post-deploy checks through completion;
subsequent beta photo checks belong to the owner. A successful deployment proves
the selected code was released, not biological correctness of a future scan.
