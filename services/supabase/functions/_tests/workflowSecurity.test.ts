import {
  assert,
  assertEquals,
  assertMatch,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const workflowsDirectory = new URL(
  "../../../../.github/workflows/",
  import.meta.url,
);
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

Deno.test("only the checklist-writing workflow requests repository write access", async () => {
  const sources = await workflowSources();
  const writers = sources
    .filter(([, source]) => /^[ ]{2}contents: write$/m.test(source))
    .map(([name]) => name);

  assertEquals(writers, ["import-community-taxonomy.yml"]);
});
