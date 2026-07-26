import {
  assert,
  assertMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const scriptsDirectory = new URL("./", import.meta.url);
const toolingGatePath = new URL(
  "test_supabase_tooling.sh",
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
  const gate = await Deno.readTextFile(toolingGatePath);

  assertMatch(
    gate,
    /--config services\/supabase\/scripts\/validate_edge_dtos\.deno\.json[\s\S]*services\/supabase\/scripts\/validate_edge_dtos_test\.ts/,
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
