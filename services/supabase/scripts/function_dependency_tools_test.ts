import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildAllFunctionGraphs,
  planAffectedFunctions,
} from "./function_dependency_tools.ts";

const graphs = await buildAllFunctionGraphs();

Deno.test("every Edge Function has a discoverable graph", () => {
  assertEquals(graphs.length, 79);
  assert(graphs.every((graph) => graph.files.has(graph.entrypoint)));
});

Deno.test("route-local changes deploy only that route", () => {
  assertEquals(
    planAffectedFunctions([
      "services/supabase/functions/identify-multimodal/index.ts",
    ], graphs),
    ["identify-multimodal"],
  );
});

Deno.test("claims auth changes deploy only its two consumers", () => {
  assertEquals(
    planAffectedFunctions([
      "services/supabase/functions/_shared/claimsAuth.ts",
    ], graphs),
    ["identify-multimodal", "update-scan-context"],
  );
});

Deno.test("documentation and test-only changes do not deploy functions", () => {
  assertEquals(
    planAffectedFunctions([
      "services/supabase/functions/identify-multimodal/README.md",
      "services/supabase/functions/identify-multimodal/index.test.ts",
    ], graphs),
    [],
  );
});

Deno.test("function-specific config changes deploy only that function", () => {
  assertEquals(
    planAffectedFunctions([
      "services/supabase/functions/delete-scan/deno.json",
    ], graphs),
    ["delete-scan"],
  );
});

Deno.test("shared dependency policy changes deploy the complete fleet", () => {
  assertEquals(
    planAffectedFunctions([
      "services/supabase/functions/dependencies.lock",
    ], graphs).length,
    graphs.length,
  );
});

Deno.test("deployment workflow changes deploy the complete fleet", () => {
  assertEquals(
    planAffectedFunctions([".github/workflows/deploy.yml"], graphs).length,
    graphs.length,
  );
});

Deno.test("removed function directories require explicit decommissioning", () => {
  let message = "";
  try {
    planAffectedFunctions([
      "services/supabase/functions/retired-route/index.ts",
    ], graphs);
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  assert(message.includes("explicit reviewed decommission"));
});
