import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const functionsRoot = new URL("../", import.meta.url);
const authHelperUrl = new URL(
  "../_shared/serviceRoleAuth.ts",
  import.meta.url,
);
const reconcileIndexUrl = new URL(
  "../reconcile-explore-media-health/index.ts",
  import.meta.url,
);
const deployWorkflowUrl = new URL(
  "../../../../.github/workflows/deploy.yml",
  import.meta.url,
);
const importWorkflowUrl = new URL(
  "../../../../.github/workflows/import-community-taxonomy.yml",
  import.meta.url,
);
const scanMediaWorkflowUrl = new URL(
  "../../../../.github/workflows/scan-media-health-monitor.yml",
  import.meta.url,
);
const revenueCatMonitorWorkflowUrl = new URL(
  "../../../../.github/workflows/revenuecat-reconciliation-health-monitor.yml",
  import.meta.url,
);
const dwcaMonitorWorkflowUrl = new URL(
  "../../../../.github/workflows/dwca-export-health-monitor.yml",
  import.meta.url,
);
const importScriptUrl = new URL(
  "../../scripts/import_community_taxonomy.ts",
  import.meta.url,
);
const scanMediaScriptUrl = new URL(
  "../../scripts/monitor_scan_media_health.ts",
  import.meta.url,
);
const accountDeletionScriptUrl = new URL(
  "../../scripts/monitor_account_deletion_health.ts",
  import.meta.url,
);
const revenueCatMonitorScriptUrl = new URL(
  "../../scripts/monitor_revenuecat_reconciliation.ts",
  import.meta.url,
);
const dwcaMonitorScriptUrl = new URL(
  "../../scripts/monitor_dwca_export_queue.ts",
  import.meta.url,
);

const EXPECTED_AUTHORIZATION_BOUNDARIES = [
  "auto-purge-nonbio/index.ts",
  "backfill-explore-audio-spectrograms/index.ts",
  "community-taxonomy-status/index.ts",
  "expire-subscription-passes/index.ts",
  "export-dwca/index.ts",
  "identify-multimodal/index.ts",
  "process-community-consensus-jobs/index.ts",
  "reconcile-account-deletions/index.ts",
  "reconcile-explore-media-health/handler.ts",
  "reconcile-ghost-profile-merges/index.ts",
  "reconcile-revenuecat-subscribers/index.ts",
  "reconcile-scan-media-assets/index.ts",
  "refresh-merian-reference-images/index.ts",
  "refresh-species-content/index.ts",
  "refresh-species-model-content/index.ts",
  "refresh-taxonomy-nodes/index.ts",
  "replay-scan-ingestion/index.ts",
  "scan-media-health/index.ts",
  "send-push-notification/index.ts",
  "sync-community-taxonomy-index/index.ts",
];

const EXPECTED_DIRECT_SUPABASE_CLIENT_BOUNDARIES = [
  "_shared/auth.ts",
  "_shared/claimsAuth.ts",
  "_shared/serviceRoleClient.ts",
  "merge-ghost-profile/db.ts",
];

function isProductionTypeScript(path: string): boolean {
  return !/(?:^|\/)[^/]*(?:_test|\.test)\.ts$/.test(path);
}

function importsSupabaseCreateClient(source: string): boolean {
  const importPattern =
    /import\s*\{([^}]*)\}\s*from\s*["']@supabase\/supabase-js["']/g;
  return [...source.matchAll(importPattern)].some((match) =>
    (match[1] ?? "").split(",").some((specifier) =>
      /^createClient(?:\s+as\s+[A-Za-z_$][\w$]*)?$/.test(
        specifier.trim(),
      )
    )
  );
}

function withoutTypeScriptComments(source: string): string {
  return source
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/\/\/[^\r\n]*/g, " ");
}

async function collectTypeScriptFiles(
  directory: URL,
  relativeDirectory = "",
): Promise<Array<{ path: string; source: string }>> {
  const files: Array<{ path: string; source: string }> = [];
  for await (const entry of Deno.readDir(directory)) {
    if (
      entry.name === "_tests" ||
      entry.name === "node_modules" ||
      entry.name.startsWith(".")
    ) {
      continue;
    }

    const relativePath = relativeDirectory
      ? `${relativeDirectory}/${entry.name}`
      : entry.name;
    const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), directory);
    if (entry.isDirectory) {
      files.push(...await collectTypeScriptFiles(url, relativePath));
    } else if (entry.isFile && entry.name.endsWith(".ts")) {
      files.push({
        path: relativePath,
        source: await Deno.readTextFile(url),
      });
    }
  }
  return files;
}

Deno.test("every service-role request boundary uses exact environment-backed authorization", async () => {
  const files = await collectTypeScriptFiles(functionsRoot);
  const boundaries = files
    .filter(({ path, source }) =>
      path !== "_shared/serviceRoleAuth.ts" &&
      isProductionTypeScript(path) &&
      /\bauthorizeServiceRoleRequest(?:FromEnvironment)?\s*\(/.test(source)
    )
    .map(({ path }) => path)
    .sort();

  assertEquals(boundaries, EXPECTED_AUTHORIZATION_BOUNDARIES);

  for (const path of boundaries) {
    const source = files.find((file) => file.path === path)?.source ?? "";
    if (path === "reconcile-explore-media-health/handler.ts") {
      assertStringIncludes(source, "authorizeServiceRoleRequest(req,");
      assertStringIncludes(source, "envServerApiKey:");
      assertStringIncludes(source, "envServiceRoleKey:");
      assertStringIncludes(source, "envSecretKeys:");
    } else {
      assertStringIncludes(
        source,
        "authorizeServiceRoleRequestFromEnvironment(",
      );
    }
    assertStringIncludes(source, "auth.ok");
    assertStringIncludes(source, "auth.serverApiKey");
    assert(
      !source.includes("auth.token"),
      `${path} must not reuse a caller-supplied credential downstream.`,
    );
    assert(
      !source.includes("serviceRoleProbe") && !source.includes("probe:"),
      `${path} must not authorize through a capability probe.`,
    );
  }
});

Deno.test("production sources cannot introduce a manual legacy-key authorization boundary", async () => {
  const files = await collectTypeScriptFiles(functionsRoot);

  for (
    const { path, source } of files.filter(({ path }) =>
      isProductionTypeScript(path)
    )
  ) {
    if (path !== "_shared/serviceRoleAuth.ts") {
      for (
        const environmentRead of [
          'Deno.env.get("SUPABASE_SERVER_API_KEY")',
          'Deno.env.get("SUPABASE_SECRET_KEYS")',
          'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")',
        ]
      ) {
        assert(
          !source.includes(environmentRead),
          `${path} reads server credentials directly instead of using the shared resolver.`,
        );
      }
    }
    assert(
      !/timingSafeCompare\([\s\S]{0,240}Bearer[\s\S]{0,80}(?:serviceRole|serverApi)/i
        .test(source),
      `${path} contains a hand-written Supabase server-key Bearer check.`,
    );
    assert(
      !/Bearer \$\{Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/.test(
        source,
      ),
      `${path} builds a Bearer credential directly from the legacy key.`,
    );
  }
});

Deno.test("service-role authorization has no database or network fallback", async () => {
  const helper = await Deno.readTextFile(authHelperUrl);
  const executableHelper = withoutTypeScriptComments(helper);

  for (
    const forbiddenFragment of [
      "taxonomy_import_runs",
      "createClient(",
      "fetch(",
      "ServiceRoleProbe",
      "probeServiceRole",
    ]
  ) {
    assert(
      !executableHelper.includes(forbiddenFragment),
      `Authorization helper contains forbidden fallback: ${forbiddenFragment}`,
    );
  }
  assert(
    !/\b(?:supabase|client|admin)\s*\.\s*(?:from|rpc)\s*\(/.test(
      executableHelper,
    ),
    "Authorization helper contains a database-client fallback.",
  );

  for (
    const requiredFragment of [
      "timingSafeCompare(",
      "envSecretKeys",
      'startsWith("sb_secret_")',
      "MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20",
      "HS256_BASE64URL_SIGNATURE_LENGTH = 43",
      '"conflicting_credentials"',
      '"invalid_secret_key_configuration"',
    ]
  ) {
    assertStringIncludes(helper, requiredFragment);
  }
});

Deno.test("privileged clients and internal calls use the shared API-key transport policy", async () => {
  const files = await collectTypeScriptFiles(functionsRoot);
  const serviceAuth =
    files.find((file) => file.path === "_shared/serviceRoleAuth.ts")
      ?.source ?? "";
  const serviceClient =
    files.find((file) => file.path === "_shared/serviceRoleClient.ts")
      ?.source ?? "";
  const replayWorker =
    files.find((file) => file.path === "replay-scan-ingestion/worker.ts")
      ?.source ?? "";
  const directClientBoundaries = files
    .filter(({ path, source }) =>
      isProductionTypeScript(path) && importsSupabaseCreateClient(source)
    )
    .map(({ path }) => path)
    .sort();
  const legacyOnlyAdminClients = files
    .filter(({ path, source }) =>
      isProductionTypeScript(path) &&
      importsSupabaseCreateClient(source) &&
      source.includes('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")')
    )
    .map(({ path }) => path)
    .sort();

  assertEquals(
    directClientBoundaries,
    EXPECTED_DIRECT_SUPABASE_CLIENT_BOUNDARIES,
  );
  assertEquals(legacyOnlyAdminClients, []);
  assertStringIncludes(
    serviceClient,
    "deadlineTransport",
  );
  assertStringIncludes(
    serviceClient,
    "createServiceRoleClientFromEnvironment(",
  );
  assertStringIncludes(
    serviceClient,
    "requireServerApiKeyFromEnvironment()",
  );
  assertStringIncludes(serviceClient, "createDeadlineFetchTransport(");
  assertStringIncludes(serviceAuth, "apikey: serverApiKey");
  assertStringIncludes(serviceAuth, "serviceRoleRequestHeaders(");
  assertStringIncludes(replayWorker, "serviceRoleRequestHeaders(");
  assertStringIncludes(
    replayWorker,
    "requireServerApiKeyFromEnvironment()",
  );
  assert(
    !replayWorker.includes(
      '"Authorization": `Bearer ${input.serviceRoleKey}`',
    ),
  );
});

Deno.test("reconcile handler receives both platform-managed key sets from its route", async () => {
  const index = await Deno.readTextFile(reconcileIndexUrl);

  assertStringIncludes(index, "serverApiKeyOptionsFromEnvironment()");
});

Deno.test("production smoke tests deny real public project API keys before privileged work", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowUrl);
  const negativeSmokeIndex = workflow.indexOf(
    "supabase-public-api-keys.json",
  );
  const positiveSmokeIndex = workflow.indexOf("status_response=");

  assert(negativeSmokeIndex >= 0);
  assert(positiveSmokeIndex > negativeSmokeIndex);
  assertStringIncludes(workflow, "resolve_project_api_keys.ts");
  assertStringIncludes(workflow, "--allow-net=api.supabase.com");
  assertStringIncludes(workflow, "'.server_api_key'");
  assertStringIncludes(workflow, "'.public_api_keys'");
  assertStringIncludes(
    workflow,
    'if [[ "$SUPABASE_SERVER_API_KEY" != sb_secret_* ]]',
  );
  assertStringIncludes(workflow, '"${server_headers[@]}"');
  assert(
    !workflow.includes('| contains("service")'),
    "Server-key discovery must not accept loosely named API keys.",
  );
  assert(
    !workflow.includes("supabase projects api-keys"),
    "Secret-key discovery must use the revealed Management API resolver.",
  );
  assertStringIncludes(workflow, 'if [ "$denied_status" != "401" ]');
  assertStringIncludes(
    workflow,
    "/functions/v1/community-taxonomy-status",
  );
  assertStringIncludes(
    workflow,
    "/rest/v1/rpc/get_owned_explore_media_incidents",
  );
  assertStringIncludes(workflow, "--connect-timeout 10");
  assertStringIncludes(workflow, "--max-time 60");
});

Deno.test("operational callers use exact server-key discovery and shared transport", async () => {
  for (
    const workflowUrl of [
      importWorkflowUrl,
      scanMediaWorkflowUrl,
      revenueCatMonitorWorkflowUrl,
      dwcaMonitorWorkflowUrl,
    ]
  ) {
    const workflow = await Deno.readTextFile(workflowUrl);
    assertStringIncludes(workflow, "resolve_project_api_keys.ts");
    assertStringIncludes(workflow, "--allow-net=api.supabase.com");
    assertStringIncludes(workflow, "SUPABASE_SERVER_API_KEY:");
    assert(
      !workflow.includes('| contains("service")'),
      `${workflowUrl.pathname} must not classify keys by a partial name.`,
    );
    assert(
      !workflow.includes("supabase projects api-keys"),
      `${workflowUrl.pathname} must not use an unrevealed secret-key listing.`,
    );
  }

  for (
    const scriptUrl of [
      importScriptUrl,
      scanMediaScriptUrl,
      accountDeletionScriptUrl,
      revenueCatMonitorScriptUrl,
      dwcaMonitorScriptUrl,
    ]
  ) {
    const script = await Deno.readTextFile(scriptUrl);
    assertStringIncludes(script, "serviceRoleRequestHeaders(");
    assertStringIncludes(script, "requireServerApiKeyFromEnvironment()");
    assert(
      !script.includes('"Authorization": `Bearer ${'),
      `${scriptUrl.pathname} must use the shared API-key transport policy.`,
    );
  }
});
