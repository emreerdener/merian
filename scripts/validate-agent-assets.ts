import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const projectSkills = [
  "merian-api-contracts",
  "merian-ios",
  "merian-release",
  "merian-supabase",
  "merian-swiftdata-migrations",
  "merian-web-admin",
] as const;

const projectAgents = {
  merian_contract_auditor: {
    model: "gpt-5.6-terra",
    effort: "high",
  },
  merian_explorer: { model: "gpt-5.6-terra", effort: "medium" },
  merian_reviewer: { model: "gpt-5.6", effort: "high" },
} as const;

const suites = new Set([
  "all",
  "ios",
  "swiftdata",
  "supabase",
  "api-contracts",
  "web-admin",
  "release",
  "agents",
]);

const failures: string[] = [];

function fail(message: string): void {
  failures.push(message);
}

function absolute(relativePath: string): string {
  return join(repositoryRoot, relativePath);
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.lstat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function read(relativePath: string): Promise<string> {
  try {
    return await Deno.readTextFile(absolute(relativePath));
  } catch (error) {
    fail(`${relativePath}: cannot read (${String(error)})`);
    return "";
  }
}

async function directoryNames(relativePath: string): Promise<string[]> {
  try {
    const names: string[] = [];
    for await (const entry of Deno.readDir(absolute(relativePath))) {
      if (entry.isDirectory || entry.isSymlink) names.push(entry.name);
    }
    return names.sort();
  } catch (error) {
    fail(`${relativePath}: cannot enumerate (${String(error)})`);
    return [];
  }
}

async function entryNames(relativePath: string): Promise<string[]> {
  try {
    return (await Array.fromAsync(Deno.readDir(absolute(relativePath))))
      .map((entry) => entry.name)
      .sort();
  } catch (error) {
    fail(`${relativePath}: cannot enumerate entries (${String(error)})`);
    return [];
  }
}

async function markdownFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  async function walk(current: string): Promise<void> {
    for await (const entry of Deno.readDir(current)) {
      const path = join(current, entry.name);
      if (entry.isDirectory) await walk(path);
      if (entry.isFile && entry.name.endsWith(".md")) files.push(path);
    }
  }
  try {
    await walk(root);
  } catch (error) {
    fail(
      `${relative(repositoryRoot, root)}: cannot scan Markdown (${
        String(error)
      })`,
    );
  }
  return files.sort();
}

function parseFrontmatter(
  source: string,
  relativePath: string,
): Record<string, string> {
  const match = source.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) {
    fail(`${relativePath}: missing leading YAML frontmatter`);
    return {};
  }

  const values: Record<string, string> = {};
  for (const line of match[1].split("\n")) {
    if (!line.trim()) continue;
    const field = line.match(/^([a-z][a-z0-9_-]*):\s*(.+)$/i);
    if (!field) {
      fail(
        `${relativePath}: unsupported frontmatter line ${JSON.stringify(line)}`,
      );
      continue;
    }
    if (field[1] in values) {
      fail(`${relativePath}: duplicate ${field[1]} field`);
    }
    const raw = field[2].trim();
    values[field[1]] = raw.startsWith('"') && raw.endsWith('"')
      ? raw.slice(1, -1)
      : raw;
  }
  const keys = Object.keys(values);
  if (keys.join(",") !== "name,description") {
    fail(
      `${relativePath}: frontmatter must contain only name then description`,
    );
  }
  return values;
}

function parseScalar(raw: string): string | number | boolean {
  if (/^"(?:[^"\\]|\\.)*"$/.test(raw)) return JSON.parse(raw);
  if (/^-?\d+$/.test(raw)) return Number(raw);
  if (raw === "true" || raw === "false") return raw === "true";
  throw new Error(`unsupported TOML scalar ${JSON.stringify(raw)}`);
}

function parseSimpleToml(
  source: string,
  relativePath: string,
): Record<string, string | number | boolean> {
  const result: Record<string, string | number | boolean> = {};
  const lines = source.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const trimmed = lines[index].trim();
    if (!trimmed || trimmed.startsWith("#") || trimmed.startsWith("[")) {
      continue;
    }
    const assignment = trimmed.match(/^([A-Za-z0-9_-]+)\s*=\s*(.*)$/);
    if (!assignment) {
      fail(`${relativePath}:${index + 1}: unsupported TOML syntax`);
      continue;
    }
    const key = assignment[1];
    if (key in result) fail(`${relativePath}: duplicate TOML key ${key}`);
    if (assignment[2] === '"""') {
      const value: string[] = [];
      let closed = false;
      for (index += 1; index < lines.length; index += 1) {
        if (lines[index].trim() === '"""') {
          closed = true;
          break;
        }
        value.push(lines[index]);
      }
      if (!closed) fail(`${relativePath}: unterminated TOML multiline string`);
      result[key] = value.join("\n");
      continue;
    }
    try {
      result[key] = parseScalar(assignment[2]);
    } catch (error) {
      fail(`${relativePath}:${index + 1}: ${String(error)}`);
    }
  }
  return result;
}

function tomlSection(source: string, section: string): string | undefined {
  const escaped = section.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return source.match(
    new RegExp(`(?:^|\\n)\\[${escaped}\\]\\n([\\s\\S]*?)(?=\\n\\[|$)`),
  )?.[1];
}

async function validateMarkdownLinks(relativePath: string): Promise<void> {
  const source = await read(relativePath);
  for (const match of source.matchAll(/!?\[[^\]]*]\(([^)\r\n]+)\)/g)) {
    let destination = match[1].trim().split(/\s+["']/u, 1)[0];
    destination = destination.split("#", 1)[0];
    if (destination.startsWith("<") && destination.endsWith(">")) {
      destination = destination.slice(1, -1);
    }
    if (
      !destination || destination.startsWith("/") ||
      /^[a-z][a-z0-9+.-]*:/i.test(destination)
    ) continue;
    const target = resolve(
      dirname(absolute(relativePath)),
      decodeURIComponent(destination),
    );
    if (!(await exists(target))) {
      fail(`${relativePath}: unresolved local link ${destination}`);
    }
  }
}

async function validateSkills(): Promise<void> {
  const discovered = (await directoryNames("skills"))
    .filter((name) => name.startsWith("merian-"));
  if (JSON.stringify(discovered) !== JSON.stringify([...projectSkills])) {
    fail(
      `skills/: expected exactly ${projectSkills.join(", ")}; found ${
        discovered.join(", ")
      }`,
    );
  }

  const seenNames = new Set<string>();
  for (const skill of projectSkills) {
    const skillPath = `skills/${skill}/SKILL.md`;
    const source = await read(skillPath);
    const frontmatter = parseFrontmatter(source, skillPath);
    if (frontmatter.name !== skill) fail(`${skillPath}: name must be ${skill}`);
    if (seenNames.has(frontmatter.name)) {
      fail(`${skillPath}: duplicate skill name`);
    }
    seenNames.add(frontmatter.name);
    if ((frontmatter.description ?? "").length < 80) {
      fail(`${skillPath}: description is too short to route reliably`);
    }
    if (!/\bUse\b/.test(frontmatter.description ?? "")) {
      fail(`${skillPath}: description must state when to use the skill`);
    }
    if (source.includes("TODO")) fail(`${skillPath}: contains TODO text`);
    if (source.split("\n").length > 500) {
      fail(`${skillPath}: exceeds 500 lines`);
    }

    const metadataPath = `skills/${skill}/agents/openai.yaml`;
    const metadata = await read(metadataPath);
    const display = metadata.match(/^\s{2}display_name:\s*"([^"]+)"$/m)?.[1];
    const short = metadata.match(/^\s{2}short_description:\s*"([^"]+)"$/m)?.[1];
    const prompt = metadata.match(/^\s{2}default_prompt:\s*"([^"]+)"$/m)?.[1];
    if (!display) fail(`${metadataPath}: missing quoted display_name`);
    if (!short || short.length < 25 || short.length > 64) {
      fail(`${metadataPath}: short_description must be 25-64 characters`);
    }
    if (!prompt?.includes(`$${skill}`)) {
      fail(`${metadataPath}: default_prompt must explicitly invoke $${skill}`);
    }
    const implicitDisabled =
      /policy:\n\s{2}allow_implicit_invocation:\s*false\s*$/m
        .test(metadata);
    if (skill === "merian-release" && !implicitDisabled) {
      fail(`${metadataPath}: release must disable implicit invocation`);
    }
    if (skill !== "merian-release" && implicitDisabled) {
      fail(`${metadataPath}: only release may disable implicit invocation`);
    }

    const referencesRoot = absolute(`skills/${skill}/references`);
    if (await exists(referencesRoot)) {
      for await (const entry of Deno.readDir(referencesRoot)) {
        if (entry.isDirectory) {
          fail(
            `skills/${skill}/references: nested reference directories are not allowed`,
          );
        }
        if (entry.isFile && entry.name.endsWith(".md")) {
          if (!source.includes(`references/${entry.name}`)) {
            fail(`${skillPath}: does not route reference ${entry.name}`);
          }
        }
      }
    }

    for (const path of await markdownFiles(absolute(`skills/${skill}`))) {
      await validateMarkdownLinks(relative(repositoryRoot, path));
    }
  }
}

async function validateDiscoveryLinks(): Promise<void> {
  const discoveryRoot = ".agents/skills";
  const names = await entryNames(discoveryRoot);
  if (JSON.stringify(names) !== JSON.stringify([...projectSkills])) {
    fail(
      `${discoveryRoot}: expected exactly ${projectSkills.join(", ")}; found ${
        names.join(", ")
      }`,
    );
  }
  for (const skill of projectSkills) {
    const link = absolute(`${discoveryRoot}/${skill}`);
    try {
      const stat = await Deno.lstat(link);
      if (!stat.isSymlink) {
        fail(`${discoveryRoot}/${skill}: must be a symlink`);
        continue;
      }
      const target = await Deno.realPath(link);
      const canonical = await Deno.realPath(absolute(`skills/${skill}`));
      if (target !== canonical) {
        fail(
          `${discoveryRoot}/${skill}: resolves to ${target}, expected ${canonical}`,
        );
      }
      if (target.startsWith(`${absolute(discoveryRoot)}/`)) {
        fail(`${discoveryRoot}/${skill}: cyclic discovery target`);
      }
    } catch (error) {
      fail(
        `${discoveryRoot}/${skill}: unresolved discovery link (${
          String(error)
        })`,
      );
    }
  }
}

async function validateAgents(): Promise<void> {
  const configPath = ".codex/config.toml";
  const config = await read(configPath);
  const agentsSection = tomlSection(config, "agents");
  if (!agentsSection) {
    fail(`${configPath}: missing [agents] section`);
  } else {
    const values = parseSimpleToml(agentsSection, `${configPath} [agents]`);
    const expected = {
      enabled: true,
      max_concurrent_threads_per_session: 3,
      default_subagent_model: "gpt-5.6-terra",
      default_subagent_reasoning_effort: "medium",
    };
    for (const [key, value] of Object.entries(expected)) {
      if (values[key] !== value) {
        fail(
          `${configPath}: [agents].${key} must equal ${JSON.stringify(value)}`,
        );
      }
    }
  }

  const agentFiles = await entryNames(".codex/agents");
  const expectedFiles = Object.keys(projectAgents).map((name) => `${name}.toml`)
    .sort();
  if (JSON.stringify(agentFiles) !== JSON.stringify(expectedFiles)) {
    fail(
      `.codex/agents: expected ${expectedFiles.join(", ")}; found ${
        agentFiles.join(", ")
      }`,
    );
  }
  for (const [name, expected] of Object.entries(projectAgents)) {
    const relativePath = `.codex/agents/${name}.toml`;
    if (!(await exists(absolute(relativePath)))) {
      fail(`${relativePath}: missing custom agent file`);
      continue;
    }
    const source = await read(relativePath);
    const values = parseSimpleToml(source, relativePath);
    const requiredKeys = [
      "name",
      "description",
      "model",
      "model_reasoning_effort",
      "sandbox_mode",
      "developer_instructions",
    ];
    for (const key of requiredKeys) {
      if (!(key in values)) fail(`${relativePath}: missing ${key}`);
    }
    if (values.name !== name) fail(`${relativePath}: name must be ${name}`);
    if (values.model !== expected.model) {
      fail(`${relativePath}: unexpected model`);
    }
    if (values.model_reasoning_effort !== expected.effort) {
      fail(`${relativePath}: unexpected reasoning effort`);
    }
    if (values.sandbox_mode !== "read-only") {
      fail(`${relativePath}: sandbox_mode must be read-only`);
    }
    const instructions = String(values.developer_instructions ?? "");
    if (!/Do not edit|Do not make code changes/i.test(instructions)) {
      fail(`${relativePath}: instructions must prohibit writes`);
    }
    if (
      /memory|workspace-write|danger-full-access/i.test(
        source,
      )
    ) {
      fail(
        `${relativePath}: contains persistent-memory or writable-sandbox configuration`,
      );
    }
  }
}

async function validateUniversalInstructions(): Promise<void> {
  const source = await read("AGENTS.md");
  const bytes = new TextEncoder().encode(source).length;
  if (bytes >= 8 * 1024) {
    fail(`AGENTS.md: ${bytes} bytes exceeds the <8 KiB budget`);
  }
  for (
    const heading of [
      "Worktree and editing safety",
      "Deployment authorization",
      "Documentation synchronization",
      "Supabase skill order",
      "Verification",
      "Read-only subagent delegation",
    ]
  ) {
    if (!source.includes(`## ${heading}`)) {
      fail(`AGENTS.md: missing ${heading}`);
    }
  }
  if (/CLAUDE\.md|\.claude\//i.test(source)) {
    fail("AGENTS.md: references removed Claude configuration");
  }

  for (
    const path of [
      "CLAUDE.md",
      ".claude",
      ".agents/CLAUDE.md",
      ".agents/.claude/settings.local.json",
    ]
  ) {
    if (await exists(absolute(path))) {
      fail(`${path}: active Claude configuration remains`);
    }
  }
  const ignore = await read(".gitignore");
  if (!ignore.includes(".agents/.claude/settings.local.legacy-*.json")) {
    fail(".gitignore: missing legacy Claude settings backup pattern");
  }
}

async function validateLegacyPointers(): Promise<void> {
  const pointers: Record<string, string> = {
    ".agents/workflows/schema_update.md": "$merian-swiftdata-migrations",
    "apps/ios/.agents/workflows/schema_update.md":
      "$merian-swiftdata-migrations",
    "apps/ios/.agents/workflows/mock_camera_inference.md": "$merian-ios",
    "apps/ios/.agents/workflows/verify_api_contracts.md":
      "$merian-api-contracts",
    "apps/ios/.agents/workflows/deploy_edge_functions.md": "$merian-release",
    "apps/ios/.agents/workflows/deploy_testflight.md": "$merian-release",
    "apps/ios/.agents/workflows/revenuecat_entitlements.md": "$merian-release",
  };
  const forbidden = [
    "UIImage(named:",
    "jpegData(",
    "processSimulatedImage",
    "manually append static coordinates",
    "safe to deploy",
    "supabase functions deploy",
    "CONSENT-",
  ];
  for (const [path, skill] of Object.entries(pointers)) {
    const source = await read(path);
    if (!source.includes(skill)) fail(`${path}: must point to ${skill}`);
    if (new TextEncoder().encode(source).length > 1800) {
      fail(`${path}: compatibility pointer is too long`);
    }
    for (const fragment of forbidden) {
      if (source.toLowerCase().includes(fragment.toLowerCase())) {
        fail(`${path}: contains stale or unsafe instruction ${fragment}`);
      }
    }
    await validateMarkdownLinks(path);
  }
}

type EvalCase = {
  id?: unknown;
  suite?: unknown;
  prompt?: unknown;
  expectedSkills?: unknown;
  expectedAgent?: unknown;
  expectedActions?: unknown;
  requiredSafetyFlags?: unknown;
  forbiddenPatterns?: unknown;
  coverage?: unknown;
};

async function validateEvaluationManifest(): Promise<void> {
  const manifestPath = "skills/evals/agent-quality.json";
  let manifest: { schemaVersion?: unknown; cases?: EvalCase[] } = {};
  try {
    manifest = JSON.parse(await read(manifestPath));
  } catch (error) {
    fail(`${manifestPath}: invalid JSON (${String(error)})`);
    return;
  }
  if (manifest.schemaVersion !== 1) {
    fail(`${manifestPath}: schemaVersion must be 1`);
  }
  if (!Array.isArray(manifest.cases) || manifest.cases.length < 11) {
    fail(`${manifestPath}: must define at least 11 cases`);
    return;
  }
  const ids = new Set<string>();
  const coverage = new Set<string>();
  for (const [index, testCase] of manifest.cases.entries()) {
    const label = `${manifestPath}: case ${index + 1}`;
    if (typeof testCase.id !== "string" || !/^[a-z0-9-]+$/.test(testCase.id)) {
      fail(`${label}: invalid id`);
    } else if (ids.has(testCase.id)) {
      fail(`${label}: duplicate id ${testCase.id}`);
    } else ids.add(testCase.id);
    if (
      typeof testCase.suite !== "string" || testCase.suite === "all" ||
      !suites.has(testCase.suite)
    ) {
      fail(`${label}: invalid suite`);
    }
    if (typeof testCase.prompt !== "string" || testCase.prompt.length < 20) {
      fail(`${label}: prompt is too short`);
    }
    if (!Array.isArray(testCase.expectedSkills)) {
      fail(`${label}: expectedSkills must be an array`);
    } else {
      for (const skill of testCase.expectedSkills) {
        if (!projectSkills.includes(skill)) {
          fail(`${label}: unknown expected skill ${skill}`);
        }
      }
    }
    if (
      testCase.expectedAgent !== null &&
      (typeof testCase.expectedAgent !== "string" ||
        !(testCase.expectedAgent in projectAgents))
    ) fail(`${label}: invalid expectedAgent`);
    for (
      const field of [
        "expectedActions",
        "requiredSafetyFlags",
        "forbiddenPatterns",
      ] as const
    ) {
      const value = testCase[field];
      if (
        !Array.isArray(value) ||
        value.some((entry) => typeof entry !== "string" || !entry)
      ) {
        fail(`${label}: ${field} must be a non-empty-string array`);
      }
    }
    if (!Array.isArray(testCase.coverage)) {
      fail(`${label}: coverage must be an array`);
    } else {for (const tag of testCase.coverage) {
        if (typeof tag === "string") coverage.add(tag);
      }}
  }
  for (
    const required of [
      "implicit-skill-selection",
      "explicit-skill-selection",
      "swiftdata-freeze-order",
      "safe-camera-fixtures",
      "xcodegen-source-of-truth",
      "dto-generate-review-validate",
      "unknown-supabase-read-only",
      "rls-user-service-role",
      "public-admin-boundary",
      "release-authorization",
      "immutable-sha",
      "agent-delegation",
      "no-parallel-writers",
      "documentation-ci-drift",
    ]
  ) {
    if (!coverage.has(required)) {
      fail(`${manifestPath}: missing coverage tag ${required}`);
    }
  }

  try {
    const schema = JSON.parse(
      await read(".github/codex/agent-eval-output.schema.json"),
    );
    if (schema.type !== "object" || schema.additionalProperties !== false) {
      fail(
        ".github/codex/agent-eval-output.schema.json: root must be a closed object",
      );
    }
  } catch (error) {
    fail(`agent eval output schema: invalid JSON (${String(error)})`);
  }
}

async function validateWorkflow(): Promise<void> {
  const path = ".github/workflows/agent-quality.yml";
  const source = await read(path);
  for (const match of source.matchAll(/^\s*uses:\s*([^@\s]+)@([^\s#]+)/gm)) {
    if (!/^[0-9a-f]{40}$/.test(match[2])) {
      fail(`${path}: ${match[1]} must use an immutable 40-character SHA`);
    }
  }
  const requiredFragments = [
    "openai/codex-action@52fe01ec70a42f454c9d2ebd47598f9fd6893d56",
    'codex-version: "0.146.0"',
    'model: "gpt-5.6-terra"',
    'effort: "medium"',
    'permission-profile: ":read-only"',
    "safety-strategy: drop-sudo",
    "codex-args: '[\"--ephemeral\"]'",
    "output-schema-file: .github/codex/agent-eval-output.schema.json",
    "openai-api-key: ${{ secrets.OPENAI_API_KEY }}",
    "name: agent-quality-${{ matrix.suite }}-${{ github.run_id }}-attempt-${{ github.run_attempt }}",
    "continue-on-error: true",
    "make validate-agent-assets",
  ];
  for (const fragment of requiredFragments) {
    if (!source.includes(fragment)) fail(`${path}: missing ${fragment}`);
  }
  if (/^\s*OPENAI_API_KEY\s*:/m.test(source)) {
    fail(
      `${path}: OPENAI_API_KEY must not be a job or step environment variable`,
    );
  }
  for (
    const secret of [
      "SUPABASE_",
      "REVENUECAT_",
      "APPLE_",
      "ASC_",
      "SIGNING_",
      "GEMINI_",
    ]
  ) {
    if (source.includes(`secrets.${secret}`)) {
      fail(`${path}: production secret family ${secret} is forbidden`);
    }
  }
  for (
    const criterion of [
      "14-day",
      "10 full-suite",
      "100%",
      "95%",
      "5%",
      "resets calibration",
    ]
  ) {
    if (!source.includes(criterion)) {
      fail(`${path}: missing calibration criterion ${criterion}`);
    }
  }
}

async function main(): Promise<void> {
  await validateUniversalInstructions();
  await validateSkills();
  await validateDiscoveryLinks();
  await validateAgents();
  await validateLegacyPointers();
  await validateEvaluationManifest();
  await validateWorkflow();

  if (failures.length) {
    for (const failure of failures) console.error(`FAIL: ${failure}`);
    console.error(
      `Agent asset validation failed with ${failures.length} issue(s).`,
    );
    Deno.exit(1);
  }
  console.log(
    `Agent assets valid: ${projectSkills.length} skills, ${
      Object.keys(projectAgents).length
    } read-only agents.`,
  );
}

if (import.meta.main) await main();
