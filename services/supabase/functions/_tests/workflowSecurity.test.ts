import {
  assert,
  assertEquals,
  assertMatch,
  assertStringIncludes,
} from "@std/assert";

const workflowsDirectory = new URL(
  "../../../../.github/workflows/",
  import.meta.url,
);
const functionsDenoConfig = new URL("../deno.json", import.meta.url);
const REMOTE_ACTION_PATTERN =
  /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*@[0-9a-f]{40}(?:\s+#\s+v?\S+)?$/;

async function workflowSources(): Promise<Array<[string, string]>> {
  const sources: Array<[string, string]> = [];
  for await (const entry of Deno.readDir(workflowsDirectory)) {
    if (
      entry.isFile &&
      (entry.name.endsWith(".yml") || entry.name.endsWith(".yaml"))
    ) {
      sources.push([
        entry.name,
        await Deno.readTextFile(new URL(entry.name, workflowsDirectory)),
      ]);
    }
  }
  return sources.sort(([left], [right]) => left.localeCompare(right));
}

Deno.test("production workflows pin remote actions and declare permissions", async () => {
  const sources = await workflowSources();
  assert(sources.length > 0);

  for (const [name, source] of sources) {
    assertMatch(
      source,
      /^permissions:\n(?:[ ]{2}[a-z-]+: (?:read|write|none)\n)+/m,
      `${name} must declare explicit top-level token permissions.`,
    );

    for (const line of source.split("\n")) {
      const action = line.match(/^\s*uses:\s*(\S.*)$/)?.[1];
      if (!action || action.startsWith("./")) continue;
      assertMatch(
        action,
        REMOTE_ACTION_PATTERN,
        `${name} uses a mutable or malformed remote action reference: ${action}`,
      );
    }
  }
});

Deno.test("first-party JavaScript actions use Node 24-era majors", async () => {
  const minimumMajor = new Map([
    ["checkout", 6],
    ["setup-node", 5],
    ["upload-artifact", 6],
    ["cache/restore", 5],
    ["cache/save", 5],
  ]);

  for (const [name, source] of await workflowSources()) {
    for (const line of source.split("\n")) {
      const action = line.match(
        /^\s*uses:\s*actions\/([^@]+)@[0-9a-f]{40}\s+#\s+v([0-9]+)\./,
      );
      if (!action || !minimumMajor.has(action[1])) continue;

      const major = Number(action[2]);
      assert(
        major >= (minimumMajor.get(action[1]) ?? Number.MAX_SAFE_INTEGER),
        `${name} uses a Node 20-era actions/${action[1]} major.`,
      );
    }
  }
});

Deno.test("uploaded artifacts are unique across workflow reruns", async () => {
  for (const [name, source] of await workflowSources()) {
    const lines = source.split("\n");
    for (let index = 0; index < lines.length; index++) {
      if (!lines[index].includes("uses: actions/upload-artifact@")) continue;

      const artifactName = lines.slice(index + 1, index + 12)
        .map((line) => line.match(/^\s+name:\s*(.+)$/)?.[1])
        .find((value) => value !== undefined);
      assert(
        artifactName?.includes("${{ github.run_attempt }}"),
        `${name}:${index + 1} has an artifact name that can collide on rerun.`,
      );
    }
  }
});

Deno.test("workflow secrets are scoped below the job environment", async () => {
  const sources = await workflowSources();

  for (const [name, source] of sources) {
    for (const line of source.split("\n")) {
      if (!line.includes("secrets.")) continue;
      const indentation = line.length - line.trimStart().length;
      assert(
        indentation >= 10,
        `${name} exposes a secret at workflow/job scope: ${line.trim()}`,
      );
    }
  }
});

Deno.test("every runner job has an explicit bounded timeout", async () => {
  const sources = await workflowSources();

  for (const [name, source] of sources) {
    const runnerJobs = source.match(/^[ ]{4}runs-on:[^\n]+$/gm) ?? [];
    const boundedRunnerJobs = source.match(
      /^[ ]{4}runs-on:[^\n]+\n[ ]{4}timeout-minutes: ([1-9][0-9]*)$/gm,
    ) ?? [];
    assertEquals(
      boundedRunnerJobs.length,
      runnerJobs.length,
      `${name} has a runner job without a timeout immediately after runs-on.`,
    );
    for (const definition of boundedRunnerJobs) {
      const minutes = Number(
        definition.match(/timeout-minutes: ([1-9][0-9]*)$/)?.[1],
      );
      assert(
        minutes <= 120,
        `${name} has an excessive ${minutes}-minute job timeout.`,
      );
    }
  }
});

Deno.test("only the isolated checklist writer requests repository write access", async () => {
  const sources = await workflowSources();
  const writers = sources
    .filter(([, source]) => /^[ ]+contents: write$/m.test(source))
    .map(([name]) => name);

  assertEquals(writers, ["import-community-taxonomy.yml"]);
  const writeGrants = sources.flatMap(([name, source]) =>
    (source.match(/^[ ]+([a-z-]+): write$/gm) ?? []).map((grant) =>
      `${name}: ${grant.trim()}`
    )
  );
  assertEquals(writeGrants, [
    "import-community-taxonomy.yml: contents: write",
  ]);

  const importWorkflow =
    sources.find(([name]) => name === "import-community-taxonomy.yml")?.[1] ??
      "";
  assertMatch(importWorkflow, /^permissions:\n[ ]{2}contents: read$/m);
  assertMatch(
    importWorkflow,
    /\n[ ]{2}commit-checklist:\n[\s\S]*?\n[ ]{4}permissions:\n[ ]{6}actions: read\n[ ]{6}contents: write\n/,
  );
});

Deno.test("production deploy invokes the complete Supabase tooling gate", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );

  assertMatch(
    deployWorkflow,
    /- name: Checkout repository[\s\S]*?fetch-depth: 0\n\s+persist-credentials: false/,
    "Production deploy must not persist its repository token into Git config.",
  );
  assertMatch(
    deployWorkflow,
    /- "apps\/ios\/Merian\/Core\/AI\/InferenceEdgeDTOs\.swift"/,
    "Swift DTO changes must trigger the contract gate.",
  );
  assertMatch(
    deployWorkflow,
    /- name: Gate whole-tree Supabase formatting\n\s+run: deno fmt --check supabase\/functions supabase\/scripts/,
    "Production deploy must format-gate functions and tooling.",
  );
  assertMatch(
    deployWorkflow,
    /- name: Gate whole-tree Supabase TypeScript lint\n\s+run: \|\n\s+deno lint --config supabase\/functions\/deno\.json \\\n\s+supabase\/functions \\\n\s+supabase\/scripts/,
    "Production deploy must lint functions and tooling.",
  );
  assertMatch(
    deployWorkflow,
    /- name: Test complete Supabase tooling suite\n\s+run: bash supabase\/scripts\/test_supabase_tooling\.sh/,
    "Production deploy must invoke the discovery-based tooling test gate.",
  );
});

Deno.test("production deploy runs the discovery-based complete Edge suite before mutation", async () => {
  const [deployWorkflow, denoConfigSource] = await Promise.all([
    Deno.readTextFile(new URL("deploy.yml", workflowsDirectory)),
    Deno.readTextFile(functionsDenoConfig),
  ]);
  const denoConfig = JSON.parse(denoConfigSource) as {
    tasks?: Record<string, unknown>;
  };
  const completeTestTask = denoConfig.tasks?.test;

  assertEquals(typeof completeTestTask, "string");
  assertMatch(
    completeTestTask as string,
    /^deno test --frozen [^\n]* \.$/,
    "The complete Edge task must discover tests from the whole Function tree.",
  );
  assert(
    !(completeTestTask as string).includes("--filter"),
    "The complete Edge task must not filter out runtime tests.",
  );

  const databaseStart = deployWorkflow.indexOf(
    "- name: Start disposable database for privileged-routine validation",
  );
  const catalogValidation = deployWorkflow.indexOf(
    "- name: Validate database security catalogs",
  );
  const completeEdgeSuite = deployWorkflow.indexOf(
    "- name: Test complete Edge Function suite",
  );
  const databaseAdvisors = deployWorkflow.indexOf(
    "- name: Validate database lint and advisors",
  );
  const deploymentPlan = deployWorkflow.indexOf(
    "- name: Plan affected Edge Function deployment",
  );
  const compatibilityPredeploy = deployWorkflow.indexOf(
    "- name: Deploy fail-closed recovery consumers before compatibility migrations",
  );
  const ghostMergeCiProof = deployWorkflow.indexOf(
    "- name: Record Ghost merge disposable-CI proof",
  );
  const ghostMergePredeploy = deployWorkflow.indexOf(
    "- name: Deploy Ghost merge mapper before Ghost merge migrations",
  );
  const migrationPush = deployWorkflow.indexOf(
    "- name: Push Database Migrations",
  );
  const functionDeploy = deployWorkflow.indexOf(
    "- name: Deploy affected Edge Functions",
  );
  const productionSmoke = deployWorkflow.indexOf(
    "- name: Smoke test production backend endpoints",
  );
  const ghostMergeHealthAudit = deployWorkflow.indexOf(
    "- name: Audit Ghost merge health after deployment",
  );

  assertMatch(
    deployWorkflow,
    /- name: Test complete Edge Function suite\n\s+env:\n\s+SUPABASE_DB_TEST_URL:[^\n]+\n\s+run: deno task --config supabase\/functions\/deno\.json test/,
  );
  for (
    const command of [
      "supabase db lint --local --schema public,internal \\\n            --level warning --fail-on warning",
      "supabase db advisors --local --type security \\\n            --level warn --fail-on error",
      "supabase db advisors --local --type performance \\\n            --level warn --fail-on error",
    ]
  ) {
    assertStringIncludes(deployWorkflow, command);
  }
  assert(
    databaseStart >= 0 &&
      databaseStart < catalogValidation &&
      catalogValidation < completeEdgeSuite &&
      completeEdgeSuite < databaseAdvisors &&
      databaseAdvisors < deploymentPlan &&
      deploymentPlan < ghostMergeCiProof &&
      ghostMergeCiProof < compatibilityPredeploy &&
      compatibilityPredeploy < ghostMergePredeploy &&
      ghostMergePredeploy < migrationPush &&
      migrationPush < functionDeploy &&
      functionDeploy < productionSmoke &&
      productionSmoke < ghostMergeHealthAudit,
    "Disposable-database catalogs, the complete Edge suite, lint, and advisors must pass before the compatibility predeploy, the first possible production mutation.",
  );
});

Deno.test("production smoke proves critical user Edge routes reach Merian handlers", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );

  assertStringIncludes(deployWorkflow, "probe_user_function_route()");
  assertStringIncludes(
    deployWorkflow,
    "grep -Eqi '^x-merian-handler:[[:space:]]*1[[:space:]]*$'",
  );
  assertStringIncludes(deployWorkflow, '[ "$status" = "401" ]');
  for (
    const functionName of [
      "identify-multimodal",
      "check-scan-status",
      "share-scan-to-explore",
      "get-explore-composer-media",
      "get-explore-media-incidents",
      "insight-chat",
    ]
  ) {
    assertMatch(
      deployWorkflow,
      new RegExp(`^\\s+${functionName}$`, "m"),
      `${functionName} must be route-probed before production smoke completes.`,
    );
  }
});

Deno.test("production smoke proves every Edge route reaches a Merian handler", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );

  assertStringIncludes(deployWorkflow, "probe_all_function_routes()");
  assertMatch(
    deployWorkflow,
    /plan_function_deploy\.ts\s+\\\n\s+--all > "\$function_plan_file"/,
  );
  assertStringIncludes(deployWorkflow, "-X OPTIONS");
  assertStringIncludes(
    deployWorkflow,
    'mapfile -t pending_functions < "$function_plan_file"',
  );
  assertStringIncludes(
    deployWorkflow,
    'map(select(startswith("sb_publishable_") | not)) | first // empty',
  );
  assertStringIncludes(
    deployWorkflow,
    '-H "Authorization: Bearer ${route_probe_jwt}"',
  );
  assertStringIncludes(
    deployWorkflow,
    "A publishable API key is never valid Bearer authorization.",
  );
  assertMatch(
    deployWorkflow,
    /grep -Eq \\\n\s+'\^\[\[:space:\]\]\*verify_jwt/,
  );
  assertStringIncludes(
    deployWorkflow,
    "grep -Eqi '^x-merian-handler:[[:space:]]*1[[:space:]]*$'",
  );
  assertMatch(
    deployWorkflow,
    /probe_all_function_routes\s*\n\s*critical_user_functions=/,
  );
  for (
    const criticalRoute of [
      "identify-multimodal",
      "check-scan-status",
      "share-scan-to-explore",
      "get-explore-composer-media",
      "get-explore-media-incidents",
      "insight-chat",
      "request-community-identification",
    ]
  ) {
    assertStringIncludes(deployWorkflow, criticalRoute);
  }
});

Deno.test("production smoke drains and checks the private DwCA cleanup outbox", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );

  assertMatch(
    deployWorkflow,
    /dwca_cleanup_response[\s\S]*post_server_json[\s\S]*\/functions\/v1\/reconcile-dwca-archive-cleanup/,
  );
  assertStringIncludes(deployWorkflow, '.health_status == "healthy"');
  assertStringIncludes(deployWorkflow, '.health_status == "warning"');
  assertStringIncludes(
    deployWorkflow,
    "'{claimed, completed, deferred, health_status}'",
  );
});

Deno.test("operational Supabase scripts run with least-privilege Deno scopes", async () => {
  const sources = new Map(await workflowSources());
  const monitorWorkflows = [
    "account-deletion-health-monitor.yml",
    "dwca-export-health-monitor.yml",
    "revenuecat-reconciliation-health-monitor.yml",
    "scan-media-health-monitor.yml",
  ];

  for (const name of monitorWorkflows) {
    const source = sources.get(name) ?? "";
    assertStringIncludes(
      source,
      '--allow-net="${PROJECT_ID}.supabase.co"',
    );
    assertStringIncludes(
      source,
      "--allow-env=SUPABASE_URL,SUPABASE_SERVER_API_KEY,MERIAN_SUPABASE_SERVER_API_KEY,SUPABASE_SECRET_KEYS,SUPABASE_SECRET_KEY,SUPABASE_SERVICE_ROLE_KEY",
    );
    assertStringIncludes(source, '--allow-write="$RUNNER_TEMP"');
    assertMatch(source, /deno run --frozen/);
    assert(
      !/--allow-(?:net|env|read|write)(?:\s|\\)/.test(source),
      `${name} contains an unrestricted Deno permission.`,
    );
  }

  const ghostMergeMonitor = sources.get(
    "ghost-profile-merge-health-monitor.yml",
  ) ?? "";
  assertStringIncludes(ghostMergeMonitor, "persist-credentials: false");
  assertStringIncludes(ghostMergeMonitor, '--allow-net="$database_endpoint"');
  assertStringIncludes(
    ghostMergeMonitor,
    "--allow-env=MERIAN_DATABASE_URL",
  );
  assertStringIncludes(ghostMergeMonitor, '--allow-write="$RUNNER_TEMP"');
  assertStringIncludes(
    ghostMergeMonitor,
    "services/supabase/scripts/monitor_ghost_profile_merges.ts",
  );
  assertMatch(ghostMergeMonitor, /deno run --frozen/);
  assert(
    !/--allow-(?:net|env|read|write)(?:\s|\\)/.test(ghostMergeMonitor),
    "Ghost merge monitor contains an unrestricted Deno permission.",
  );

  const importWorkflow = sources.get("import-community-taxonomy.yml") ?? "";
  assertStringIncludes(importWorkflow, "persist-credentials: false");
  assertStringIncludes(
    importWorkflow,
    '--allow-net="${PROJECT_ID}.supabase.co"',
  );
  assertStringIncludes(
    importWorkflow,
    "--allow-env=SUPABASE_URL,SUPABASE_SERVER_API_KEY,MERIAN_SUPABASE_SERVER_API_KEY,SUPABASE_SECRET_KEYS,SUPABASE_SECRET_KEY,SUPABASE_SERVICE_ROLE_KEY",
  );
  assertStringIncludes(
    importWorkflow,
    "--allow-read=docs/backend-and-data/07-community-taxonomy-import-checklist.md",
  );
  assertStringIncludes(
    importWorkflow,
    '--allow-write="$RUNNER_TEMP",docs/backend-and-data/07-community-taxonomy-import-checklist.md',
  );
  assert(
    !/--allow-(?:net|env|read|write)(?:\s|\\)/.test(importWorkflow),
    "Taxonomy import contains an unrestricted Deno permission.",
  );

  const importStep = importWorkflow.indexOf(
    "services/supabase/scripts/import_community_taxonomy.ts",
  );
  const tokenStep = importWorkflow.indexOf("GH_TOKEN: ${{ github.token }}");
  assert(importStep >= 0 && tokenStep > importStep);
  assertStringIncludes(importWorkflow, "needs: import");
  assertStringIncludes(importWorkflow, 'gh run download "$GITHUB_RUN_ID"');
  assertStringIncludes(importWorkflow, "gh auth setup-git");
});
