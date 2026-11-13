import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  HISTORY_RECOVERY_MIGRATIONS,
  HISTORY_RECOVERY_REMOTE_TIP,
  MigrationHistoryError,
  migrationPreflightFailure,
  planMigrationPush,
  readLocalMigrations,
  RECOVERY_MIGRATION,
  RECOVERY_REMOTE_TIP,
} from "./plan_database_migration_push.ts";

const baseline = {
  name: "20260927185833_require_identification_result_reader.sql",
  sha256: "baseline",
};
const future = { name: "20260929000000_future.sql", sha256: "future" };
const files = [baseline, RECOVERY_MIGRATION, RECOVERY_REMOTE_TIP];
const version = (file: { name: string }) => file.name.split("_")[0];
const remote = [version(baseline), version(RECOVERY_REMOTE_TIP)];

Deno.test("ordinary forward, empty, and already-recovered histories never enable include-all", () => {
  assertEquals(planMigrationPush(files, []), "normal");
  assertEquals(planMigrationPush(files, [version(baseline)]), "normal");
  assertEquals(planMigrationPush(files, files.map(version)), "normal");
  assertEquals(
    planMigrationPush([...files, future], files.map(version)),
    "normal",
  );
});

Deno.test("legacy five-digit versions participate in gap detection", () => {
  const legacy = { name: "00001_initial_schema.sql", sha256: "legacy" };
  assertEquals(
    planMigrationPush([legacy, ...files], ["00001", ...remote]),
    "reviewed-backfill",
  );
  assertThrows(() => planMigrationPush([legacy, ...files], remote));
  assertEquals(planMigrationPush([legacy, ...files], ["00001"]), "normal");
});

Deno.test("only the reviewed missing migration and remote tip enable recovery", () => {
  assertEquals(planMigrationPush(files, remote), "reviewed-backfill");
  assertEquals(
    planMigrationPush([...files].reverse(), [...remote].reverse()),
    "reviewed-backfill",
  );
  assertEquals(
    planMigrationPush([...files, future], remote),
    "reviewed-backfill",
  );
});

Deno.test("unknown gaps, extra gaps, remote-only versions and later remote tips fail closed", () => {
  assertThrows(() => planMigrationPush(files, [version(RECOVERY_REMOTE_TIP)]));
  assertThrows(() => planMigrationPush(files, [version(RECOVERY_MIGRATION)]));
  assertThrows(() => planMigrationPush(files, [...remote, version(future)]));
  assertThrows(() =>
    planMigrationPush([...files, future], [...remote, version(future)])
  );
});

Deno.test("modified or renamed reviewed SQL cannot authorize recovery", () => {
  for (const target of [RECOVERY_MIGRATION, RECOVERY_REMOTE_TIP]) {
    assertThrows(() =>
      planMigrationPush(
        files.map((f) => f === target ? { ...f, sha256: "changed" } : f),
        remote,
      )
    );
    assertThrows(() =>
      planMigrationPush(
        files.map((f) =>
          f === target ? { ...f, name: version(f) + "_renamed.sql" } : f
        ),
        remote,
      )
    );
  }
});

Deno.test("malformed and duplicate histories fail closed", () => {
  assertThrows(() => planMigrationPush([], []));
  assertThrows(() => planMigrationPush([...files, baseline], remote));
  assertThrows(() =>
    planMigrationPush([{ name: "invalid.sql", sha256: "x" }], [])
  );
  assertThrows(() => planMigrationPush(files, [...remote, remote[0]]));
  assertThrows(() => planMigrationPush(files, ["bad-version"]));
});

Deno.test("checked-in SQL bytes match the reviewed recovery and complete baseline", async () => {
  const local = await readLocalMigrations();
  const tip = version(RECOVERY_REMOTE_TIP);
  const applied = local.map(version).filter((v) =>
    v <= tip && v !== version(RECOVERY_MIGRATION)
  );
  assertEquals(planMigrationPush(local, applied), "reviewed-backfill");
  assertEquals(
    planMigrationPush(local, [...applied, version(RECOVERY_MIGRATION)]),
    "normal",
  );
});

Deno.test("deployment retains closed-mode selection and a dry-run before applying", async () => {
  const workflow = await Deno.readTextFile(
    new URL("../../../.github/workflows/deploy.yml", import.meta.url),
  );
  const block = workflow.slice(
    workflow.indexOf("- name: Push Database Migrations"),
    workflow.indexOf("- name: Enforce production privileged routine ACLs"),
  );
  assertStringIncludes(block, "plan_database_migration_push.ts");
  assertStringIncludes(block, "reviewed-backfill)");
  assertStringIncludes(
    block,
    '*) echo "Invalid migration preflight result." >&2; exit 1',
  );
  assertStringIncludes(
    block,
    'supabase db push "${push_args[@]}" --dry-run\n          supabase db push "${push_args[@]}"',
  );
  const candidate = await Deno.readTextFile(
    new URL(
      "../../../.github/workflows/supabase-candidate-validation.yml",
      import.meta.url,
    ),
  );
  assertStringIncludes(
    candidate,
    "bash supabase/scripts/test_migration_recovery_replay.sh",
  );
});

Deno.test("Gemini deployment followed by the eight history migrations permits only pinned gaps", async () => {
  const local = await readLocalMigrations();
  const tip = version(HISTORY_RECOVERY_REMOTE_TIP);
  const missing = HISTORY_RECOVERY_MIGRATIONS.map(version);
  // Reconstruct the successfully deployed #1860 source history, without any
  // production connection, and exercise every interrupted recovery prefix.
  const applied = local.map(version).filter((v) =>
    v <= tip && !missing.includes(v)
  );
  assertEquals(missing.length, 8);
  for (let recovered = 0; recovered <= missing.length; recovered++) {
    assertEquals(
      planMigrationPush(local, [...applied, ...missing.slice(0, recovered)]),
      recovered === missing.length ? "normal" : "reviewed-backfill",
    );
  }
  // Exhaust every subset, rejecting states that an ordered interrupted push
  // cannot produce (for example the second migration applied before the first).
  for (let mask = 0; mask < 2 ** missing.length; mask++) {
    const recovered = missing.filter((_, index) => (mask & (1 << index)) !== 0);
    if (recovered.every((value, index) => value === missing[index])) continue;
    assertThrows(
      () => planMigrationPush(local, [...applied, ...recovered]),
      MigrationHistoryError,
      "Unreviewed out-of-order migration history",
    );
  }
  const later = local.map(version).filter((v) => v > tip).sort()[0];
  assertThrows(() => planMigrationPush(local, [...applied, later]));
  assertThrows(() =>
    planMigrationPush(local, applied.filter((v) => v !== "00001"))
  );
  assertThrows(() => planMigrationPush(local, [...applied, "99999999999999"]));
  for (
    const pinned of [
      ...HISTORY_RECOVERY_MIGRATIONS,
      HISTORY_RECOVERY_REMOTE_TIP,
    ]
  ) {
    for (
      const replacement of [
        { ...pinned, sha256: "changed" },
        { ...pinned, name: version(pinned) + "_renamed.sql" },
      ]
    ) {
      assertThrows(() =>
        planMigrationPush(
          local.map((file) => file.name === pinned.name ? replacement : file),
          applied,
        )
      );
      assertThrows(() =>
        planMigrationPush(
          local.map((file) => file.name === pinned.name ? replacement : file),
          [...applied, missing[0]],
        )
      );
    }
  }
});

Deno.test("preflight reports closed reason codes without serializing unexpected errors", () => {
  assertStringIncludes(
    migrationPreflightFailure(
      new MigrationHistoryError("unreviewed_history_gap"),
    ),
    "[unreviewed_history_gap]",
  );
  const safe = migrationPreflightFailure(
    new Error("synthetic-sensitive-driver-detail"),
  );
  assertStringIncludes(safe, "[database_or_runtime_failure]");
  assertEquals(safe.includes("synthetic-sensitive-driver-detail"), false);
  assertEquals(
    migrationPreflightFailure({ message: "synthetic-sensitive-driver-detail" }),
    safe,
  );
});
