import { assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260725045544_repair_complete_edge_database_contracts.sql",
  import.meta.url,
);

async function migrationSql(): Promise<string> {
  return (await Deno.readTextFile(migrationUrl)).replaceAll(/\s+/g, " ").trim();
}

Deno.test("complete Edge database repair restores publication and invoker contracts", async () => {
  const sql = await migrationSql();

  assertStringIncludes(
    sql,
    "requests.explore_published_at IS NOT NULL",
  );
  assertStringIncludes(sql, "ep.moderated_at IS NULL");
  assertStringIncludes(
    sql,
    "IN ('normal', 'withdrawn')",
  );
  assertStringIncludes(
    sql,
    "GRANT SELECT ON TABLE public.user_field_trips, public.field_trip_templates, public.field_trip_challenge_participants TO service_role",
  );
});

Deno.test("reference refresh sequences provenance mutations after candidate reconciliation", async () => {
  const sql = await migrationSql();

  assertStringIncludes(
    sql,
    "SELECT NULL::UUID AS id",
  );
  assertStringIncludes(
    sql,
    "reference_image_id = reference.id",
  );
  assertStringIncludes(
    sql,
    "FROM public.species_reference_images AS reference",
  );
  assertStringIncludes(
    sql,
    "WHERE source.disqualified_at IS NULL",
  );
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.refresh_merian_reference_images",
  );
});
