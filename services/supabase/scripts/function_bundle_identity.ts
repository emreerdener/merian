import { join } from "node:path";
import {
  buildAllFunctionGraphs,
  functionsRoot,
  repoRelative,
} from "./function_dependency_tools.ts";

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

/** Local runtime graph plus pinned dependency identity, excluding the generated
 * file itself. This is not a Git, database or deployed environment revision. */
export async function computeFunctionBundleDigests<T extends string>(
  names: readonly T[],
  generatedPath: string,
): Promise<Readonly<Record<T, string>>> {
  const graphs = await buildAllFunctionGraphs();
  const result = {} as Record<T, string>;
  for (const name of names) {
    const graph = graphs.find((candidate) => candidate.name === name);
    if (!graph) throw new Error("function_bundle_graph_missing");
    const files = new Set([
      ...graph.files,
      join(functionsRoot, "deno.json"),
      join(functionsRoot, "dependencies.lock"),
    ]);
    files.delete(generatedPath);
    // A function may share several generated identities. Exclude all generated
    // digest payloads so cross-imports cannot create a circular hash dependency.
    for (
      const name of [
        "geminiDeploymentIdentity.ts",
        "fieldChatDeploymentIdentity.ts",
        "identificationDeploymentIdentity.ts",
      ]
    ) {
      files.delete(join(functionsRoot, "_shared", name));
    }
    const config = join(functionsRoot, name, "deno.json");
    try {
      if ((await Deno.stat(config)).isFile) files.add(config);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    const entries: string[] = [];
    for (const path of [...files].sort()) {
      entries.push(
        `${repoRelative(path)}\0${await sha256(await Deno.readFile(path))}\n`,
      );
    }
    result[name] = await sha256(new TextEncoder().encode(entries.join("")));
  }
  return Object.freeze(result);
}
