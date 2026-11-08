import postgres from "npm:postgres@3.4.7";

export const INSPECTION_PROJECT = "qlarqavoqhkuwzmevrmf";
export const VERSION_LIMIT = 10_000;
const VERSION = /^(\d{5}|\d{14})$/;

// No URL, driver error, server notice, SQL statement, or migration name is output.
export const INSPECTION_FAILURE =
  "Migration inspection failed; verify Production connection configuration and metadata access. No migration was applied.";

export function inspectionConnection(value: string) {
  const url = new URL(value);
  const user = decodeURIComponent(url.username);
  const password = decodeURIComponent(url.password);
  const direct = url.hostname === `db.${INSPECTION_PROJECT}.supabase.co` &&
    user === "postgres";
  const pooler = /^[a-z0-9-]+\.pooler\.supabase\.com$/.test(url.hostname) &&
    user === `postgres.${INSPECTION_PROJECT}`;
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    !(direct || pooler) || !password || url.pathname !== "/postgres" ||
    url.hash || !["", "5432", "6543"].includes(url.port) ||
    (direct && url.port === "6543") ||
    [...url.searchParams].some(([key, val]) =>
      key !== "sslmode" || !["require", "verify-full"].includes(val)
    ) || [...url.searchParams].length > 1
  ) throw new Error(INSPECTION_FAILURE);
  // Build explicit options instead of forwarding query parameters to the driver.
  return {
    host: url.hostname,
    port: Number(url.port || 5432),
    user,
    password,
    database: "postgres",
  };
}

export function validatedVersions(values: unknown[]): string[] {
  if (
    values.length > VERSION_LIMIT ||
    values.some((v) => typeof v !== "string" || !VERSION.test(v)) ||
    new Set(values).size !== values.length
  ) throw new Error(INSPECTION_FAILURE);
  return (values as string[]).toSorted();
}

export async function localMigrationVersions(): Promise<string[]> {
  const versions: string[] = [];
  for await (
    const entry of Deno.readDir(new URL("../migrations/", import.meta.url))
  ) {
    if (!entry.name.endsWith(".sql")) continue;
    const match = /^(\d{5}|\d{14})_[a-zA-Z0-9_]+\.sql$/.exec(entry.name);
    if (!entry.isFile || !match || versions.length >= VERSION_LIMIT) {
      throw new Error(INSPECTION_FAILURE);
    }
    versions.push(match[1]);
  }
  if (!versions.length) throw new Error(INSPECTION_FAILURE);
  return validatedVersions(versions);
}

export function migrationVersionReport(
  localValues: unknown[],
  remoteValues: unknown[],
  comparisonSha: string,
) {
  if (!/^[a-f0-9]{40}$/.test(comparisonSha)) {
    throw new Error(INSPECTION_FAILURE);
  }
  const local = validatedVersions(localValues);
  const remote = validatedVersions(remoteValues);
  if (!local.length) throw new Error(INSPECTION_FAILURE);
  const localSet = new Set(local);
  const remoteSet = new Set(remote);
  return {
    project: INSPECTION_PROJECT,
    comparison_sha: comparisonSha,
    local_count: local.length,
    remote_count: remote.length,
    local_versions: local,
    remote_versions: remote,
    local_only_versions: local.filter((v) => !remoteSet.has(v)),
    remote_only_versions: remote.filter((v) => !localSet.has(v)),
  };
}

export type VersionReader = (query: string) => Promise<{ version: unknown }[]>;

// This function runs only inside the driver's pinned read-only transaction.
// The extra row detects truncation rather than silently reporting completeness.
export async function readMigrationVersions(query: VersionReader) {
  await query("SET LOCAL statement_timeout = '10s'");
  await query("SET LOCAL lock_timeout = '2s'");
  await query("SET LOCAL idle_in_transaction_session_timeout = '15s'");
  const rows = await query(
    "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version LIMIT 10001",
  );
  return validatedVersions(rows.map((row) => row.version));
}

async function main() {
  const connection = inspectionConnection(
    Deno.env.get("MERIAN_DATABASE_URL") ?? "",
  );
  if (Deno.args.length === 1 && Deno.args[0] === "--validate-target") return;
  if (Deno.args.length !== 2) throw new Error(INSPECTION_FAILURE);
  const [comparisonSha, reportDirectory] = Deno.args;
  // Validate candidate identity and local filenames before opening a connection.
  const local = await localMigrationVersions();
  migrationVersionReport(local, [], comparisonSha);
  const sql = postgres({
    ...connection,
    ssl: "verify-full",
    max: 1,
    prepare: false,
    debug: false,
    fetch_types: false,
    connect_timeout: 10,
    idle_timeout: 5,
    max_lifetime: 30,
    connection: {
      application_name: "merian-migration-inspection",
      default_transaction_read_only: true,
      statement_timeout: 10000,
      lock_timeout: 2000,
      idle_in_transaction_session_timeout: 15000,
    },
    onnotice: () => {},
  });
  let remote: string[];
  try {
    remote = await sql.begin(
      "read only",
      (tx) =>
        readMigrationVersions((query) =>
          tx.unsafe<{ version: unknown }[]>(query)
        ),
    );
  } finally {
    await sql.end({ timeout: 5 });
  }
  const report = {
    inspected_at: new Date().toISOString(),
    ...migrationVersionReport(local, remote, comparisonSha),
  };
  const markdown = [
    "# Supabase migration version inspection",
    "",
    "Read-only metadata snapshot; no deployment or compatibility clearance.",
    "Comparison uses this workflow's main commit, not an unpublished candidate.",
    "Migration versions do not prove migration contents or deployed function compatibility.",
    "",
    "```json",
    JSON.stringify(report, null, 2),
    "```",
    "",
  ].join("\n");
  await Deno.mkdir(reportDirectory, { recursive: true });
  await Deno.writeTextFile(
    `${reportDirectory}/migration-versions.json`,
    JSON.stringify(report, null, 2) + "\n",
  );
  await Deno.writeTextFile(
    `${reportDirectory}/migration-versions.md`,
    markdown,
  );
}

if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error(INSPECTION_FAILURE);
    Deno.exit(1);
  }
}
