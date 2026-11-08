import postgres from "npm:postgres@3.4.7";

// Digest-pinned recoveries, not permission to backfill arbitrary migrations.
export const RECOVERY_MIGRATION = {
  name: "20260927220537_hide_reported_explore_posts.sql",
  sha256: "f17a155a6784614b52cb4e2352a3c9cf026ebd3ce8788afb6c07d4440d7570e0",
};
export const RECOVERY_REMOTE_TIP = {
  name: "20260927230801_account_identification_invocations.sql",
  sha256: "790dd80c9c1540a7bc3a824a1c73e167de843e43435591233a1332067532f48d",
};

// Run #1860 applied the Gemini tip before these eight branch migrations merged.
export const HISTORY_RECOVERY_MIGRATIONS = [
  {
    name: "20261002213257_prepare_observation_analysis_history.sql",
    sha256: "13e1be36376b51adf1c10917a67948b9ba31c0efb463ff0459f99a8fb0e31e49",
  },
  {
    name: "20261002215330_protect_enrolled_observation_retention.sql",
    sha256: "bb923606ff46eebdbe156dc0eba5801870201f87de3a1706e49a555d86a47f1b",
  },
  {
    name: "20261002215809_prepare_observation_selection_transactions.sql",
    sha256: "afbb3239c085ef136091220558e579de04471721cf523e4bd849e54e4ec86294",
  },
  {
    name: "20261003034325_prepare_owner_analysis_history_reader.sql",
    sha256: "daf66cd04e821219b6e631b93d08501eca220edfc25ab045660cafd25652aafd",
  },
  {
    name: "20261003043015_prepare_observation_analysis_append.sql",
    sha256: "07b6222d75b2708185153e2c16562eced620cadc055b45768004063058dd6254",
  },
  {
    name: "20261003051251_prepare_private_observation_evidence.sql",
    sha256: "769e32df6f8409fafa79d134b19b47361e646350bd16e7206f350ff81e3d5fed",
  },
  {
    name: "20261003054717_prepare_funded_observation_analysis.sql",
    sha256: "d79fbdc19bc14096e608224fb870fd97c78faa0e2ea1f1518ccb576e6b0216aa",
  },
  {
    name: "20261003063309_bind_protected_analysis_evidence.sql",
    sha256: "1535ababcaa55513b0070e1fac3b5bc136cee47e3923ed040aaad608d7ce3c72",
  },
];
export const HISTORY_RECOVERY_REMOTE_TIP = {
  name: "20261003063950_restore_gemini_beta_photo_identification.sql",
  sha256: "2f3a3be89291dd34a0dc6acf8343dfc970f606f8c1f93b11faa0947a2ecc8981",
};

const PREFLIGHT_FAILURES = {
  invalid_local_history: "Invalid, duplicate, or empty local migration history",
  invalid_remote_history: "Invalid or duplicate remote migration version",
  remote_only_version: "Remote migration is absent from this candidate",
  unreviewed_history_gap:
    "Unreviewed out-of-order migration history; deployment remains blocked",
  reviewed_content_changed:
    "Reviewed migration content changed; deployment remains blocked",
} as const;

export class MigrationHistoryError extends Error {
  constructor(readonly reason: keyof typeof PREFLIGHT_FAILURES) {
    super(PREFLIGHT_FAILURES[reason]);
  }
}

export function migrationPreflightFailure(error: unknown): string {
  // Never serialize driver errors: messages, causes and connection fields may contain secrets.
  const reason = error instanceof MigrationHistoryError
    ? error.reason
    : "database_or_runtime_failure";
  return `Migration history preflight failed [${reason}]; inspect the reviewed candidate and migration versions. No migration was applied by this preflight.`;
}

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
      throw new MigrationHistoryError("invalid_local_history");
    }
    versions.set(version, file);
  }
  if (versions.size === 0) {
    throw new MigrationHistoryError("invalid_local_history");
  }
  const applied = new Set<string>();
  for (const version of remote) {
    if (
      typeof version !== "string" || !/^(\d{5}|\d{14})$/.test(version) ||
      applied.has(version)
    ) {
      throw new MigrationHistoryError("invalid_remote_history");
    }
    if (!versions.has(version)) {
      throw new MigrationHistoryError("remote_only_version");
    }
    applied.add(version);
  }
  const tip = [...applied].sort().at(-1) ?? "";
  const gaps = [...versions.keys()].filter((v) => v < tip && !applied.has(v));
  if (gaps.length === 0) return "normal";
  const recovery = [
    { migrations: [RECOVERY_MIGRATION], tip: RECOVERY_REMOTE_TIP },
    {
      migrations: HISTORY_RECOVERY_MIGRATIONS,
      tip: HISTORY_RECOVERY_REMOTE_TIP,
    },
  ].find((candidate) => {
    const reviewed = candidate.migrations.map((file) => file.name.slice(0, 14))
      .sort();
    const firstMissing = reviewed.findIndex((version) => !applied.has(version));
    const remaining = reviewed.slice(firstMissing);
    // db push applies in order. A retry can only have an applied prefix and a
    // missing suffix, never an arbitrary subset from a different execution order.
    return tip === candidate.tip.name.slice(0, 14) &&
      firstMissing >= 0 && gaps.length === remaining.length &&
      remaining.every((version) => gaps.includes(version));
  });
  if (!recovery) throw new MigrationHistoryError("unreviewed_history_gap");
  // Check the whole reviewed set, including already-applied members after an
  // interrupted push. Only remaining approved gaps can be backfilled.
  for (const reviewed of [...recovery.migrations, recovery.tip]) {
    const actual = versions.get(reviewed.name.slice(0, 14));
    if (actual?.name !== reviewed.name || actual.sha256 !== reviewed.sha256) {
      throw new MigrationHistoryError("reviewed_content_changed");
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
  } catch (error) {
    console.error(migrationPreflightFailure(error));
    Deno.exitCode = 1;
  }
}
