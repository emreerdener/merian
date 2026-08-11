# Authorized release procedures

Use this reference only after an explicit release, deployment, production
mutation, cleanup, reset, rollback, or external publication request.

## Authorization envelope

Before a mutating step, make all of these explicit:

- operation: what will be deployed, published, mutated, rotated, cleaned, or
  rolled back;
- target: exact Supabase project/environment, Apple application/build,
  RevenueCat project/app/customer cohort, or other destination;
- source: immutable commit SHA and generated artifact/build identity;
- authority: user approval for this operation and target, plus any runbook owner
  or protected-environment approval;
- evidence: prerequisite checks on that same SHA/artifact;
- recovery: stop conditions, monitoring, and tested rollback or forward-repair
  path.

Preparation authorization permits read-only inspection, local checks, and a
release plan. It does not permit upload, distribution, deployment, dashboard
mutation, SQL execution, secret change, account action, or cleanup.

## TestFlight and App Store

Canonical procedure: `docs/development-guides/14-ios-release-versioning.md`.

- Keep `project.yml` versioning, automatic signing, permanent bundle IDs, and
  the existing app record authoritative.
- Require exact-SHA iOS Build and Test evidence, archive privacy and transport
  checks, and every release-specific legal/product hold in the canonical docs.
- Xcode Organizer is the sole distribution authority: Product → Archive, then
  Organizer → Distribute App. Do not add CI/Fastlane signing or upload logic.
- Treat upload, processing, internal distribution, external distribution, and
  App Review submission as separate authorization points when the runbook does.
- Promote the same processed binary; do not silently rebuild between evidence
  and distribution.

## Supabase production

Canonical procedure: `docs/backend-and-data/06-supabase-deployment-runbook.md`.
Load `$merian-supabase` and all references it requires.

- Candidate validation runs the exact candidate against disposable
  infrastructure and has no production authority or production secrets.
- Production changes flow through the protected GitHub `Production` workflow
  at the exact SHA. Preserve the pinned CLI, migration history validation,
  Function fleet plan, secret synchronization, approvals, pre/post checks, and
  evidence artifacts.
- Do not replace the workflow with local `db push`, Function deploy, MCP
  `execute_sql`, dashboard SQL, manual secret mutation, or a mutable branch ref.
- Database fixes are forward migrations. Do not edit applied history or repair
  hosted state without the explicit runbook path and target authorization.
- Positive and negative post-deploy checks must prove auth/RLS/error behavior
  without printing credentials, response bodies, personal data, or coordinates.

## RevenueCat and App Store products

Canonical contract: `docs/features-and-hardware/02-revenue-and-identity.md`.

- Use the existing Naturebook app, permanent bundle ID, RevenueCat app,
  offering, entitlement namespace, and Supabase Auth UUID customer identity.
- Product or price work does not imply permission to create a new app/customer,
  rename stable identifiers, grant entitlements, delete customers, or reset the
  project.
- Dashboard changes must be represented in checked-in client policy, webhook
  reconciliation, documentation, and tests when they alter the contract.
- Cleanup/reset/grant tools run in dry-run mode first where available and require
  an exact bounded cohort plus explicit apply authorization.
- Never expose RevenueCat secret keys, webhook secrets, Apple signing material,
  or App Store Connect credentials to application targets, logs, or artifacts.

## Rollout readiness and evidence

Use current canonical readiness records and runbooks; do not copy a dated status
paragraph into agent instructions. For each release, retain a redacted summary
of:

1. exact source SHA and artifact/build;
2. required check URLs or identifiers and their conclusions;
3. target and approver;
4. planned and actual mutation;
5. post-release positive and negative verification;
6. monitoring owner/window and rollback status.

Stop when the checked-in runbook, live target, or evidence disagree. Resolve the
drift through review; do not improvise around a protected control.
