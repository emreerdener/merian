import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { parseSpeciesModelContentRefreshRequest } from "./db.ts";

Deno.test("refresh species model content - parses defaults and filters", () => {
  const defaultResult = parseSpeciesModelContentRefreshRequest({});
  assertEquals(defaultResult.request?.limit, 12);
  assertEquals(defaultResult.request?.dryRun, false);
  assertEquals(defaultResult.request?.contentGroups, undefined);

  const customResult = parseSpeciesModelContentRefreshRequest({
    limit: 6,
    dry_run: true,
    as_of: "2026-06-22T00:00:00Z",
    content_groups: ["habitat", "lookalikes", "habitat"],
  });

  assertEquals(customResult.request?.limit, 6);
  assertEquals(customResult.request?.dryRun, true);
  assertEquals(customResult.request?.asOf, "2026-06-22T00:00:00.000Z");
  assertEquals(customResult.request?.contentGroups, ["habitat", "lookalikes"]);
});

Deno.test("refresh species model content - rejects invalid inputs", () => {
  assertEquals(parseSpeciesModelContentRefreshRequest({ limit: 51 }), {
    error: "limit must be an integer from 1 to 50.",
    status: 400,
  });
  assertEquals(
    parseSpeciesModelContentRefreshRequest({ content_groups: ["taxonomy"] }),
    {
      error: "Unsupported content group: taxonomy",
      status: 400,
    },
  );
  assertEquals(parseSpeciesModelContentRefreshRequest({ dry_run: "yes" }), {
    error: "dry_run must be a boolean.",
    status: 400,
  });
});
