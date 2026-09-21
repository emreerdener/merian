import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { handleDiscoverySearch, type SearchDependencies } from "./index.ts";
import type { SearchPage } from "./db.ts";
import type { AIProviderQuotaLease } from "../_shared/aiQuota.ts";
const id = "00000000-0000-4000-8000-000000000001";
const user = { id } as User;
const admin = {} as SupabaseClient;
const context = {
  query: "orange black butterfly",
  group: "insects" as const,
  media: null,
  mode: "description" as const,
};
const empty: SearchPage = { species: [], sightings: [], next_cursor: null };
function request(body: object) {
  return new Request("https://example.invalid", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ request_id: id, result_kind: "species", ...body }),
  });
}
function harness() {
  const events: string[] = [];
  const lease = {
    reservation: { model: "gemini-2.5-flash" },
    commit: () => {
      events.push("commit");
      return Promise.resolve();
    },
    fail: () => {
      events.push("fail");
      return Promise.resolve(true);
    },
    refund: () => {
      events.push("refund");
      return Promise.resolve(true);
    },
  } as AIProviderQuotaLease;
  const deps: SearchDependencies = {
    search: (_db, viewer, criteria, kind) => {
      assertEquals(viewer, id);
      events.push(`search:${kind}:${criteria.mode}`);
      return Promise.resolve(empty);
    },
    reserve: (_req, _db, args) => {
      assertEquals(args.operation, "species_discovery_search");
      events.push("reserve");
      return Promise.resolve(lease);
    },
    interpret: () => {
      events.push("provider");
      return Promise.resolve({
        interpretation: {
          status: "results",
          context,
          message: "Orange and black butterflies",
        },
        usage: undefined,
      });
    },
    record: () => {
      events.push("usage");
    },
  };
  return { deps, events };
}
Deno.test("AI retrieval commits consent/quota before provider and returns only server records", async () => {
  const { deps, events } = harness();
  const result = await handleDiscoverySearch(
    request({ question: "Orange and black insects" }),
    user,
    admin,
    deps,
  );
  assertEquals(events, [
    "search:species:name",
    "reserve",
    "commit",
    "provider",
    "usage",
    "search:species:description",
  ]);
  assertEquals((await result.json()).species, []);
  assertEquals(result.headers.get("Cache-Control"), "private, no-store");
});
Deno.test("exact name lookup never calls provider or consumes allowance", async () => {
  const { deps, events } = harness();
  deps.search = () =>
    Promise.resolve({
      ...empty,
      species: [{
        item: {
          id,
          scientific_name: "Exemplum test",
          common_name: "Example",
          content_quality: "sparse",
          taxonomy: null,
          iucn_red_list_status: null,
          hazard_type: null,
          group_tags: [],
          reference_image_url: null,
        },
        excerpt: "",
      }],
    });
  const result = await handleDiscoverySearch(
    request({ question: "Example" }),
    user,
    admin,
    deps,
  );
  assertEquals((await result.json()).context.mode, "name");
  assertEquals(events, []);
});
Deno.test("tab and page reads reuse context without provider calls", async () => {
  const { deps, events } = harness();
  await handleDiscoverySearch(
    request({ context, result_kind: "sightings" }),
    user,
    admin,
    deps,
  );
  assertEquals(events, ["search:sightings:description"]);
});
Deno.test("unsupported query does not silently broaden retrieval", async () => {
  const { deps, events } = harness();
  deps.interpret = () =>
    Promise.resolve({
      interpretation: {
        status: "unsupported",
        context,
        message: "Nearby filtering is not supported.",
      },
      usage: undefined,
    });
  const result = await handleDiscoverySearch(
    request({ context, question: "near me" }),
    user,
    admin,
    deps,
  );
  assertEquals((await result.json()).status, "unsupported");
  assertEquals(events.some((e) => e.startsWith("search:")), false);
});
Deno.test("provider failure preserves allowance accounting and never publishes partial results", async () => {
  const { deps, events } = harness();
  deps.interpret = () => Promise.reject(new Error("private provider body"));
  await assertRejects(
    () =>
      handleDiscoverySearch(
        request({ context, question: "Only butterflies" }),
        user,
        admin,
        deps,
      ),
    Error,
    "Search is temporarily unavailable",
  );
  assertEquals(events, ["reserve", "commit", "fail"]);
});
