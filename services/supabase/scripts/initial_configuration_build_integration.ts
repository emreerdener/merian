import catalog from "../functions/_shared/initialAnalysis/configuration-assets-v1.json" with {
  type: "json",
};
import { resolveInitialSourceArchive } from "../functions/_shared/initialAnalysis/sourceArchive.ts";
import {
  INITIAL_ASSET_BYTES,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";
import { buildInitialSourceArchiveFromGit } from "./build_initial_source_archive.ts";
import { repoRoot } from "./function_dependency_tools.ts";
import { assertEquals, assertRejects } from "@std/assert";
import fixture from "./fixtures/initial_configuration_graph_v1.json" with {
  type: "json",
};
import {
  type InitialConfigurationGraph,
  inspectInitialConfigurationBuild,
} from "./initial_configuration_build.ts";

const root = "file:///initial-configuration-checkout/";
const fresh = () => structuredClone(fixture) as InitialConfigurationGraph;
// Archived inputs, not the moving checkout: ordinary AI work must not be
// frozen merely because the inactive initial executor supports catalog v1.
let archive: ReturnType<typeof resolveInitialSourceArchive> | undefined;
const read = async (path: string) => {
  const signal = new AbortController().signal;
  archive ??= (async () => {
    const bytes = await buildInitialSourceArchiveFromGit(repoRoot, signal);
    return await resolveInitialSourceArchive(
      new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(bytes);
          controller.close();
        },
      }),
      catalog.digest,
      signal,
    );
  })();
  return await readInitialStream(
    await (await archive).readAsset(
      path,
      catalog.manifest.repository_revision,
      signal,
    ),
    INITIAL_ASSET_BYTES,
    signal,
  );
};
const production = root +
  "services/supabase/functions/_shared/ai/production.ts";

Deno.test("initial compiled source closure: pinned parser graph and staged sources", async () => {
  const result = await inspectInitialConfigurationBuild(fresh(), root, read);
  assertEquals(result.runtime_files.length, 58);
  assertEquals(Object.keys(result.npm_packages).length, 51);
  assertEquals(result.unused_dependency_metadata.length, 14);
  assertEquals(result.erased_type_files, [
    "services/supabase/functions/_shared/ai/contracts.ts",
    "services/supabase/functions/_shared/identify/types.ts",
  ]);
  assertEquals(result.qualification, "source_graph_only_not_deployed_artifact");
});

Deno.test("initial compiled source closure rejects missing, foreign and dynamic runtime edges", async () => {
  const cases: ((graph: InitialConfigurationGraph) => void)[] = [
    (g) => g.roots.pop(),
    (g) => g.roots.push(g.roots[0]),
    (g) => g.modules.push(g.modules[0]),
    (g) =>
      g.modules.splice(
        g.modules.findIndex((m) => m.specifier === production),
        1,
      ),
    (g) => {
      g.modules.find((m) => m.specifier === production)!.dependencies!.push({
        specifier: "./contracts.ts",
        code: {
          specifier: root +
            "services/supabase/functions/_shared/ai/contracts.ts",
        },
      });
    },
    (g) => {
      g.modules.find((m) => m.specifier === production)!.dependencies![0]
        .isDynamic = true;
    },
    (g) => {
      g.redirects[production] = production;
    },
    (g) => {
      g.modules.find((m) => m.specifier === production)!.dependencies!.push({
        specifier: "https://example.invalid/code.ts",
        code: { specifier: "https://example.invalid/code.ts" },
      });
    },
  ];
  for (const change of cases) {
    const graph = fresh();
    change(graph);
    let reads = 0;
    await assertRejects(
      () =>
        inspectInitialConfigurationBuild(graph, root, () => {
          reads++;
          throw new Error("unexpected read");
        }),
      Error,
      "initial_configuration_build_unavailable",
    );
    assertEquals(reads, 0);
  }
});

Deno.test("initial compiled source closure rejects changed SDK identities and transitive edges", async () => {
  const cases: ((graph: InitialConfigurationGraph) => void)[] = [
    (g) => delete g.npmPackages["@google/genai@2.24.0"],
    (g) => {
      g.npmPackages["@google/genai@2.24.0"].version = "2.24.1";
    },
    (g) => {
      g.npmPackages["@google/genai@2.24.0"].registryUrl =
        "https://example.invalid/";
    },
    (g) => {
      g.npmPackages["@google/genai@2.24.0"].dependencies.pop();
    },
    (g) => {
      g.npmPackages["@google/genai@2.24.0"].dependencies.push(
        "aws4fetch@1.0.20",
      );
    },
    (g) => {
      g.npmPackages["unexpected@1.0.0"] = {
        name: "unexpected",
        version: "1.0.0",
        registryUrl: "https://registry.npmjs.org/",
        dependencies: [],
      };
    },
  ];
  for (const change of cases) {
    const graph = fresh();
    change(graph);
    await assertRejects(
      () => inspectInitialConfigurationBuild(graph, root, read),
      Error,
      "initial_configuration_build_unavailable",
    );
  }
});

Deno.test("initial compiled source closure checks all saved source bytes including import map and lock", async () => {
  for (
    const changed of [
      "_shared/ai/production.ts",
      "deno.json",
      "dependencies.lock",
    ]
  ) {
    await assertRejects(
      () =>
        inspectInitialConfigurationBuild(fresh(), root, async (path) => {
          const bytes = await read(path);
          if (path === "services/supabase/functions/" + changed) bytes[0] ^= 1;
          return bytes;
        }),
      Error,
      "initial_configuration_build_unavailable",
    );
  }
});

Deno.test("initial compiled source closure snapshots resolver input before awaits", async () => {
  const graph = fresh();
  const result = await inspectInitialConfigurationBuild(graph, root, (path) => {
    graph.npmPackages = {};
    graph.modules = [];
    return read(path);
  });
  assertEquals(Object.keys(result.npm_packages).length, 51);
  assertEquals(result.runtime_files.length, 58);
});
