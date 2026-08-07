import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const repositoryRoot = new URL("../../../", import.meta.url);
const userSkillsRoot = new URL("skills/user/", repositoryRoot);

interface SafetyEvalCase {
  id: string;
  skills: string[];
  prompt: string;
  expectedBehaviors: string[];
  forbiddenBehaviors: string[];
}

interface SafetyEvalSuite {
  schemaVersion: number;
  cases: SafetyEvalCase[];
}

function repositoryFile(relativePath: string): URL {
  return new URL(relativePath, repositoryRoot);
}

async function read(relativePath: string): Promise<string> {
  return await Deno.readTextFile(repositoryFile(relativePath));
}

async function markdownFiles(directory: URL): Promise<URL[]> {
  const files: URL[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const child = new URL(
      entry.name + (entry.isDirectory ? "/" : ""),
      directory,
    );
    if (entry.isDirectory) {
      files.push(...await markdownFiles(child));
    } else if (entry.isFile && entry.name.endsWith(".md")) {
      files.push(child);
    }
  }
  return files;
}

async function unresolvedLocalMarkdownLinks(file: URL): Promise<string[]> {
  const source = await Deno.readTextFile(file);
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
      await Deno.stat(new URL(decodeURIComponent(destination), file));
    } catch {
      unresolved.push(destination);
    }
  }
  return unresolved;
}

function frontmatterKeys(source: string): string[] {
  const frontmatter = source.match(/^---\n([\s\S]*?)\n---\n/);
  assert(frontmatter, "SKILL.md must start with YAML frontmatter.");
  return frontmatter[1]
    .split("\n")
    .filter((line) => /^[a-z][a-z0-9_-]*:/i.test(line))
    .map((line) => line.slice(0, line.indexOf(":")));
}

Deno.test("tracked user Supabase skills have current packaging", async () => {
  const skills = ["supabase", "supabase-postgres-best-practices"];

  for (const skillName of skills) {
    const [skill, interfaceSource, license] = await Promise.all([
      read(`skills/user/${skillName}/SKILL.md`),
      read(`skills/user/${skillName}/agents/openai.yaml`),
      read(`skills/user/${skillName}/LICENSE`),
    ]);

    assertEquals(frontmatterKeys(skill), ["name", "description"]);
    assertStringIncludes(skill, `name: ${skillName}`);
    assertStringIncludes(interfaceSource, `$${skillName}`);
    assertStringIncludes(license, "Copyright (c) 2026 Supabase");
    assert(!skill.includes("TODO"));
    assert(
      !(await Array.fromAsync(
        Deno.readDir(repositoryFile(`skills/user/${skillName}/`)),
      )).some((entry) => entry.name === "CHANGELOG.md"),
      `${skillName} must not ship a changelog into agent context resources.`,
    );
  }
});

Deno.test("tracked user Supabase skill preserves target and schema boundaries", async () => {
  const [skill, database, edge, operations] = await Promise.all([
    read("skills/user/supabase/SKILL.md"),
    read("skills/user/supabase/references/database-and-security.md"),
    read("skills/user/supabase/references/edge-auth-and-clients.md"),
    read("skills/user/supabase/references/operations-and-tooling.md"),
  ]);
  const normalized = `${skill}\n${database}\n${edge}\n${operations}`.replace(
    /\s+/g,
    " ",
  );

  for (
    const fragment of [
      "Treat an unresolved target as hosted production and remain read-only.",
      "Separate authorization to implement or test from authorization to deploy",
      "Use direct SQL iteration only against an explicitly identified disposable local database",
      "Do not create a repository schema change by mutating a hosted database",
      "PostgreSQL reuses `USING` when `WITH CHECK` is omitted",
      "Never impose a blanket `auth.uid()` requirement on a service worker.",
      "Never bypass a repository version guard",
      "Treat Data API exposure, object privileges, and RLS as separate layers.",
      "verify_jwt = false",
      "Storage upsert generally needs INSERT, SELECT, and UPDATE access",
      "allowed-MIME limits",
    ]
  ) {
    assertStringIncludes(normalized, fragment);
  }

  assert(
    !/CLI v?\d+\.\d+\.\d+/i.test(normalized),
    "The generic skill must not preserve stale CLI minimum-version claims.",
  );
});

Deno.test("Postgres skill indexes every shipped rule and fail-closes unsafe guidance", async () => {
  const [skill, constraints, rls, rlsPerformance] = await Promise.all([
    read("skills/user/supabase-postgres-best-practices/SKILL.md"),
    read(
      "skills/user/supabase-postgres-best-practices/references/schema-constraints.md",
    ),
    read(
      "skills/user/supabase-postgres-best-practices/references/security-rls-basics.md",
    ),
    read(
      "skills/user/supabase-postgres-best-practices/references/security-rls-performance.md",
    ),
  ]);
  const references = repositoryFile(
    "skills/user/supabase-postgres-best-practices/references/",
  );
  const normalizedConstraints = constraints.replace(/\s+/g, " ");
  const normalizedRls = rls.replace(/\s+/g, " ");
  const normalizedRlsPerformance = rlsPerformance.replace(/\s+/g, " ");

  for await (const entry of Deno.readDir(references)) {
    if (entry.isFile && entry.name.endsWith(".md")) {
      assertStringIncludes(
        skill,
        `references/${entry.name}`,
        `SKILL.md must route to ${entry.name}.`,
      );
    }
  }

  assertStringIncludes(normalizedConstraints, "fail when the catalog differs");
  assertStringIncludes(normalizedConstraints, "fail on any unexpected state");
  assertStringIncludes(
    normalizedRls,
    "PostgreSQL reuses `USING` as `WITH CHECK`",
  );
  assertStringIncludes(
    normalizedRlsPerformance,
    "A blanket `auth.uid()` rule is incorrect",
  );
});

Deno.test("user skill source manifest pins reviewed upstream releases", async () => {
  const manifest = JSON.parse(
    await read("skills/user/manifest.json"),
  ) as {
    schemaVersion: number;
    sourceRepository: string;
    skills: Array<{
      name: string;
      upstreamRelease: string;
      localPatches: string[];
    }>;
  };

  assertEquals(manifest.schemaVersion, 1);
  assertEquals(
    manifest.sourceRepository,
    "https://github.com/supabase/agent-skills",
  );
  assertEquals(
    manifest.skills.map((skill) => [skill.name, skill.upstreamRelease]),
    [
      ["supabase", "supabase-v0.1.6"],
      [
        "supabase-postgres-best-practices",
        "supabase-postgres-best-practices-v1.6.0",
      ],
    ],
  );
  for (const skill of manifest.skills) {
    assert(skill.localPatches.length >= 5);
  }
});

Deno.test("Supabase safety eval suite covers high-risk behavioral branches", async () => {
  const suite = JSON.parse(
    await read("skills/user/evals/supabase-safety.json"),
  ) as SafetyEvalSuite;
  const ids = suite.cases.map((testCase) => testCase.id);

  assertEquals(suite.schemaVersion, 1);
  assert(suite.cases.length >= 12);
  assertEquals(new Set(ids).size, ids.length, "Eval case IDs must be unique.");
  for (
    const required of [
      "unknown-mcp-target",
      "imperative-migration",
      "declarative-schema",
      "production-deploy-not-authorized",
      "update-policy-semantics",
      "service-worker-security-definer",
      "user-security-definer",
      "repository-cli-pin",
      "diagnosis-is-read-only",
      "production-explain",
      "verify-jwt-handler-auth",
      "storage-upsert-boundary",
    ]
  ) {
    assert(ids.includes(required), `Missing safety eval: ${required}`);
  }

  for (const testCase of suite.cases) {
    assert(testCase.prompt.length > 20);
    assert(testCase.skills.length > 0);
    assert(testCase.expectedBehaviors.length >= 2);
    assert(testCase.forbiddenBehaviors.length >= 1);
  }
});

Deno.test("user skill installer is recoverable and duplicate-aware", async () => {
  const installer = await read("skills/user/install.sh");

  assertStringIncludes(installer, ".agents/skills");
  assertStringIncludes(installer, ".codex}/skills");
  assertStringIncludes(installer, "mv --");
  assertStringIncludes(installer, "ln -s --");
  assertStringIncludes(installer, "--apply");
  assertStringIncludes(installer, "must not be the filesystem root");
  assert(!installer.includes("rm -rf"));
  assert(!installer.includes("curl"));
});

Deno.test("tracked user skill Markdown links resolve", async () => {
  for (const file of await markdownFiles(userSkillsRoot)) {
    assertEquals(
      await unresolvedLocalMarkdownLinks(file),
      [],
      `${file.pathname} contains unresolved local Markdown links.`,
    );
  }
});
