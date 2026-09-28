import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  handleViewerDictionary,
  viewerDictionaryHttpHandler,
} from "./index.ts";

const viewer = "00000000-0000-4000-8000-000000000001";
function request(body: object): Request {
  return new Request("https://example.invalid/species-dictionary-for-viewer", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}
Deno.test("viewer dictionary passes the authenticated viewer through all projection modes and disables shared caching", async () => {
  const calls: string[] = [];
  const dependencies = {
    catalog: (
      ...args: Parameters<
        typeof import("../species-dictionary/db.ts").fetchSpeciesDictionaryCatalog
      >
    ) => {
      assertEquals(args[2], viewer);
      calls.push("catalog");
      return Promise.resolve({ data: [], nextCursor: null });
    },
    overview: (
      ...args: Parameters<
        typeof import("../species-dictionary/db.ts").fetchSpeciesDictionaryOverview
      >
    ) => {
      assertEquals(args[2], viewer);
      calls.push("overview");
      // The payload is opaque to the handler; projection correctness has separate tests.
      return Promise.resolve(
        {} as Awaited<
          ReturnType<
            typeof import("../species-dictionary/db.ts").fetchSpeciesDictionaryOverview
          >
        >,
      );
    },
    detail: (
      ...args: Parameters<
        typeof import("../species-dictionary/db.ts").fetchSpeciesDictionary
      >
    ) => {
      assertEquals(args[3], viewer);
      calls.push("detail");
      return Promise.resolve(null);
    },
  };
  for (
    const body of [{ mode: "catalog" }, { mode: "overview" }, {
      scientific_name: "Testus example",
    }]
  ) {
    const response = await handleViewerDictionary(
      request(body),
      viewer,
      {} as SupabaseClient,
      dependencies,
    );
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals(response.headers.get("Vary"), "Authorization");
  }
  assertEquals(calls, ["catalog", "overview", "detail"]);
});
Deno.test("viewer dictionary rejects missing authentication without querying or fetching", async () => {
  const names = ["SUPABASE_URL", "SUPABASE_SECRET_KEY"];
  const old = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], "sb_secret_" + "test_only_not_a_credential");
  try {
    const response = await viewerDictionaryHttpHandler(
      request({ mode: "catalog" }),
    );
    assertEquals(response.status, 401);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals(response.headers.get("X-Merian-Handler"), "1");
    await response.body?.cancel();
  } finally {
    names.forEach((name, i) =>
      old[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, old[i]!)
    );
  }
});
