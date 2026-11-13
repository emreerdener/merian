import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import {
  INSPECTION_PROJECT,
  inspectionConnection,
  inspectionFailureMessage,
  inspectionTls,
  localMigrationVersions,
  migrationVersionReport,
  readMigrationVersions,
  validatedVersions,
  VERSION_LIMIT,
} from "./inspect_migration_versions.ts";

const direct =
  `postgresql://postgres:synthetic@db.${INSPECTION_PROJECT}.supabase.co:5432/postgres`;
const pooler =
  `postgresql://postgres.${INSPECTION_PROJECT}:synthetic@aws-0-us-east-1.pooler.supabase.com:6543/postgres`;
const sha = "a".repeat(40);

Deno.test("inspection accepts only the fixed project with an existing password", () => {
  assertEquals(
    inspectionConnection(direct).host,
    `db.${INSPECTION_PROJECT}.supabase.co`,
  );
  assertEquals(inspectionConnection(pooler + "?sslmode=require").port, 6543);
  assertEquals(
    inspectionConnection(pooler.replace(":6543", ":5432")).port,
    5432,
  );
  assertEquals(
    inspectionConnection(direct.replace("synthetic", "a%40b%3Ac%2F%25"))
      .password,
    "a@b:c/%",
  );
  for (
    const invalid of [
      direct.replace(INSPECTION_PROJECT, "anotherproject"),
      pooler.replace(INSPECTION_PROJECT, "anotherproject"),
      direct.replace(".supabase.co", ".supabase.co.evil.test"),
      pooler.replace(".supabase.com", ".supabase.com.evil.test"),
      direct.replace("db." + INSPECTION_PROJECT + ".supabase.co", "127.0.0.1"),
      direct.replace("postgres:synthetic", "service_role:synthetic"),
      direct.replace(":synthetic", ""),
      direct.replace("5432", "6543"),
      pooler.replace("6543", "1234"),
      direct.replace("/postgres", "/other"),
      direct + "?sslmode=disable",
      direct + "?sslmode=require&sslmode=verify-full",
      direct + "?options=-c%20default_transaction_read_only%3Doff",
      direct + "?host=evil.test",
      direct + "?password=other",
      direct + "#fragment",
      "",
    ]
  ) assertThrows(() => inspectionConnection(invalid));
});

Deno.test("version report preserves legacy versions and describes both difference directions", () => {
  assertEquals(
    migrationVersionReport(["20261108000000", "00001"], [
      "00001",
      "20261107000000",
    ], sha),
    {
      project: INSPECTION_PROJECT,
      comparison_sha: sha,
      local_count: 2,
      remote_count: 2,
      local_versions: ["00001", "20261108000000"],
      remote_versions: ["00001", "20261107000000"],
      local_only_versions: ["20261108000000"],
      remote_only_versions: ["20261107000000"],
    },
  );
  assertEquals(migrationVersionReport(["00001"], [], sha).remote_count, 0);
  assertEquals(
    migrationVersionReport(["00001"], ["00001"], sha).local_only_versions,
    [],
  );
});

Deno.test("metadata output refuses malformed, duplicate, excessive, or injected values", () => {
  for (
    const values of [[null], [1], ["123456"], ["00001", "00001"], [
      "00001\n::error::injection",
    ], new Array(VERSION_LIMIT + 1).fill("00001")]
  ) {
    assertThrows(() => validatedVersions(values));
  }
  assertThrows(() => migrationVersionReport([], [], sha));
  assertThrows(() =>
    migrationVersionReport(["00001"], [], "main\n::error::injection")
  );
});

Deno.test("bounded reader sets limits before reading only the migration version column", async () => {
  const queries: string[] = [];
  const result = await readMigrationVersions((query) => {
    queries.push(query);
    return Promise.resolve(
      query.startsWith("SELECT") ? [{ version: "00001" }] : [],
    );
  });
  assertEquals(result, ["00001"]);
  assertEquals(queries, [
    "SET LOCAL statement_timeout = '10s'",
    "SET LOCAL lock_timeout = '2s'",
    "SET LOCAL idle_in_transaction_session_timeout = '15s'",
    "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version LIMIT 10001",
  ]);
});

Deno.test("reader propagates missing-table and invalid-history failures without a partial success", async () => {
  await assertRejects(() =>
    readMigrationVersions(() =>
      Promise.reject(new Error("synthetic missing table"))
    )
  );
  await assertRejects(() =>
    readMigrationVersions(() => Promise.resolve([{ version: "invalid" }]))
  );
});

Deno.test("current repository migration filenames form a nonempty valid version inventory", async () => {
  const versions = await localMigrationVersions();
  assertEquals(versions.length > 0, true);
  assertEquals(versions.includes("00001"), true);
});

Deno.test("manual workflow restricts Production inspection to main without deployment commands", async () => {
  const workflow = await Deno.readTextFile(
    ".github/workflows/supabase-migration-inspection.yml",
  );
  assertStringIncludes(workflow, "workflow_dispatch:");
  assertStringIncludes(workflow, "if: github.ref == 'refs/heads/main'");
  assertStringIncludes(workflow, "environment: Production");
  assertStringIncludes(workflow, "contents: read");
  assertStringIncludes(workflow, "persist-credentials: false");
  assertStringIncludes(workflow, "secrets.SUPABASE_DB_PASSWORD");
  assertStringIncludes(workflow, "--validate-target");
  assertStringIncludes(workflow, '--allow-net="$database_network_scope"');
  assertEquals(
    /schedule:|push:|pull_request:|supabase (link|db push|migration repair|functions deploy)|SUPABASE_ACCESS_TOKEN|add-mask|set -x/
      .test(workflow),
    false,
  );
  const source = await Deno.readTextFile(
    new URL("./inspect_migration_versions.ts", import.meta.url),
  );
  assertEquals(/sql\.begin\(\s*"read only"/.test(source), true);
  assertStringIncludes(source, "default_transaction_read_only: true");
  assertStringIncludes(source, "ssl: inspectionTls(ca)");
  assertStringIncludes(source, "fetch_types: false");
  assertStringIncludes(source, "onnotice: () => {}");
  assertStringIncludes(
    source,
    "console.error(inspectionFailureMessage(error, phase))",
  );
});

Deno.test("existing separate password fills only a validated password-free URL", () => {
  assertEquals(
    inspectionConnection(direct.replace(":synthetic", ""), "separate synthetic")
      .password,
    "separate synthetic",
  );
  assertEquals(
    inspectionConnection(direct, "other synthetic").password,
    "synthetic",
  );
  assertThrows(() =>
    inspectionConnection(
      direct.replace(INSPECTION_PROJECT, "otherproject"),
      "separate synthetic",
    )
  );
});

Deno.test("failure labels disclose neither credentials nor unknown driver details", () => {
  const privateDetail = "synthetic-private-connection-detail";
  const cases = [
    ["28P01", "authentication_refused"],
    ["42501", "metadata_permission_refused"],
    ["42P01", "migration_table_unavailable"],
    ["SELF_SIGNED_CERT_IN_CHAIN", "certificate_verification_failed"],
    ["ENETUNREACH", "database_connection_unavailable"],
    [privateDetail, "unclassified_failure"],
  ];
  for (const [code, reason] of cases) {
    const error = Object.assign(new Error(privateDetail), {
      code,
      cause: privateDetail,
    });
    const message = inspectionFailureMessage(error, "metadata_read");
    assertStringIncludes(message, `phase=metadata_read; reason=${reason}`);
    assertEquals(message.includes(privateDetail), false);
  }
  for (
    const [url, reason] of [
      ["invalid", "invalid_connection_url"],
      [direct.replace(INSPECTION_PROJECT, "otherproject"), "target_mismatch"],
      [direct + "?options=private", "unsupported_connection_options"],
      [direct.replace(":synthetic", ""), "missing_existing_password"],
    ]
  ) {
    try {
      inspectionConnection(url);
      throw new Error("expected refusal");
    } catch (error) {
      assertStringIncludes(
        inspectionFailureMessage(error, "target_validation"),
        `reason=${reason}`,
      );
    }
  }
});

Deno.test("inspection trusts the pinned public Supabase CA without disabling verification", async () => {
  const bytes = await Deno.readFile(
    new URL("./certificates/supabase-prod-ca-2021.crt", import.meta.url),
  );
  const digest = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  assertEquals(
    digest,
    "700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7",
  );
  const ca = new TextDecoder().decode(bytes);
  assertEquals(inspectionTls(ca), { ca, rejectUnauthorized: true });
});
