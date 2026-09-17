---
name: merian-incident-response
description: "Diagnose, test, remediate, and document Merian reliability, security, privacy, data-integrity, or production incidents. Use for active incident response, post-incident review, regression reproduction, or incident-record creation across iOS, Supabase, web/admin, and release systems. This skill never authorizes hosted mutation, deployment, data repair, or external publication."
---

# Merian Incident Response

Turn symptoms into bounded evidence, a reproducible invariant, and independently
verifiable closure without confusing repository work with production recovery.

## Start safely

1. Read `AGENTS.md`, inspect `git status`, and preserve unrelated work.
2. Read [incident-workflow.md](references/incident-workflow.md) completely and
   the incident index/template under `docs/incidents/`.
3. Bound the affected user workflow, time window, versions, surfaces, durable
   states, and known-good comparison. Mark assumptions explicitly.
4. Load each applicable implementation skill. Use read-only hosted inspection
   unless the user explicitly authorizes a named mutation and target.
5. Redact credentials, personal data, raw coordinates, auth/session state, and
   production response bodies. Prefer aggregates, hashes, stable internal IDs
   only when safe, and synthetic reproductions.

## Build the evidence chain

- Separate observation from inference. Record the source and timestamp of each
  claim without pasting sensitive payloads.
- Trace the complete state transition across boundaries: initiating action,
  durable write, queue or job ownership, remote request, response mapping,
  presentation, retry/recovery, and terminal cleanup.
- Identify the invariant that failed and the owner that should enforce it.
- Reproduce with the narrowest deterministic test or fixture before changing
  production code when feasible. Add negative and concurrency coverage for the
  discovered failure mode.
- Treat hosted state as evidence, not as permission to mutate it. Do not repair
  data while still establishing root cause.

## Remediate in layers

1. Contain further harm with the smallest reversible repository change or
   documented operator option.
2. Fix the invariant at its owning boundary rather than masking the symptom in
   presentation code.
3. Add regression coverage that fails for the original cause and proves
   idempotency, authorization, cancellation, or retry behavior as applicable.
4. Update current contracts with `$merian-docs-sync` and create or amend the
   incident record without rewriting historical evidence.
5. Independently distinguish these statuses:
   - repository mitigation implemented,
   - candidate validation passed,
   - production deployment completed,
   - runtime behavior verified,
   - affected data recovered or explicitly unrecoverable.

Green tests can establish repository mitigation; they cannot establish the last
three statuses. Load `$merian-release` only after an explicit user request names
the operation and target.

## Close with evidence

Run the narrowest reproducer first, then every affected surface's complete gate.
Record unrun device, hosted, production, or recovery checks as open exit
criteria. An incident is closed only when its declared exit criteria are met;
otherwise use a precise state such as `mitigated in source`, `deployed`, or
`monitoring`.
