import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export interface FunctionEntrypoint {
  name: string;
  directory: string;
  entrypoint: string;
}

export interface FunctionGraph extends FunctionEntrypoint {
  files: Set<string>;
  externalSpecifiers: Set<string>;
}

export const repoRoot = resolve(
  fileURLToPath(new URL("../../../", import.meta.url)),
);
export const supabaseRoot = resolve(
  fileURLToPath(new URL("../", import.meta.url)),
);
export const functionsRoot = join(supabaseRoot, "functions");

export function repoRelative(path: string): string {
  return relative(repoRoot, path).split(sep).join("/");
}

export function configuredFunctionNames(configToml: string): string[] {
  return [...configToml.matchAll(/^\[functions\.([^\]]+)\]$/gm)]
    .map((match) => match[1])
    .sort();
}

export async function discoverFunctionEntrypoints(
  root = functionsRoot,
): Promise<FunctionEntrypoint[]> {
  const functions: FunctionEntrypoint[] = [];
  for await (const entry of Deno.readDir(root)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;

    const directory = join(root, entry.name);
    const entrypoint = join(directory, "index.ts");
    try {
      if ((await Deno.stat(entrypoint)).isFile) {
        functions.push({ name: entry.name, directory, entrypoint });
      }
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }

  return functions.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
}

export function importedSpecifiers(source: string): string[] {
  const specifiers = new Set<string>();
  const staticPattern =
    /\b(?:import|export)\s+(type\s+)?(?:[^"'`;]*?\s+from\s+)?["']([^"']+)["']/g;
  const dynamicPattern = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;

  for (const match of source.matchAll(staticPattern)) {
    // Explicit type-only edges are erased from the deployed bundle. Tracking
    // them here causes unrelated routes to redeploy when only a compile-time
    // contract changes; whole-tree Deno checks remain responsible for them.
    if (!match[1] && match[2]) specifiers.add(match[2]);
  }
  for (const match of source.matchAll(dynamicPattern)) {
    if (match[1]) specifiers.add(match[1]);
  }
  return [...specifiers];
}

async function existingLocalModule(
  importer: string,
  specifier: string,
): Promise<string> {
  const base = resolve(dirname(importer), specifier);
  const candidates = [base];
  if (!basename(base).includes(".")) {
    candidates.push(`${base}.ts`, join(base, "index.ts"));
  }

  for (const candidate of candidates) {
    try {
      if ((await Deno.stat(candidate)).isFile) return candidate;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }

  throw new Error(
    `Unable to resolve local import ${specifier} from ${
      repoRelative(importer)
    }`,
  );
}

export async function buildFunctionGraph(
  fn: FunctionEntrypoint,
): Promise<FunctionGraph> {
  const pending = [fn.entrypoint];
  const files = new Set<string>();
  const externalSpecifiers = new Set<string>();

  while (pending.length > 0) {
    const current = pending.pop()!;
    if (files.has(current)) continue;
    files.add(current);

    const source = await Deno.readTextFile(current);
    for (const specifier of importedSpecifiers(source)) {
      if (!specifier.startsWith(".")) {
        externalSpecifiers.add(specifier);
        continue;
      }

      const imported = await existingLocalModule(current, specifier);
      const relativeToFunctions = relative(functionsRoot, imported);
      if (
        relativeToFunctions === ".." ||
        relativeToFunctions.startsWith(`..${sep}`)
      ) {
        throw new Error(
          `${
            repoRelative(current)
          } imports outside the Edge Function root: ${specifier}`,
        );
      }
      pending.push(imported);
    }
  }

  return { ...fn, files, externalSpecifiers };
}

export async function buildAllFunctionGraphs(): Promise<FunctionGraph[]> {
  return await Promise.all(
    (await discoverFunctionEntrypoints()).map(buildFunctionGraph),
  );
}

function normalizedChangedPath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}

function isTestOrDocumentation(path: string): boolean {
  const name = basename(path);
  return name === "README.md" || name.endsWith(".md") ||
    name.endsWith(".test.ts") || name.endsWith("_test.ts") ||
    path.includes("/_tests/");
}

export function planAffectedFunctions(
  changedFiles: string[],
  graphs: FunctionGraph[],
): string[] {
  const allNames = graphs.map((graph) => graph.name).sort();
  const controlPaths = new Set([
    ".github/workflows/deploy.yml",
    "services/supabase/config.toml",
    "services/supabase/functions/deno.json",
    "services/supabase/functions/dependencies.lock",
  ]);
  const affected = new Set<string>();

  for (const rawPath of changedFiles) {
    const path = normalizedChangedPath(rawPath);
    if (!path) continue;
    if (controlPaths.has(path)) return allNames;

    const configMatch = path.match(
      /^services\/supabase\/functions\/([^/]+)\/deno\.json$/,
    );
    if (configMatch && graphs.some((graph) => graph.name === configMatch[1])) {
      affected.add(configMatch[1]);
      continue;
    }

    const absolutePath = resolve(repoRoot, path);
    let matchedGraph = false;
    for (const graph of graphs) {
      if (graph.files.has(absolutePath)) {
        affected.add(graph.name);
        matchedGraph = true;
      }
    }
    if (matchedGraph || isTestOrDocumentation(path)) continue;

    const functionMatch = path.match(
      /^services\/supabase\/functions\/([^/_][^/]*)\/(.+)$/,
    );
    if (functionMatch) {
      if (!graphs.some((graph) => graph.name === functionMatch[1])) {
        throw new Error(
          `Changed function directory has no current index.ts: ${
            functionMatch[1]
          }. ` +
            "Retire deployed functions through an explicit reviewed decommission instead of silently omitting them.",
        );
      }
      // Conservatively deploy for new/deleted runtime files or static assets
      // that are not visible in the current TypeScript import graph.
      affected.add(functionMatch[1]);
      continue;
    }

    if (path.startsWith("services/supabase/functions/_shared/")) {
      // A deleted or newly introduced shared runtime file may not appear in the
      // graph at the checked-out revision. A full deploy is the safe fallback.
      return allNames;
    }
  }

  return [...affected].sort();
}
