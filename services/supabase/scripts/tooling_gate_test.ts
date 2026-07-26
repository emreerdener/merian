import {
  assert,
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
const iosProjectGuardrailPath = new URL(
  "../../../.github/workflows/ios-project-guardrails.yml",
  scriptsDirectory,
);
const deployWorkflowPath = new URL(
  "../../../.github/workflows/deploy.yml",
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
});

Deno.test("production deploy reports aggregate Explore publication health", async () => {
  const workflow = await Deno.readTextFile(deployWorkflowPath);

  assertMatch(
    workflow,
    /\/rest\/v1\/rpc\/get_explore_publication_health_summary/,
  );
  assertMatch(
    workflow,
    /server_headers=\([\s\S]*apikey: \$\{SUPABASE_SERVER_API_KEY\}[\s\S]*if \[\[ "\$SUPABASE_SERVER_API_KEY" != sb_secret_\* \]\][\s\S]*Authorization: Bearer \$\{SUPABASE_SERVER_API_KEY\}/,
  );
  assertMatch(
    workflow,
    /post_server_json\(\)[\s\S]*"\$\{server_headers\[@\]\}"/,
  );
  assertMatch(
    workflow,
    /publication_health_response[\s\S]*post_server_json[\s\S]*get_explore_publication_health_summary/,
  );
  assertMatch(
    workflow,
    /publication_health_response[\s\S]*affected_author_count[\s\S]*missing_media_item_count/,
  );
});
