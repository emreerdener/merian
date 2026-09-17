# Documentation ownership map

Read this reference before a repository-wide documentation update or drift
audit. It supplements the contributor matrix in `docs/CONTRIBUTING.md`.

## Authority classes

| Class               | Purpose                                                                                | Update rule                                                                            |
| ------------------- | -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Current contract    | Defines behavior, ownership, security, privacy, payload, or release rules now          | Change with the implementation and its executable checks                               |
| Local README        | Explains the boundary and entry points of one source tree                              | Change when files, owners, or contributor workflow move                                |
| Runbook             | Defines an operator action and its evidence, authorization, recovery, and rollback     | Change when the operation or gate changes; never imply authorization                   |
| Verification matrix | Maps behavior to exact tests, selectors, scripts, or CI checks                         | Change when coverage or ownership changes; executable manifests win                    |
| RFC                 | Records a proposal, decision, or completed implementation history                      | Preserve history; add status and a current-contract link                               |
| Incident            | Records evidence, impact, root cause, mitigation, and closure state at a point in time | Preserve evidence; separate repository mitigation from production/runtime/data closure |
| Release evidence    | Proves one candidate, artifact, environment, or operation                              | Immutable once accepted; supersede with a new record                                   |

## Change-to-document routing

| Change                                                          | Required documentation review                                                                            |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Source ownership, folder, or public initializer move            | Nearest README, `docs/codebase-map.md`, current architecture guide, test ownership matrix                |
| API field, request, response, event, webhook, or wire semantics | API contracts, executable schema/generator docs, client mappings, cross-client tests                     |
| SwiftData model or migration stage                              | Schema contract, startup recovery, migration test matrix, release/install-over gate                      |
| Auth, privacy, RLS, secrets, or data disclosure                 | Security/privacy contract, affected runbook, negative tests, public policy only when its promises change |
| CI selector, target, workflow, or benchmark methodology         | Testing strategy, focused quality guide, machine-readable selector manifest, workflow contract tests     |
| Deployment, promotion, rollback, or operator control            | Canonical runbook and release architecture; candidate evidence stays separate                            |
| User-visible copy, route, accessibility, or workflow            | Feature contract, relevant UI matrix, release notes when user-facing and release-bound                   |
| Historical incident follow-up                                   | Incident status/addendum and current contract; never erase original observations                         |

## Conflict resolution

1. Executable source, schemas, generators, and tests establish implemented
   behavior; documentation must not invent behavior they do not support.
2. Current canonical contracts own intended present behavior. If code differs,
   report the drift rather than silently choosing one side.
3. Local READMEs summarize their tree and link outward. They do not override a
   cross-surface contract.
4. RFCs, incidents, and release evidence remain valid historical records even
   after the current design changes.
5. When two current documents claim ownership, choose one canonical owner and
   replace the other claim with a concise link.

## Audit output

A complete audit identifies:

- the changed invariant and its source owner,
- every current document that states the invariant,
- any historical record that needs only a status link,
- exact tests or scripts backing the new claim,
- stale references intentionally removed,
- checks run and environment-limited checks left open.
