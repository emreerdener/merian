/** Source-side prerequisite for the dormant compiled-v1 initial executor.
 * The graph must come from Deno's parser/resolver for the exact build inputs.
 * This is NOT an attestation of a deployed artifact or permission to dispatch.
 * The eventual artifact gate must bind the emitted inventory to its actual
 * bundled modules, dependency bytes and runtime configuration before install.
 */
import catalog from "../functions/_shared/initialAnalysis/configuration-assets-v1.json" with {
  type: "json",
};
import {
  hex,
  initialCanonicalText,
  initialDigest,
} from "../functions/_shared/initialAnalysis/canonical.ts";

type Resolution = { specifier: string; error?: unknown };
type Dependency = {
  specifier: string;
  code?: Resolution;
  type?: Resolution;
  isDynamic?: boolean;
};
type Module = {
  kind: string;
  specifier: string;
  dependencies?: Dependency[];
  npmPackage?: string;
  error?: unknown;
};
type Package = {
  name: string;
  version: string;
  dependencies: string[];
  registryUrl: string;
};
export interface InitialConfigurationGraph {
  version: number;
  roots: string[];
  modules: Module[];
  redirects: Record<string, string>;
  npmPackages: Record<string, Package>;
}
type LockPackage = {
  integrity: string;
  dependencies?: string[];
  optionalDependencies?: string[];
};
const failure = () => new Error("initial_configuration_build_unavailable");
const prefix = "services/supabase/functions/";
const typeOnly = new Set([
  `${prefix}_shared/ai/contracts.ts`,
  `${prefix}_shared/identify/types.ts`,
]);
const equal = (a: string[], b: string[]) =>
  JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
const packageName = (id: string) => id.slice(0, id.lastIndexOf("@"));

/** Checks only the one supported saved catalog, never a supplied replacement.
 * readSource receives catalog paths exclusively and must read the exact staged
 * build input, not a moving checkout after bundling. Type-only edges cannot
 * silently become runtime edges. SDK package identities/edges/integrities are
 * retained for the later artifact-byte check, not inferred from folder names.
 */
export async function inspectInitialConfigurationBuild(
  value: InitialConfigurationGraph,
  repositoryURL: string,
  readSource: (path: string) => Promise<Uint8Array>,
) {
  // Snapshot resolver metadata before asynchronous source hashing.
  const raw = JSON.stringify(value);
  if (raw.length > 2_097_152) throw failure();
  const graph = JSON.parse(raw) as InitialConfigurationGraph;
  const root = new URL(repositoryURL);
  if (
    root.protocol !== "file:" || root.host || root.search || root.hash ||
    !root.pathname.endsWith("/") || graph.version !== 1 ||
    !Array.isArray(graph.modules) || graph.modules.length > 512 ||
    !Array.isArray(graph.roots) || !graph.redirects || !graph.npmPackages ||
    Object.keys(graph.npmPackages).length > 256 ||
    await initialDigest("assets", initialCanonicalText(catalog.manifest)) !==
      catalog.digest
  ) throw failure();
  const url = (path: string) => new URL(path, root).href;
  const roots = catalog.manifest.roots.map((p) => url(prefix + p));
  if (!equal(graph.roots, roots)) throw failure();
  const paths = new Map(catalog.manifest.files.map((f) => [url(f.path), f]));
  const modules = new Map<string, Module>();
  for (const module of graph.modules) {
    if (modules.has(module.specifier) || module.error) throw failure();
    modules.set(module.specifier, module);
  }
  const resolve = (specifier: string) => {
    const seen = new Set<string>();
    while (Object.hasOwn(graph.redirects, specifier)) {
      if (seen.has(specifier) || seen.size > 16) throw failure();
      seen.add(specifier);
      specifier = graph.redirects[specifier];
    }
    return specifier;
  };
  const runtime = new Set<string>(), erased = new Set<string>();
  const npmRoots = new Set<string>();
  const pending = [...roots];
  while (pending.length) {
    const specifier = resolve(pending.pop()!);
    if (runtime.has(specifier)) continue;
    runtime.add(specifier);
    const module = modules.get(specifier);
    if (!module) throw failure();
    if (module.kind === "npm") {
      if (!module.npmPackage) throw failure();
      npmRoots.add(module.npmPackage);
      continue;
    }
    if (module.kind !== "esm" || !paths.has(specifier)) throw failure();
    for (const dependency of module.dependencies ?? []) {
      // Dynamic imports/assets need explicit qualification; this build has none.
      if (dependency.isDynamic || dependency.code?.error) throw failure();
      if (dependency.code) pending.push(dependency.code.specifier);
      if (dependency.type) erased.add(resolve(dependency.type.specifier));
      if (!dependency.code && !dependency.type) throw failure();
    }
  }
  const checked = new Map<string, Uint8Array<ArrayBuffer>>();
  const readChecked = async (path: string) => {
    if (checked.has(path)) return checked.get(path)!;
    const file = catalog.manifest.files.find((f) => f.path === path);
    if (!file) throw failure();
    const supplied = await readSource(path);
    if (
      !(supplied instanceof Uint8Array) ||
      !(supplied.buffer instanceof ArrayBuffer) || supplied.length > 2_097_152
    ) throw failure();
    const bytes = new Uint8Array(supplied);
    if (
      hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))) !==
        file.sha256
    ) throw failure();
    checked.set(path, bytes);
    return bytes;
  };
  const config = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(
    await readChecked(prefix + "deno.json"),
  ));
  const expectedNpm = catalog.manifest.external_specifiers.map((name) => {
    const specifier = config.imports[name];
    if (!specifier?.startsWith("npm:")) throw failure();
    return specifier.slice(4);
  });
  if (!equal([...npmRoots], expectedNpm)) throw failure();
  const runtimeFiles = [...runtime].filter((s) => paths.has(s)).map((s) =>
    paths.get(s)!.path
  ).sort();
  const erasedFiles = [...erased].filter((s) => !runtime.has(s)).map((s) => {
    const path = s.startsWith(root.href) ? s.slice(root.href.length) : "";
    if (!typeOnly.has(path) && !paths.has(s)) throw failure();
    return path;
  }).sort();
  const packages: Record<
    string,
    { integrity: string; dependencies: string[] }
  > = {};
  const packagePending = [...npmRoots];
  const lock = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(
    await readChecked(prefix + "dependencies.lock"),
  ));
  const locked = lock.npm as Record<string, LockPackage>;
  while (packagePending.length) {
    const id = packagePending.pop()!;
    if (Object.hasOwn(packages, id)) continue;
    const p = graph.npmPackages[id], saved = locked[id];
    if (
      !p || !saved || p.name !== packageName(id) ||
      id !== `${p.name}@${p.version}` ||
      p.registryUrl !== "https://registry.npmjs.org/" ||
      !/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(saved.integrity) ||
      !Array.isArray(p.dependencies) || new Set(p.dependencies).size !==
        p.dependencies.length
    ) throw failure();
    const required = saved.dependencies ?? [];
    const allowed = [...required, ...saved.optionalDependencies ?? []];
    const matches = (declaration: string, resolved: string) => {
      if (Object.hasOwn(locked, declaration)) return declaration === resolved;
      const candidates = Object.keys(locked).filter((key) =>
        packageName(key) === declaration
      );
      return candidates.length === 1 && candidates[0] === resolved;
    };
    if (
      p.dependencies.some((d) =>
        !locked[d] ||
        !allowed.some((a) => matches(a, d))
      ) ||
      required.some((d) => !p.dependencies.some((a) => matches(d, a)))
    ) throw failure();
    packages[id] = {
      integrity: saved.integrity,
      dependencies: [...p.dependencies].sort(),
    };
    packagePending.push(...p.dependencies);
  }
  // Deno info also lists packages resolved from unused import-map entries.
  // They are metadata, not part of this execution closure. Unknown packages
  // still reject; only the traversed closure may be certified in the output.
  if (Object.keys(graph.npmPackages).some((id) => !Object.hasOwn(locked, id))) {
    throw failure();
  }
  for (const file of catalog.manifest.files) {
    await readChecked(file.path);
  }
  return {
    version: 1,
    asset_manifest_digest: catalog.digest,
    repository_revision: catalog.manifest.repository_revision,
    runtime_files: runtimeFiles,
    erased_type_files: erasedFiles,
    npm_packages: Object.fromEntries(
      Object.entries(packages).sort(([a], [b]) => a.localeCompare(b)),
    ),
    unused_dependency_metadata: Object.keys(graph.npmPackages).filter((id) =>
      !Object.hasOwn(packages, id)
    ).sort(),
    qualification: "source_graph_only_not_deployed_artifact" as const,
  };
}
