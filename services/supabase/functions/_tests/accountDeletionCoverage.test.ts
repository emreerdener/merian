import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const handlerUrl = new URL("../safe-delete/handler.ts", import.meta.url);
const workerUrl = new URL("../safe-delete/worker.ts", import.meta.url);
const dbUrl = new URL("../safe-delete/db.ts", import.meta.url);
const storageWorkerUrl = new URL(
  "../safe-delete/storageWorker.ts",
  import.meta.url,
);
const reaperUrl = new URL(
  "../reconcile-account-deletions/index.ts",
  import.meta.url,
);
const configUrl = new URL("../../config.toml", import.meta.url);
const workflowUrl = new URL(
  "../../../../.github/workflows/deploy.yml",
  import.meta.url,
);

Deno.test("account deletion source preserves durable cleanup-before-Auth ordering", async () => {
  const [handler, worker, db, storageWorker] = await Promise.all([
    Deno.readTextFile(handlerUrl),
    Deno.readTextFile(workerUrl),
    Deno.readTextFile(dbUrl),
    Deno.readTextFile(storageWorkerUrl),
  ]);

  assert(
    handler.indexOf("await request(userId, supabaseAdmin)") <
      handler.indexOf("await process(supabaseAdmin"),
    "The request receipt must be durable before the fast-path worker runs.",
  );
  assertStringIncludes(worker, 'if (cleanupPhase === "storage_pending")');
  assert(
    worker.indexOf('if (cleanupPhase === "storage_pending")') <
      worker.indexOf("await deleteAuth(claim.userId, supabaseAdmin)"),
    "Auth deletion must be unreachable while storage cleanup is pending.",
  );
  assert(
    worker.indexOf("await cleanup(supabaseAdmin, claim)") <
      worker.indexOf("await deleteAuth(claim.userId, supabaseAdmin)"),
    "Relational cleanup must complete before Auth deletion.",
  );
  assert(
    !worker.includes('if (claim.status === "pending")'),
    "Every retry must revalidate cleanup immediately before Auth deletion.",
  );
  assertStringIncludes(worker, '"completion_write_failed"');
  assertStringIncludes(db, "auth.admin.deleteUser(userId)");
  assertStringIncludes(db, 'error.code === "user_not_found"');
  assertStringIncludes(db, "status === 404");
  for (
    const fragment of [
      "claimStorageDeletionJobs",
      "listR2ObjectKeys",
      "deleteR2Object",
      "advanceStorageDeletionJob",
      "failStorageDeletionJob",
      "MAX_LIMIT = 4",
    ]
  ) {
    assertStringIncludes(storageWorker, fragment);
  }
});

Deno.test("account deletion reaper is service-only, bounded, and deployed", async () => {
  const [reaper, config, workflow] = await Promise.all([
    Deno.readTextFile(reaperUrl),
    Deno.readTextFile(configUrl),
    Deno.readTextFile(workflowUrl),
  ]);

  for (
    const fragment of [
      "timingSafeCompare(providedAuth, `Bearer ${serviceRoleKey}`)",
      'limit: "small"',
      "allowEmpty: true",
      "processAccountDeletionJobs(supabaseAdmin",
      "processPendingStorageDeletions(",
    ]
  ) {
    assertStringIncludes(reaper, fragment);
  }
  assert(
    !reaper.includes("targetUserId"),
    "The service reaper must never accept a caller-selected target user.",
  );

  const configStart = config.indexOf(
    "[functions.reconcile-account-deletions]",
  );
  const configEnd = config.indexOf("\n[functions.", configStart + 1);
  const section = config.slice(configStart, configEnd);
  assertStringIncludes(section, "verify_jwt = false");
  assertStringIncludes(
    workflow,
    "supabase/functions/_tests/accountDeletionCoverage.test.ts",
  );
  assertStringIncludes(
    workflow,
    "supabase/tests/account_deletion_security.sql",
  );
});
