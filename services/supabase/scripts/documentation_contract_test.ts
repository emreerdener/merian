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
      "singular `SUPABASE_SECRET_KEY` for local/manual environments",
      "`/v1/projects/<ref>/api-keys?reveal=true`",
      "returns every real current publishable and exact legacy `anon` key for negative smoke controls",
      "creates downstream clients from the environment-resolved key, never from the accepted request value",
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
      "schema-migration history insert as one `pgconn.ExecBatch`",
      "new migrations at or after `20260727183356` contain no top-level transaction control",
      "historical migrations that contain explicit transaction controls remain compatibility artifacts, not examples for future work",
      "Every table created in `public` must have effective RLS enabled",
      "PostgreSQL 17 `MAINTAIN`",
      "at most 32 MiB",
      "`pg_index.indisvalid` and `indisready`",
      "build equivalent valid leading indexes concurrently on every leaf partition first",
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
  const [rootReadme, documentationReadme, changelog, offlinePipeline, testing] =
    await Promise.all([
      read("README.md"),
      read("docs/README.md"),
      read("CHANGELOG.md"),
      read("docs/backend-and-data/01-offline-sync-pipeline.md"),
      read("docs/development-guides/08-testing-strategy.md"),
    ]);

  for (const source of [rootReadme, documentationReadme]) {
    assertStringIncludes(
      source,
      "13-server-credentials-and-database-release-safety.md",
    );
  }
  assertStringIncludes(
    changelog,
    "Stale server retry timestamps now trigger a one-second client recheck",
  );
  assertStringIncludes(
    changelog,
    "Closed the remaining exposed-table security gap",
  );
  assertStringIncludes(
    offlinePipeline,
    "already stale schedules a one-second recheck",
  );
  assertStringIncludes(
    testing,
    "`scripts/documentation_contract_test.ts` locks the same header matrix",
  );
});

Deno.test("maintained contract documentation has no unresolved local file links", async () => {
  const maintainedFiles = [
    "README.md",
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
    "docs/codebase-map.md",
    "docs/development-guides/05-keychain-and-secrets.md",
    "docs/development-guides/07-ai-agent-guidelines.md",
    "docs/development-guides/08-testing-strategy.md",
    "docs/incidents/2026-07-account-scoped-r2-image-loss.md",
    "docs/incidents/2026-07-server-key-authorization-mismatch.md",
    "docs/system-architecture/01-system-architecture.md",
    "docs/system-architecture/02-zero-oom-and-concurrency.md",
    "services/supabase/README.md",
    "services/supabase/functions/_shared/README.md",
    "services/supabase/functions/reconcile-explore-media-health/README.md",
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
