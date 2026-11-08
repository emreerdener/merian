import postgres from "npm:postgres@3.4.7";

export const INSPECTION_PROJECT = "qlarqavoqhkuwzmevrmf";
export const VERSION_LIMIT = 10_000;
const VERSION = /^(\d{5}|\d{14})$/;

// No URL, driver error, server notice, SQL statement, or migration name is output.
export const INSPECTION_FAILURE =
  "Migration inspection failed; verify Production connection configuration and metadata access. No migration was applied.";

type InspectionPhase =
  | "target_validation"
  | "local_inventory"
  | "metadata_read"
  | "report_write";
let phase: InspectionPhase = "target_validation";
const CONFIG_FAILURES = new Set([
  "invalid_connection_url",
  "target_mismatch",
  "unsupported_connection_options",
  "missing_existing_password",
]);

class ConnectionConfigurationError extends Error {
  constructor(readonly reason: string) {
    super(INSPECTION_FAILURE);
  }
}

export function inspectionFailureMessage(
  error: unknown,
  failedPhase: InspectionPhase,
): string {
  let reason = "unclassified_failure";
  if (
    error instanceof ConnectionConfigurationError &&
    CONFIG_FAILURES.has(error.reason)
  ) {
    reason = error.reason;
  } else if (error instanceof Error) {
    const code = "code" in error ? error.code : undefined;
    switch (code) {
      case "28P01":
        reason = "authentication_refused";
        break;
      case "42501":
        reason = "metadata_permission_refused";
        break;
      case "42P01":
        reason = "migration_table_unavailable";
        break;
      case "57014":
        reason = "statement_cancelled";
        break;
      case "ENETUNREACH":
      case "EHOSTUNREACH":
      case "ENOTFOUND":
      case "ECONNREFUSED":
      case "ETIMEDOUT":
        reason = "database_connection_unavailable";
        break;
      case "CERT_HAS_EXPIRED":
      case "DEPTH_ZERO_SELF_SIGNED_CERT":
      case "SELF_SIGNED_CERT_IN_CHAIN":
      case "UNABLE_TO_VERIFY_LEAF_SIGNATURE":
      case "UNABLE_TO_GET_ISSUER_CERT_LOCALLY":
      case "ERR_TLS_CERT_ALTNAME_INVALID":
        reason = "certificate_verification_failed";
        break;
    }
    if (error.name === "NotCapable" || error.name === "PermissionDenied") {
      reason = "runtime_permission_refused";
    }
  }
  // Only fixed labels are emitted. Never serialize the error, its message/cause,
  // unknown code, URL, host, username, password, or server response.
  return `${INSPECTION_FAILURE} [phase=${failedPhase}; reason=${reason}]`;
}

export function inspectionConnection(value: string, existingPassword = "") {
  let url: URL;
  let user: string;
  let password: string;
  try {
    url = new URL(value);
    user = decodeURIComponent(url.username);
    password = decodeURIComponent(url.password) || existingPassword;
  } catch {
    throw new ConnectionConfigurationError("invalid_connection_url");
  }
  const direct = url.hostname === `db.${INSPECTION_PROJECT}.supabase.co` &&
    user === "postgres";
  const pooler = /^[a-z0-9-]+\.pooler\.supabase\.com$/.test(url.hostname) &&
    user === `postgres.${INSPECTION_PROJECT}`;
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    !(direct || pooler) || url.pathname !== "/postgres" ||
    !["", "5432", "6543"].includes(url.port) ||
    (direct && url.port === "6543")
  ) throw new ConnectionConfigurationError("target_mismatch");
  if (
    url.hash ||
    [...url.searchParams].some(([key, val]) =>
      key !== "sslmode" || !["require", "verify-full"].includes(val)
    ) || [...url.searchParams].length > 1
  ) throw new ConnectionConfigurationError("unsupported_connection_options");
  if (!password) {
    throw new ConnectionConfigurationError("missing_existing_password");
  }
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
    Deno.env.get("MERIAN_DATABASE_PASSWORD") ?? "",
  );
  if (Deno.args.length === 1 && Deno.args[0] === "--validate-target") return;
  if (Deno.args.length !== 2) throw new Error(INSPECTION_FAILURE);
  const [comparisonSha, reportDirectory] = Deno.args;
  // Validate candidate identity and local filenames before opening a connection.
  phase = "local_inventory";
  const local = await localMigrationVersions();
  migrationVersionReport(local, [], comparisonSha);
  phase = "metadata_read";
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
  phase = "report_write";
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
  } catch (error) {
    console.error(inspectionFailureMessage(error, phase));
    Deno.exit(1);
  }
}
