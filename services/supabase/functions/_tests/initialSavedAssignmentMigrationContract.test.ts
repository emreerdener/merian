import { assert, assertEquals } from "@std/assert";
import assignmentSchema from "../_shared/initialAnalysis/assignment-schema-v2.json" with {
  type: "json",
};
import candidateSchema from "../_shared/initialAnalysis/preparation-candidate-schema-v2.json" with {
  type: "json",
};

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011192000_prepare_initial_saved_assignment.sql",
    import.meta.url,
  ),
);

Deno.test("saved assignment SQL and TypeScript closed schemas stay identical", () => {
  const schemas = [...migration.matchAll(/SELECT '(.*?)'::JSONB;/g)];
  assertEquals(JSON.parse(schemas[0][1]), assignmentSchema);
  assertEquals(JSON.parse(schemas[1][1]), candidateSchema);
});

Deno.test("saved assignment entrypoints retain service-only inactive authority", () => {
  for (
    const name of [
      "create_initial_preparation_intent",
      "get_initial_preparation_status",
      "finalize_initial_preparation",
    ]
  ) {
    const body = migration.split(`CREATE FUNCTION public.${name}`)[1]
      .split("$$;")[0];
    assert(body.includes("SECURITY DEFINER SET search_path=''"));
    assert(body.includes("PERFORM internal.require_service_role();"));
    assert(body.includes("PERFORM internal.lock_initial_preparation_scope("));
  }
  assert(migration.includes("FROM PUBLIC,anon,authenticated;"));
  assert(migration.includes("TO service_role;"));
  assert(migration.includes("'preserve',902,NULL"));
  assert(!/UPDATE internal\.initial_analysis_rollout/.test(migration));
  assert(!/CREATE (?:OR REPLACE )?FUNCTION .*dispatch/.test(migration));
});

Deno.test("shared funding and erasure patches require exact effective anchors", () => {
  const patches = migration.split("DO $quota$")[1];
  assert(patches.includes("anchor:='        IF usage_changed THEN'"));
  assert(patches.includes("resolved_plan,resolved_flash_fallback,FALSE"));
  assert(patches.includes("initial preparation core4 clock drift"));
  assert(patches.includes("initial preparation v1 replay drift"));
  assert(patches.includes("saved.binding_version<>1"));
  assert(patches.includes("internal.lock_initial_media_scope"));
  assert(patches.includes("public.apply_user_tombstone"));
  assert(patches.includes("fence_initial_analysis_before_owner_delete"));
  const mutations = patches.split(
    /(?:definition:=|EXECUTE )replace\(definition,anchor/,
  );
  assert(mutations.length > 10);
  for (const preceding of mutations.slice(0, -1)) {
    assert(preceding.includes("/length(anchor)<>1"));
  }
});
