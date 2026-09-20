# Field Chat beta release decision — September 18, 2026

## Owner decision and scope

The sole repository owner explicitly requested proceeding with Field Chat for
users already testing the beta, followed by the emoji-reaction backend rollout
to Supabase project `qlarqavoqhkuwzmevrmf`. This changes the repository's
release policy for the existing beta backend. It does not describe the beta as
internal-only, attest to legal compliance, approve unfinished reviews, or
authorize an App Store release, new TestFlight distribution, new audience,
secret rotation, or production data repair.

“Beta” describes the current app distribution, not a server-enforced tester
allowlist. The production Field Chat endpoints remain reachable by authenticated
users who satisfy the existing Pro and subject-eligibility rules. This decision
does not introduce an invitation or cohort gate or claim production is isolated.

The source hold `species_dictionary_chat_production_hold` is inactive under this
owner decision. Its eight original exit criteria stay in the manifest as the
full-release evidence inventory. Inactive means the owner has accepted a beta
exception; it does not mean those eight criteria passed. The explicit beta
exception supersedes statements elsewhere that require every full-release
artifact before this beta backend can deploy. This enables automatic backend
deployment for subsequent qualifying main pushes, not only this rollout. It has
no automatic expiry or beta/public audience enforcement. The full-public-launch
checklist remains an owner responsibility, not a machine-enforced backend hold.
Before changing distribution or audience, the owner must revisit that checklist
and decide any renewed source hold. Separate iOS distribution/install-over gates
are unchanged.

## Evidence and explicitly deferred work

Full Supabase Candidate Validation passed for main commit
`e4966a6693c78fc6598b04d9049022fabbdabe40` in
[run 35418402967](https://github.com/emreerdener/merian/actions/runs/35418402967).
It executed disposable migration replay, database catalogs, Edge and concurrency
tests, and database advisors. This historical result is not evidence for a later
commit: the workflow must validate the final merged release SHA again.

The same main SHA's
[iOS run 35417519911](https://github.com/emreerdener/merian/actions/runs/35417519911)
completed with a passing Release archive and a failing complete unit-test step.
The failure has not been diagnosed in this backend policy change. It is not
passing iOS evidence; retain and investigate it before any iOS distribution.

The owner reported an upgrade retaining the scan library, reviewed App Store
age/privacy settings, and paid Gemini billing. Those reports are not substituted
for build-specific upgrade evidence, archived App Store records, a confirmed
project-specific DPA, or counsel approval. Legal review was reported unfinished.

The following remain open for full release and are deferred as beta backend
prerequisites, not recorded as successful:

- Physical released-build install-over evidence, including the historical
  V49→V50 and current V50→V51 checks. This backend release distributes no
  binary.
- Same-SHA complete iOS release nomination and the retained client evidence
  package. Existing CI failures must still be investigated; this exception does
  not turn a failed test into a pass or permit merging through required checks.
- Hosted real-token Field Chat authentication evidence. The probe in
  `services/supabase/scripts/verify_field_chat_hosted_auth.ts` is ready for a
  separately authorized staging target; no staging project or live result is
  represented as existing. Deterministic wrapper/auth tests remain mandatory.
- External consent/store/billing/DPA/legal approval records and the all-eight
  retained-artifact closure package. Follow
  [production consent readiness](../legal/production-consent-readiness-2026-08-03.md)
  before public-launch approval. Unfinished review is not a legal exemption.

## Controls retained for every beta deployment

Production still flows only through the reviewed GitHub Production workflow. It
requires the exact clean current main SHA, merged-PR provenance, strict
Candidate readiness and live branch/environment controls. A missing read-only
`MERIAN_GITHUB_RELEASE_AUDIT_TOKEN` must fail before Supabase mutation. No local
CLI deployment, fabricated clearance statement, skipped migration, force merge,
or credential bypass is authorized by this decision.

Keep the full disposable database/catalog/security/concurrency suite, runtime
verified-user authentication, ownership/blocking checks, RLS, consent/provider
eligibility, paid-provider configuration, quota enforcement, idempotent replay,
and error boundaries unchanged. This is a release-policy change only.

The durable-admission migration remains a required ordered forward migration. It
closes novel Field Chat sends until the next database-observed UTC-day boundary.
A subsequent ready-state workflow run must deploy and verify all three candidate
bundles and perform the one-way activation. Reads and exact persisted replays
remain available during the fence. Do not shorten or bypass the fence, use a
client timestamp, or report Field Chat available before activation.

After rollout, retain actual migration/function results, bundle identities,
activation state, and positive/negative smokes. Verify multiple emoji selections
persist together after refresh. Stop and investigate failed verification;
post-activation recovery is a reviewed forward fix, never an unreviewed database
reset. Follow the
[canonical deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
for execution, monitoring, and recovery.

## September 19 superseding decision

The owner subsequently requested immediate beta activation instead of waiting.
The
[September 19 decision](./field-chat-immediate-beta-activation-2026-09-19.md)
supersedes this record's next-UTC-day wait only, with explicit partial-day
accounting limitations and audited forward migration. This record retains the
original September 18 decision; other runtime and release controls still apply.
