import { join } from "node:path";
import {
  discoverFunctionEntrypoints,
  functionsRoot,
  repoRelative,
} from "./function_dependency_tools.ts";

interface RootDenoConfig {
  imports?: Record<string, string>;
  lock?: { path?: string; frozen?: boolean };
}

export async function expectedFunctionDenoConfig(): Promise<string> {
  const rootConfigPath = join(functionsRoot, "deno.json");
  const rootConfig = JSON.parse(
    await Deno.readTextFile(rootConfigPath),
  ) as RootDenoConfig;
  if (!rootConfig.imports || Object.keys(rootConfig.imports).length === 0) {
    throw new Error("functions/deno.json must declare shared imports.");
  }
  if (
    rootConfig.lock?.path !== "./dependencies.lock" ||
    rootConfig.lock.frozen !== true
  ) {
    throw new Error(
      "functions/deno.json must use the frozen ./dependencies.lock file.",
    );
  }

  return `${
    JSON.stringify(
      {
        lock: { path: "../dependencies.lock", frozen: true },
        imports: rootConfig.imports,
      },
      null,
      2,
    )
  }\n`;
}

export async function staleFunctionDenoConfigs(): Promise<string[]> {
  const expected = await expectedFunctionDenoConfig();
  const stale: string[] = [];
  for (const fn of await discoverFunctionEntrypoints()) {
    const path = join(fn.directory, "deno.json");
    try {
      if (await Deno.readTextFile(path) !== expected) stale.push(path);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) {
        stale.push(path);
      } else {
        throw error;
      }
    }
  }
  return stale;
}

async function main(): Promise<void> {
  const checkOnly = Deno.args.includes("--check");
  const listOnly = Deno.args.includes("--list");
  const functions = await discoverFunctionEntrypoints();

  if (listOnly) {
    for (const fn of functions) console.log(fn.name);
    return;
  }

  const expected = await expectedFunctionDenoConfig();
  if (checkOnly) {
    const stale = await staleFunctionDenoConfigs();
    if (stale.length > 0) {
      console.error("Function Deno configs are missing or stale:");
      for (const path of stale) console.error(`- ${repoRelative(path)}`);
      Deno.exit(1);
    }
    console.log(
      `Validated ${functions.length} function-specific Deno configs.`,
    );
    return;
  }

  for (const fn of functions) {
    await Deno.writeTextFile(join(fn.directory, "deno.json"), expected);
  }
  console.log(
    `Synchronized ${functions.length} function-specific Deno configs.`,
  );
}

if (import.meta.main) await main();
