import postgres from "npm:postgres@3.4.7";

// A single reviewed recovery, not permission to backfill arbitrary migrations.
export const RECOVERY_MIGRATION = {
  name: "20260927220537_hide_reported_explore_posts.sql",
  sha256: "f17a155a6784614b52cb4e2352a3c9cf026ebd3ce8788afb6c07d4440d7570e0",
};
export const RECOVERY_REMOTE_TIP = {
  name: "20260927230801_account_identification_invocations.sql",
  sha256: "790dd80c9c1540a7bc3a824a1c73e167de843e43435591233a1332067532f48d",
};

export interface MigrationFile {
  name: string;
  sha256: string;
}

export function planMigrationPush(
  local: MigrationFile[],
  remote: string[],
): "normal" | "reviewed-backfill" {
  const versions = new Map<string, MigrationFile>();
  for (const file of local) {
    const version = /^(\d{5}|\d{14})_[a-zA-Z0-9_]+\.sql$/.exec(file.name)?.[1];
    if (!version || versions.has(version)) {
      throw new Error("Invalid or duplicate local migration version");
    }
    versions.set(version, file);
  }
  if (versions.size === 0) throw new Error("Local migration history is empty");
  const applied = new Set<string>();
  for (const version of remote) {
    if (
      typeof version !== "string" || !/^(\d{5}|\d{14})$/.test(version) ||
      applied.has(version)
    ) {
      throw new Error("Invalid or duplicate remote migration version");
    }
    if (!versions.has(version)) {
      throw new Error("Remote migration is absent from this candidate");
    }
    applied.add(version);
  }
  const tip = [...applied].sort().at(-1) ?? "";
  const gaps = [...versions.keys()].filter((v) => v < tip && !applied.has(v));
  if (gaps.length === 0) return "normal";
  const recoveryVersion = RECOVERY_MIGRATION.name.slice(0, 14);
  const reviewedTip = RECOVERY_REMOTE_TIP.name.slice(0, 14);
  if (gaps.length !== 1 || gaps[0] !== recoveryVersion || tip !== reviewedTip) {
    throw new Error(
      "Unreviewed out-of-order migration history; deployment remains blocked",
    );
  }
  for (const reviewed of [RECOVERY_MIGRATION, RECOVERY_REMOTE_TIP]) {
    const actual = versions.get(reviewed.name.slice(0, 14));
    if (actual?.name !== reviewed.name || actual.sha256 !== reviewed.sha256) {
      throw new Error(
        "Reviewed migration content changed; deployment remains blocked",
      );
    }
  }
  return "reviewed-backfill";
}

export async function readLocalMigrations(): Promise<MigrationFile[]> {
  const directory = new URL("../migrations/", import.meta.url);
  const files: MigrationFile[] = [];
  for await (const entry of Deno.readDir(directory)) {
    if (!entry.name.endsWith(".sql")) continue;
    if (!entry.isFile) throw new Error("Migration must be a regular file");
    const bytes = await Deno.readFile(new URL(entry.name, directory));
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    files.push({
      name: entry.name,
      sha256: [...digest].map((b) => b.toString(16).padStart(2, "0")).join(""),
    });
  }
  return files;
}

async function main(): Promise<void> {
  if (Deno.args.length) throw new Error("This preflight accepts no arguments");
  const databaseUrl = Deno.env.get("SUPABASE_DB_PUSH_URL");
  if (!databaseUrl) throw new Error("SUPABASE_DB_PUSH_URL is required");
  const local = await readLocalMigrations();
  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    debug: false,
    fetch_types: false,
    connect_timeout: 10,
    idle_timeout: 2,
    max_lifetime: 30,
    connection: { statement_timeout: 10000 },
    onnotice: () => {},
  });
  try {
    const rows = await sql.begin("read only", async (tx) => {
      return await tx<{ version: string }[]>`
        SELECT version FROM supabase_migrations.schema_migrations ORDER BY version
      `;
    });
    // stdout is a closed enum consumed by the workflow, never SQL or flags.
    console.log(planMigrationPush(local, rows.map((row) => row.version)));
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  try {
    await main();
  } catch {
    // Connection exceptions can contain credentials; never print driver errors.
    console.error(
      "Migration history preflight failed; inspect the reviewed candidate and migration versions. No migration was applied by this preflight.",
    );
    Deno.exitCode = 1;
  }
}
