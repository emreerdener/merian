import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const functionsRoot = new URL("../", import.meta.url);

const EXPECTED_SIGNED_TRANSPORT_CALLS = new Map<string, number>([
  ["_shared/aws.ts", 6],
  ["_shared/identify/media.ts", 2],
  ["export-dwca/storage.ts", 6],
]);
const GLOBAL_FETCH_CALL_PATTERN =
  /(?:^|[^.\w])fetch\s*\(|\b(?:globalThis|self|window)\s*(?:(?:\?\.|\.)\s*fetch|\[\s*["']fetch["']\s*\])\s*\(/m;

interface RuntimeSource {
  path: string;
  source: string;
}

async function collectRuntimeSources(
  directory: URL,
  relativeDirectory = "",
): Promise<RuntimeSource[]> {
  const files: RuntimeSource[] = [];
  for await (const entry of Deno.readDir(directory)) {
    if (
      entry.name === "_tests" ||
      entry.name === "node_modules" ||
      entry.name.startsWith(".")
    ) {
      continue;
    }

    const relativePath = relativeDirectory
      ? `${relativeDirectory}/${entry.name}`
      : entry.name;
    const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), directory);
    if (entry.isDirectory) {
      files.push(...await collectRuntimeSources(url, relativePath));
    } else if (
      entry.isFile &&
      entry.name.endsWith(".ts") &&
      !entry.name.endsWith("_test.ts") &&
      !entry.name.endsWith(".test.ts")
    ) {
      files.push({
        path: relativePath,
        source: await Deno.readTextFile(url),
      });
    }
  }
  return files;
}

Deno.test("production outbound transports cannot bypass reviewed deadline adapters", async () => {
  const files = await collectRuntimeSources(functionsRoot);
  const signedCallCounts = new Map<string, number>();
  const geminiClients: string[] = [];

  for (const file of files) {
    assert(
      !GLOBAL_FETCH_CALL_PATTERN.test(file.source),
      `${file.path} calls global fetch directly; use fetchWithDeadline.`,
    );
    assert(
      file.path === "_shared/outbound.ts" ||
        !/\b(?:fetcher|fetchImpl|fetchImplementation)\s*\(/.test(file.source),
      `${file.path} calls an injected fetch transport directly; pass it to fetchWithDeadline.`,
    );
    assert(
      file.path === "_shared/outbound.ts" ||
        !/\?\?\s*fetch\s*\)\s*\(/.test(file.source),
      `${file.path} invokes a fallback fetch expression directly; use fetchWithDeadline.`,
    );
    if (/\bnew\s+GoogleGenAI\s*\(/.test(file.source)) {
      geminiClients.push(file.path);
    }

    const signedFetchPattern = /\.fetch\s*\(/g;
    const matches = [...file.source.matchAll(signedFetchPattern)];
    if (matches.length === 0) continue;
    signedCallCounts.set(file.path, matches.length);

    for (const match of matches) {
      const callStart = match.index ?? 0;
      const deadlineWindow = file.source.slice(callStart, callStart + 320);
      const expectedRequestAdapter = file.path === "export-dwca/storage.ts"
        ? /\br2Request\s*\(/
        : /\br2RequestWithDeadline\s*\(/;
      assert(
        expectedRequestAdapter.test(deadlineWindow),
        `${file.path} has a signed fetch without its deadline-bound Request adapter.`,
      );
    }
  }

  assertEquals(
    [...signedCallCounts.entries()].sort(([left], [right]) =>
      left.localeCompare(right)
    ),
    [...EXPECTED_SIGNED_TRANSPORT_CALLS.entries()].sort(([left], [right]) =>
      left.localeCompare(right)
    ),
  );
  assertEquals(geminiClients, ["_shared/gemini.ts"]);

  const geminiSource = files.find((file) => file.path === "_shared/gemini.ts")
    ?.source ?? "";
  assert(
    /GEMINI_REQUEST_TIMEOUT_MS\s*=\s*90_000/.test(geminiSource) &&
      /httpOptions\s*:\s*\{\s*timeout\s*:\s*GEMINI_REQUEST_TIMEOUT_MS/s.test(
        geminiSource,
      ),
    "The shared Google GenAI client must enforce its reviewed HTTP deadline.",
  );
});
