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
const importScriptUrl = new URL(
  "../../scripts/import_community_taxonomy.ts",
  import.meta.url,
);
const scanMediaScriptUrl = new URL(
  "../../scripts/monitor_scan_media_health.ts",
  import.meta.url,
);

const EXPECTED_AUTHORIZATION_BOUNDARIES = [
  "community-taxonomy-status/index.ts",
  "identify-multimodal/index.ts",
  "reconcile-explore-media-health/handler.ts",
  "replay-scan-ingestion/index.ts",
  "scan-media-health/index.ts",
  "sync-community-taxonomy-index/index.ts",
];

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
      source.includes("authorizeServiceRoleRequest(")
    )
    .map(({ path }) => path)
    .sort();

  assertEquals(boundaries, EXPECTED_AUTHORIZATION_BOUNDARIES);

  for (const path of boundaries) {
    const source = files.find((file) => file.path === path)?.source ?? "";
    assertStringIncludes(source, "envServiceRoleKey:");
    assertStringIncludes(source, "envSecretKeys:");
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

Deno.test("service-role authorization has no database or network fallback", async () => {
  const helper = await Deno.readTextFile(authHelperUrl);

  for (
    const forbiddenFragment of [
      "taxonomy_import_runs",
      ".from(",
      "createClient(",
      "fetch(",
      "ServiceRoleProbe",
      "probeServiceRole",
    ]
  ) {
    assert(
      !helper.includes(forbiddenFragment),
      `Authorization helper contains forbidden fallback: ${forbiddenFragment}`,
    );
  }

  for (
    const requiredFragment of [
      "timingSafeCompare(",
      "envSecretKeys",
      'startsWith("sb_secret_")',
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

  assertStringIncludes(serviceClient, 'startsWith("sb_secret_")');
  assertStringIncludes(
    serviceClient,
    'accessToken: () => Promise.resolve("")',
  );
  assertStringIncludes(serviceClient, "createServiceRoleDataClient(");
  assertStringIncludes(
    serviceClient,
    "Do not use the returned client's Auth namespace.",
  );
  assertStringIncludes(serviceAuth, "apikey: serverApiKey");
  assertStringIncludes(serviceAuth, "serviceRoleRequestHeaders(");
  assertStringIncludes(replayWorker, "serviceRoleRequestHeaders(");
  assert(
    !replayWorker.includes(
      '"Authorization": `Bearer ${input.serviceRoleKey}`',
    ),
  );
});

Deno.test("reconcile handler receives both platform-managed key sets from its route", async () => {
  const index = await Deno.readTextFile(reconcileIndexUrl);

  assertStringIncludes(index, 'Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")');
  assertStringIncludes(index, 'Deno.env.get("SUPABASE_SECRET_KEYS")');
});

Deno.test("production smoke tests deny real public project API keys before privileged work", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowUrl);
  const negativeSmokeIndex = workflow.indexOf(
    "supabase-public-api-keys.json",
  );
  const positiveSmokeIndex = workflow.indexOf("status_response=");

  assert(negativeSmokeIndex >= 0);
  assert(positiveSmokeIndex > negativeSmokeIndex);
  assertStringIncludes(workflow, 'startswith("sb_publishable_")');
  assertStringIncludes(workflow, 'startswith("sb_secret_")');
  assertStringIncludes(
    workflow,
    '$type == "legacy" and $name == "service_role"',
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
  assertStringIncludes(workflow, 'if [ "$denied_status" != "401" ]');
  assertStringIncludes(
    workflow,
    "/functions/v1/community-taxonomy-status",
  );
});

Deno.test("operational callers use exact server-key discovery and shared transport", async () => {
  for (const workflowUrl of [importWorkflowUrl, scanMediaWorkflowUrl]) {
    const workflow = await Deno.readTextFile(workflowUrl);
    assertStringIncludes(workflow, 'startswith("sb_secret_")');
    assertStringIncludes(
      workflow,
      '$type == "legacy" and $name == "service_role"',
    );
    assertStringIncludes(workflow, "SUPABASE_SERVER_API_KEY:");
    assert(
      !workflow.includes('| contains("service")'),
      `${workflowUrl.pathname} must not classify keys by a partial name.`,
    );
  }

  for (const scriptUrl of [importScriptUrl, scanMediaScriptUrl]) {
    const script = await Deno.readTextFile(scriptUrl);
    assertStringIncludes(script, "serviceRoleRequestHeaders(");
    assertStringIncludes(script, 'Deno.env.get("SUPABASE_SERVER_API_KEY")');
    assert(
      !script.includes('"Authorization": `Bearer ${'),
      `${scriptUrl.pathname} must use the shared API-key transport policy.`,
    );
  }
});
