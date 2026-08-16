# Codex Project Guidance

Codex is the only supported repository development agent. Keep universal rules
here and load task procedures from the project skills discovered through
`.agents/skills/`.

## Worktree and editing safety

- Inspect `git status` before changing files. Existing changes are user-owned;
  preserve unrelated work and do not rewrite or discard overlapping edits.
- Prefer the smallest scoped change. Do not create parallel writing agents or
  let multiple agents edit the same worktree.
- Treat checked-in generators and manifests as sources of truth. In particular,
  change `project.yml` and run `make xcodegen`; never hand-edit generated Xcode
  project files.
- Never place credentials, personal data, raw coordinates, auth/session state,
  or production response bodies in source, fixtures, logs, prompts, or
  artifacts.

## Deployment authorization

- Implementation, validation, green CI, and release preparation do not authorize
  deployment or external publication.
- Production Supabase mutations, Edge Function deployment, TestFlight upload or
  distribution, App Store actions, RevenueCat mutations, secret rotation, data
  cleanup, and rollback require an explicit user request naming the operation
  and target. Keep unknown targets read-only.
- Use `$merian-release` only after that explicit request. Preserve the reviewed
  exact-SHA, approval, evidence, and rollback controls in canonical runbooks.

## Documentation synchronization

- Before structural changes, read the associated canonical document under
  `docs/` and nearby README files.
- Update documentation in the same change when behavior, API payloads, domain
  boundaries, security or privacy contracts, operational controls, CI gates, or
  release procedures change. A local refactor with no externally meaningful
  contract change does not require broad documentation churn.
- Never treat Markdown-only edits as formatter-exempt. After editing Markdown,
  run `deno fmt` on every changed `.md` file before handoff. If the change
  touches `services/supabase/functions` or `services/supabase/scripts`, also run
  the exact candidate gate:
  `deno fmt --check services/supabase/functions services/supabase/scripts`. Do
  not rely on manual line wrapping as a substitute for the formatter.

## Supabase skill order

- For Supabase, PostgreSQL, database security, Deno Edge Functions,
  Supabase-backed clients, or backend release work, read these in order:
  `skills/user/supabase/SKILL.md`, then—when SQL, schema, migrations, queries,
  RLS, grants, or routines are involved—
  `skills/user/supabase-postgres-best-practices/SKILL.md`, then
  `skills/merian-supabase/SKILL.md`.
- Follow every conditionally required reference. The reviewed packages under
  `skills/user/` remain separate; verify their user-level links with
  `bash skills/user/install.sh --check`. Merian's checked-in contracts,
  commands, and exact tool pins take precedence over generic guidance.

## Verification

- Run the narrowest relevant checks while iterating, then the complete
  repository gate for every affected surface. Report what ran and what could not
  run; never imply an unrun check passed.
- New Swift files must compile, generated artifacts must be regenerated and
  diff-reviewed, Deno changes must pass recursive type checks, and database work
  must pass the repository's disposable-database and contract gates.
- Run `make validate-agent-assets` after changing these instructions, project
  skills, custom agents, legacy workflow pointers, or Agent Quality evaluation
  infrastructure.

## Read-only subagent delegation

- Delegate only when ownership or execution flow is unknown, a task spans at
  least two major subsystems, or a schema, API, security, concurrency, or
  release contract needs independent review.
- Use the matching read-only project agent: `merian_explorer` for evidence and
  path tracing, `merian_reviewer` for correctness and safety review, and
  `merian_contract_auditor` for cross-surface drift.
- Do not delegate routine single-file work or parallelize edits. Subagents
  return file-and-symbol evidence or review findings; the primary agent owns all
  writes.
