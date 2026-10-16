import { assert, assertStringIncludes } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261005151359_retain_acknowledged_observation_science.sql",
    import.meta.url,
  ),
);
Deno.test("scientific retention uses the existing restricted row and never activates history", () => {
  assertStringIncludes(
    migration,
    "ALTER TABLE public.scans ADD COLUMN retained_identification JSONB",
  );
  assert(!/CREATE TABLE/i.test(migration));
  assert(!/UPDATE internal\.observation_history_rollout/i.test(migration));
  assertStringIncludes(migration, "user_id IS NULL AND is_tombstoned");
  assertStringIncludes(
    migration,
    "REVOKE INSERT(retained_identification), UPDATE(retained_identification)",
  );
});
Deno.test("scientific retention materializes before cascade under owner-first locks", () => {
  const body = migration.split(
    "CREATE OR REPLACE FUNCTION public.apply_user_tombstone",
  )[1];
  const ordered = [
    "FROM public.users AS users",
    "FOR UPDATE OF request NOWAIT",
    "FOR UPDATE OF published NOWAIT",
    "pg_advisory_xact_lock",
    "INTO original",
    "FOR SHARE OF r",
    "FOR SHARE OF a",
    "facts := internal.observation_retained_identification",
    "UPDATE public.scans SET (",
    "DELETE FROM public.users",
  ];
  let position = -1;
  for (const marker of ordered) {
    const next = body.indexOf(marker);
    assert(next > position, marker);
    position = next;
  }
  assertStringIncludes(
    migration,
    "projection IS DISTINCT FROM history.active_projection",
  );
  assertStringIncludes(
    migration,
    "ELSIF history.active_projection IS NOT NULL",
  );
});
Deno.test("scientific retention has an explicit baseline and rejects unknown generated columns", () => {
  const owner = migration.split(
    "CREATE FUNCTION internal.scientific_detached_observation",
  )[1].split("CREATE FUNCTION internal.guard_retained_observation")[0];
  const retained = [...owner.matchAll(/retained\.(\w+) := original\.\1;/g)].map(
    (match) => match[1],
  );
  assert(retained.length === 34);
  for (
    const forbidden of [
      "ai_reasoning",
      "captured_media",
      "user_observation_context",
      "ai_identification_review",
      "candidates",
      "pet_identification",
      "ecological_interactions",
    ]
  ) assert(!retained.includes(forbidden));
  assertStringIncludes(owner, "DECLARE retained public.scans;");
  assertStringIncludes(migration, "scientific_retention_schema_unclassified");
  assertStringIncludes(
    migration,
    "CREATE TRIGGER zz_guard_retained_observation",
  );
  assertStringIncludes(
    migration,
    "pg_catalog.to_jsonb(NEW) IS DISTINCT FROM pg_catalog.to_jsonb(expected)",
  );
  assertStringIncludes(
    migration,
    "pg_catalog.to_jsonb(NEW) IS DISTINCT FROM pg_catalog.to_jsonb(OLD)",
  );
});
