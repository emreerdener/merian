import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008191800_centralize_observation_source_binding_validation.sql",
    import.meta.url,
  ),
);
Deno.test("source binding validation remains private and cannot admit, release or dispatch", () => {
  assertEquals(
    (source.match(/CREATE FUNCTION internal\.lock_owned_observation_source/g) ??
      []).length,
    2,
  );
  assert(
    source.includes("binding.input_snapshot IS DISTINCT FROM p_expected_input"),
  );
  assert(source.includes("binding.fingerprint IS DISTINCT FROM fingerprint"));
  assert(
    source.includes("FROM internal.observation_analysis_source_occupancy"),
  );
  assert(source.includes("analysis_history_current_snapshot_required"));
  assert(
    !/GRANT |CREATE TABLE|CREATE (?:OR REPLACE )?FUNCTION public\./.test(
      source,
    ),
  );
  assert(!/INSERT INTO|UPDATE internal\.|DELETE FROM/.test(source));
});
