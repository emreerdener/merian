---
name: merian-notion
description: "Connect Naturebook product knowledge to Merian repository work. Use when planning against Notion requirements, auditing approved intent against implementation, maintaining the skills index, or performing authorized documentation, delivery, decision, risk, or question updates in the Naturebook workspace. Not for unrelated code edits or automatic writes after each commit."
---

# Naturebook Notion Workflow

Use Naturebook for the workspace and public product; Merian names the codebase
and its stable engineering identifiers. Keep one canonical owner for each fact.

## Establish scope and destination

1. Read `AGENTS.md` and inspect `git status` before repository edits. Preserve
   user-owned changes. Read [workspace.md](references/workspace.md) for verified
   destinations and authority; never use personal-workspace migration copies.
2. Use the connected Notion tools and their current schemas. Verify the
   authenticated workspace ID matches the reference before writing. Fetch the
   target and verify its ancestry, schema and existing content before mutation.
   If the workspace differs or access fails, keep that target read-only, explain
   the gap and continue independent repository work. Do not create a replacement
   workspace, duplicate infrastructure or change the connection yourself.
3. Read the workspace Agent Operating Guide if present, otherwise the approved
   home and Planning & Operations working guide. Report a missing guide without
   treating a guide in another workspace as this workspace's authority. Resolve
   conflicts against the user's instruction and repository safety rules.
4. Consult relevant approved Notion requirements before substantial planning.
   Routine reads do not need renewed approval. If unavailable, identify the
   missing context; do not invent decisions or block independent safe work.

## Reconcile intent and evidence

- Notion owns approved product strategy, requirements, planning, decisions and
  business documentation. A draft, imported page, assistant suggestion or file
  commit is not product approval. Keep approval provenance and unresolved
  questions explicit. Do not silently change intent to match code.
- Git owns source, migrations, executable contracts, technical implementation
  and version history. Keep canonical architecture, API, security, privacy,
  testing and operational contracts with code. Use `$merian-docs-sync` and the
  relevant implementation skill for repository contract changes.
- Verify status against current source, configuration, tests and dated evidence.
  Distinguish local changes, committed implementation, inactive owners,
  candidate validation, environment-specific deployment and public release.
  Source presence, schema version or green CI alone never proves release.
- Record source links, verification date and commit/environment as applicable.
  Use immutable commits for audit evidence; label branch links as current
  navigation. Untracked files have no GitHub permalink. Leave unknown owners,
  target dates, costs, outcomes and hosted configuration unset or explicitly
  unknown. Preserve research exposure and qualification limits.

## Propose or apply updates

1. Recommend precise Notion changes when substantial scope, requirements,
   architecture, privacy, commercial assumptions or milestone evidence changes.
   Write only within the current task's authorization or explicit standing
   instructions. A request to implement code alone is not standing authorization
   to update Notion after every change. Keep same-change Git contract updates.
2. Reuse existing pages and records. Search/fetch before creation; do not assume
   partial search is exhaustive. Fetch a database's collection schema before
   writing rows; match exact properties, options and relation targets.
3. Use Delivery for feature outcomes and milestones, not a duplicate engineering
   task backlog. Keep Product status independent from Delivery status and relate
   children to their milestone. Released needs explicit environment/build/date
   and verification evidence; approved scope or a target date is insufficient.
4. Use Decisions & Issues for one decision, risk or question per row. Record
   rationale, alternatives, source and affected delivery work. Set Approved and
   its date only with explicit approval evidence. Link superseding records;
   preserve historical facts, pauses and rejected proposals. Record closure
   evidence without claiming the associated feature shipped.
5. Prefer concise technical overviews with Git links. Do not copy source files,
   SQL, generated schemas, research registers or operational evidence into a
   second mutable manual. The skills index is navigation, not an executable
   skill copy or an installation mechanism.
6. Keep private by default. Check actual access before restricted business or
   research imports; views and hidden properties do not restrict access. Never
   store secrets, transcripts, user data, raw coordinates, auth state, private
   fixtures or production/provider response bodies. Document financial scenario
   assumptions without inventing figures or promoting projections to actuals.

Read Notion's Markdown specification before content writes. Make targeted edits
that preserve child pages, databases, native mentions and unrelated content. Do
not change sharing, workspace-wide schemas or enabled skills as an inferred part
of documentation work. Setup and recordkeeping authorize no spending,
deployment, data cleanup or external publication.

## Verify and hand off

- Inspect each write result and warnings. Read back ancestry, stored statuses,
  relations, content or view filters when the result does not establish them.
  After an uncertain create, check for success before retrying to avoid
  duplicates.
- Report exact updated pages/records with links, sources and outstanding gaps.
  Distinguish source inspection from checks actually run. An inaccessible or
  plan-limited operation is not a successful update.
- For repository skill/instruction changes, format changed Markdown and run
  `make validate-agent-assets`, `make validate-markdown-format` and
  `git diff --check`. Keep the human skills directory synchronized when scope
  changes, without enabling workspace skills automatically.
