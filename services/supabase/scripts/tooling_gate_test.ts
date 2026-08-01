import {
  assert,
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const scriptsDirectory = new URL("./", import.meta.url);
const toolingGatePath = new URL(
  "test_supabase_tooling.sh",
  scriptsDirectory,
);
const dtoContractGatePath = new URL(
  "validate_edge_dto_contract.sh",
  scriptsDirectory,
);
const migrationContractGatePath = new URL(
  "validate_migration_contracts.sh",
  scriptsDirectory,
);
const iosProjectGuardrailPath = new URL(
  "../../../.github/workflows/ios-project-guardrails.yml",
  scriptsDirectory,
);
const deployWorkflowPath = new URL(
  "../../../.github/workflows/deploy.yml",
  scriptsDirectory,
);
const databaseCatalogGatePath = new URL(
  "test_database_catalogs.sh",
  scriptsDirectory,
);
const supabaseCliVersionGatePath = new URL(
  "require_supabase_cli_version.sh",
  scriptsDirectory,
);
const makefilePath = new URL(
  "../../../Makefile",
  scriptsDirectory,
);
const dependabotPath = new URL(
  "../../../.github/dependabot.yml",
  scriptsDirectory,
);

Deno.test("Supabase tooling gate discovers every standard TypeScript test", async () => {
  const gate = await Deno.readTextFile(toolingGatePath);
  const testFiles: string[] = [];
  for await (const entry of Deno.readDir(scriptsDirectory)) {
    if (entry.isFile && entry.name.endsWith("_test.ts")) {
      testFiles.push(entry.name);
    }
  }

  assert(testFiles.includes("audit_ghost_users_test.ts"));
  assert(testFiles.includes("cleanup_ghost_users_test.ts"));
  assertMatch(
    gate,
    /for source in services\/supabase\/scripts\/\*\.ts/,
  );
  assertMatch(
    gate,
    /for test_file in services\/supabase\/scripts\/\*_test\.ts/,
  );
  assert(
    !gate.includes("audit_ghost_users_test.ts") &&
      !gate.includes("cleanup_ghost_users_test.ts"),
    "Ghost tooling tests must be discovered rather than maintained in a selected list.",
  );
});

Deno.test("Supabase tooling gate covers the isolated DTO and shell graphs", async () => {
  const [gate, dtoContractGate] = await Promise.all([
    Deno.readTextFile(toolingGatePath),
    Deno.readTextFile(dtoContractGatePath),
  ]);

  assertMatch(
    gate,
    /bash services\/supabase\/scripts\/validate_edge_dto_contract\.sh/,
  );
  assertMatch(
    gate,
    /bash services\/supabase\/scripts\/check_secret_shaped_literals\.sh/,
  );
  assertMatch(
    dtoContractGate,
    /--config services\/supabase\/scripts\/validate_edge_dtos\.deno\.json[\s\S]*services\/supabase\/scripts\/validate_edge_dtos_test\.ts/,
  );
  assertMatch(
    dtoContractGate,
    /dto_validator_read_allowlist="apps\/ios"/,
  );
  assertMatch(
    dtoContractGate,
    /services\/supabase\/functions\/_shared\/identify\/contract_test\.ts/,
  );
  assertMatch(
    gate,
    /shell_sources=\(services\/supabase\/scripts\/\*\.sh\)/,
  );
  assertMatch(
    gate,
    /shell_tests=\(services\/supabase\/scripts\/\*_test\.sh\)/,
  );
  assertMatch(
    gate,
    /--allow-read=services\/supabase,\.github\/workflows,\.github\/dependabot\.yml,Makefile,README\.md,CHANGELOG\.md,docs,apps,scripts\/check-ios-release-prep\.sh,scripts\/validate-ios-archive\.sh/,
  );
  assertMatch(gate, /--allow-run=bash/);
});

Deno.test("migration contract gate discovers tests for local and deploy validation", async () => {
  const [gate, workflow, makefile] = await Promise.all([
    Deno.readTextFile(migrationContractGatePath),
    Deno.readTextFile(deployWorkflowPath),
    Deno.readTextFile(makefilePath),
  ]);
  const migrationContractTests: string[] = [];
  const testsDirectory = new URL("../functions/_tests/", scriptsDirectory);

  for await (const entry of Deno.readDir(testsDirectory)) {
    if (
      entry.isFile &&
      (entry.name.includes("Migration") ||
        entry.name.startsWith("migration")) &&
      entry.name.endsWith(".test.ts")
    ) {
      migrationContractTests.push(entry.name);
    }
  }

  assert(
    migrationContractTests.length > 0,
    "The migration contract suite must not be empty.",
  );
  assertMatch(gate, /functions\/_tests\/\*Migration\*\.test\.ts/);
  assertMatch(gate, /functions\/_tests\/migration\*\.test\.ts/);
  assertMatch(gate, /--allow-read=services\/supabase/);
  for (const testFile of migrationContractTests) {
    assert(
      !gate.includes(testFile),
      `${testFile} must be discovered rather than explicitly selected.`,
    );
  }
  assertMatch(
    workflow,
    /run: bash supabase\/scripts\/validate_migration_contracts\.sh/,
  );
  assertMatch(
    makefile,
    /validate-supabase-migrations:[\s\S]*bash services\/supabase\/scripts\/validate_migration_contracts\.sh/,
  );
});

Deno.test("focused DwC-A tests can read every transitive contract root", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);
  const stepStart = workflow.indexOf(
    "- name: Test Darwin Core export boundary",
  );
  const stepEnd = workflow.indexOf(
    "- name: Test production workflow security",
    stepStart,
  );

  assert(
    stepStart >= 0 && stepEnd > stepStart,
    "The focused DwC-A workflow step must exist before its permission contract can be checked.",
  );
  const step = workflow.slice(stepStart, stepEnd);
  assertMatch(
    step,
    /--allow-read=[^\n]*supabase\/tests/,
  );
  assertMatch(
    step,
    /--allow-read=[^\n]*\.\.\/apps\/ios/,
  );
  assertMatch(
    step,
    /dwcaDownloadAndScanFinalizationMigrationContract\.test\.ts/,
  );
});

Deno.test("focused species stats tests can read their catalog contract", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);
  const stepStart = workflow.indexOf(
    "- name: Test public species observation stats boundary",
  );
  const stepEnd = workflow.indexOf(
    "- name: Validate authoritative AI quota coverage",
    stepStart,
  );

  assert(
    stepStart >= 0 && stepEnd > stepStart,
    "The focused species stats workflow step must exist before its permission contract can be checked.",
  );
  const step = workflow.slice(stepStart, stepEnd);
  assertMatch(
    step,
    /--allow-read=[^\n]*supabase\/tests\/species_observation_stats_security\.sql/,
  );
  assertMatch(
    step,
    /speciesObservationStatsMigrationContract\.test\.ts/,
  );
});

Deno.test("GitHub Actions SHA pins receive weekly dependency updates", async () => {
  const dependabot = await Deno.readTextFile(dependabotPath);

  assertMatch(dependabot, /package-ecosystem: "github-actions"/);
  assertMatch(dependabot, /directory: "\/"/);
  assertMatch(dependabot, /interval: "weekly"/);
});

Deno.test("database catalog gate discovers every SQL fixture", async () => {
  const [gate, cliVersionGate, workflow, makefile] = await Promise.all([
    Deno.readTextFile(databaseCatalogGatePath),
    Deno.readTextFile(supabaseCliVersionGatePath),
    Deno.readTextFile(deployWorkflowPath),
    Deno.readTextFile(makefilePath),
  ]);
  const databaseTests: string[] = [];
  const databaseTestsDirectory = new URL(
    "../tests/",
    scriptsDirectory,
  );
  for await (const entry of Deno.readDir(databaseTestsDirectory)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      databaseTests.push(entry.name);
    }
  }

  assert(
    databaseTests.length > 0,
    "The database catalog suite must not be empty.",
  );
  assertMatch(
    gate,
    /catalog_tests=\(services\/supabase\/tests\/\*\.sql\)/,
  );
  assertMatch(
    gate,
    /if \[ "\$\{#catalog_tests\[@\]\}" -eq 0 \]/,
  );
  assertMatch(gate, /SUPABASE_TELEMETRY_DISABLED/);
  assertMatch(
    gate,
    /bash "\$catalog_script_dir\/require_supabase_cli_version\.sh"/,
  );
  assertMatch(
    cliVersionGate,
    /required_supabase_cli_version="2\.109\.1"/,
  );
  assertMatch(
    workflow,
    /version: 2\.109\.1[\s\S]*run: bash supabase\/scripts\/require_supabase_cli_version\.sh/,
  );
  assertMatch(
    gate,
    /\^Files=\$\{expected_file_count\}, Tests=\[1-9\]\[0-9\]\*,/,
  );
  assertMatch(gate, /\^Result: PASS/);
  for (const testFile of databaseTests) {
    assert(
      !gate.includes(testFile),
      `${testFile} must be discovered rather than explicitly selected.`,
    );
  }
  assertMatch(
    workflow,
    /run: bash supabase\/scripts\/test_database_catalogs\.sh/,
  );
  assert(
    !workflow.includes("supabase test db --local"),
    "The deploy workflow must delegate catalog discovery to the shared gate.",
  );
  assertMatch(
    makefile,
    /test-supabase-privileged-routines:[\s\S]*bash services\/supabase\/scripts\/require_supabase_cli_version\.sh[\s\S]*bash services\/supabase\/scripts\/test_database_catalogs\.sh/,
  );
  assertMatch(
    makefile,
    /db-push:[\s\S]*bash services\/supabase\/scripts\/require_supabase_cli_version\.sh/,
  );
  assertMatch(
    makefile,
    /functions-deploy:[\s\S]*bash services\/supabase\/scripts\/require_supabase_cli_version\.sh/,
  );
  assert(
    !makefile.includes("services/supabase/tests/account_deletion_security.sql"),
    "The local make target must not maintain a selected catalog list.",
  );
});

Deno.test("iOS project guardrail runs the DTO contract gate for all app sources", async () => {
  const workflow = await Deno.readTextFile(iosProjectGuardrailPath);

  assertMatch(workflow, /- "apps\/ios\/\*\*"/);
  assertMatch(
    workflow,
    /- "services\/supabase\/functions\/_shared\/identify\/contract\.ts"/,
  );
  assertMatch(
    workflow,
    /- "services\/supabase\/functions\/_shared\/identify\/schema\.ts"/,
  );
  assertMatch(
    workflow,
    /uses: denoland\/setup-deno@[0-9a-f]{40}/,
  );
  assertMatch(
    workflow,
    /run: bash services\/supabase\/scripts\/validate_edge_dto_contract\.sh/,
  );
  assertEquals(
    [...workflow.matchAll(/- "scripts\/validate-ios-exported-ipa[.]sh"/g)]
      .length,
    2,
    "Pull-request and main-push project guardrails must both cover the exported-IPA validator.",
  );
});

Deno.test("production deploy plans every runtime change since the last successful release", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);

  for (
    const requiredFragment of [
      "fetch-depth: 0",
      "actions: read",
      "actions/workflows/deploy.yml/runs?branch=main&status=success&per_page=1",
      'git merge-base --is-ancestor "$last_success_sha" "$HEAD_SHA"',
      "Planning from last successful production deploy: $last_success_sha",
      '--base "$last_success_sha"',
      '--head "$HEAD_SHA"',
      "Unable to resolve a safe successful deploy baseline; planning a full deployment.",
    ]
  ) {
    assert(
      workflow.includes(requiredFragment),
      `Cumulative production deployment contract is missing: ${requiredFragment}`,
    );
  }

  const planIndex = workflow.indexOf(
    "- name: Plan affected Edge Function deployment",
  );
  const planEndIndex = workflow.indexOf(
    "- name: Prepare database connection URL",
    planIndex,
  );
  const databasePushIndex = workflow.indexOf(
    "- name: Push Database Migrations",
  );
  assert(
    planIndex >= 0 &&
      planEndIndex > planIndex &&
      databasePushIndex > planIndex,
    "The cumulative function plan must be resolved before production migration begins.",
  );
  const planStep = workflow.slice(planIndex, planEndIndex);
  for (
    const requiredTransportBound of [
      "--connect-timeout 10",
      "--max-time 30",
      "--max-filesize 1048576",
      "--retry 3",
      "--retry-all-errors",
      "--retry-delay 2",
    ]
  ) {
    assert(
      planStep.includes(requiredTransportBound),
      `Production deploy baseline lookup is missing: ${requiredTransportBound}`,
    );
  }

  const fullDeployFallbacks =
    workflow.match(/--all > "\$plan_file"/g)?.length ?? 0;
  assert(
    fullDeployFallbacks >= 2,
    "Manual dispatch and an unsafe or unavailable baseline must both select the full fleet.",
  );
});

Deno.test("production deploy fences the separate scan-recovery migration transactions", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);

  for (
    const requiredFragment of [
      "recovery_predeploy_required=false",
      "20260729173000_recover_media_abandoned_owned_scans.sql",
      "20260729200000_harden_media_abandoned_scan_recovery_proof.sql",
      'echo "recovery_predeploy_required=$recovery_predeploy_required" >> "$GITHUB_OUTPUT"',
      "if: steps.function-plan.outputs.recovery_predeploy_required == 'true'",
    ]
  ) {
    assert(
      workflow.includes(requiredFragment),
      `Recovery migration transaction fence is missing: ${requiredFragment}`,
    );
  }

  const enabledBranches =
    workflow.match(/recovery_predeploy_required=true/g)?.length ?? 0;
  assert(
    enabledBranches >= 3,
    "Manual, migration-diff, and unsafe-baseline paths must all predeploy the fail-closed consumers.",
  );

  const planIndex = workflow.indexOf(
    "- name: Plan affected Edge Function deployment",
  );
  const connectionIndex = workflow.indexOf(
    "- name: Prepare database connection URL",
  );
  const predeployIndex = workflow.indexOf(
    "- name: Deploy fail-closed recovery consumers before compatibility migrations",
  );
  const databasePushIndex = workflow.indexOf(
    "- name: Push Database Migrations",
  );
  const finalDeployIndex = workflow.indexOf(
    "- name: Deploy affected Edge Functions",
  );
  assert(
    planIndex >= 0 &&
      connectionIndex > planIndex &&
      predeployIndex > connectionIndex &&
      databasePushIndex > predeployIndex &&
      finalDeployIndex > databasePushIndex,
    "Fail-closed recovery consumers must deploy after planning and before either migration transaction; the cumulative exact-SHA plan deploys afterward.",
  );

  const predeployEnd = workflow.indexOf(
    "\n      - name:",
    predeployIndex + 1,
  );
  assert(predeployEnd > predeployIndex);
  const predeployBlock = workflow.slice(predeployIndex, predeployEnd);
  for (
    const functionName of [
      "generate-upload-urls",
      "check-scan-status",
      "share-scan-to-explore",
    ]
  ) {
    assert(
      predeployBlock.includes(functionName),
      `Recovery predeploy is missing ${functionName}.`,
    );
  }
  assertMatch(
    predeployBlock,
    /deploy_function_batches\.sh[\s\S]*"\$pre_migration_plan"[\s\S]*"\$PROJECT_ID"/,
  );
  assert(
    !predeployBlock.includes("identify-multimodal"),
    "The structured-proof producer is not compatible until its schema migration commits.",
  );
  assert(
    !predeployBlock.includes("request-community-identification"),
    "Community identification imports Explore publication helpers but does not accept recovery_scan or invoke owner-row recovery; it belongs only in the final cumulative deployment.",
  );
});

Deno.test("production deploy reports aggregate Explore publication health", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);
  const synchronizeIndex = workflow.indexOf(
    "Synchronize active server API key to Edge fallback",
  );
  const digestVerificationIndex = workflow.indexOf(
    "verify_edge_secret_digest.ts",
  );
  const functionDeployIndex = workflow.indexOf(
    "Deploy affected Edge Functions",
  );

  assert(synchronizeIndex >= 0);
  assert(digestVerificationIndex > synchronizeIndex);
  assert(functionDeployIndex > digestVerificationIndex);
  assertMatch(
    workflow,
    /supabase secrets list[\s\S]*--output json[\s\S]*--allow-env=MERIAN_SUPABASE_SERVER_API_KEY[\s\S]*verify_edge_secret_digest\.ts[\s\S]*--secret-name MERIAN_SUPABASE_SERVER_API_KEY/,
  );

  assertMatch(
    workflow,
    /\/rest\/v1\/rpc\/get_explore_publication_health_summary/,
  );
  assertMatch(
    workflow,
    /server_headers=\([\s\S]*apikey: \$\{SUPABASE_SERVER_API_KEY\}[\s\S]*if \[\[ "\$SUPABASE_SERVER_API_KEY" != sb_secret_\* \]\][\s\S]*Authorization: Bearer \$\{SUPABASE_SERVER_API_KEY\}/,
  );
  assert(
    !workflow.includes("x-supabase-server-key"),
    "Internal service calls must use Supabase's standard apikey transport.",
  );
  assertMatch(
    workflow,
    /post_server_json\(\)[\s\S]*"\$\{server_headers\[@\]\}"/,
  );
  assertMatch(
    workflow,
    /Response body withheld because internal endpoints may contain sensitive operational data/,
  );
  assert(
    !workflow.includes('cat "$smoke_response_file" >&2'),
    "Failed internal smoke responses must not be copied into Actions logs.",
  );
  assertMatch(
    workflow,
    /publication_health_response[\s\S]*post_server_json[\s\S]*get_explore_publication_health_summary/,
  );
  assertMatch(
    workflow,
    /dwca_cleanup_response[\s\S]*post_server_json[\s\S]*reconcile-dwca-archive-cleanup[\s\S]*health_status == "healthy"[\s\S]*health_status == "warning"/,
  );
  assertMatch(
    workflow,
    /publication_health_response[\s\S]*affected_author_count[\s\S]*missing_media_item_count/,
  );
  assertMatch(
    workflow,
    /owned_incidents_response[\s\S]*post_server_json[\s\S]*get_owned_explore_media_incidents/,
  );
  assertMatch(workflow, /--connect-timeout 10[\s\S]*--max-time 60/);
});

Deno.test("production deploy proves critical scan RPC readiness without mutation", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);

  for (
    const requiredFragment of [
      "probe_server_rpc_validation_boundary()",
      'local endpoint="/rest/v1/rpc/${rpc_name}"',
      '.code == "22023" and .message == $expected_message',
      '"ensure_scan_user_profile"',
      '"scan_user_profile_invalid_user"',
      '"publish_scan_to_explore_atomically"',
      '"Explore media count is outside the supported range"',
      '"request_community_identification_atomically"',
      '"Community request identifiers are required"',
      '"recover_missing_owned_scan"',
      '"invalid_scan_recovery"',
      '"get_media_abandoned_scan_recovery_proofs"',
      '"invalid_media_abandoned_recovery_proof_request"',
      '"reserve_field_chat_send"',
      '"field_chat_invalid_request"',
      '"recover_stale_field_chat_quota"',
      '"field_chat_invalid_recovery_request"',
      "critical_service_rpc_names=(",
      "critical_service_rpc_payloads=(",
      "A public Supabase API credential unexpectedly reached the service-only",
      "Data API schema cache, routine grant, and database logs",
      "response bodies and request identifiers are intentionally withheld",
    ]
  ) {
    assert(
      workflow.includes(requiredFragment),
      `Critical production RPC smoke contract is missing: ${requiredFragment}`,
    );
  }

  for (
    const criticalRoute of [
      "generate-upload-urls",
      "identify-multimodal",
      "check-scan-status",
      "share-scan-to-explore",
      "get-scan-explore-share-state",
      "get-explore-composer-media",
      "get-explore-media-incidents",
      "insight-chat",
      "explore-post-chat",
      "request-community-identification",
      "delete-scan",
    ]
  ) {
    assert(
      workflow.includes(`            ${criticalRoute}\n`),
      `Explicit critical-route smoke is missing: ${criticalRoute}`,
    );
  }

  const rpcProbeIndex = workflow.indexOf(
    "probe_server_rpc_validation_boundary \\",
  );
  const publicDenialIndex = workflow.indexOf(
    "critical_service_rpc_names=(",
  );
  const credentialedBusinessSmokeIndex = workflow.indexOf(
    'status_response="$(',
  );
  assert(
    rpcProbeIndex >= 0 &&
      publicDenialIndex > rpcProbeIndex &&
      credentialedBusinessSmokeIndex > publicDenialIndex,
    "No-write RPC readiness and public-denial probes must precede credentialed production business smokes.",
  );
  const productionSmokeIndex = workflow.indexOf(
    "- name: Smoke test production backend endpoints",
  );
  assert(
    productionSmokeIndex >= 0,
    "Production smoke step must remain present.",
  );
  const productionSmoke = workflow.slice(productionSmokeIndex);
  const smokeCurlCount = productionSmoke.match(/curl -sS/g)?.length ?? 0;
  const boundedSmokeCurlCount =
    productionSmoke.match(/--max-filesize 1048576/g)?.length ?? 0;
  assertEquals(smokeCurlCount, 8);
  assertEquals(
    boundedSmokeCurlCount,
    smokeCurlCount,
    "Every production smoke response must have a fixed download-size ceiling.",
  );
  assert(
    !workflow.includes('cat "$rpc_validation_response_file"'),
    "Critical RPC validation responses must never be copied into Actions logs.",
  );
});
