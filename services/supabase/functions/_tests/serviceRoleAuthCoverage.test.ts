import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const functionsRoot = new URL("../", import.meta.url);
const authHelperUrl = new URL(
  "../_shared/serviceRoleAuth.ts",
  import.meta.url,
);
const publishableKeyHelperUrl = new URL(
  "../_shared/publishableKey.ts",
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
const accountDeletionMonitorWorkflowUrl = new URL(
  "../../../../.github/workflows/account-deletion-health-monitor.yml",
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
  "reconcile-dwca-archive-cleanup/index.ts",
  "reconcile-explore-media-health/handler.ts",
  "reconcile-ghost-profile-merges/index.ts",
  "reconcile-revenuecat-subscribers/index.ts",
  "reconcile-scan-deletions/index.ts",
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
  "transfer-signout-purchases/db.ts",
];

const EXPECTED_PUBLIC_KEY_CONSUMERS = [
  "_shared/auth.ts",
  "_shared/claimsAuth.ts",
  "merge-ghost-profile/db.ts",
  "species-observation-stats/security.ts",
  "transfer-signout-purchases/db.ts",
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
      assertStringIncludes(source, "extends ServiceRoleAuthOptions");
      assertStringIncludes(source, "authorizeServiceRoleRequest(req, options)");
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
    for (
      const forbiddenDiagnostic of [
        "hasServerKey",
        "hasSecretKeys",
        "secretKeysLength",
        "secretKeysPrefix",
        "secretKeysSuffix",
        "tokenPrefix",
        "tokenSuffix",
        "tokenLength",
      ]
    ) {
      assert(
        !source.includes(forbiddenDiagnostic),
        `${path} exposes a secret-derived authentication diagnostic.`,
      );
    }
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
          'Deno.env.get("MERIAN_SUPABASE_SERVER_API_KEY")',
          'Deno.env.get("SUPABASE_SECRET_KEYS")',
          'Deno.env.get("SUPABASE_SECRET_KEY")',
          'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")',
        ]
      ) {
        assert(
          !source.includes(environmentRead),
          `${path} reads server credentials directly instead of using the shared resolver.`,
        );
      }
    }
    if (
      path !== "_shared/serviceRoleAuth.ts" &&
      path !== "_shared/serviceRoleClient.ts"
    ) {
      assert(
        !/timingSafeCompare\([\s\S]{0,240}Bearer[\s\S]{0,80}(?:serviceRole|serverApi)/i
          .test(source),
        `${path} contains a hand-written Supabase server-key Bearer check.`,
      );
    }
    assert(
      !/Bearer \$\{Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/.test(
        source,
      ),
      `${path} builds a Bearer credential directly from the legacy key.`,
    );
  }
});

Deno.test("public project key reads and parsing remain centralized", async () => {
  const files = await collectTypeScriptFiles(functionsRoot);
  const consumers = files
    .filter(({ path, source }) =>
      isProductionTypeScript(path) &&
      path !== "_shared/publishableKey.ts" &&
      /\brequirePublicApiKeys?FromEnvironment\s*\(/.test(source)
    )
    .map(({ path }) => path)
    .sort();

  assertEquals(consumers, EXPECTED_PUBLIC_KEY_CONSUMERS);

  for (
    const { path, source } of files.filter(({ path }) =>
      isProductionTypeScript(path)
    )
  ) {
    if (path === "_shared/publishableKey.ts") continue;
    for (
      const environmentRead of [
        'Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")',
        'Deno.env.get("SUPABASE_ANON_KEY")',
      ]
    ) {
      assert(
        !source.includes(environmentRead),
        `${path} reads public project credentials outside the shared resolver.`,
      );
    }
  }

  const helper = await Deno.readTextFile(publishableKeyHelperUrl);
  for (
    const requiredFragment of [
      'Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")',
      'Deno.env.get("SUPABASE_ANON_KEY")',
      "startsWith(PUBLISHABLE_KEY_PREFIX)",
      'payload?.role === "anon"',
      'entry.name === "default"',
      "legacyAnonKeyValid",
      "acceptedPublicApiKeys",
      '"invalid_publishable_key_configuration"',
    ]
  ) {
    assertStringIncludes(helper, requiredFragment);
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
      "envSecretKey",
      "envSecretKeys",
      "envSynchronizedServerApiKey",
      "classifyServerKeyConfiguration(",
      "validConfiguredServerKeys",
      "hasInvalidServerKeySource",
      'Deno.env.get("MERIAN_SUPABASE_SERVER_API_KEY")',
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
  assertStringIncludes(serviceClient, 'startsWith("sb_secret_")');
  assertStringIncludes(
    serviceClient,
    "timingSafeCompare(bearerCredential, validatedServerApiKey)",
  );
  assertStringIncludes(serviceClient, "/^Bearer\\s+([^\\s]+)$/i");
  assertStringIncludes(
    serviceClient,
    "input instanceof Request ? input.headers",
  );
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
  assertStringIncludes(
    serviceClient,
    "createResponseBodyLimitFetchTransport(",
  );
  assertStringIncludes(serviceClient, "createServiceRoleClientWithOptions(");
  assertStringIncludes(
    serviceClient,
    "createServiceRoleClientFromEnvironmentWithOptions(",
  );
  assertStringIncludes(serviceClient, "invokeServiceRoleJson<");
  assertStringIncludes(
    serviceClient,
    "ServiceRoleFunctionInvocationError",
  );
  assertStringIncludes(serviceClient, '"X-Merian-Handler"');
  assertStringIncludes(serviceClient, "Response body withheld.");
  assertStringIncludes(serviceAuth, "apikey: serverApiKey");
  assert(
    !serviceAuth.includes("x-supabase-server-key"),
    "Internal service authentication must use Supabase's standard apikey transport.",
  );
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

Deno.test("reconcile handler receives every shared server-key source from its route", async () => {
  const index = await Deno.readTextFile(reconcileIndexUrl);

  assertStringIncludes(index, "serverApiKeyOptionsFromEnvironment()");
});

Deno.test("production smoke tests deny real public project API keys before privileged work", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowUrl);
  const synchronizedFallbackIndex = workflow.indexOf(
    "Synchronize active server API key to Edge fallback",
  );
  const digestVerificationIndex = workflow.indexOf(
    "verify_edge_secret_digest.ts",
  );
  const functionDeployIndex = workflow.indexOf(
    "Deploy affected Edge Functions",
  );
  const negativeSmokeIndex = workflow.indexOf(
    "supabase-public-api-keys.json",
  );
  const positiveSmokeIndex = workflow.indexOf("status_response=");
  const functionFailureDiagnosticIndex = workflow.indexOf("/functions/v1/*)");
  const handlerMarkerDiagnosticIndex = workflow.indexOf(
    "grep -Eqi '^x-merian-handler:[[:space:]]*1[[:space:]]*$'",
  );
  const dataApiFailureDiagnosticIndex = workflow.indexOf("/rest/v1/*)");

  assert(synchronizedFallbackIndex >= 0);
  assert(digestVerificationIndex > synchronizedFallbackIndex);
  assert(functionDeployIndex > digestVerificationIndex);
  assert(negativeSmokeIndex >= 0);
  assert(positiveSmokeIndex > negativeSmokeIndex);
  assert(functionFailureDiagnosticIndex >= 0);
  assert(handlerMarkerDiagnosticIndex > functionFailureDiagnosticIndex);
  assert(dataApiFailureDiagnosticIndex > handlerMarkerDiagnosticIndex);
  assertStringIncludes(workflow, "resolve_project_api_keys.ts");
  assertStringIncludes(workflow, "--allow-net=api.supabase.com");
  assertStringIncludes(workflow, "'.server_api_key'");
  assertStringIncludes(workflow, "'.public_api_keys'");
  assertStringIncludes(
    workflow,
    '"MERIAN_SUPABASE_SERVER_API_KEY=$MERIAN_SUPABASE_SERVER_API_KEY"',
  );
  assertStringIncludes(workflow, "supabase secrets list");
  assertStringIncludes(workflow, "--output json");
  assertStringIncludes(
    workflow,
    "--allow-env=MERIAN_SUPABASE_SERVER_API_KEY",
  );
  assertStringIncludes(
    workflow,
    "--secret-name MERIAN_SUPABASE_SERVER_API_KEY",
  );
  assertStringIncludes(workflow, "smoke_max_attempts=6");
  assertStringIncludes(workflow, "is_retryable_smoke_status()");
  assertStringIncludes(workflow, "--dump-header");
  assertStringIncludes(workflow, ': > "$smoke_header_file"');
  assertStringIncludes(workflow, ': > "$smoke_response_file"');
  assertStringIncludes(
    workflow,
    "This request targeted the Data API; inspect the API gateway, PostgREST RPC grants, and database logs.",
  );
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
      accountDeletionMonitorWorkflowUrl,
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
    assert(
      /\bcreateServiceRoleClientFromEnvironment(?:WithOptions)?\s*\(/.test(
        script,
      ),
      `${scriptUrl.pathname} must use an environment-backed shared client.`,
    );
    assert(
      !script.includes('"Authorization": `Bearer ${'),
      `${scriptUrl.pathname} must use the shared API-key transport policy.`,
    );
  }

  for (const functionCallerUrl of [importScriptUrl, scanMediaScriptUrl]) {
    const script = await Deno.readTextFile(functionCallerUrl);
    assertStringIncludes(script, "invokeServiceRoleJson");
  }

  for (
    const boundedMonitorUrl of [
      accountDeletionScriptUrl,
      revenueCatMonitorScriptUrl,
      dwcaMonitorScriptUrl,
    ]
  ) {
    const script = await Deno.readTextFile(boundedMonitorUrl);
    assertStringIncludes(
      script,
      "createServiceRoleClientFromEnvironmentWithOptions(",
    );
    assertStringIncludes(script, "MONITOR_REQUEST_TIMEOUT_MS = 15_000");
    assertStringIncludes(
      script,
      "MONITOR_MAXIMUM_RESPONSE_BYTES = 64 * 1_024",
    );
    assertStringIncludes(
      script,
      "maximumResponseBytes: MONITOR_MAXIMUM_RESPONSE_BYTES",
    );
  }

  const scanMediaScript = await Deno.readTextFile(scanMediaScriptUrl);
  assertStringIncludes(
    scanMediaScript,
    "createServiceRoleClientFromEnvironmentWithOptions(",
  );
  assertStringIncludes(
    scanMediaScript,
    "MONITOR_REQUEST_TIMEOUT_MS = 15_000",
  );
  assertStringIncludes(
    scanMediaScript,
    "MONITOR_MAXIMUM_RESPONSE_BYTES = 2 * 1_024 * 1_024",
  );
  assertStringIncludes(
    scanMediaScript,
    "maximumResponseBytes: MONITOR_MAXIMUM_RESPONSE_BYTES",
  );
});
