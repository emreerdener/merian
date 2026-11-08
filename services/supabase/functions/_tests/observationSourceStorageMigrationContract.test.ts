import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008171734_prepare_analysis_source_binding_storage.sql",
    import.meta.url,
  ),
);
Deno.test("private source storage has no callable reservation or release path", () => {
  assertEquals(
    (source.match(/CREATE TABLE internal\.observation_analysis_source_/g) ?? [])
      .length,
    2,
  );
  assertEquals((source.match(/ENABLE ROW LEVEL SECURITY/g) ?? []).length, 2);
  assert(!/CREATE (?:OR REPLACE )?FUNCTION public\./.test(source));
  assert(!/GRANT EXECUTE|GRANT (?:SELECT|INSERT|UPDATE|DELETE)/.test(source));
  assert(
    source.includes("PRIMARY KEY(owner_id,observation_id,source_analysis_id)"),
  );
  assert(
    source.includes(
      "internal.observation_source_fingerprint(NEW.input_snapshot)",
    ),
  );
  assert(
    source.includes(
      "internal.lock_owned_observation_evidence(NEW.owner_id,NEW.observation_id)",
    ),
  );
  assert(source.includes("AFTER INSERT ON internal.scan_deletion_tombstones"));
  assert(source.includes("ghost_merge_source_history_requires_attention"));
  assert(source.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
