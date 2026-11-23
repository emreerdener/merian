import { assert } from "@std/assert";
const path = new URL(
  "../../migrations/20261120184235_preserve_initial_photo_preparation.sql",
  import.meta.url,
);
Deno.test("initial photo geometry migration preserves explicit readers and authority fences", async () => {
  const sql = await Deno.readTextFile(path);
  assert(sql.includes("internal.initial_photo_preparation_fields"));
  assert(sql.includes("pg_catalog.float8send"));
  assert(sql.includes("p_reader<>18 AND EXISTS"));
  assert(sql.includes("p_reader NOT IN (17,18)"));
  assert(sql.includes("ordinary_geometry_v9_source_drift"));
  assert(sql.includes("ordinary_geometry_v9_constraint_drift"));
  assert(
    !/GRANT\s|UPDATE\s+internal\.observation_history_rollout|cron\.schedule/i
      .test(sql),
  );
  assert(!sql.includes("isPro"));
});

Deno.test("full aspect selection successor changes acceptance without granting authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121192558_allow_full_aspect_photo_selection.sql",
      import.meta.url,
    ),
  );
  assert(
    sql.includes(
      "CREATE OR REPLACE FUNCTION internal.initial_photo_preparation_fields(p_value JSONB)",
    ),
  );
  assert(
    sql.includes(
      "crop_display_size'='null'::JSONB AND (p_value->'quarter_turns'<>'0'::JSONB",
    ),
  );
  assert(
    sql.includes(
      "p_value->>'format'='nativeSelectedStillImageV2' AND (p_value->'camera_vertical_center'<>'null'::JSONB OR selection IS NULL)",
    ),
  );
  assert(sql.includes("pg_catalog.float8send"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(!/GRANT\s|UPDATE\s|cron\.schedule/i.test(sql));
});
