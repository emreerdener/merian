import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260726212549_harden_service_role_request_authentication.sql",
  import.meta.url,
);
const serverKeyBoundaryMigrationName =
  "20260727013416_future_proof_server_key_boundaries.sql";
const serverKeyBoundaryMigrationUrl = new URL(
  `../../migrations/${serverKeyBoundaryMigrationName}`,
  import.meta.url,
);
const migrationsDirectoryUrl = new URL("../../migrations/", import.meta.url);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

function withoutSqlComments(sql: string): string {
  return sql
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/--[^\r\n]*/g, " ");
}

Deno.test("taxonomy import history is inaccessible to public API roles", async () => {
  const migration = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    migration,
    "REVOKE ALL PRIVILEGES ON TABLE public.taxonomy_import_runs FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    migration,
    "GRANT SELECT, INSERT, UPDATE ON TABLE public.taxonomy_import_runs TO service_role",
  );
  assert(
    !migration.includes(
      "GRANT DELETE ON TABLE public.taxonomy_import_runs TO service_role",
    ),
    "Taxonomy workers do not require DELETE access to import history.",
  );
  assertStringIncludes(migration, "NOTIFY pgrst, 'reload schema'");
});

Deno.test("database-to-Edge dispatch supports opaque and legacy server keys", async () => {
  const migration = normalized(
    await Deno.readTextFile(serverKeyBoundaryMigrationUrl),
  );

  for (
    const fragment of [
      "BEGIN; CREATE OR REPLACE FUNCTION internal.server_api_request_headers( server_api_key TEXT )",
      "IF server_api_key ~ '^sb_secret_[A-Za-z0-9_-]{20,}$' THEN",
      "'^[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+[.][A-Za-z0-9_-]{43}$'",
      "header_json ->> 'alg' = 'HS256'",
      "payload_json ->> 'role' = 'service_role'",
      "RAISE EXCEPTION 'invalid server API key configuration'",
      "'apikey', server_api_key",
      "'Authorization', 'Bearer ' || server_api_key",
      "REVOKE ALL ON FUNCTION internal.server_api_request_headers(TEXT) FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION public.get_owned_explore_media_incidents",
      "IF auth.uid() IS NULL THEN PERFORM internal.require_service_role()",
      "GRANT EXECUTE ON FUNCTION public.get_owned_explore_media_incidents(UUID) TO authenticated, service_role",
      "internal.server_api_request_headers(service_role_key)",
      "FROM cron.job",
      "A pg_net routine still uses Bearer-only server-key transport.",
      "An active cron job still uses Bearer-only server-key transport.",
      "NOTIFY pgrst, 'reload schema'; COMMIT;",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }
});

Deno.test("later migrations cannot restore Bearer-only service-key dispatch", async () => {
  const violations: string[] = [];

  for await (const entry of Deno.readDir(migrationsDirectoryUrl)) {
    if (
      !entry.isFile ||
      !entry.name.endsWith(".sql") ||
      entry.name <= serverKeyBoundaryMigrationName
    ) {
      continue;
    }

    const sql = withoutSqlComments(
      await Deno.readTextFile(new URL(entry.name, migrationsDirectoryUrl)),
    );
    if (/'Bearer '\s*\|\|\s*service_role_key/i.test(sql)) {
      violations.push(entry.name);
    }
  }

  assert(
    violations.length === 0,
    "Later migrations must use internal.server_api_request_headers(...) for " +
      `database-to-Edge service-key dispatch: ${violations.join(", ")}`,
  );
});
