import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { join, relative } from "node:path";
import {
  configuredFunctionNames,
  discoverFunctionEntrypoints,
  repoRoot,
  supabaseRoot,
} from "./function_dependency_tools.ts";

const callerRoots = [
  join(repoRoot, "apps"),
  join(repoRoot, ".github/workflows"),
  join(supabaseRoot, "functions"),
  join(supabaseRoot, "migrations"),
  join(supabaseRoot, "scripts"),
];

const productionSourceExtensions = new Set([
  ".js",
  ".mjs",
  ".sh",
  ".sql",
  ".swift",
  ".ts",
  ".tsx",
  ".yaml",
  ".yml",
]);

const reviewedRetiredCallers = new Map([
  [
    "services/supabase/migrations/00008_auto_purge_domesticated_cron.sql -> auto-purge-domesticated",
    {
      jobName: "auto_purge_domesticated_daily",
      retirementMigration:
        "services/supabase/migrations/20260616130000_disable_free_tier_media_expiration.sql",
    },
  ],
]);

function extension(path: string): string {
  const match = path.match(/(\.[^.\/]+)$/);
  return match?.[1] ?? "";
}

function isProductionCallerSource(path: string): boolean {
  const normalized = path.replaceAll("\\", "/");
  if (!productionSourceExtensions.has(extension(normalized))) return false;
  return !normalized.includes("/node_modules/") &&
    !normalized.includes("/.next/") &&
    !normalized.includes("/_tests/") &&
    !normalized.includes("/MerianTests/") &&
    !normalized.includes("/MerianUITests/") &&
    !/(?:_test|\.test)\.[^.\/]+$/.test(normalized);
}

async function* productionCallerSources(
  directory: string,
): AsyncGenerator<string> {
  for await (const entry of Deno.readDir(directory)) {
    const path = join(directory, entry.name);
    if (entry.isDirectory) {
      if (entry.name === "node_modules" || entry.name === ".next") continue;
      yield* productionCallerSources(path);
    } else if (entry.isFile && isProductionCallerSource(path)) {
      yield path;
    }
  }
}

function literalFunctionNames(source: string): string[] {
  const names = new Set<string>();
  for (
    const pattern of [
      /\bendpointURL\(\s*["']([a-z0-9-]+)["']/g,
      /\bfunctions\.invoke\(\s*["']([a-z0-9-]+)["']/g,
      /\/functions\/v1\/([a-z0-9-]+)/g,
    ]
  ) {
    for (const match of source.matchAll(pattern)) {
      if (match[1]) names.add(match[1]);
    }
  }
  return [...names];
}

Deno.test("every static production Edge Function caller targets a configured entrypoint", async () => {
  const config = await Deno.readTextFile(join(supabaseRoot, "config.toml"));
  const configured = configuredFunctionNames(config);
  const entrypoints = (await discoverFunctionEntrypoints()).map(({ name }) =>
    name
  );
  assertEquals(configured, entrypoints);

  const knownFunctions = new Set(entrypoints);
  const unknownCallers: string[] = [];
  const observedRetiredCallers = new Set<string>();
  const calledFunctions = new Set<string>();
  for (const root of callerRoots) {
    for await (const path of productionCallerSources(root)) {
      const source = await Deno.readTextFile(path);
      for (const functionName of literalFunctionNames(source)) {
        calledFunctions.add(functionName);
        if (!knownFunctions.has(functionName)) {
          const caller = `${relative(repoRoot, path)} -> ${functionName}`;
          const retirement = reviewedRetiredCallers.get(caller);
          if (!retirement) {
            unknownCallers.push(caller);
            continue;
          }

          const retirementSource = await Deno.readTextFile(
            join(repoRoot, retirement.retirementMigration),
          );
          assert(
            retirementSource.includes(
              `cron.unschedule('${retirement.jobName}')`,
            ),
            `${caller} lacks its reviewed retirement evidence.`,
          );
          observedRetiredCallers.add(caller);
        }
      }
    }
  }

  assert(
    unknownCallers.length === 0,
    `Production callers target missing Edge Functions:\n${
      unknownCallers.sort().map((value) => `- ${value}`).join("\n")
    }`,
  );
  assertEquals(
    [...observedRetiredCallers].sort(),
    [...reviewedRetiredCallers.keys()].sort(),
    "Reviewed retired-caller exceptions must remain exact and exercised.",
  );
  assert(
    calledFunctions.size >= 75,
    `Expected broad static caller coverage; found ${calledFunctions.size} routes.`,
  );
});
