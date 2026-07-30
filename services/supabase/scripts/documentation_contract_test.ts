import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const repositoryRoot = new URL("../../../", import.meta.url);

function repositoryFile(relativePath: string): URL {
  return new URL(relativePath, repositoryRoot);
}

async function read(relativePath: string): Promise<string> {
  return await Deno.readTextFile(repositoryFile(relativePath));
}

function compact(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim();
}

async function unresolvedLocalMarkdownLinks(
  relativePath: string,
): Promise<string[]> {
  const source = await read(relativePath);
  const unresolved: string[] = [];

  for (const match of source.matchAll(/!?\[[^\]]*]\(([^)\r\n]+)\)/g)) {
    let destination = match[1].trim();
    if (destination.startsWith("<") && destination.endsWith(">")) {
      destination = destination.slice(1, -1);
    } else {
      destination = destination.replace(/\s+["'][^"']*["']$/, "");
    }

    destination = destination.split("#", 1)[0];
    if (
      !destination ||
      destination.startsWith("/") ||
      /^[a-z][a-z0-9+.-]*:/i.test(destination)
    ) {
      continue;
    }

    try {
      await Deno.stat(
        new URL(decodeURIComponent(destination), repositoryFile(relativePath)),
      );
    } catch {
      unresolved.push(destination);
    }
  }

  return unresolved;
}

Deno.test("credential documentation preserves the format-aware header contract", async () => {
  const [
    canonicalSource,
    apiSource,
    mediaSource,
    secretsSource,
    workerReadmeSource,
  ] = await Promise.all([
    read(
      "docs/backend-and-data/13-server-credentials-and-database-release-safety.md",
    ),
    read("docs/backend-and-data/05-api-contracts.md"),
    read(
      "docs/backend-and-data/12-explore-media-health-and-quarantine.md",
    ),
    read("docs/development-guides/05-keychain-and-secrets.md"),
    read(
      "services/supabase/functions/reconcile-explore-media-health/README.md",
    ),
  ]);
  const canonical = compact(canonicalSource);
  const api = compact(apiSource);
  const media = compact(mediaSource);
  const secrets = compact(secretsSource);
  const workerReadme = compact(workerReadmeSource);

  for (
    const fragment of [
      "Opaque publishable and secret project keys belong only in the standard `apikey` header.",
      "Bearer transport is reserved for a user access JWT or the legacy `service_role` JWT during migration overlap.",
      "`x-supabase-server-key` is not part of the protocol.",
      "non-reserved Edge secret `MERIAN_SUPABASE_SERVER_API_KEY`",
      "singular `SUPABASE_SECRET_KEY` for local/manual environments",
      "`/v1/projects/<ref>/api-keys?reveal=true`",
      "returns every real current publishable and exact legacy `anon` key for negative smoke controls",
      "makes at most five attempts for transport failures, HTTP 408/425/429, and HTTP 5xx",
      "fails immediately on HTTP 401/403",
      "never prints a credential, response body, token, or raw transport error",
      "creates downstream clients from the environment-resolved key, never from the accepted request value",
      "A malformed source contributes no authorization candidate and cannot veto an exact key supplied by another valid source.",
      "compares the exact local key's SHA-256 digest",
      "`scripts/verify_edge_secret_digest.ts`",
      "Positive smoke requests retry bounded transient deployment statuses for up to six attempts.",
      "Operational JSON Function calls also pass through `invokeServiceRoleJson(...)`.",
      "It withholds response bodies, request IDs, variable header values, and credentials.",
      "`20260727183356_restore_identity_first_media_incident_guard.sql`",
    ]
  ) {
    assertStringIncludes(canonical, fragment);
  }

  assertStringIncludes(
    secrets,
    "Hosted `SUPABASE_SECRET_KEYS` and `SUPABASE_PUBLISHABLE_KEYS` values are JSON objects",
  );
  assertStringIncludes(
    media,
    "Authorization is an exact constant-time comparison and never a table/RLS capability probe.",
  );
  assertStringIncludes(
    api,
    "`verify_jwt = false` does not make the route public",
  );
  assertStringIncludes(
    workerReadme,
    "an explicit `SUPABASE_SERVER_API_KEY`",
  );
  assertStringIncludes(
    workerReadme,
    "production-deploy-synchronized `MERIAN_SUPABASE_SERVER_API_KEY`",
  );
  assertStringIncludes(
    workerReadme,
    "non-JWT secret keys must use standard `apikey` only",
  );

  for (
    const obsoleteClaim of [
      "service-role-only database access probe",
      "Kong dynamically strips the `Authorization` header",
      "Gateway strips the `Authorization` header",
    ]
  ) {
    assert(
      !apiSource.includes(obsoleteClaim) &&
        !mediaSource.includes(obsoleteClaim),
      `Obsolete authorization guidance returned: ${obsoleteClaim}`,
    );
  }
});

Deno.test("database documentation preserves migration, RLS, and index safety", async () => {
  const [canonicalSource, schemaSource, contributingSource, backendSource] =
    await Promise.all([
      read(
        "docs/backend-and-data/13-server-credentials-and-database-release-safety.md",
      ),
      read("docs/backend-and-data/04-database-schema.md"),
      read("docs/CONTRIBUTING.md"),
      read("services/supabase/README.md"),
    ]);
  const canonical = compact(canonicalSource);
  const schema = compact(schemaSource);
  const contributing = compact(contributingSource);
  const backend = compact(backendSource);

  for (
    const fragment of [
      "normal migration apply path wraps pipeline-compatible statements and the history insert in a transaction",
      "new migrations at or after `20260727183356` contain no top-level transaction control",
      "`SET LOCAL` timeout guards are forbidden",
      "session `SET` with a matching `RESET`",
      "historical migrations that contain explicit transaction controls remain compatibility artifacts, not examples for future work",
      "Every table created in `public` must have effective RLS enabled",
      "PostgreSQL 17 `MAINTAIN`",
      "at most 32 MiB",
      "`pg_index.indisvalid` and `indisready`",
      "build equivalent valid leading indexes concurrently on every leaf partition first",
      "schema-qualified `SUBSTRING` calls use ordinary comma-separated function arguments",
      "every migration for schema-qualified `SUBSTRING` keyword syntax",
    ]
  ) {
    assertStringIncludes(canonical, fragment);
  }

  assertStringIncludes(
    schema,
    "Historical applied files with explicit controls remain immutable compatibility artifacts",
  );
  assertStringIncludes(
    schema,
    "`service_role` only `SELECT`, `INSERT`, and `DELETE`",
  );
  assertStringIncludes(
    schema,
    "`20260729120000_align_explore_share_state_media_health.sql` aligns",
  );
  assertStringIncludes(
    schema,
    "`SECURITY INVOKER`, and service-role-only; `PUBLIC`, `anon`, and `authenticated` cannot invoke it",
  );
  assertStringIncludes(
    contributing,
    "New migrations must not add top-level transaction controls or concurrent index DDL.",
  );
  assertStringIncludes(
    backend,
    "`tests/public_schema_security.sql` verifies those behaviors",
  );
  assertStringIncludes(
    backend,
    "`pg_catalog.SUBSTRING(value, pattern)`, not `pg_catalog.SUBSTRING(value FROM pattern)`",
  );
  assertStringIncludes(
    backend,
    "mutation-capable Make targets enforce this exact pin before touching a database or deploying a Function",
  );
});

Deno.test("operator documentation preserves destructive-queue and evidence rules", async () => {
  const [
    canonicalSource,
    runbookSource,
    agentSource,
    mediaIncidentSource,
    taxonomyChecklistSource,
    architectureSource,
  ] = await Promise.all([
    read(
      "docs/backend-and-data/13-server-credentials-and-database-release-safety.md",
    ),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
    read("docs/development-guides/07-ai-agent-guidelines.md"),
    read("docs/incidents/2026-07-account-scoped-r2-image-loss.md"),
    read("docs/backend-and-data/07-community-taxonomy-import-checklist.md"),
    read("docs/system-architecture/01-system-architecture.md"),
  ]);
  const canonical = compact(canonicalSource);
  const runbook = compact(runbookSource);
  const agent = compact(agentSource);
  const mediaIncident = compact(mediaIncidentSource);
  const taxonomyChecklist = compact(taxonomyChecklistSource);
  const architecture = compact(architectureSource);

  for (
    const fragment of [
      "An old `pending_storage_deletions` row is not deletion authority.",
      "Never clear an alert by blanket-deleting queue rows",
      "prepare a reviewed forward metadata migration after provenance is understood",
      "Every artifact includes `run_attempt` plus a run-specific identity",
      "Operational response bodies are withheld",
      "“Repository corrected” and “production verified” are deliberately separate statuses.",
    ]
  ) {
    assertStringIncludes(canonical, fragment);
  }

  assertStringIncludes(
    runbook,
    "Never blanket-delete outbox rows, sweep their prefixes, make them due, or run ad-hoc SQL merely to clear an alert.",
  );
  assertStringIncludes(
    runbook,
    "`scan-media-health-summary-<run_number>-attempt-<run_attempt>`",
  );
  assertStringIncludes(
    runbook,
    "Because this endpoint is read-only, transient network, routing, authorization-propagation, rate-limit, and server statuses receive at most six attempts",
  );
  assertStringIncludes(
    runbook,
    "A final invocation failure reports only HTTP status, bounded SDK failure class, and whether the fixed `X-Merian-Handler: 1` marker was present",
  );
  assertStringIncludes(
    runbook,
    "a fixed `X-Merian-Handler: 1` marker means the",
  );
  assertStringIncludes(
    runbook,
    "`services/supabase/scripts/verify_edge_secret_digest.ts` compares the exact selected key's SHA-256 digest",
  );
  assertStringIncludes(
    runbook,
    "A malformed source contributes no candidate and cannot veto an exact request key from another valid source.",
  );
  assertStringIncludes(
    runbook,
    "PostgREST RPC grants, and database logs without expecting a Function marker.",
  );
  assertStringIncludes(
    runbook,
    "If key resolution exhausts its five attempts on a retryable status such as HTTP 502",
  );
  assertStringIncludes(
    runbook,
    "run `require_supabase_cli_version.sh` before config parsing or mutation",
  );
  assertStringIncludes(runbook, "rerun the same workflow SHA");
  assertStringIncludes(
    runbook,
    "`20260729120000_align_explore_share_state_media_health.sql` aligns the owner-facing scan share-state visibility bit",
  );
  assertStringIncludes(
    runbook,
    "Require all four migration versions",
  );
  assertStringIncludes(
    runbook,
    "`client_can_read_scan_share_state_directly = false`",
  );
  assertStringIncludes(
    agent,
    "A queue marker is not destructive authority.",
  );
  assertStringIncludes(
    agent,
    "Do not create secret-derived diagnostics.",
  );
  assertStringIncludes(
    mediaIncident,
    "An orphan count is deliberately critical",
  );
  assertStringIncludes(
    mediaIncident,
    "never mutate queue state merely to obtain green",
  );
  assertStringIncludes(
    taxonomyChecklist,
    "isolated writer job commits it",
  );
  assertStringIncludes(
    architecture,
    "An orphan critical is a provenance incident, not deletion authority",
  );
});

Deno.test("documentation navigation and release notes expose the corrected contracts", async () => {
  const [
    rootReadme,
    documentationReadme,
    changelog,
    offlinePipeline,
    testing,
    logging,
    runbook,
    backendReadme,
    releaseHold,
  ] = await Promise.all([
    read("README.md"),
    read("docs/README.md"),
    read("CHANGELOG.md"),
    read("docs/backend-and-data/01-offline-sync-pipeline.md"),
    read("docs/development-guides/08-testing-strategy.md"),
    read("docs/development-guides/04-logging-and-debugging.md"),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
    read("services/supabase/README.md"),
    read(
      "docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md",
    ),
  ]);

  for (const source of [rootReadme, documentationReadme]) {
    assertStringIncludes(
      source,
      "13-server-credentials-and-database-release-safety.md",
    );
    assertStringIncludes(
      source,
      "14-dwca-and-public-web-release-hold-2026-07-27.md",
    );
    assertStringIncludes(
      source,
      "15-edge-function-fleet-review-2026-07-28.md",
    );
  }
  assertStringIncludes(
    compact(changelog),
    "full-member privacy revalidation now fences assembly, staging, email, and completion",
  );
  assertStringIncludes(
    compact(changelog),
    "Stale server retry timestamps now trigger a one-second client recheck",
  );
  assertStringIncludes(
    compact(changelog),
    "Closed the remaining exposed-table security gap",
  );
  assertStringIncludes(
    compact(offlinePipeline),
    "already stale schedules a one-second recheck",
  );
  assertStringIncludes(
    compact(testing),
    "`scripts/documentation_contract_test.ts` locks the same header matrix",
  );
  assertStringIncludes(
    compact(releaseHold),
    "the stable hosted `iOS Build and Test / Production readiness` result",
  );
  assertStringIncludes(
    compact(changelog),
    "DwC-A exports are now intentionally unavailable for the initial production launch",
  );
  assertStringIncludes(
    compact(changelog),
    "Focused DwC-A CI now grants Deno read access to every repository root",
  );
  assertStringIncludes(
    compact(changelog),
    "DwC-A health acquisition failures now fail closed",
  );
  assertStringIncludes(
    compact(changelog),
    "disposable-catalog scan ACL assertion now uses one exact five-column",
  );
  assertStringIncludes(
    compact(changelog),
    "Scan-table Data API privileges are now explicit",
  );
  assertStringIncludes(
    compact(changelog),
    "Fresh-catalog static analysis now passes an explicit trigger-relation OID",
  );
  assertStringIncludes(
    compact(changelog),
    "same-generation `failed_terminal / replay_exhausted` ingestion ledger",
  );
  assertStringIncludes(
    compact(changelog),
    "execute their mutating completion calls in dedicated statements before reading post-state",
  );
  assertStringIncludes(
    compact(changelog),
    "only failing test in iOS workflow run 73",
  );
  assertStringIncludes(
    compact(changelog),
    "next fresh-catalog parser blocker exposed by backend workflow run 1550",
  );
  assertStringIncludes(
    compact(runbook),
    "--allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/scripts,services/supabase/tests,apps/ios,.github/workflows",
  );
  assertStringIncludes(
    compact(testing),
    "Focused source-inspection lanes have a separate Deno permission contract.",
  );
  assertStringIncludes(
    compact(testing),
    "stable catalog/read/shape failure classification",
  );
  assertStringIncludes(
    compact(testing),
    "scan ACL check single-sources the exact five-column rolling-client update allowlist",
  );
  assertStringIncludes(
    compact(testing),
    "exact `service_role` CRUD",
  );
  assertStringIncludes(
    compact(testing),
    "every trigger routine to declare the relation OID that supplies its trigger context",
  );
  assertStringIncludes(
    compact(testing),
    "structured result summary",
  );
  assertStringIncludes(
    compact(logging),
    "`catalog_contract_missing/archive_cleanup` means production does not currently expose the required zero-argument cleanup-health RPC",
  );
  assertStringIncludes(
    compact(logging),
    "Do not reintroduce `[RepliesDebug]`, `[UIRepliesDebug]`, or identifier-bearing `print()` calls.",
  );
  assert(
    !logging.includes("## Comment Replies Diagnostic Tracing"),
    "Obsolete identifier-bearing reply tracing guidance returned.",
  );
  assertStringIncludes(
    compact(backendReadme),
    "Selected source-inspection lanes retain narrow permissions",
  );
  assertStringIncludes(
    compact(backendReadme),
    "An unreadable aggregate never becomes a zero-count result.",
  );
  assertStringIncludes(
    compact(backendReadme),
    "no launch path may depend on Supabase's changing automatic-exposure defaults",
  );
  assertStringIncludes(
    compact(runbook),
    "All six client-mutation table booleans must be false.",
  );
  assertStringIncludes(
    compact(runbook),
    "use zero only for ordinary routines and the concrete relation OID for each trigger",
  );
  assertStringIncludes(
    compact(runbook),
    "Never direct-write `complete`, which must remain protected by the completion fence.",
  );
  assertStringIncludes(
    compact(runbook),
    "Never embed a mutating routine call in an `AND` or `OR` assertion",
  );
  assertStringIncludes(
    compact(runbook),
    "`pg_catalog.SUBSTRING(value, pattern)` or `pg_catalog.SUBSTRING(value, 1, count)`",
  );
  assertStringIncludes(
    compact(runbook),
    "pg_catalog.SUBSTRING(table_name, 1, 24)",
  );
  assert(
    !runbook.includes("pg_catalog.SUBSTRING(table_name FOR"),
    "Runbook index SQL returned to invalid qualified SUBSTRING keyword syntax.",
  );
  assertStringIncludes(
    compact(releaseHold),
    "DwC-A is not part of the active initial-launch product surface",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Focused test evidence: run 1539 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Fresh-catalog scan ACL evidence: run 1541 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Explicit scan ACL evidence: run 1542 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Trigger static-validation evidence: run 1543 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Recovery-fixture evidence: run 1544 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Completion-order evidence: run 1545 attempt 1",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Production monitor catalog gap after failed deploys",
  );
  assertStringIncludes(
    compact(releaseHold),
    "Active export maximum-shape, queue-throughput, R2 multipart, Resend, and positive capability-delivery tests do not block that default-off promotion",
  );
});

Deno.test("fleet review inventory exactly matches configured Edge Functions", async () => {
  const [configSource, reviewSource] = await Promise.all([
    read("services/supabase/config.toml"),
    read(
      "docs/backend-and-data/15-edge-function-fleet-review-2026-07-28.md",
    ),
  ]);
  const configured = [...configSource.matchAll(/^\[functions\.([^\]]+)]$/gm)]
    .map((match) => match[1])
    .sort();
  const inventoryBlock = reviewSource.match(
    /## Reviewed Entrypoints\s+```text\s+([\s\S]*?)```/,
  );
  assert(inventoryBlock, "Fleet review entrypoint inventory is missing.");
  const documented = inventoryBlock[1].trim().split(/\s+/).sort();

  assertEquals(configured.length, 89);
  assertEquals(documented, configured);
  assertStringIncludes(
    compact(reviewSource),
    "Repository review complete. Exact-SHA application CI, production route, and authenticated customer smoke evidence remain release-blocking.",
  );
  assertStringIncludes(
    compact(reviewSource),
    "Preflight uses a validated legacy anon JWT only to cross the two intentional gateway `verify_jwt = true` boundaries",
  );
});

Deno.test("scan owner-row documentation preserves durable success and guarded recovery", async () => {
  const [
    rootSource,
    documentationSource,
    apiSource,
    runbookSource,
    agentSource,
    errorSource,
    featureSource,
    incidentSource,
    idempotencyIncidentSource,
    architectureRulesSource,
    identifyReadmeSource,
    statusReadmeSource,
    shareReadmeSource,
    purgeReadmeSource,
  ] = await Promise.all([
    read("README.md"),
    read("docs/README.md"),
    read("docs/backend-and-data/05-api-contracts.md"),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
    read("docs/development-guides/07-ai-agent-guidelines.md"),
    read("docs/development-guides/06-error-handling.md"),
    read("docs/features-and-hardware/05-insight-sheet.md"),
    read("docs/incidents/2026-07-scan-owner-row-durability-gap.md"),
    read("docs/incidents/2026-07-identify-idempotency-conflict.md"),
    read("docs/system-architecture/06-edge-modularization.md"),
    read("services/supabase/functions/identify-multimodal/README.md"),
    read("services/supabase/functions/check-scan-status/README.md"),
    read("services/supabase/functions/share-scan-to-explore/README.md"),
    read("services/supabase/functions/auto-purge-nonbio/README.md"),
  ]);
  const root = compact(rootSource);
  const documentation = compact(documentationSource);
  const api = compact(apiSource);
  const runbook = compact(runbookSource);
  const agent = compact(agentSource);
  const errors = compact(errorSource);
  const feature = compact(featureSource);
  const incident = compact(incidentSource);
  const idempotencyIncident = compact(idempotencyIncidentSource);
  const architectureRules = compact(architectureRulesSource);
  const identifyReadme = compact(identifyReadmeSource);
  const statusReadme = compact(statusReadmeSource);
  const shareReadme = compact(shareReadmeSource);
  const purgeReadme = compact(purgeReadmeSource);

  for (const source of [root, documentation]) {
    assertStringIncludes(
      source,
      "moderation, required media promotion, primary species resolution, scan",
    );
  }
  assertStringIncludes(
    documentation,
    "2026-07-scan-owner-row-durability-gap.md",
  );
  for (const source of [api, identifyReadme]) {
    assertStringIncludes(source, "scan_persistence_failed");
    assertStringIncludes(source, "observation_rejected");
  }
  assertStringIncludes(api, "Owner read-back");
  assertStringIncludes(api, "authenticated `user_id`");
  assertStringIncludes(identifyReadme, "owner-scoped read-back");
  assertStringIncludes(
    identifyReadme,
    "`multimodal/dead_letter_write_failed`",
  );
  assertStringIncludes(
    identifyReadme,
    "An ordinary owner generation may become quota-retry-ready only when",
  );
  assertStringIncludes(
    runbook,
    "Any current identify `200` followed immediately by owner status `not_found` is",
  );
  assertStringIncludes(
    runbook,
    "Do not roll `identify-multimodal` back to a version that can return success before owner-row read-back",
  );
  assertStringIncludes(
    runbook,
    "`generate-upload-urls`, `identify-multimodal`, `identify`, `identify-describe`, `audio-spec`, `check-scan-status`, `reconcile-scan-media-assets`, `repair-scan-image`, and `share-scan-to-explore`",
  );
  assertStringIncludes(
    runbook,
    "`20260728233000_recover_identity_merge_interrupted_scans.sql`",
  );
  assertStringIncludes(
    agent,
    "Identify success owns the scan row.",
  );
  assertStringIncludes(
    agent,
    "Missing-row recovery stays server-owned.",
  );
  assertStringIncludes(
    statusReadme,
    "Recovery is deliberately unavailable in bulk probes.",
  );
  assertStringIncludes(
    statusReadme,
    'client-facing `job_status = "failed"`',
  );
  assertStringIncludes(
    api,
    "`failed` is the client-safe projection of a `failed_terminal` ledger row.",
  );
  assertStringIncludes(
    shareReadme,
    "Media is never accepted inside `recovery_scan`",
  );
  assertStringIncludes(shareReadme, "A missing ledger also defers.");
  assertStringIncludes(
    incident,
    "Scan age was not the cause.",
  );
  for (const source of [api, runbook, idempotencyIncident]) {
    assertStringIncludes(source, "X-Merian-Idempotent-Replay");
    assertStringIncludes(
      source,
      "20260728220000_persist_idempotent_scan_responses.sql",
    );
    assertStringIncludes(source, "70 seconds");
  }
  for (const source of [runbook, idempotencyIncident]) {
    assertStringIncludes(
      source,
      "public.complete_scan_ingestion_finalization_with_response(uuid,uuid,jsonb,jsonb,text[])",
    );
    assertStringIncludes(source, "internal.privileged_routine_grants");
  }
  assertStringIncludes(
    idempotencyIncident,
    "This was not caused by scan age and does not require rescanning older observations.",
  );
  assertStringIncludes(
    idempotencyIncident,
    "a faulted post-row finalizer returns `503` to the fresh multimodal request, then a same-UUID retry reconstructs the marked response without provider redispatch",
  );
  assertStringIncludes(feature, "Restoring scan");
  assertStringIncludes(errors, "Safely saved");
  assertStringIncludes(
    errors,
    "No job / missing ledger | Defer; arbitrary local state is not recovery authority",
  );
  assertStringIncludes(
    architectureRules,
    "Await every operation required for the endpoint's documented success contract.",
  );
  assertStringIncludes(
    architectureRules,
    "A background promise remains bounded by the worker lifetime and is never a durability mechanism.",
  );
  assertStringIncludes(api, "request_scan_deletion");
  assertStringIncludes(api, "complete_scan_deletion");
  assertStringIncludes(api, "/reconcile-scan-deletions");
  assertStringIncludes(api, "compare-before-released");
  assertStringIncludes(runbook, "internal.scan_deletion_tombstones");
  assertStringIncludes(runbook, "get_scan_deletion_health()");
  assertStringIncludes(incident, "scan deletion tombstone");
  assertStringIncludes(incident, "independently leases oldest-due");
  assertStringIncludes(
    incident,
    "Scheduled retention cannot bypass that generation fence.",
  );
  assertStringIncludes(
    purgeReadme,
    "It does not delete R2 objects or scan rows in its HTTP invocation.",
  );
  assertStringIncludes(purgeReadme, "`is_tombstoned = false`");
  assertStringIncludes(purgeReadme, "`reconcile-scan-deletions`");

  const expectedCustomerMessages = [
    "Explore is temporarily unavailable. Please try again in a few minutes.",
    "This observation is still syncing. Please wait a moment and try sharing again.",
    "This observation is still syncing. Please try Field chat again in a moment.",
  ];
  for (const message of expectedCustomerMessages) {
    assertStringIncludes(errors, message);
    assertStringIncludes(feature, message);
  }

  for (
    const obsoleteClaim of [
      "inserting a minimal owned `scans` row",
      "all future ingestion silently halts",
      "It never blocks the HTTP response.",
      "strictly after returning the native HTTP `200 OK` response",
      "Only a missing ledger entry",
      "Promotion or persistence failure publishes nothing and rolls back promoted objects.",
      "handles only a generation fenced by identity merge",
      "No job or `complete` without a row",
      "bulk status probes remain read-only",
      "Bulk status remains read-only",
    ]
  ) {
    assert(
      !api.includes(obsoleteClaim) &&
        !errors.includes(obsoleteClaim) &&
        !feature.includes(obsoleteClaim) &&
        !identifyReadme.includes(obsoleteClaim) &&
        !architectureRules.includes(obsoleteClaim) &&
        !shareReadme.includes(obsoleteClaim),
      `Obsolete scan durability guidance returned: ${obsoleteClaim}`,
    );
  }
  for (
    const obsoleteBulkClaim of [
      "bulk status is read-only",
      "bulk status probes remain read-only",
      "Bulk status remains read-only",
      "Bulk probes remain read-only",
    ]
  ) {
    assert(
      !api.includes(obsoleteBulkClaim) &&
        !errors.includes(obsoleteBulkClaim) &&
        !incident.includes(obsoleteBulkClaim) &&
        !statusReadme.includes(obsoleteBulkClaim) &&
        !shareReadme.includes(obsoleteBulkClaim),
      `Obsolete bulk-status mutation guidance returned: ${obsoleteBulkClaim}`,
    );
  }
});

Deno.test("TestFlight scan recovery documentation preserves retry and legacy-share boundaries", async () => {
  const [
    rootSource,
    documentationSource,
    changelogSource,
    offlineSource,
    reliabilitySource,
    deploymentRunbookSource,
    loggingSource,
    coreDataSource,
    networkSource,
    insightSharingSource,
    insightChatSource,
    networkClientImplementationSource,
    insightViewModelImplementationSource,
    recordBindingImplementationSource,
    exploreSharingImplementationSource,
    insightSheetImplementationSource,
    collectionModifiersImplementationSource,
    candidateCardImplementationSource,
    namePreferencesImplementationSource,
    reportInsightImplementationSource,
    inferenceEngineImplementationSource,
    insightContentImplementationSource,
    candidateSwipeImplementationSource,
    shareButtonImplementationSource,
    chatViewModelImplementationSource,
    queuedContentImplementationSource,
    displayImplementationSource,
    toolbarImplementationSource,
    biologicalImplementationSource,
    confidenceBadgeImplementationSource,
    confidenceExplanationImplementationSource,
    mediaExportImplementationSource,
    signerReadmeSource,
    statusReadmeSource,
    shareReadmeSource,
    reconciliationReadmeSource,
    retryIncidentSource,
    shareIncidentSource,
    migrationSource,
    recoveryProofMigrationSource,
    recoverySource,
    signerSource,
    reconciliationWorkerSource,
    reconciliationDbSource,
    apiContractSource,
    backendArchitectureSource,
    mediaHealthSource,
    featureModulesSource,
    imagePipelineSource,
    supabaseReadmeSource,
    testingStrategySource,
    releaseVersioningSource,
    releasePreflightImplementationSource,
    releaseExportImplementationSource,
    queueDurabilityImplementationSource,
    settingsImplementationSource,
    settingsReadmeSource,
    offlineQueueTestsSource,
  ] = await Promise.all([
    read("README.md"),
    read("docs/README.md"),
    read("CHANGELOG.md"),
    read("docs/backend-and-data/01-offline-sync-pipeline.md"),
    read(
      "docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md",
    ),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
    read("docs/development-guides/04-logging-and-debugging.md"),
    read("apps/ios/Merian/Core/Data/README.md"),
    read("apps/ios/Merian/Core/Network/README.md"),
    read("apps/ios/Merian/Features/Insights/Sharing/README.md"),
    read("apps/ios/Merian/Features/Insights/Chat/README.md"),
    read("apps/ios/Merian/Core/Network/MerianNetworkClient.swift"),
    read(
      "apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Records.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Sharing/ViewModels/InsightSheetViewModel+ExploreSharing.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView.swift",
    ),
    read("apps/ios/Merian/Core/UI/Modifiers/CollectionModifiers.swift"),
    read(
      "apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Components/CandidatesCard.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Content/NamePreferences/ViewModels/InsightSheetViewModel+NamePreferences.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Reporting/ViewModels/ReportInsightViewModel.swift",
    ),
    read("apps/ios/Merian/Core/AI/InferenceEngine.swift"),
    read(
      "apps/ios/Merian/Features/Insights/Shell/Views/InsightContentView.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Views/CandidateSwipeModal.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Sharing/Components/InsightShareButton.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Chat/ViewModels/InsightChatViewModel.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Content/Views/QueuedContentView.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Shell/ViewModels/InsightSheetViewModel+Display.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Shell/Views/InsightSheetView+Toolbar.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Content/Views/BiologicalView.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Views/ConfidenceBadge.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/IdentificationReview/Confidence/Views/ConfidenceExplanationSheet.swift",
    ),
    read(
      "apps/ios/Merian/Features/Insights/Media/Utilities/InsightSheetViewModel+MediaExport.swift",
    ),
    read("services/supabase/functions/generate-upload-urls/README.md"),
    read("services/supabase/functions/check-scan-status/README.md"),
    read("services/supabase/functions/share-scan-to-explore/README.md"),
    read(
      "services/supabase/functions/reconcile-scan-media-assets/README.md",
    ),
    read(
      "docs/incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md",
    ),
    read(
      "docs/incidents/2026-07-media-abandoned-explore-share-recovery.md",
    ),
    read(
      "services/supabase/migrations/20260729173000_recover_media_abandoned_owned_scans.sql",
    ),
    read(
      "services/supabase/migrations/20260729200000_harden_media_abandoned_scan_recovery_proof.sql",
    ),
    read("services/supabase/functions/_shared/scanRecovery.ts"),
    read("services/supabase/functions/_shared/scanMediaAssets.ts"),
    read(
      "services/supabase/functions/reconcile-scan-media-assets/worker.ts",
    ),
    read("services/supabase/functions/reconcile-scan-media-assets/db.ts"),
    read("docs/backend-and-data/05-api-contracts.md"),
    read("docs/backend-and-data/02-supabase-edge-and-database.md"),
    read(
      "docs/backend-and-data/12-explore-media-health-and-quarantine.md",
    ),
    read("docs/features-and-hardware/07-feature-modules-and-ui.md"),
    read("docs/system-architecture/03-image-pipeline.md"),
    read("services/supabase/README.md"),
    read("docs/development-guides/08-testing-strategy.md"),
    read("docs/development-guides/14-ios-release-versioning.md"),
    read("scripts/check-ios-release-prep.sh"),
    read("scripts/export-ios-release.sh"),
    read(
      "apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueDurability.swift",
    ),
    read(
      "apps/ios/Merian/Features/Profile/Settings/Views/SettingsTabView.swift",
    ),
    read("apps/ios/Merian/Features/Profile/Settings/README.md"),
    read("apps/ios/MerianTests/Core/Data/OfflineQueueManagerTests.swift"),
  ]);

  for (const source of [rootSource, documentationSource]) {
    assertStringIncludes(
      source,
      "2026-07-failed-retryable-scan-status-upload-deadlock.md",
    );
    assertStringIncludes(
      source,
      "2026-07-media-abandoned-explore-share-recovery.md",
    );
  }

  for (
    const source of [
      offlineSource,
      reliabilitySource,
      coreDataSource,
      networkSource,
      retryIncidentSource,
    ]
  ) {
    assertStringIncludes(compact(source), "`server_retryable_failure`");
  }
  assertStringIncludes(
    compact(retryIncidentSource),
    "`/check-scan-status` requests | 64",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "`/identify`, `/identify-multimodal`, `/identify-describe`, or `audio-spec` | 0",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "the ambiguous field measured the two-byte `{}` request body, not the response",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "latest 100 first-parent commits",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "zero merge commits in that window",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "`cc664a20d6212299966b4579f733e612ed836514`",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "disabled both Wi-Fi and cellular data",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "not exact-source structured closure evidence",
  );
  assertStringIncludes(
    compact(shareIncidentSource),
    "positive tester-observed offline-queue evidence",
  );
  assertStringIncludes(
    compact(retryIncidentSource),
    "`fab31d92a5985c7c02669c33cadfcc2b1091e3a8`",
  );
  assertStringIncludes(
    compact(rootSource),
    "preserves one exact retry latch through re-stage",
  );
  assertStringIncludes(
    compact(changelogSource),
    "instead of endlessly alternating status checks and successful uploads",
  );
  for (
    const source of [
      rootSource,
      changelogSource,
      offlineSource,
      reliabilitySource,
      coreDataSource,
      retryIncidentSource,
    ]
  ) {
    assertStringIncludes(compact(source), "one trailing pass");
  }
  assertStringIncludes(
    testingStrategySource,
    "`inferenceReplayReconciliationCoalescesConcurrentWakeSources()`",
  );
  for (
    const source of [
      rootSource,
      changelogSource,
      offlineSource,
      reliabilitySource,
      coreDataSource,
      networkSource,
      retryIncidentSource,
    ]
  ) {
    const canonicalSource = compact(source);
    assert(
      canonicalSource.includes("mirror"),
      "Offline retry documentation must preserve its redundant durable-copy boundary.",
    );
    assertStringIncludes(canonicalSource, "monotonic maximum");
    assert(
      canonicalSource.includes("cloud-complete") ||
        canonicalSource.includes("completed-cloud") ||
        canonicalSource.includes("cloud result is complete"),
      "Offline retry documentation must preserve cloud-completion precedence.",
    );
  }
  for (
    const source of [
      rootSource,
      changelogSource,
      offlineSource,
      reliabilitySource,
      coreDataSource,
    ]
  ) {
    assertStringIncludes(compact(source), "description-only");
    assertStringIncludes(compact(source), "same scan UUID");
  }
  for (
    const source of [
      changelogSource,
      offlineSource,
      reliabilitySource,
      coreDataSource,
    ]
  ) {
    assertStringIncludes(compact(source), "process-local single-flight");
  }
  assertStringIncludes(
    compact(testingStrategySource),
    "`testManualRetryResetsBudgetForDescriptionOnlyScan`",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "`cloudDeletionDrainIsProcessSingleFlight`",
  );
  assertStringIncludes(
    compact(loggingSource),
    "unchanged queue/record snapshots and throttled duplicate pipeline kicks emit no refresh diagnostics",
  );
  assertStringIncludes(
    compact(loggingSource),
    "`status`, `requestBytes`, and `responseBytes` as distinct fields",
  );
  for (
    const benchmarkField of [
      "status=\\(httpResponse.statusCode",
      "requestBytes=\\(body?.count ?? 0",
      "responseBytes=\\(data.count",
    ]
  ) {
    assertStringIncludes(
      networkClientImplementationSource,
      benchmarkField,
    );
  }
  assert(
    !networkClientImplementationSource.includes(
      'transfer+server=\\(String(format: "%.3f", responseCompletedAt - authCompletedAt), privacy: .public)s bytes=\\(body?.count ?? 0',
    ),
    "The ambiguous request-body `bytes` benchmark must not return.",
  );
  assertStringIncludes(
    compact(networkSource),
    "canonical `{data:[...]}` envelope and one exact direct-array compatibility shape retained defensively",
  );
  assertStringIncludes(
    testingStrategySource,
    "`MerianNetworkClientTests.testExploreMediaIncidentsAcceptsLegacyEmptyArrayAtNetworkBoundary`",
  );
  assertStringIncludes(
    compact(changelogSource),
    "the former ambiguous `bytes` field measured the request",
  );
  for (
    const source of [
      changelogSource,
      offlineSource,
      loggingSource,
      settingsReadmeSource,
    ]
  ) {
    const canonicalSource = compact(source);
    assertStringIncludes(canonicalSource, "Beta Diagnostics");
    assertStringIncludes(canonicalSource, "source revision/fingerprint/state");
    assertStringIncludes(canonicalSource, "arbitrary");
  }
  for (
    const implementationFragment of [
      "let formatVersion: Int",
      "static let maximumRowsPerSection = 500",
      "min(max(1, requestedLimit), maximumRowsPerSection)",
      "jobDescriptor.fetchLimit =",
      "scanDescriptor.fetchLimit =",
      "eventDescriptor.fetchLimit = boundedEventLimit",
      "canonicalMachineToken(",
      "lastErrorMessage: nil",
      "message: nil",
      ".completeFileProtection",
      'forInfoDictionaryKey: "MERIAN_SOURCE_REVISION"',
      'forInfoDictionaryKey: "MERIAN_SOURCE_FINGERPRINT"',
      'forInfoDictionaryKey: "MERIAN_SOURCE_STATE"',
      "formatVersion: 1",
    ]
  ) {
    assertStringIncludes(
      queueDurabilityImplementationSource,
      implementationFragment,
    );
  }
  for (
    const settingsFragment of [
      "if Self.shouldShowQueueDiagnostics",
      "Share offline queue diagnostics",
      ".writeQueueDiagnosticsExport()",
      '"sandboxReceipt"',
    ]
  ) {
    assertStringIncludes(settingsImplementationSource, settingsFragment);
  }
  for (
    const testFragment of [
      "queueDiagnosticsExportOmitsPrivateAndFreeFormValues",
      "queueDiagnosticsRowLimitsAlwaysStayWithinOneThroughFiveHundred",
      "PRIVATE-MEDIA-PATH",
      "PRIVATE-DESCRIPTION",
      "PRIVATE-FIELD-NOTES",
      "PRIVATE-LOCATION",
      "PRIVATE-ERROR-MESSAGE",
      "PRIVATE-METADATA",
      "PRIVATE-MACHINE-FIELD",
      "for index in 0..<510",
      "eventLimit: .max",
      "writeQueueDiagnosticsExport(eventLimit: 0)",
      "maximumJobs.count == 500",
      "maximumScans.count == 500",
    ]
  ) {
    assertStringIncludes(offlineQueueTestsSource, testFragment);
  }
  for (
    const provenanceKey of [
      "`MERIAN_SOURCE_REVISION`",
      "`MERIAN_SOURCE_FINGERPRINT`",
      "`MERIAN_SOURCE_STATE`",
    ]
  ) {
    assertStringIncludes(releaseVersioningSource, provenanceKey);
  }
  assertStringIncludes(
    compact(releaseVersioningSource),
    "the final `Info.plist` must be a single-link regular file",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "Symbolic links and multiple hard links are rejected before `PlistBuddy` can write through them",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "A marker from an earlier source tree cannot authorize an archive",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "`prepared_from_sha`, the exact commit on which release preparation began",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "valid commit and an ancestor of the final clean checkout",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "parses the marker as typed JSON",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "CI-only marker instead requires `ci_validation_only: true` and an exact `source_sha`",
  );
  for (
    const implementationFragment of [
      "read_marker_value prepared_from_sha string",
      "read_marker_value source_sha string",
      '--is-ancestor "$marker_prepared_from_sha" "$source_revision"',
      '"$marker_ci_validation_only" == "true"',
    ]
  ) {
    assertStringIncludes(
      releasePreflightImplementationSource,
      implementationFragment,
    );
  }
  assertStringIncludes(
    compact(releaseVersioningSource),
    "sourceState=clean",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "globally higher App Store Connect build number",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "`EXPORT_PATH` must resolve to a child of this repository's `build/` directory",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "`EXPORT_OPTIONS_PLIST` must resolve inside that export directory",
  );
  assertStringIncludes(
    compact(releaseVersioningSource),
    "lexical `.`/`..` components—including traversal hidden behind a not-yet-created directory—are rejected",
  );
  for (
    const exportImplementationFragment of [
      'reject_dot_path_components "EXPORT_PATH" "$export_path_input"',
      'reject_dot_path_components "EXPORT_OPTIONS_PLIST" "$export_options_input"',
    ]
  ) {
    assertStringIncludes(
      releaseExportImplementationSource,
      exportImplementationFragment,
    );
  }
  for (const source of [releaseVersioningSource, shareIncidentSource]) {
    const canonicalSource = compact(source);
    assertStringIncludes(
      canonicalSource,
      "all 417 retained local",
    );
    assertStringIncludes(
      canonicalSource,
      "zero archives contained",
    );
  }
  assertStringIncludes(
    compact(loggingSource),
    "`source=unavailable` identifies a build made before provenance embedding",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "stale release-marker rejection after tracked-source changes",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "typed local-marker preparation ancestry, typed CI-marker exact-SHA enforcement, malformed identity rejection",
  );
  for (
    const source of [
      apiContractSource,
      backendArchitectureSource,
      mediaHealthSource,
      featureModulesSource,
      imagePipelineSource,
      supabaseReadmeSource,
    ]
  ) {
    const canonicalSource = compact(source);
    assertStringIncludes(canonicalSource, '`{"data":[...]}`');
    assert(
      canonicalSource.includes("direct array") ||
        canonicalSource.includes("direct-array"),
      "Media-incident rollout documentation must preserve the exact legacy direct-array compatibility boundary.",
    );
  }
  assertStringIncludes(
    compact(apiContractSource),
    "Rapid queue-driven refresh triggers are coalesced within five seconds",
  );
  assertStringIncludes(
    compact(apiContractSource),
    "A trigger received during an in-flight call receives one trailing refresh rather than being dropped",
  );
  assertStringIncludes(
    compact(networkSource),
    "revalidates the authenticated owner before projecting the private incident queue",
  );
  assertStringIncludes(
    compact(featureModulesSource),
    "malformed `2xx` bodies fail as `invalidResponse`",
  );

  const localShareStart = networkClientImplementationSource.indexOf(
    "func shareScanToExplore(\n        scan: LocalScanRecord",
  );
  const localShareEnd = networkClientImplementationSource.indexOf(
    "func requestCommunityIdentification(",
    localShareStart,
  );
  assert(
    localShareStart >= 0 && localShareEnd > localShareStart,
    "Local Explore-share implementation could not be isolated.",
  );
  const localShare = compact(
    networkClientImplementationSource.slice(localShareStart, localShareEnd),
  );
  const recoveryPayloadIndex = localShare.indexOf(
    "let recoveryScan = try await makeOwnedScanRecoveryPayload(",
  );
  const ownerRecoveryIndex = localShare.indexOf(
    "let recovered = try await recoverMissingOwnedCloudScan(",
  );
  const restoreSigningIndex = localShare.indexOf(
    "let restoredObjectKeys = try await restoreExploreMediaObjectKeys(",
  );
  assert(
    recoveryPayloadIndex >= 0 &&
      ownerRecoveryIndex > recoveryPayloadIndex &&
      restoreSigningIndex > ownerRecoveryIndex,
    "Current iOS must build recovery evidence and repair the missing owner row before requesting restore upload URLs.",
  );
  assertStringIncludes(localShare, "recoveryScan: recoveryScan");
  assertStringIncludes(
    compact(networkClientImplementationSource),
    'if let code = stableEdgeErrorCode(from: error) { return code == "not_found" }',
  );
  assertStringIncludes(
    compact(networkClientImplementationSource),
    "snapshot.scanId.caseInsensitiveCompare(expectedScanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(insightViewModelImplementationSource),
    "scanBoundActionGeneration &+= 1",
  );
  assertStringIncludes(
    compact(recordBindingImplementationSource),
    "scanBoundActionGeneration &+= 1",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "generation == scanBoundActionGeneration",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "isPresentingLocalRecord( scanId: scanId, generation: generation )",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "state.sharedExplorePostId? .caseInsensitiveCompare(postId) == .orderedSame",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "state.sharedCommunityIdentificationRequestId? .caseInsensitiveCompare(requestId) == .orderedSame",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "MerianNetworkClient.shouldAttemptExploreCloudScanRestore( after: error )",
  );
  assertStringIncludes(
    compact(exploreSharingImplementationSource),
    "cacheSharedExplorePostId( nil, for: scanId, generation: generation )",
  );
  assertStringIncludes(
    compact(insightSheetImplementationSource),
    "pendingDeletionScanId = targetScanId",
  );
  assertStringIncludes(
    compact(insightSheetImplementationSource),
    "newCollectionAlertBinding",
  );
  assertStringIncludes(
    compact(insightSheetImplementationSource),
    "exploreOnboardingPresentedBinding",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "identificationReviewWriteTail = Task",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "current.scientificName.caseInsensitiveCompare(scientificName) == .orderedSame",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "executeSpeciesMetadataWrite( scanId: capturedScanId, scientificName: capturedScientificName, presentationGeneration: capturedPresentationGeneration",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "presentationGeneration: historicPresentationGeneration, reviewActionGeneration: reviewActionGeneration",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "private let pendingBackgroundWriteTaskCap = 8",
  );
  assertStringIncludes(
    compact(inferenceEngineImplementationSource),
    "guard pendingBackgroundTasks.count < pendingBackgroundWriteTaskCap else",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "bounded inference metadata-write backlog",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "explorePostComposerPresentationGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "communityRequestPresentationGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "explorePostComposerPresentationPostId",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "communityRequestPresentationRequestId",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "let carouselGeneration = viewModel.scanBoundActionGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "observationPresentationGeneration = carouselGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "fullscreenGalleryPresentationGeneration = carouselGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "candidateSwipeEnginePresentationGeneration",
  );
  assertStringIncludes(
    compact(insightContentImplementationSource),
    "viewModel.state.safariPresentationScanId? .caseInsensitiveCompare(expectedScanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(candidateSwipeImplementationSource),
    "inferenceEngine.scanPresentationGeneration == presentationGeneration",
  );
  assertStringIncludes(
    compact(shareButtonImplementationSource),
    "actionGeneration &+= 1",
  );
  assertStringIncludes(
    compact(shareButtonImplementationSource),
    "actionPresentationGeneration == presentationGeneration",
  );
  assertStringIncludes(
    compact(shareButtonImplementationSource),
    "isActionPresentationCurrent( submittedScanId, generation: submittedGeneration )",
  );
  assertStringIncludes(
    compact(shareButtonImplementationSource),
    "optionsActionGeneration == expectedGeneration",
  );
  assertStringIncludes(
    compact(shareButtonImplementationSource),
    "composerActionGeneration == expectedGeneration",
  );
  assertStringIncludes(
    compact(chatViewModelImplementationSource),
    "subjectGeneration &+= 1",
  );
  assertStringIncludes(
    compact(chatViewModelImplementationSource),
    "response.subjectId? .caseInsensitiveCompare(scanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(queuedContentImplementationSource),
    "viewModel.refreshQueuedContextIfCurrent( refreshed, expectedScanId: scanId )",
  );
  assertStringIncludes(
    compact(queuedContentImplementationSource),
    "retryingScanId? .caseInsensitiveCompare(scanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(displayImplementationSource),
    "queuedContext?.id .caseInsensitiveCompare(expectedScanId) == .orderedSame",
  );
  assertStringIncludes(
    compact(displayImplementationSource),
    "cachedActiveMedia = refreshedContext.capturedMediaSnapshot.activeScanMedia",
  );
  assertStringIncludes(
    compact(displayImplementationSource),
    "func audioBoostBinding( expectedScanId: String, expectedGeneration: UInt64 ) -> Binding<Bool>",
  );
  assertStringIncludes(
    compact(displayImplementationSource),
    "func isPresentingMedia( scanId: String, generation: UInt64 ) -> Bool",
  );
  assertStringIncludes(
    compact(toolbarImplementationSource),
    "let toolbarGeneration = viewModel.scanBoundActionGeneration",
  );
  assertStringIncludes(
    compact(toolbarImplementationSource),
    "viewModel.saveUserPhotos( expectedScanId: scanId, expectedGeneration: toolbarGeneration",
  );
  assertStringIncludes(
    compact(toolbarImplementationSource),
    "viewModel.shareDiscovery( expectedScanId: scanId, expectedGeneration: toolbarGeneration",
  );
  assertStringIncludes(
    compact(toolbarImplementationSource),
    "selectedInsightChatGeneration = toolbarGeneration",
  );
  assertStringIncludes(
    compact(biologicalImplementationSource),
    ".sheet(isPresented: namePickerPresentedBinding)",
  );
  assertStringIncludes(
    compact(biologicalImplementationSource),
    "isSafariPresented: safariPresentedBinding(",
  );
  assertStringIncludes(
    compact(confidenceBadgeImplementationSource),
    "inferenceEngine.scanPresentationGeneration == expectedGeneration",
  );
  assertStringIncludes(
    compact(confidenceExplanationImplementationSource),
    "private var isSubjectPresentationCurrent: Bool",
  );
  for (
    const mediaExportEntryPoint of [
      "func saveUserPhotos( expectedScanId: String, expectedGeneration: UInt64",
      "func shareDiscovery( expectedScanId: String, expectedGeneration: UInt64",
    ]
  ) {
    assertStringIncludes(
      compact(mediaExportImplementationSource),
      mediaExportEntryPoint,
    );
  }
  assertStringIncludes(
    compact(recordBindingImplementationSource),
    "func bindQueuedPresentation(_ context: QueuedScanContext)",
  );
  assertStringIncludes(
    compact(insightViewModelImplementationSource),
    "sharedExploreStateRevision &+= 1",
  );
  assertStringIncludes(
    compact(insightViewModelImplementationSource),
    "sharedExploreStateRequestToken &+= 1",
  );
  assertStringIncludes(
    compact(insightSheetImplementationSource),
    "viewModel.bindQueuedPresentation(newScan)",
  );
  assertStringIncludes(
    compact(collectionModifiersImplementationSource),
    "guard canExecuteAction?() != false else",
  );
  assertStringIncludes(
    compact(candidateCardImplementationSource),
    "inferenceEngine.scanPresentationGeneration == generation",
  );
  assertStringIncludes(
    compact(candidateCardImplementationSource),
    "swipeModalGeneration = presentedGeneration",
  );
  assertStringIncludes(
    compact(namePreferencesImplementationSource),
    "generation: expectedGeneration",
  );
  assertStringIncludes(
    compact(reportInsightImplementationSource),
    "engine.scanPresentationGeneration == presentationGeneration",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "The completed engine scan ID is also the client presentation authority.",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "completed engine result, active local-record model and ID, and immutable toolbar snapshot",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "`InsightShareButton` has an independent action generation",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "the parent view model's presentation generation",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "exact post or request UUID they addressed",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "The follow-up post-detail read is advisory",
  );
  assertStringIncludes(
    compact(insightChatSource),
    "`InsightChatViewModel` provides a second subject boundary",
  );
  assertStringIncludes(
    compact(insightChatSource),
    "parent Insight sheet applies the same scan/generation check",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "Local/cloud review writes and review-triggered species-metadata writes execute through one serial tail",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "A queued-to-completed transition advances that generation even when the UUID is unchanged",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "a direct parent `queuedScan` A → B replacement invalidates A before binding B",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "Issue reporting rejects a supplied scan that no longer matches the engine before remote or local flag mutation",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "Reset also advances the Explore request and revision clocks instead of zeroing them",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "changed-scan and stale same-scan-generation issue-report rejection",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "post/request publication target capture, target-scoped sheet dismissal",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "An authoritative share-state `404` activates compatibility behavior only",
  );
  assertStringIncludes(
    compact(changelogSource),
    "Fenced Field Chat and Explore actions to one exact presented scan.",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "the joined presentation-identity, offline-handoff, response-validation, and bounded-backlog follow-up is committed",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "The exact-identity fixture and fail-closed result-gate follow-up is committed on `main` as `21df28d6be1d20b27a1a31bd5812689b5a3c8fa5`",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "The exact Swift Testing display-name validator follow-up is committed on `main` as `bdf84b52e146c3777240c83937025adf2aaf1150`",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "Exact-source portable repetition passes",
  );
  assertStringIncludes(
    compact(reliabilitySource),
    "critical-result validator with 61 protected exact cases total, including all 19 added by the joined follow-up, five menu/Field Notes regressions exposed by the prior failed hosted run, the two bounded/redacted queue-diagnostic cases, and the actual network-boundary media-incident compatibility case",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "The current validator protects 61 exact cases; 19 were added by the joined scan-reliability follow-up, five menu/Field Notes regressions exposed by the prior failed hosted run are individually protected, two require the bounded/redacted offline-queue support artifact, and the media-incident compatibility case exercises the actual network-client boundary",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "the inference engine's completed `SpeciesData.scanId`, `activeLocalRecord`, `activeLocalRecordId`, and `toolbarRecordSnapshot` must identify the same scan",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "an Edge mock that represents a handler-owned `404` must include `X-Merian-Handler: 1`",
  );
  assertStringIncludes(
    compact(testingStrategySource),
    'Swift Testing reports an explicit `@Test("Display Name")` through that display name rather than the source function name',
  );
  assertStringIncludes(
    compact(testingStrategySource),
    "never use substring or suite-only matching as a workaround",
  );
  assertStringIncludes(
    compact(shareIncidentSource),
    "A same-account legacy-record smoke test is also mandatory.",
  );
  assertStringIncludes(
    compact(shareIncidentSource),
    "The trace therefore predates the remediation by about four hours",
  );

  for (
    const source of [
      reliabilitySource,
      signerReadmeSource,
      statusReadmeSource,
      shareReadmeSource,
      reconciliationReadmeSource,
      shareIncidentSource,
      insightSharingSource,
    ]
  ) {
    assertStringIncludes(
      compact(source),
      "composite",
    );
    assertStringIncludes(
      compact(source),
      "media_reconciliation_abandoned",
    );
  }
  assertStringIncludes(
    compact(insightSharingSource),
    "asks single-scan status recovery to commit the guarded owner row and requires an authoritative `found` response",
  );
  assertStringIncludes(
    compact(insightSharingSource),
    "currently released/TestFlight client uses the older order",
  );
  assertStringIncludes(
    compact(shareIncidentSource),
    "`multimodal/dead_letter_write_failed`",
  );
  assertStringIncludes(
    compact(shareIncidentSource),
    "check-scan-status(recovery_scan) → 503 service_unavailable",
  );
  for (
    const source of [
      rootSource,
      changelogSource,
      reliabilitySource,
      shareIncidentSource,
      supabaseReadmeSource,
    ]
  ) {
    const recoveryBoundary = compact(source);
    assertStringIncludes(recoveryBoundary, "immutable");
    assertStringIncludes(recoveryBoundary, "dead-letter-ID snapshot");
    assertStringIncludes(recoveryBoundary, "transaction-start timestamp");
  }
  for (
    const source of [
      rootSource,
      changelogSource,
      reliabilitySource,
      deploymentRunbookSource,
      shareIncidentSource,
      supabaseReadmeSource,
      apiContractSource,
      signerReadmeSource,
      statusReadmeSource,
      shareReadmeSource,
    ]
  ) {
    const rolloutFence = compact(source);
    assertStringIncludes(rolloutFence, "separate migration-file transactions");
    assertStringIncludes(rolloutFence, "predeploy");
  }
  for (
    const source of [
      reliabilitySource,
      deploymentRunbookSource,
      shareIncidentSource,
      supabaseReadmeSource,
      apiContractSource,
    ]
  ) {
    const rolloutFence = compact(source);
    assertStringIncludes(rolloutFence, "`generate-upload-urls`");
    assertStringIncludes(rolloutFence, "`check-scan-status`");
    assertStringIncludes(rolloutFence, "`share-scan-to-explore`");
  }
  const recoveryImplementation = compact(recoverySource);
  const boundaryProofIndex = recoveryImplementation.indexOf(
    '"get_media_abandoned_scan_recovery_proofs"',
  );
  const atomicRecoveryIndex = recoveryImplementation.indexOf(
    '"recover_missing_owned_scan"',
  );
  assert(
    boundaryProofIndex >= 0 && atomicRecoveryIndex > boundaryProofIndex,
    "Owner-row reconstruction must prove the hardened migration boundary before calling the atomic recovery routine.",
  );
  assertStringIncludes(
    recoveryImplementation,
    "hardened recovery boundary unavailable",
  );
  for (
    const isolatedRecoveryVeto of [
      "moderation-only legacy evidence",
      "pre-safety legacy evidence",
      "wrong-producer endpoint",
      "incomplete structured safety",
      "active replay",
      "corrupt timestamp lineage",
    ]
  ) {
    assertStringIncludes(
      compact(shareIncidentSource),
      isolatedRecoveryVeto,
    );
  }
  for (
    const requiredMirrorRegression of [
      "`testScheduleInferenceRetryUsesMonotonicMirroredAttempt`",
      "`testInferenceRetryCannotOverrideCompletedCloudOwnership`",
    ]
  ) {
    assertStringIncludes(
      compact(testingStrategySource),
      requiredMirrorRegression,
    );
  }

  const migration = compact(migrationSource);
  assertStringIncludes(
    migration,
    "FROM public.failed_scan_ingestions AS failures",
  );
  assertStringIncludes(
    migration,
    "failures.scan_id = p_scan_id::TEXT",
  );
  assertStringIncludes(migration, "failures.user_id = p_user_id");
  const recoveryProofMigration = compact(recoveryProofMigrationSource);
  assertStringIncludes(
    recoveryProofMigration,
    "internal.media_abandoned_scan_has_recovery_proof",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "exact_reservations.state = 'reserved'",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "exact_reservations.committed_at < exact_reservations.reserved_at",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "failures.failed_at >= latest_authority.authority_at",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "failures.quota_reservation_id = latest_authority.id",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "failures.identify_safety_evaluation_completed IS TRUE",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "CREATE TABLE IF NOT EXISTS internal.scan_recovery_legacy_dead_letters",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "WITH inserted_control AS ( INSERT INTO internal.scan_recovery_evidence_control",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "ON CONFLICT (singleton) DO NOTHING RETURNING legacy_unstructured_before",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "legacy_failures.failed_scan_ingestion_id = failures.id",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "failures.failed_at < evidence_control.legacy_unstructured_before",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "jobs.endpoint = 'identify-multimodal'",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "pg_catalog.LOWER(failures.error_message) NOT LIKE 'failed to ensure scan user exists:%'",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "pg_catalog.LOWER(failures.error_message) NOT LIKE '%moderation%'",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "latest_authority.attempt = 0",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "latest_authority.attempt_count = 1",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "assets.failure_reason IN ( 'moderation_rejected', 'moderation_pipeline_error' )",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "'scan-ingestion-replay:' || attempts.attempt::TEXT",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "pg_catalog.GENERATE_SERIES(1, 10)",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "candidates.state IN ('failed', 'committed')",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "jobs.terminal_reason_code = 'media_reconciliation_abandoned'",
  );
  assertStringIncludes(
    recoveryProofMigration,
    "pg_catalog.NOW() - INTERVAL '30 days'",
  );
  assertStringIncludes(
    compact(signerSource),
    '"get_media_abandoned_scan_recovery_proofs"',
  );
  assertStringIncludes(
    compact(reconciliationWorkerSource),
    'job.status !== "complete" && job.status !== "failed_terminal"',
  );
  assertStringIncludes(
    compact(reconciliationDbSource),
    '.not("status", "in", "(complete,failed_terminal)")',
  );
  assertStringIncludes(
    compact(reconciliationReadmeSource),
    "It never overwrites an existing `complete` or `failed_terminal` decision",
  );
});

Deno.test("joined scan reliability documentation preserves critical contracts", async () => {
  const [
    joinedSource,
    rootSource,
    documentationSource,
    generateUploadSource,
    multimodalSource,
    identifyCompatibilitySource,
    describeCompatibilitySource,
    audioCompatibilitySource,
    repairImageSource,
    exploreShareSource,
    exploreShareStateSource,
    communityRequestSource,
    insightChatSource,
    coreDataSource,
    chatClientSource,
    sharingClientSource,
    exploreFeedSource,
    incidentSource,
    videoIncidentSource,
    offlinePipelineSource,
    errorHandlingSource,
    networkClientSource,
    inAppChangelogSource,
  ] = await Promise.all([
    read(
      "docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md",
    ),
    read("README.md"),
    read("docs/README.md"),
    read("services/supabase/functions/generate-upload-urls/README.md"),
    read("services/supabase/functions/identify-multimodal/README.md"),
    read("services/supabase/functions/identify/README.md"),
    read("services/supabase/functions/identify-describe/README.md"),
    read("services/supabase/functions/audio-spec/README.md"),
    read("services/supabase/functions/repair-scan-image/README.md"),
    read("services/supabase/functions/share-scan-to-explore/README.md"),
    read(
      "services/supabase/functions/get-scan-explore-share-state/README.md",
    ),
    read(
      "services/supabase/functions/request-community-identification/README.md",
    ),
    read("services/supabase/functions/insight-chat/README.md"),
    read("apps/ios/Merian/Core/Data/README.md"),
    read("apps/ios/Merian/Features/Insights/Chat/README.md"),
    read("apps/ios/Merian/Features/Insights/Sharing/README.md"),
    read("apps/ios/Merian/Features/Explore/Feed/README.md"),
    read(
      "docs/incidents/2026-07-inline-scan-staging-manifest-regression.md",
    ),
    read(
      "docs/incidents/2026-07-video-scan-canonical-finalization-regression.md",
    ),
    read("docs/backend-and-data/01-offline-sync-pipeline.md"),
    read("docs/development-guides/06-error-handling.md"),
    read("apps/ios/Merian/Core/Network/README.md"),
    read("apps/ios/Merian/Resources/Changelog/changelog.json"),
  ]);
  const joined = compact(joinedSource);

  for (
    const fragment of [
      "Every producer HTTP `200` guarantees the shared boundary below:",
      "A fresh, provider-owning `/identify-multimodal` invocation has the stricter initial-delivery boundary:",
      "`complete_scan_ingestion_finalization` wrote `media_finalization_complete` last",
      "A later same-UUID marked idempotent replay is different.",
      "`X-Merian-Idempotent-Replay: reconstructed`, performs no second provider call",
      "Compatibility producers (`identify`, `identify-describe`, and `audio-spec`) invoke and await the same finalizer synchronously.",
      "The ledger remains `failed_retryable` for same-UUID canonical reconciliation without another provider call.",
      "A transport retry never creates a replacement UUID for the same user action.",
      "Inline image bytes are authoritative. A current foreground still sends `imageBase64s` and `r2ObjectKeys: []`.",
      "A malformed or partial signing response starts no upload.",
      "every requested file declares `scan_share_restore`",
      "proves the row absent for guarded reconstruction; tombstoned or foreign rows fail closed",
      "contradictory aliases fail before lifecycle registration",
      "the combined active staged/processing capture-key set cannot exceed six",
      "the accumulator equals the duplicate-free exact complete expected key set",
      "Sanitized filename/object-key collisions are rejected locally before signing or upload.",
      "`markScanAsStaged` must atomically save the keys, normally reset upload retry accounting",
      "An exact scheduled server-failure retry instead preserves its reclaim marker/count",
      "A retryable fetch/state/manifest/save outcome returns before inference dispatch",
      "Durable upload retry accounting normally resets only in the same save that promotes that exact complete manifest to staged.",
      "A transient signer or PUT failure during re-stage also retains the machine marker",
      "increments from the maximum committed count rather than a cached main-context value",
      "mismatched already-staged manifest, or persistence failure cannot advance the callback to inference",
      "server status `found` starts local result recovery but does not zero the attempt count",
      "the queue stays server-owned and `.inferencing`",
      "the row cannot retreat to `.staged` and issue a second provider request",
      "A background download's HTTP `200` is not itself a durable client success.",
      "does not explicitly report failure, contains a bounded nonempty scan ID",
      "Only after both local commits succeed may the offline job become complete.",
      "the committed queue-deletion path is the sole local file-cleanup authority",
      "one main-context save marks the job complete, clears transient job errors, inserts the completed event, and deletes the queue row",
      "Explicit deletion remains the only path that records cancellation.",
      "Pending cloud erasure uses the same positive-proof rule.",
      "No local error category is treated as proof that owner data has been erased.",
      "privacy erasure never exhausts an automatic retry budget",
      "repairs legacy paused or contradictory terminal job status",
      "The owner-row observation is marked durably before hydration",
      "a failed, unavailable, or temporarily inconsistent status probe therefore continues completed-result recovery",
      "`server_result_local_recovery_pending`",
      "`ensure_scan_user_profile(uuid)`",
      "Bulk status never accepts `recovery_scan` and never inserts or updates `public.scans`.",
      "Destructive media cleanup requires positive exact-owner absence evidence.",
      "Field Chat receives text-only context; Explore receives only the explicitly selected and privacy-projected public snapshot.",
      "`20260728230000_recover_inline_scan_ingestion_completions.sql`",
      "`20260728233000_recover_identity_merge_interrupted_scans.sql`",
      "`20260729012153_fix_video_scan_canonical_finalization.sql`",
      "`20260729024157_atomic_explore_scan_publication.sql`",
      "`20260729033000_atomic_community_identification_requests.sql`",
      "`20260729044500_grant_atomic_explore_service_privileges.sql`",
      "`publish_scan_to_explore_atomically(...)` transaction",
      "`request_community_identification_atomically(...)`",
      "The routines deliberately remain `SECURITY INVOKER`",
      "The reported bad plans—21 planned/4 run and 24 planned/5 run—were consequences",
      "omitted `location_sharing` value is resolved from the locked scan",
      "A transaction-time `needs_id` request fails with conflict and leaves the prior publication unchanged.",
      "An Explore source is unavailable only on the handler code `post_not_available`",
      "Every successful Insight or Explore thread/action response echoes the exact requested scan or post as `subject_id`.",
      "A send UUID is required and becomes the durable request identity",
      "The backend canonicalizes UUID case, rejects reuse with different normalized text, reserves both rows under the 30-row cap",
      "gives every assistant a deterministic UUIDv8 row identity",
      "reconciles an ambiguous insert by reading the pair back",
      "After atomic admission, the backend coalesces duplicate and quota-layer retries into that exact pair",
      "Duplicate-insert and waited-replay boundaries revalidate UUID/text binding",
      "the exact acknowledged user text",
      "restores that row as the failed pending bubble under the same canonical UUID",
      "Composer capacity uses the unfiltered persisted row count",
      "an incomplete retry requires one remaining assistant slot",
      "Prompt filtering targets unsafe user action intent rather than isolated words at generation and send time",
      "This response-identity change is an expand-first rollout.",
      "force same-UUID ambiguous replay",
      "Older clients ignore the additive fields; the corrected client intentionally rejects an older function response without its subject or current send-pair proof.",
      "The community request is locked before its scan",
      "Ask the Community uses the same eligible canonical image, playback-video, and standalone-audio projection.",
      "The Community client treats HTTP `200` as candidate evidence only.",
      "A decodable but unconfirmed response remains failure",
      "canonicalizes UUID casing before exact comparison",
      "Authoritative share-state reconciliation is also identity-bound.",
      "`20260729120000_align_explore_share_state_media_health.sql`",
      "preserves owner-only publication identity while quarantine or moderation",
      "API roles cannot substitute another `self_id`",
      "Private location sharing hides location, not the post",
      "visible-without-post `200` preserves the local optimistic cache",
      "deploys them sequentially in the listed order before unrelated parallel batches",
      "stops immediately when an ordered member exhausts its bounded retries",
      "The planner compares the current exact SHA with the most recent successful production workflow SHA",
      "fixture-only follow-up to failed catalog runs still includes every undeployed scan and Explore runtime change",
      "Production smoke must prove database readiness as well as Edge route liveness.",
      "requires each routine's exact SQLSTATE `22023` message",
      "a public `400` would prove the service-only body was reached and fails closed",
      "Race a direct Explore share against request creation",
      "the observation must remain hidden from normal Explore projections",
      "manually dispatch `iOS Build and Test` on that final SHA",
      "a scope-only success is not release evidence",
      "neither is UI-bundle compilation without execution",
      "the deterministic queued-scan completion UI smoke",
      "testQueuedAudioScanRetainsAudioAcrossCompletionHandoff",
      "a valid Documents PCM WAV",
      "preventing filename-only media evidence",
      "Merely transitioning `isSharingToExplore` back to `false` is not publication evidence.",
      "authoritative known location-sharing value",
      "At the retained parser evidence review, `HEAD` and `origin/main` both resolved to `bdf84b52`",
      "The current published descendant is `c30ad1a46`",
      "`bdf84b52` adds the exact display-name evidence parser",
      "`scripts/require_supabase_cli_version.sh`",
      "Current deterministic non-PostgreSQL Deno discovery run: 1,338 passed, 0 failed",
      "The current configured broad task reported 1,421 passed",
      "the latest focused recovery/runtime/documentation suite reported 148 passed",
      "A prior unrestricted run connected to a stale local Docker schema",
      "1,386 passed and the two affected author-profile integration cases failed",
      "Localhost early returns and stale-listener failures are retained as environment evidence",
      "191 assertions passed across 30 migration contract files",
      "110 tooling assertions and 12 documentation contracts passed",
      "`migrations/20260729173000_recover_media_abandoned_owned_scans.sql`",
      "`migrations/20260729200000_harden_media_abandoned_scan_recovery_proof.sql`",
      "The hosted 21-assertion revision completed its first four preflight assertions",
      "The revised fixture plans 22 assertions",
      "atomic_community_identification_request_security.sql",
      "The hosted 24-assertion revision completed its first five preflight assertions",
      "The revised rollback-only fixture plans 25 assertions",
      "The reviewed committed union from `daa18da00` through `bdf84b52` contains 136 changed paths",
      "is an explicit deployment control path, so the fail-closed planner resolves all 89 configured functions",
      "On exact parser/gate SHA `bdf84b52`",
      "all four portable iOS tooling contracts and all 109 Supabase tooling assertions pass",
      "the cumulative planner selects all 89 functions",
      "Exact parent `21df28d6b` additionally passed all 89 isolated function graphs across 292 runtime files",
      "Full-fallback, shuffled-plan, compatibility-order, and fail-stop fixtures passed.",
      "An unsafe or missing baseline falls back to all 89 functions.",
      "Selected critical members deploy sequentially in compatibility order",
      "The latest hosted run discovered 26 files and completed 24.",
      "Identity merge/recovery and all 30 inline/video assertions passed.",
      "Only the two atomic files aborted at their first service-role body call with SQLSTATE `42501`",
      "the 16-assertion Field Chat file, and all 27 files must pass",
      "Run 91 on exact SHA `21df28d6b` compiled and executed the complete target",
      "structured summary reported 1,226 passed tests with zero failed or skipped",
      "the Swift Testing subrun reported 917 tests in 67 suites passed",
      "All six previously failing fixture cases therefore passed",
      "Release archive also succeeded at 238,694,400 bytes",
      'uses explicit `@Test("…")` display names',
      "Exact descendant `bdf84b52` supplies those two display-name aliases",
      "For exact fixture/gate SHA `21df28d6b`",
      "all 58 protected case names resolve to maintained tests",
      "the configured Edge suite reports 1,421 passed with zero failed",
      "all 89 isolated dependency graphs across 292 runtime files",
      "the workflow's overall result remains failed infrastructure evidence",
      "One fresh full gate identifying `bdf84b52` or a documented descendant",
      "`1a75179dd88f20163cb5c01bffd60478b9545009` then stopped during isolated Edge graph validation",
      "does not restore that partial-write helper",
      "All 89 isolated entrypoints type-check locally",
      "Workflow run 1551 for commit",
      "Workflow run 1552 for commit",
      "22 of 24 catalog files",
      "the latest 26-file catalog run all stopped before production mutation",
      "trigger-aware profile upserts",
      "owner-matched ready rows",
      "`sandbox_apply: Operation not permitted`",
    ]
  ) {
    assertStringIncludes(joined, fragment);
  }
  assert(
    !joined.includes("Bulk status is always read-only."),
    "Obsolete bulk status mutation guidance returned.",
  );
  assert(
    !joined.includes(
      "An HTTP `200` from any scan-producing route means all required work below has completed:",
    ),
    "Obsolete universal finalization-before-success guidance returned.",
  );
  assert(
    !joined.includes(
      "The current `/identify-multimodal` route has the stricter completion boundary:",
    ),
    "Obsolete universal multimodal-finalization guidance returned.",
  );
  for (
    const [source, fragment] of [
      [
        offlinePipelineSource,
        "`invalidResponse` is not not-found proof",
      ],
      [
        errorHandlingSource,
        "Never infer a remote mutation from this error.",
      ],
      [
        networkClientSource,
        "never evidence that remote data is absent",
      ],
    ] as const
  ) {
    assertStringIncludes(compact(source), fragment);
  }
  for (
    const source of [
      offlinePipelineSource,
      errorHandlingSource,
      networkClientSource,
    ]
  ) {
    assert(
      !compact(source).includes(
        "invalidResponse → tombstone (resource already gone",
      ) &&
        !compact(source).includes(
          "invalidResponse` (resource already gone) is treated as terminal",
        ),
      "Obsolete invalidResponse-as-erasure guidance returned.",
    );
  }

  for (const source of [rootSource, documentationSource]) {
    assertStringIncludes(
      source,
      "16-scan-ingestion-reliability-and-recovery.md",
    );
  }
  assertStringIncludes(
    compact(generateUploadSource),
    "A partial, extra, malformed, cross-owner, or media-incompatible response starts no upload.",
  );
  assertStringIncludes(
    compact(incidentSource),
    "100 linear/squash history entries and zero merge commits",
  );
  assertStringIncludes(
    compact(multimodalSource),
    "The latter may still have a `processing`, `finalizing`, `retrying`, or `failed_retryable` ledger.",
  );
  assertStringIncludes(
    compact(multimodalSource),
    "A later same-UUID invocation may independently return a marked reconstructed replay from that exact owner row while canonical finalization remains retryable.",
  );
  assertStringIncludes(
    compact(multimodalSource),
    "Sampled inference frames may remain in `image_storage_urls` as compatibility/thumbnail inputs but are not required or created as standalone ready images.",
  );
  assertStringIncludes(
    compact(identifyCompatibilitySource),
    "If only finalization or bookkeeping fails after that row committed, this compatibility route may return its already validated response while leaving the ledger retryable for same-UUID canonical reconciliation.",
  );
  for (
    const source of [
      describeCompatibilitySource,
      audioCompatibilitySource,
    ]
  ) {
    assertStringIncludes(
      compact(source),
      "if only its post-insert bookkeeping fails, the owner row remains the canonical response surface and the ledger remains retryable for reconstruction/reconciliation.",
    );
  }
  assertStringIncludes(
    compact(repairImageSource),
    "Every unknown topology returns retryable `503 scan_image_repair_persistence_unknown`.",
  );
  assertStringIncludes(
    compact(exploreShareSource),
    "replaces the post row, media snapshot, hashtag edges, and resolved community-publication state in one service-role transaction",
  );
  assertStringIncludes(
    compact(exploreShareSource),
    "`publication_status` must be exactly `published`",
  );
  assertStringIncludes(
    compact(exploreShareSource),
    "`shared_at` must be a parseable timestamp",
  );
  assertStringIncludes(
    compact(exploreShareSource),
    "only for the exact PostgreSQL `P0001` code and canonical pending-request message",
  );
  assertStringIncludes(
    compact(exploreShareSource),
    "`20260729044500_grant_atomic_explore_service_privileges.sql` also installs the operation-scoped table privileges",
  );
  assertStringIncludes(
    compact(exploreShareStateSource),
    "Current iOS only applies an HTTP-successful response when it echoes the exact requested scan ID",
  );
  assertStringIncludes(
    compact(exploreShareStateSource),
    "no feed-visible claim without a post",
  );
  assertStringIncludes(
    compact(communityRequestSource),
    "Both final transaction RPCs remain `SECURITY INVOKER`.",
  );
  assertStringIncludes(
    compact(communityRequestSource),
    "A video-only or audio-only biological scan is valid recovery input",
  );
  assertStringIncludes(
    compact(communityRequestSource),
    "An HTTP-successful response is only a candidate success.",
  );
  assertStringIncludes(
    compact(coreDataSource),
    "resets upload retry state, updates the queue job, and transitions `.uploading → .staged` in one save",
  );
  assertStringIncludes(
    compact(coreDataSource),
    "must equal the duplicate-free exact expected key set",
  );
  assertStringIncludes(
    compact(coreDataSource),
    "writes the scan job's `.complete` status",
  );
  assertStringIncludes(
    compact(coreDataSource),
    "Explicit user/system deletion instead records `.cancelled`.",
  );
  assertStringIncludes(
    compact(insightChatSource),
    "`/insight-chat` itself does not create a scan, restore media, or accept `recovery_scan`.",
  );
  assertStringIncludes(
    compact(chatClientSource),
    "Do not cache this result as permanent unavailability.",
  );
  assertStringIncludes(
    compact(chatClientSource),
    "one ready playback clip and its poster, not separate ready image rows for sampled inference frames",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "A lost database response can occur after restored media was promoted and the owner scan update committed.",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "they are not standalone composer items",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "The composer closes only after publication returns and the response confirms success",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "parseable share timestamp",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "It does not require a recovered image",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "A decodable but unconfirmed HTTP `200` cannot",
  );
  assertStringIncludes(
    compact(sharingClientSource),
    "cannot overwrite the optimistic cache for the open Insight",
  );
  assertStringIncludes(
    compact(exploreFeedSource),
    "A post is feed-visible only when the canonical public projection sees at least one eligible saved media row.",
  );
  assertStringIncludes(
    compact(incidentSource),
    "Repository remediation, merge to `main`, backend deployment, iOS release, and production verification are separate states.",
  );
  assertStringIncludes(
    compact(incidentSource),
    "`OfflineQueueManagerTests.testMediaStagingContractBuildsSanitizedMixedMediaKeys()`",
  );
  assertStringIncludes(
    compact(incidentSource),
    "Failure reporting now reads Xcode's structured result-summary failures first",
  );
  assertStringIncludes(
    compact(incidentSource),
    "The latest hosted fresh-catalog replay discovered all 26 pgTAP files present on that SHA.",
  );
  assertStringIncludes(
    compact(incidentSource),
    "The later TAP reports—21 planned/4 run and 24 planned/5 run—were consequences of those two statement errors",
  );
  const videoIncident = compact(videoIncidentSource);
  for (
    const fragment of [
      "Assertions 13–15 prove",
      "sampled inference frames are thumbnail inputs, not standalone canonical images",
      "`internal.scan_canonical_media_projection_complete(scan_id)`",
      "`internal.scan_media_reference_is_video_inference_frame(scan_id, user_id, url)`",
      "requires an exact scan, owner, kind, URL, and `ready` status",
      "positive numeric `video_inference_frame_count`",
      "endpoint-normalized image count",
      "compatibility counts subtract their separately validated declared frame subset",
      "It made no production mutation.",
      "Field Chat opening and Explore publication for that same completed scan",
    ]
  ) {
    assertStringIncludes(videoIncident, fragment);
  }

  const inAppChangelog = JSON.parse(inAppChangelogSource) as {
    entries: Array<{
      id: string;
      sections: Array<{ items: string[] }>;
    }>;
  };
  const reliabilityEntry = inAppChangelog.entries.find((entry) =>
    entry.id === "2026-07-28-critical-scan-reliability"
  );
  assert(
    reliabilityEntry,
    "Critical scan reliability release note is missing.",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "Offline image, audio, video, and description scans",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "require the completed upload state to save before analysis starts",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "verify the exact completed media set",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "reject empty or damaged success responses",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "require every later local save and cleanup step to finish before completion",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "retain source media until durable cleanup even when no identification is found",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "record successful work as completed instead of cancelled",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "one playable clip and poster",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "stays available to retry while an observation is still syncing",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "remains safely queued and keeps retrying until cloud erasure is explicitly confirmed",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "safely coordinates simultaneous sends across devices",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "recovers a long-interrupted unanswered request without duplicating the saved question",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "restores an unanswered question to Retry and Edit after relaunch",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "A failed Explore share now keeps your post draft open",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "stale or partial share-state responses cannot create a phantom post",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "Ask the Community now saves the observation and identification request together",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "recovery keeps surviving image, video, and audio media",
  );
  assertStringIncludes(
    reliabilityEntry.sections.flatMap((section) => section.items).join(" "),
    "an unconfirmed response no longer shows a false success",
  );
});

Deno.test("Field Chat documentation preserves atomic admission and stale recovery", async () => {
  const [
    schemaSource,
    apiSource,
    reliabilitySource,
    backendSource,
    sharedSource,
    insightSource,
    exploreSource,
    testingSource,
    errorSource,
    aiSource,
    codebaseSource,
    networkSource,
    clientSource,
    runbookSource,
  ] = await Promise.all([
    read("docs/backend-and-data/04-database-schema.md"),
    read("docs/backend-and-data/05-api-contracts.md"),
    read(
      "docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md",
    ),
    read("services/supabase/README.md"),
    read("services/supabase/functions/_shared/README.md"),
    read("services/supabase/functions/insight-chat/README.md"),
    read("services/supabase/functions/explore-post-chat/README.md"),
    read("docs/development-guides/08-testing-strategy.md"),
    read("docs/development-guides/06-error-handling.md"),
    read("docs/system-architecture/04-ai-engineering.md"),
    read("docs/codebase-map.md"),
    read("apps/ios/Merian/Core/Network/README.md"),
    read("apps/ios/Merian/Features/Insights/Chat/README.md"),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
  ]);

  for (
    const source of [
      schemaSource,
      apiSource,
      reliabilitySource,
      backendSource,
      insightSource,
      exploreSource,
      testingSource,
      codebaseSource,
      runbookSource,
    ]
  ) {
    assertStringIncludes(
      compact(source),
      "`20260729163616_reserve_field_chat_sends_atomically.sql`",
    );
  }

  for (
    const fragment of [
      "`reserve_field_chat_send(...)`",
      "`recover_stale_field_chat_quota(...)`",
      "cross-table",
      "newly metered",
    ]
  ) {
    assertStringIncludes(compact(reliabilitySource), fragment);
    assertStringIncludes(compact(backendSource), fragment);
  }

  assertStringIncludes(
    compact(reliabilitySource),
    "A separately focused frozen Field Chat run passed 30 tests with 0 failures across nine",
  );
  assertStringIncludes(
    compact(testingSource),
    "30 passed and 0 failed across nine files with a frozen dependency graph",
  );
  for (const source of [insightSource, exploreSource]) {
    assertStringIncludes(
      compact(source),
      "deno test --frozen --config services/supabase/functions/deno.json",
    );
  }

  assertStringIncludes(
    compact(sharedSource),
    "The database transaction—not an Edge count-then-insert read—owns",
  );
  assertStringIncludes(
    compact(testingSource),
    "`tests/field_chat_reservation_security.sql`",
  );
  assertStringIncludes(
    compact(errorSource),
    "`503 field_chat_admission_unavailable`",
  );
  assertStringIncludes(
    compact(errorSource),
    "`503 field_chat_recovery_unavailable`",
  );
  assertStringIncludes(
    compact(aiSource),
    "`_shared/fieldChatReservation.ts`",
  );
  for (const source of [networkSource, clientSource]) {
    assertStringIncludes(
      compact(source),
      "`field_chat_admission_unavailable`",
    );
    assertStringIncludes(
      compact(source),
      "`field_chat_recovery_unavailable`",
    );
  }
});

Deno.test("Edge route availability docs preserve the gateway-handler boundary", async () => {
  const [
    networkSource,
    errorSource,
    runbookSource,
    backendSource,
    documentationIndexSource,
    incidentSource,
  ] = await Promise
    .all([
      read("apps/ios/Merian/Core/Network/README.md"),
      read("docs/development-guides/06-error-handling.md"),
      read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
      read("services/supabase/README.md"),
      read("docs/README.md"),
      read("docs/incidents/2026-07-supabase-edge-route-not-found.md"),
    ]);
  const network = compact(networkSource);
  const errors = compact(errorSource);
  const runbook = compact(runbookSource);
  const backend = compact(backendSource);
  const documentationIndex = compact(documentationIndexSource);
  const incident = compact(incidentSource);

  assertStringIncludes(
    network,
    "A Supabase platform `404 NOT_FOUND` is not an application-level missing record.",
  );
  assertStringIncludes(
    network,
    "A marked handler-owned `404`, including `Scan not found`, is never route-retried",
  );
  assertStringIncludes(
    network,
    "A platform route `404` preserves the queued scan and schedules its normal durable retry",
  );
  assertStringIncludes(
    network,
    "A queued handler `401`, `408`, `409`, `425`, or `429` is also retryable",
  );
  assertStringIncludes(
    network,
    "Other handler-owned `4xx` responses preserve the local media as `queueNeedsAttention`",
  );
  assertStringIncludes(
    errors,
    "The response must omit `X-Merian-Handler: 1` and match Supabase's stable `SB-Error-Code: NOT_FOUND` header",
  );
  for (
    const functionName of [
      "`generate-upload-urls`",
      "`identify-multimodal`",
      "`check-scan-status`",
      "`share-scan-to-explore`",
      "`get-scan-explore-share-state`",
      "`get-explore-composer-media`",
      "`get-explore-media-incidents`",
      "`insight-chat`",
      "`explore-post-chat`",
      "`request-community-identification`",
      "`delete-scan`",
    ]
  ) {
    assertStringIncludes(runbook, functionName);
    assertStringIncludes(backend, functionName);
  }
  for (
    const routineName of [
      "`ensure_scan_user_profile`",
      "`publish_scan_to_explore_atomically`",
      "`request_community_identification_atomically`",
      "`recover_missing_owned_scan`",
      "`get_media_abandoned_scan_recovery_proofs`",
      "`reserve_field_chat_send`",
      "`recover_stale_field_chat_quota`",
    ]
  ) {
    assertStringIncludes(runbook, routineName);
    assertStringIncludes(backend, routineName);
  }
  assertStringIncludes(
    runbook,
    "All inputs are syntactically valid JSON but raise their exact SQLSTATE `22023` message before any advisory lock, row lock, or write.",
  );
  assertStringIncludes(
    backend,
    "proving every real anon/publishable project credential remains denied from all seven routines.",
  );
  assertStringIncludes(
    runbook,
    "Each critical route must return `401` with the marker",
  );
  assertStringIncludes(
    runbook,
    "separately probes eleven customer-critical routes",
  );
  assertStringIncludes(
    backend,
    "all eleven customer-critical scan, signing, share-state, Explore, Field Chat, Community, and deletion routes",
  );
  assertStringIncludes(
    incident,
    "The following eleven customer-critical routes",
  );
  assertStringIncludes(
    backend,
    "A platform `404` therefore cannot be mistaken for an application-level missing scan",
  );
  assertStringIncludes(
    documentationIndex,
    "2026-07-supabase-edge-route-not-found.md",
  );
  assertStringIncludes(
    incident,
    "Rescanning cannot repair a platform route that did not reach the function.",
  );
  assertStringIncludes(
    incident,
    "Field Chat does not cache the scan as deterministically unavailable.",
  );
});

Deno.test("Field Trip documentation preserves the confidence evidence policy", async () => {
  const [
    featureSource,
    insightSource,
    gamificationSource,
    authorProfileSource,
    aiReadmeSource,
    networkReadmeSource,
    offlineSource,
    backendSource,
    schemaSource,
    apiSource,
    runbookSource,
    productSource,
    functionReadmeSource,
    rfcSource,
    changelogSource,
    appChangelogSource,
  ] = await Promise.all([
    read("docs/features-and-hardware/25-field-trips.md"),
    read("docs/features-and-hardware/05-insight-sheet.md"),
    read("docs/features-and-hardware/06-profile-and-gamification.md"),
    read("docs/features-and-hardware/14-explore-author-profiles.md"),
    read("apps/ios/Merian/Core/AI/README.md"),
    read("apps/ios/Merian/Core/Network/README.md"),
    read("docs/backend-and-data/01-offline-sync-pipeline.md"),
    read("docs/backend-and-data/02-supabase-edge-and-database.md"),
    read("docs/backend-and-data/04-database-schema.md"),
    read("docs/backend-and-data/05-api-contracts.md"),
    read("docs/backend-and-data/06-supabase-deployment-runbook.md"),
    read("docs/product/01-master-product-document.md"),
    read("services/supabase/functions/field-trips/README.md"),
    read("docs/rfcs/active-capture-goal-context.md"),
    read("CHANGELOG.md"),
    read("apps/ios/Merian/Resources/Changelog/changelog.json"),
  ]);
  const feature = compact(featureSource);
  const insight = compact(insightSource);
  const gamification = compact(gamificationSource);
  const authorProfile = compact(authorProfileSource);
  const aiReadme = compact(aiReadmeSource);
  const networkReadme = compact(networkReadmeSource);
  const offline = compact(offlineSource);
  const backend = compact(backendSource);
  const schema = compact(schemaSource);
  const api = compact(apiSource);
  const runbook = compact(runbookSource);
  const product = compact(productSource);
  const functionReadme = compact(functionReadmeSource);
  const rfc = compact(rfcSource);
  const changelog = compact(changelogSource);

  assertStringIncludes(feature, "Flash | `0.75` (75%)");
  assertStringIncludes(feature, "Pro | `0.65` (65%)");
  assertStringIncludes(feature, "Missing or unknown | `0.75` (75%)");
  assertStringIncludes(feature, "`user_confirmed_identification` is true");
  assertStringIncludes(feature, "`confirmed_species_id` is populated");
  assertStringIncludes(feature, "selected-goal preference remains pending");
  assertStringIncludes(feature, "soft-deletes completion publications/entries");
  assertStringIncludes(
    insight,
    "automatic evidence gate for Field trip goals: `0.75` for Flash and `0.65` for Pro",
  );
  assertStringIncludes(
    product,
    "Evidence-policy invalidation is the exception",
  );
  assertStringIncludes(
    gamification,
    "A later downgrade to weak unreviewed evidence removes the contribution",
  );
  assertStringIncludes(
    authorProfile,
    "apply the complete ordered migration chain through",
  );
  assertStringIncludes(
    aiReadme,
    "The server receipt is also the evidence authority",
  );
  assertStringIncludes(
    networkReadme,
    "Possible-match boundary (`Flash >= 0.75`, `Pro >= 0.65`)",
  );
  assertStringIncludes(
    offline,
    "included in the scan-ingestion request so the insert trigger can apply the atomic preference/progress contract",
  );
  assertStringIncludes(
    rfc,
    "confidence-gate release pending the normal Supabase deployment process",
  );
  assertStringIncludes(
    api,
    "evidence-policy invalidation is the exception",
  );
  assertStringIncludes(
    runbook,
    "The confidence migration performs a forward-only data repair.",
  );
  assertStringIncludes(
    schema,
    "`public.field_trip_scan_identification_is_eligible",
  );

  for (
    const policyDocument of [
      feature,
      backend,
      schema,
      api,
      runbook,
      functionReadme,
      authorProfile,
      rfc,
    ]
  ) {
    assertStringIncludes(
      policyDocument,
      "`20260730023042_gate_field_trip_progress_by_confidence.sql`",
    );
  }

  assertStringIncludes(
    changelog,
    "Prevented unreviewed **Weak match** identifications from counting toward Field trip goals.",
  );

  const appChangelog = JSON.parse(appChangelogSource) as {
    entries?: Array<{
      id?: string;
      date?: string;
      title?: string;
      sections?: Array<{ title?: string; items?: string[] }>;
    }>;
  };
  const releaseEntry = appChangelog.entries?.find((entry) =>
    entry.id === "2026-07-29-field-trip-confidence"
  );
  assert(releaseEntry, "Field Trip confidence release note is missing");
  assertEquals(releaseEntry.date, "2026-07-29");
  const releaseCopy = compact(JSON.stringify(releaseEntry));
  assertStringIncludes(releaseCopy, "Possible match");
  assertStringIncludes(releaseCopy, "A Weak match stays pending");
});

Deno.test("maintained contract documentation has no unresolved local file links", async () => {
  const maintainedFiles = [
    "README.md",
    "apps/ios/Merian/Core/AI/README.md",
    "apps/ios/Merian/Core/Network/README.md",
    "apps/ios/Merian/Features/Explore/Feed/README.md",
    "apps/ios/Merian/Features/Insights/Chat/README.md",
    "apps/ios/Merian/Features/Insights/Sharing/README.md",
    "apps/web/README.md",
    "docs/CONTRIBUTING.md",
    "docs/README.md",
    "docs/backend-and-data/01-offline-sync-pipeline.md",
    "docs/backend-and-data/02-supabase-edge-and-database.md",
    "docs/backend-and-data/04-database-schema.md",
    "docs/backend-and-data/05-api-contracts.md",
    "docs/backend-and-data/06-supabase-deployment-runbook.md",
    "docs/backend-and-data/07-community-taxonomy-import-checklist.md",
    "docs/backend-and-data/12-explore-media-health-and-quarantine.md",
    "docs/backend-and-data/13-server-credentials-and-database-release-safety.md",
    "docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md",
    "docs/backend-and-data/15-edge-function-fleet-review-2026-07-28.md",
    "docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md",
    "docs/codebase-map.md",
    "docs/development-guides/04-logging-and-debugging.md",
    "docs/development-guides/05-keychain-and-secrets.md",
    "docs/development-guides/06-error-handling.md",
    "docs/development-guides/07-ai-agent-guidelines.md",
    "docs/development-guides/08-testing-strategy.md",
    "docs/development-guides/09-core-managers.md",
    "docs/development-guides/10-safety-and-moderation.md",
    "docs/development-guides/11-swiftdata-and-api-gotchas.md",
    "docs/features-and-hardware/05-insight-sheet.md",
    "docs/features-and-hardware/06-profile-and-gamification.md",
    "docs/features-and-hardware/07-feature-modules-and-ui.md",
    "docs/features-and-hardware/14-explore-author-profiles.md",
    "docs/features-and-hardware/25-field-trips.md",
    "docs/incidents/2026-07-account-scoped-r2-image-loss.md",
    "docs/incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md",
    "docs/incidents/2026-07-identify-idempotency-conflict.md",
    "docs/incidents/2026-07-inline-scan-staging-manifest-regression.md",
    "docs/incidents/2026-07-media-abandoned-explore-share-recovery.md",
    "docs/incidents/2026-07-scan-owner-row-durability-gap.md",
    "docs/incidents/2026-07-server-key-authorization-mismatch.md",
    "docs/incidents/2026-07-supabase-edge-route-not-found.md",
    "docs/incidents/2026-07-video-scan-canonical-finalization-regression.md",
    "docs/product/01-master-product-document.md",
    "docs/rfcs/active-capture-goal-context.md",
    "docs/system-architecture/01-system-architecture.md",
    "docs/system-architecture/02-zero-oom-and-concurrency.md",
    "docs/system-architecture/03-image-pipeline.md",
    "docs/system-architecture/04-ai-engineering.md",
    "docs/system-architecture/06-edge-modularization.md",
    "docs/system-architecture/system-overview.md",
    "services/supabase/README.md",
    "services/supabase/functions/_shared/README.md",
    "services/supabase/functions/check-scan-status/README.md",
    "services/supabase/functions/download-dwca/README.md",
    "services/supabase/functions/export-dwca/README.md",
    "services/supabase/functions/audio-spec/README.md",
    "services/supabase/functions/field-trips/README.md",
    "services/supabase/functions/generate-upload-urls/README.md",
    "services/supabase/functions/identify/README.md",
    "services/supabase/functions/identify-describe/README.md",
    "services/supabase/functions/identify-multimodal/README.md",
    "services/supabase/functions/insight-chat/README.md",
    "services/supabase/functions/reconcile-explore-media-health/README.md",
    "services/supabase/functions/reconcile-dwca-archive-cleanup/README.md",
    "services/supabase/functions/reconcile-scan-media-assets/README.md",
    "services/supabase/functions/repair-scan-image/README.md",
    "services/supabase/functions/request-community-identification/README.md",
    "services/supabase/functions/request-export-dwca/README.md",
    "services/supabase/functions/share-scan-to-explore/README.md",
    "services/supabase/functions/species-dictionary/README.md",
  ];
  const failures: string[] = [];

  for (const relativePath of maintainedFiles) {
    for (const link of await unresolvedLocalMarkdownLinks(relativePath)) {
      failures.push(`${relativePath}: ${link}`);
    }
  }

  assertEquals(
    failures,
    [],
    `Unresolved local Markdown links:\n${failures.join("\n")}`,
  );
});
