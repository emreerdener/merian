---
name: merian-docs-sync
description: "Audit and synchronize Merian documentation after code, ownership, API, security, operational, testing, or release-contract changes. Use when asked to update all necessary documentation, reconcile documentation drift, move a documented owner, or review whether current docs match implementation. Preserve historical RFC and incident facts; use the relevant implementation skill as well when code or a cross-surface contract changes."
---

# Merian Documentation Synchronization

Keep current contracts accurate without turning historical evidence into a
mutable description of the present.

## Establish the change boundary

1. Read `AGENTS.md`, inspect `git status`, and preserve unrelated work.
2. Inspect the complete affected diff, including generated files, tests, CI,
   manifests, and local READMEs. Do not infer the documentation surface from a
   single implementation file.
3. Read [documentation-ownership.md](references/documentation-ownership.md)
   completely, then read `docs/README.md`, `docs/CONTRIBUTING.md`, the nearest
   owner README, and every canonical document identified by the ownership map.
4. Load the implementation skill for any code or contract surface being changed.
   This skill coordinates documentation; it does not replace iOS, Supabase,
   API-contract, migration, web/admin, or release rules.

## Classify before editing

Classify every candidate document as one of these authorities:

- current normative contract,
- local ownership or contributor guide,
- executable test or operational runbook,
- historical RFC or incident record,
- release evidence or candidate-specific record.

Update current normative claims and ownership pointers in the same change as
their implementation. Preserve time-scoped facts, decisions, measurements, and
verification status in historical records. When current behavior supersedes a
historical record, add a clearly dated status note or link to the current
contract instead of rewriting the original evidence.

## Reconcile claims with sources

- Trace every changed owner, route, state transition, selector, command, and
  release gate to source or executable tests before documenting it.
- Search for stale symbols, paths, copy, route names, version numbers, and
  ownership statements with `rg`. Review each match in context; identical words
  do not imply identical authority.
- Keep `docs/README.md`, `docs/codebase-map.md`, local READMEs, verification
  matrices, and runbooks synchronized only where their stated scope applies.
- Prefer links to one canonical contract over copying a long rule into many
  documents. Short summaries must name the canonical owner.
- Report checks as passed only when they ran successfully for the current
  change. Distinguish source implementation, candidate validation, production
  deployment, runtime verification, and data recovery.
- Never place credentials, personal data, raw coordinates, auth/session state,
  or production response bodies in documentation or fixtures.

## Verify documentation

Format every changed Markdown file with `deno fmt <paths...>`, then run:

```bash
make validate-markdown-format
git diff --check
```

Run any link, generated-contract, or surface-specific validation required by the
implementation skill. If agent instructions, project skills, custom agents,
compatibility pointers, or agent-quality evaluations changed, also run
`make validate-agent-assets`.

At handoff, list the documents updated, the canonical owner chosen for each
claim, and any verification that remains unrun. Do not describe documentation as
synchronized when known stale references remain.
