import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260727013416_future_proof_server_key_boundaries.sql",
  import.meta.url,
);
const migrationsUrl = new URL("../../migrations/", import.meta.url);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

async function latestMixedIncidentRoutine(): Promise<string> {
  const migrationNames: string[] = [];
  for await (const entry of Deno.readDir(migrationsUrl)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      migrationNames.push(entry.name);
    }
  }
  migrationNames.sort();

  const routinePrefix =
    "CREATE OR REPLACE FUNCTION public.get_owned_explore_media_incidents(";
  let latestRoutine = "";
  for (const migrationName of migrationNames) {
    const sql = normalized(
      await Deno.readTextFile(new URL(migrationName, migrationsUrl)),
    );
    const routineStart = sql.indexOf(routinePrefix);
    if (routineStart < 0) continue;
    const routineEnd = sql.indexOf("$$;", routineStart);
    assert(routineEnd >= 0, `${migrationName} has an unterminated routine.`);
    latestRoutine = sql.slice(routineStart, routineEnd + 3);
  }
  return latestRoutine;
}

Deno.test("server-key migration centralizes key-format-aware pg_net headers", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.server_api_request_headers( server_api_key TEXT )",
      "IF server_api_key ~ '^sb_secret_[A-Za-z0-9_-]{20,}$' THEN",
      "'^[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]{43}$'",
      "header_json ->> 'alg' = 'HS256'",
      "payload_json ->> 'role' = 'service_role'",
      "RAISE EXCEPTION 'invalid server API key configuration'",
      "'apikey', server_api_key",
      "'Authorization', 'Bearer ' || server_api_key",
      "REVOKE ALL ON FUNCTION internal.server_api_request_headers(TEXT) FROM PUBLIC, anon, authenticated, service_role",
      "pg_catalog.PG_GET_FUNCTIONDEF(routine_row.oid)",
      "PERFORM cron.alter_job( job_row.jobid, command := patched_command )",
      "A pg_net routine still uses Bearer-only server-key transport.",
      "An active cron job still uses Bearer-only server-key transport.",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const helperStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION internal.server_api_request_headers(",
  );
  const helperEnd = sql.indexOf(
    "COMMENT ON FUNCTION internal.server_api_request_headers(TEXT)",
    helperStart,
  );
  assert(
    !sql.slice(helperStart, helperEnd).includes(" STRICT "),
    "A null Vault key must execute the helper and fail rather than silently returning null headers.",
  );
  assert(
    !sql.includes("UPDATE cron.job"),
    "Cron jobs must be changed through cron.alter_job rather than direct catalog writes.",
  );
});

Deno.test("effective mixed incident routine dispatches by user identity before the server guard", async () => {
  const routine = await latestMixedIncidentRoutine();

  assert(routine.length > 0, "Mixed incident routine definition is missing.");
  assertStringIncludes(routine, "IF auth.uid() IS NULL THEN");
  assertStringIncludes(routine, "PERFORM internal.require_service_role()");
  assertStringIncludes(
    routine,
    "ELSIF auth.uid() IS DISTINCT FROM self_id THEN",
  );
  assert(
    !routine.includes("auth.role()"),
    "Mixed authorization must not dispatch on a role claim.",
  );
  assert(
    !routine.includes("CURRENT_SETTING('role'"),
    "Mixed authorization must delegate server-role checks to the shared guard.",
  );
});

Deno.test("new migrations cannot add Bearer-only pg_net server-key transport", async () => {
  for await (const entry of Deno.readDir(migrationsUrl)) {
    if (
      !entry.isFile ||
      !entry.name.endsWith(".sql") ||
      entry.name < "20260727013416"
    ) {
      continue;
    }
    const sql = await Deno.readTextFile(new URL(entry.name, migrationsUrl));
    assert(
      !/'Authorization'\s*,\s*'Bearer '\s*\|\|\s*service_role_key/i.test(
        sql,
      ),
      `${entry.name} adds Bearer-only pg_net server-key transport.`,
    );
  }
});
