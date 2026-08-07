import {
  assert,
  assertEquals,
  assertMatch,
  assertStringIncludes,
} from "@std/assert";

const repositoryRoot = new URL("../../../", import.meta.url);

function repositoryFile(relativePath: string): URL {
  return new URL(relativePath, repositoryRoot);
}

async function read(relativePath: string): Promise<string> {
  return await Deno.readTextFile(repositoryFile(relativePath));
}

async function unresolvedLocalMarkdownLinks(
  relativePath: string,
): Promise<string[]> {
  const source = await read(relativePath);
  const unresolved: string[] = [];

  for (const match of source.matchAll(/!?\[[^\]]*]\(([^)\r\n]+)\)/g)) {
    const destination = match[1].trim().split("#", 1)[0];
    if (
      !destination ||
      destination.startsWith("/") ||
      /^[a-z][a-z0-9+.-]*:/i.test(destination)
    ) {
      continue;
    }

    try {
      await Deno.stat(
        new URL(decodeURIComponent(destination), repositoryFile(relativePath)),
      );
    } catch {
      unresolved.push(destination);
    }
  }

  return unresolved;
}

Deno.test("Merian Supabase skill has valid discoverable packaging", async () => {
  const [skill, interfaceSource, agentSource] = await Promise.all([
    read("skills/merian-supabase/SKILL.md"),
    read("skills/merian-supabase/agents/openai.yaml"),
    read("AGENTS.md"),
  ]);
  const frontmatter = skill.match(/^---\n([\s\S]*?)\n---\n/);

  assert(frontmatter, "SKILL.md must start with YAML frontmatter.");
  const topLevelKeys = frontmatter[1]
    .split("\n")
    .filter((line) => /^[a-z][a-z0-9_-]*:/i.test(line))
    .map((line) => line.slice(0, line.indexOf(":")));
  assertEquals(topLevelKeys, ["name", "description"]);
  assertStringIncludes(frontmatter[1], "name: merian-supabase");
  assertStringIncludes(interfaceSource, 'display_name: "Merian Supabase"');
  assertStringIncludes(interfaceSource, "$merian-supabase");
  assertStringIncludes(agentSource, "skills/merian-supabase/SKILL.md");
  assertStringIncludes(agentSource, ".agents/CLAUDE.md");
  assert(!skill.includes("TODO"), "The shipped skill must not contain TODOs.");
});

Deno.test("Merian Supabase skill routes every safety-critical surface", async () => {
  const skill = await read("skills/merian-supabase/SKILL.md");
  const normalizedSkill = skill.replace(/\s+/g, " ");

  for (
    const fragment of [
      "Treat an unknown target as hosted and read-only.",
      "Do not treat implementation authorization as deployment authorization.",
      "Never use MCP `execute_sql`",
      "Do not edit an applied historical migration.",
      "services/supabase/scripts/require_supabase_cli_version.sh",
      "references/migrations-and-database.md",
      "references/edge-functions-and-clients.md",
      "references/release-and-operations.md",
    ]
  ) {
    assertStringIncludes(normalizedSkill, fragment);
  }

  assert(
    !/\b2\.\d+\.\d+\b/.test(skill),
    "The core skill must defer to the repository version gate instead of duplicating its pin.",
  );
});

Deno.test("Merian Supabase references preserve current repository contracts", async () => {
  const [config, versionGate, migrations, edge, release] = await Promise.all([
    read("services/supabase/config.toml"),
    read("services/supabase/scripts/require_supabase_cli_version.sh"),
    read("skills/merian-supabase/references/migrations-and-database.md"),
    read("skills/merian-supabase/references/edge-functions-and-clients.md"),
    read("skills/merian-supabase/references/release-and-operations.md"),
  ]);
  const normalizedRelease = release.replace(/\s+/g, " ");

  assertMatch(
    config,
    /\[db\.migrations][\s\S]*?schema_paths\s*=\s*\[\]/,
  );
  assertMatch(
    versionGate,
    /required_supabase_cli_version="\d+\.\d+\.\d+"/,
  );
  assertStringIncludes(migrations, "`schema_paths = []`");
  assertStringIncludes(
    migrations,
    "PostgreSQL reuses `USING` when no separate expression is supplied.",
  );
  assertStringIncludes(migrations, "`internal.require_service_role()`");
  assertStringIncludes(
    migrations,
    "Never impose a blanket `auth.uid()` rule on a service-only worker.",
  );
  assertStringIncludes(edge, "`verify_jwt = false`");
  assertStringIncludes(edge, "functions/_shared/serviceRoleClient.ts");
  assertStringIncludes(normalizedRelease, "Candidate Validation proves");
  assertStringIncludes(
    normalizedRelease,
    "An instruction to implement, test, or prepare a release does not authorize a production mutation.",
  );
});

Deno.test("Merian Supabase skill has no unresolved local Markdown links", async () => {
  const files = [
    "skills/merian-supabase/SKILL.md",
    "skills/merian-supabase/references/migrations-and-database.md",
    "skills/merian-supabase/references/edge-functions-and-clients.md",
    "skills/merian-supabase/references/release-and-operations.md",
  ];

  for (const file of files) {
    assertEquals(
      await unresolvedLocalMarkdownLinks(file),
      [],
      `${file} contains unresolved local Markdown links.`,
    );
  }
});
