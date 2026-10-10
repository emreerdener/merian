import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008181427_fence_reserved_analysis_child_identity.sql",
    import.meta.url,
  ),
);
Deno.test("source child ingestion fence remains private and preserves canonical locking", () => {
  assert(!/CREATE (?:OR REPLACE )?FUNCTION public\./.test(source));
  assert(!/GRANT EXECUTE|GRANT (?:SELECT|INSERT|UPDATE|DELETE)/.test(source));
  assertEquals(
    (source.match(/CREATE TRIGGER b_guard_source_child_ingestion/g) ?? [])
      .length,
    3,
  );
  assert(
    source.indexOf("FOR KEY SHARE") <
      source.indexOf("'merian-scan-ingestion:' || child"),
  );
  assert(
    source.includes("internal.source_child_uuid(scan_id)=NEW.analysis_id"),
  );
  assert(source.includes("source_binding_ingestion_intent_uuid"));
  assert(source.includes("source_binding_ingestion_job_uuid"));
  assert(source.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
