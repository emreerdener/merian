# Codex Project Guidance

- Read `.agents/CLAUDE.md` completely before making repository changes.
- For any task involving Supabase, PostgreSQL migrations, database security,
  Deno Edge Functions, Supabase-backed clients, or backend release operations,
  read `skills/user/supabase/SKILL.md` completely. For PostgreSQL, schema,
  migration, query, RLS, grant, or database-routine work, also read
  `skills/user/supabase-postgres-best-practices/SKILL.md` completely. Then read
  `skills/merian-supabase/SKILL.md` completely before acting and follow every
  conditionally required reference it names.
- `skills/user/supabase` and `skills/user/supabase-postgres-best-practices` are
  the reviewed sources for the corresponding user skills. Install or verify
  their symlinks with `bash skills/user/install.sh --apply` or `--check`; do not
  merge either package into the Merian overlay.
- Apply the Merian overlay after the general Supabase skills. Merian's checked-in
  instructions, contracts, commands, and exact tool pins take precedence when
  generic guidance differs.
