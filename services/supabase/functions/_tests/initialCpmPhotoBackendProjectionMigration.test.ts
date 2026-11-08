import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/cpm-photo-recovery-schema-v3.json" with {
  type: "json",
};
const sql = Deno.readTextFileSync(
  new URL(
    "../../migrations/20261030131532_prepare_initial_cpm_photo_backend_projection.sql",
    import.meta.url,
  ),
);
Deno.test("CPM v3 SQL embeds the closed recovery authority without changing legacy producers", () => {
  assertEquals(JSON.parse(sql.split("$schema$")[1]), schema);
  assert(!/CREATE OR REPLACE|ALTER TABLE|CREATE TABLE/.test(sql));
  assert(
    !/UPDATE internal.initial_analysis_rollout|INSERT INTO internal.initial_preparation_source_backends/
      .test(sql),
  );
  assert(
    !/current_selection|begin_initial_cpm_photo_write|clock_timestamp/.test(
      sql,
    ),
  );
  assert(sql.includes("saved.canonical_assignment::JSONB"));
  assert(sql.includes("WHERE generation=saved_generation"));
  assert(
    sql.includes("r.backend_generation IS DISTINCT FROM saved_generation"),
  );
});
Deno.test("CPM v3 service-only wrappers retain existing locked lifecycle owners", () => {
  assertEquals((sql.match(/SECURITY DEFINER/g) ?? []).length, 2);
  assertEquals(
    (sql.match(/PERFORM internal.require_service_role\(\)/g) ?? []).length,
    2,
  );
  assertEquals(
    (sql.match(/SET search_path='' SET statement_timeout='10s'/g) ?? []).length,
    2,
  );
  for (
    const name of [
      "create_initial_cpm_photo_v3_allocation",
      "get_initial_cpm_photo_v3_status",
    ]
  ) {
    assert(sql.includes(`'public.${name}(`));
    assert(sql.includes(`REVOKE ALL ON FUNCTION public.${name}`));
  }
  assert(
    sql.includes(
      "response:=public.create_initial_preparation_intent(p_owner,p_scan,p_candidate)",
    ),
  );
  assert(
    sql.includes(
      "response:=public.get_initial_preparation_status(p_owner,p_scan)",
    ),
  );
  assert(sql.includes("saved.owner_id IS DISTINCT FROM p_owner"));
  assert(
    sql.includes(
      "internal.parse_initial_cpm_photo_recovery(saved.canonical_candidate",
    ),
  );
  assert(!/GRANT (ALL|SELECT|UPDATE|INSERT|DELETE)/.test(sql));
});
