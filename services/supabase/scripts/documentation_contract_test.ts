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
  assertStringIncludes(runbook, "rerun the same workflow SHA");
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
    insightChatSource,
    chatClientSource,
    sharingClientSource,
    exploreFeedSource,
    incidentSource,
    videoIncidentSource,
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
    read("services/supabase/functions/insight-chat/README.md"),
    read("apps/ios/Merian/Features/Insights/Chat/README.md"),
    read("apps/ios/Merian/Features/Insights/Sharing/README.md"),
    read("apps/ios/Merian/Features/Explore/Feed/README.md"),
    read(
      "docs/incidents/2026-07-inline-scan-staging-manifest-regression.md",
    ),
    read(
      "docs/incidents/2026-07-video-scan-canonical-finalization-regression.md",
    ),
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
      "the combined non-superseded capture-key union cannot exceed six",
      "`ensure_scan_user_profile(uuid)`",
      "Bulk status never accepts `recovery_scan` and never inserts or updates `public.scans`.",
      "Destructive media cleanup requires positive exact-owner absence evidence.",
      "Field Chat receives text-only context; Explore receives only the explicitly selected and privacy-projected public snapshot.",
      "`20260728230000_recover_inline_scan_ingestion_completions.sql`",
      "`20260728233000_recover_identity_merge_interrupted_scans.sql`",
      "`20260729012153_fix_video_scan_canonical_finalization.sql`",
      "deploys them sequentially in the listed order before unrelated parallel batches",
      "stops immediately when an ordered member exhausts its bounded retries",
      "Local working-tree evidence is not immutable release evidence.",
      "Full Deno function suite: 1,347 passed, 0 failed",
      "165 assertions passed across 25 migration contract files",
      "including all nine required scan functions",
      "shuffled-plan and fail-stop fixtures passed",
      "Pending an exact-remediated-SHA replay of all 24 catalog files",
      "Workflow run 1551 for commit",
      "Workflow run 1552 for commit",
      "22 of 24 catalog files",
      "Runs 1549–1552 made no production mutation",
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
    "one playable clip and poster",
  );
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
      "`identify-multimodal`",
      "`check-scan-status`",
      "`share-scan-to-explore`",
      "`get-explore-composer-media`",
      "`insight-chat`",
    ]
  ) {
    assertStringIncludes(runbook, functionName);
    assertStringIncludes(backend, functionName);
  }
  assertStringIncludes(
    runbook,
    "Each critical route must return `401` with the marker",
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
    "docs/incidents/2026-07-account-scoped-r2-image-loss.md",
    "docs/incidents/2026-07-identify-idempotency-conflict.md",
    "docs/incidents/2026-07-inline-scan-staging-manifest-regression.md",
    "docs/incidents/2026-07-scan-owner-row-durability-gap.md",
    "docs/incidents/2026-07-server-key-authorization-mismatch.md",
    "docs/incidents/2026-07-supabase-edge-route-not-found.md",
    "docs/incidents/2026-07-video-scan-canonical-finalization-regression.md",
    "docs/product/01-master-product-document.md",
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
    "services/supabase/functions/generate-upload-urls/README.md",
    "services/supabase/functions/identify/README.md",
    "services/supabase/functions/identify-describe/README.md",
    "services/supabase/functions/identify-multimodal/README.md",
    "services/supabase/functions/insight-chat/README.md",
    "services/supabase/functions/reconcile-explore-media-health/README.md",
    "services/supabase/functions/reconcile-dwca-archive-cleanup/README.md",
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
