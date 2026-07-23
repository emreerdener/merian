import { join } from "node:path";
import {
  buildAllFunctionGraphs,
  configuredFunctionNames,
  functionsRoot,
  repoRelative,
  supabaseRoot,
} from "./function_dependency_tools.ts";
import { staleFunctionDenoConfigs } from "./sync_function_deno_configs.ts";

interface RootDenoConfig {
  imports?: Record<string, string>;
  lock?: { path?: string; frozen?: boolean };
  minimumDependencyAge?: string;
}

function sortedDifference(lhs: Set<string>, rhs: Set<string>): string[] {
  return [...lhs].filter((value) => !rhs.has(value)).sort();
}

function isConfiguredSpecifier(
  specifier: string,
  configuredAliases: string[],
): boolean {
  return configuredAliases.some((alias) =>
    alias === specifier || (alias.endsWith("/") && specifier.startsWith(alias))
  );
}

async function main(): Promise<void> {
  const rootConfig = JSON.parse(
    await Deno.readTextFile(join(functionsRoot, "deno.json")),
  ) as RootDenoConfig;
  const imports = rootConfig.imports ?? {};
  if (rootConfig.minimumDependencyAge !== "P1D") {
    throw new Error(
      "functions/deno.json must keep minimumDependencyAge at P1D.",
    );
  }
  const expectedSupabaseSpecifier = "npm:@supabase/supabase-js@2.110.6";
  if (imports["@supabase/supabase-js"] !== expectedSupabaseSpecifier) {
    throw new Error(
      `@supabase/supabase-js must resolve exactly to ${expectedSupabaseSpecifier}`,
    );
  }
  if (
    Object.keys(imports).some((name) => name.includes("supabase-js-claims"))
  ) {
    throw new Error(
      "The split claims-only Supabase SDK alias must be removed.",
    );
  }

  const staleConfigs = await staleFunctionDenoConfigs();
  if (staleConfigs.length > 0) {
    throw new Error(
      `Run sync_function_deno_configs.ts; stale configs: ${
        staleConfigs.map(repoRelative).join(", ")
      }`,
    );
  }

  const graphs = await buildAllFunctionGraphs();
  const configuredAliases = Object.keys(imports);
  const dependencyErrors: string[] = [];
  const runtimeFiles = new Set<string>();
  for (const graph of graphs) {
    for (const file of graph.files) runtimeFiles.add(file);
    for (const specifier of graph.externalSpecifiers) {
      if (specifier.startsWith("node:")) continue;
      if (isConfiguredSpecifier(specifier, configuredAliases)) continue;
      dependencyErrors.push(`${graph.name}: ${specifier}`);
    }
  }
  if (dependencyErrors.length > 0) {
    throw new Error(
      `Production dependency specifiers must use pinned Deno aliases:\n${
        dependencyErrors.sort().map((value) => `- ${value}`).join("\n")
      }`,
    );
  }

  const legacyLocks: string[] = [];
  for (
    const path of [
      join(functionsRoot, "deno.lock"),
      ...graphs.map((graph) => join(graph.directory, "deno.lock")),
    ]
  ) {
    try {
      if ((await Deno.stat(path)).isFile) legacyLocks.push(path);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  if (legacyLocks.length > 0) {
    throw new Error(
      `Remove legacy deno.lock files; dependencies.lock is canonical: ${
        legacyLocks.map(repoRelative).join(", ")
      }`,
    );
  }

  const configToml = await Deno.readTextFile(join(supabaseRoot, "config.toml"));
  const configuredFunctions = new Set(configuredFunctionNames(configToml));
  const functionNames = new Set(graphs.map((graph) => graph.name));
  const missingConfig = sortedDifference(functionNames, configuredFunctions);
  const staleConfig = sortedDifference(configuredFunctions, functionNames);
  if (missingConfig.length > 0 || staleConfig.length > 0) {
    throw new Error(
      [
        missingConfig.length > 0
          ? `Missing config.toml entries: ${missingConfig.join(", ")}`
          : "",
        staleConfig.length > 0
          ? `Stale config.toml entries: ${staleConfig.join(", ")}`
          : "",
      ].filter(Boolean).join("\n"),
    );
  }

  const lock = JSON.parse(
    await Deno.readTextFile(join(functionsRoot, "dependencies.lock")),
  ) as { specifiers?: Record<string, string> };
  const lockedSpecifiers = Object.keys(lock.specifiers ?? {});
  if (!lockedSpecifiers.includes(expectedSupabaseSpecifier)) {
    throw new Error(
      `${expectedSupabaseSpecifier} is missing from dependencies.lock.`,
    );
  }
  if (
    lockedSpecifiers.some((specifier) =>
      specifier.includes("supabase-js@2.49.1")
    )
  ) {
    throw new Error("dependencies.lock still contains Supabase JS 2.49.1.");
  }

  console.log(
    `Validated ${graphs.length} isolated function graphs across ${runtimeFiles.size} runtime files.`,
  );
}

if (import.meta.main) await main();
