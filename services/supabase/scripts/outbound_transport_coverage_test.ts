import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const scriptsDirectory = new URL("./", import.meta.url);
const geocodingScript = new URL(
  "retroactive_geocoding.ts",
  scriptsDirectory,
);
const taxonomyImportScript = new URL(
  "import_community_taxonomy.ts",
  scriptsDirectory,
);
const GLOBAL_FETCH_CALL_PATTERN =
  /(?:^|[^.\w])fetch\s*\(|\b(?:globalThis|self|window)\s*(?:(?:\?\.|\.)\s*fetch|\[\s*["']fetch["']\s*\])\s*\(/m;

function withoutTypeScriptComments(source: string): string {
  return source
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/\/\/[^\r\n]*/g, " ");
}

Deno.test("production scripts cannot call rename-sensitive global fetch", async () => {
  const violations: string[] = [];
  for await (const entry of Deno.readDir(scriptsDirectory)) {
    if (
      !entry.isFile ||
      !entry.name.endsWith(".ts") ||
      entry.name.endsWith("_test.ts") ||
      entry.name.endsWith(".test.ts")
    ) {
      continue;
    }

    const source = withoutTypeScriptComments(
      await Deno.readTextFile(new URL(entry.name, scriptsDirectory)),
    );
    if (GLOBAL_FETCH_CALL_PATTERN.test(source)) {
      violations.push(entry.name);
    }
  }

  assert(
    violations.length === 0,
    `Global fetch bypasses reviewed transport policy: ${violations.join(", ")}`,
  );
});

Deno.test("global-fetch guard covers direct property access", () => {
  for (
    const source of [
      "fetch(url)",
      "globalThis.fetch(url)",
      "globalThis?.fetch(url)",
      'globalThis["fetch"](url)',
      "self.fetch(url)",
      "window.fetch(url)",
    ]
  ) {
    assert(
      GLOBAL_FETCH_CALL_PATTERN.test(source),
      `Global fetch form escaped the transport guard: ${source}`,
    );
  }
  assert(!GLOBAL_FETCH_CALL_PATTERN.test("reviewedClient.fetch(request)"));
});

Deno.test("Nominatim migration bounds deadline and response bytes", async () => {
  const source = await Deno.readTextFile(geocodingScript);

  for (
    const fragment of [
      'NOMINATIM_ORIGIN = "https://nominatim.openstreetmap.org"',
      "NOMINATIM_REQUEST_TIMEOUT_MS = 15_000",
      "NOMINATIM_MAXIMUM_RESPONSE_BYTES = 64 * 1_024",
      "fetchWithDeadline(",
      "readResponseJsonWithinLimit<unknown>(",
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
});

Deno.test("taxonomy import bounds its long-running function invocation", async () => {
  const source = await Deno.readTextFile(taxonomyImportScript);

  for (
    const fragment of [
      "IMPORT_REQUEST_TIMEOUT_MS = 3 * 60 * 1_000",
      "IMPORT_MAXIMUM_RESPONSE_BYTES = 512 * 1_024",
      "createServiceRoleClientFromEnvironmentWithOptions({",
      "requestTimeoutMs: IMPORT_REQUEST_TIMEOUT_MS",
      "maximumResponseBytes: IMPORT_MAXIMUM_RESPONSE_BYTES",
      "invokeServiceRoleJson<T>(",
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
});
