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
const setupDenoActionUrl = new URL(
  "../../../../.github/actions/setup-deno/action.yml",
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

  const setupDenoAction = await Deno.readTextFile(setupDenoActionUrl);
  for (const line of setupDenoAction.split("\n")) {
    const action = line.match(/^\s*uses:\s*(\S.*)$/)?.[1];
    if (!action || action.startsWith("./")) continue;
    assertMatch(
      action,
      REMOTE_ACTION_PATTERN,
      `setup-deno/action.yml uses a mutable or malformed remote action reference: ${action}`,
    );
  }
});

Deno.test("every Deno workflow uses the bounded exact-version installer", async () => {
  const sources = await workflowSources();
  const setupDenoAction = await Deno.readTextFile(setupDenoActionUrl);
  let localSetupCount = 0;
  let versionInputCount = 0;

  for (const [name, source] of sources) {
    assert(
      !source.includes("uses: denoland/setup-deno@"),
      `${name} bypasses the repository's bounded Deno installer`,
    );
    localSetupCount += source.match(/uses: \.\/\.github\/actions\/setup-deno/g)
      ?.length ?? 0;
    versionInputCount += source.match(/deno-version: v2\.9\.4/g)?.length ?? 0;
  }

  assert(localSetupCount > 0, "No workflow uses the pinned Deno installer.");
  assertEquals(
    versionInputCount,
    localSetupCount,
    "Every Deno installer invocation must request the exact reviewed version.",
  );
  assertEquals(
    setupDenoAction.match(
      /uses: denoland\/setup-deno@22d081ff2d3a40755e97629de92e3bcbfa7cf2ed/g,
    )
      ?.length ?? 0,
    3,
    "The shared installer must make exactly three bounded attempts with the reviewed action SHA.",
  );
  assertEquals(
    setupDenoAction.match(/continue-on-error: true/g)?.length ?? 0,
    2,
    "Only the first two Deno installation attempts may tolerate failure.",
  );
  for (
    const fragment of [
      "steps.setup_deno_attempt_1.outcome == 'failure'",
      "steps.setup_deno_attempt_2.outcome == 'failure'",
      'expected_version="${EXPECTED_DENO_VERSION#v}"',
      'actual_version="$(deno --version | awk',
      'if [ "$actual_version" != "$expected_version" ]; then',
    ]
  ) {
    assertStringIncludes(setupDenoAction, fragment);
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

Deno.test("production Supabase CLI telemetry is disabled at job scope", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );
  const telemetryOptOut = deployWorkflow.indexOf(
    '      SUPABASE_TELEMETRY_DISABLED: "1"',
  );
  const steps = deployWorkflow.indexOf("    steps:");

  assert(
    telemetryOptOut >= 0 && telemetryOptOut < steps,
    "The production job must disable Supabase telemetry before any CLI step runs.",
  );
});

Deno.test("Supabase candidate validation is reusable and production-isolated", async () => {
  const [candidateWorkflow, deployWorkflow] = await Promise.all([
    Deno.readTextFile(
      new URL("supabase-candidate-validation.yml", workflowsDirectory),
    ),
    Deno.readTextFile(new URL("deploy.yml", workflowsDirectory)),
  ]);

  assertStringIncludes(candidateWorkflow, "  pull_request:");
  assertStringIncludes(candidateWorkflow, "  merge_group:");
  assertStringIncludes(candidateWorkflow, "  workflow_dispatch:");
  assertStringIncludes(candidateWorkflow, "  workflow_call:");
  assert(
    !/^\s{4}paths(?:-ignore)?:/m.test(candidateWorkflow),
    "Candidate validation must report on every pull request and scope work inside the workflow.",
  );
  assertStringIncludes(
    candidateWorkflow,
    "bash scripts/test-ci-detect-supabase-candidate-source-changes.sh",
  );
  assertStringIncludes(
    candidateWorkflow,
    "bash scripts/ci-detect-supabase-candidate-source-changes.sh",
  );
  assertStringIncludes(candidateWorkflow, "needs: scope");
  assertStringIncludes(
    candidateWorkflow,
    "if: needs.scope.outputs.should_run == 'true'",
  );
  assertStringIncludes(candidateWorkflow, "candidate-readiness:");
  assertStringIncludes(candidateWorkflow, "name: Candidate readiness");
  assertStringIncludes(candidateWorkflow, "if: always()");
  assertStringIncludes(
    candidateWorkflow,
    'if [ "$SCOPE_RESULT" != "success" ]; then',
  );
  assertStringIncludes(
    candidateWorkflow,
    'if [ "$VALIDATION_RESULT" != "success" ]; then',
  );
  assertStringIncludes(candidateWorkflow, "deno-version: v2.9.4");
  assertStringIncludes(candidateWorkflow, "version: 2.109.1");
  assertStringIncludes(candidateWorkflow, "fetch-depth: 0");
  assertStringIncludes(candidateWorkflow, "persist-credentials: false");
  assertStringIncludes(candidateWorkflow, "git status --porcelain");
  assertStringIncludes(candidateWorkflow, "supabase db start");
  assertStringIncludes(
    candidateWorkflow,
    "bash supabase/scripts/test_database_catalogs.sh",
  );
  assertStringIncludes(
    candidateWorkflow,
    "deno task --config supabase/functions/deno.json test",
  );
  assertStringIncludes(candidateWorkflow, "supabase db lint --local");
  assertStringIncludes(candidateWorkflow, "supabase db advisors --local");
  assertStringIncludes(candidateWorkflow, "supabase stop --no-backup");
  assert(
    !candidateWorkflow.includes("environment: Production") &&
      !candidateWorkflow.includes("secrets.") &&
      !candidateWorkflow.includes("supabase db push") &&
      !candidateWorkflow.includes("deploy_function_batches.sh"),
    "Candidate validation must not receive production access or perform production mutations.",
  );

  const prerequisite = deployWorkflow.indexOf(
    "candidate-validation:\n    name: Validate candidate without production access",
  );
  const reusableCall = deployWorkflow.indexOf(
    "uses: ./.github/workflows/supabase-candidate-validation.yml",
    prerequisite,
  );
  const deployJob = deployWorkflow.indexOf("  deploy:", reusableCall);
  const dependency = deployWorkflow.indexOf(
    "needs: candidate-validation",
    deployJob,
  );
  assert(
    prerequisite >= 0 && reusableCall > prerequisite &&
      deployJob > reusableCall &&
      dependency > deployJob,
    "Production deployment must require the reusable candidate validation job first.",
  );
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

Deno.test("production smoke authenticates the deletion reaper without mutating work", async () => {
  const deployWorkflow = await Deno.readTextFile(
    new URL("deploy.yml", workflowsDirectory),
  );

  for (
    const fragment of [
      '"/functions/v1/reconcile-account-deletions"',
      "'{\"dry_run\":true}'",
      '(keys | sort) == ["dry_run", "success"]',
      ".success == true",
      ".dry_run == true",
    ]
  ) {
    assertStringIncludes(deployWorkflow, fragment);
  }
  assert(
    deployWorkflow.indexOf("probe_all_function_routes") <
      deployWorkflow.indexOf('account_deletion_reaper_validation="$('),
    "The authenticated non-mutating reaper probe must run after every route reaches a Merian handler.",
  );
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
      "transfer-signout-purchases",
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
  const deployWorkflow = sources.get("deploy.yml") ?? "";
  assertStringIncludes(ghostMergeMonitor, "persist-credentials: false");
  for (const source of [ghostMergeMonitor, deployWorkflow]) {
    assertStringIncludes(source, "deno_postgres_net_scope.sh");
    assertStringIncludes(source, 'database_network_scope="$(');
    assertStringIncludes(
      source,
      '--allow-net="$database_network_scope"',
    );
    assertStringIncludes(
      source,
      '--allow-env="MERIAN_DATABASE_URL,PG*"',
    );
  }
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

Deno.test("production RevenueCat monitoring isolates the additive rotation-health window", async () => {
  const monitor = await Deno.readTextFile(
    new URL("revenuecat-reconciliation-health-monitor.yml", workflowsDirectory),
  );

  assertStringIncludes(
    monitor,
    "--purchase-principal-signout-rotation-health-mode expand-compatible",
  );
  assertStringIncludes(monitor, "--warning-prepared-rotations");
  assertStringIncludes(monitor, "--critical-prepared-rotations");
  assertStringIncludes(
    monitor,
    "INPUT_WARNING_PREPARED_ROTATIONS: ${{ inputs.warning_prepared_rotations || '100' }}",
  );
  assertStringIncludes(
    monitor,
    "INPUT_CRITICAL_PREPARED_ROTATIONS: ${{ inputs.critical_prepared_rotations || '500' }}",
  );
  assertStringIncludes(
    monitor,
    "The established purchase-principal aggregate remains mandatory",
  );
  assert(
    !monitor.includes("--purchase-principal-health-mode"),
    "The established principal-health RPC must not expose a compatibility flag.",
  );
  assert(
    !monitor.includes(
      "--purchase-principal-signout-rotation-health-mode required",
    ),
    "The additive rotation-health RPC cannot become required before its hosted smoke passes.",
  );
});

Deno.test("account deletion monitor marks the additive recovery pre-deploy window explicitly", async () => {
  const monitor = await Deno.readTextFile(
    new URL("account-deletion-health-monitor.yml", workflowsDirectory),
  );

  assertStringIncludes(
    monitor,
    "--recovery-health-mode expand-compatible",
  );
  assert(
    !monitor.includes("--recovery-health-mode required"),
    "The schedule cannot require recovery health until both additive RPCs pass hosted smoke.",
  );
});

Deno.test("candidate and deploy workflows never mutate purchase identity rollout modes", async () => {
  for (
    const filename of [
      "supabase-candidate-validation.yml",
      "deploy.yml",
    ]
  ) {
    const workflow = (await Deno.readTextFile(
      new URL(filename, workflowsDirectory),
    )).toLowerCase();

    for (
      const forbidden of [
        "apply_purchase_identity_rollout_operation",
        "control_purchase_identity_rollout.ts --apply",
        "update internal.purchase_identity_rollout_config",
      ]
    ) {
      assert(
        !workflow.includes(forbidden),
        `${filename} must not contain rollout mutation ${forbidden}.`,
      );
    }
  }
});

Deno.test("complete release gates execute the purchase identity rollout tool tests", async () => {
  const denoConfig = JSON.parse(
    await Deno.readTextFile(functionsDenoConfig),
  ) as { tasks?: Record<string, string> };
  const completeTestTask = denoConfig.tasks?.test ?? "";

  assertStringIncludes(
    completeTestTask,
    "../scripts/control_purchase_identity_rollout_test.ts",
  );
  for (const filename of ["supabase-candidate-validation.yml", "deploy.yml"]) {
    const workflow = await Deno.readTextFile(
      new URL(filename, workflowsDirectory),
    );
    assertStringIncludes(
      workflow,
      "deno task --config supabase/functions/deno.json test",
    );
  }
});
