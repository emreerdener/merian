import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";
import { fetchVerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";
import {
  handleAuthenticatedResolution,
  handleResolution,
  type ResolutionDependencies,
} from "./index.ts";

const id = "00000000-0000-4000-8000-000000000001";
const user = { id } as User;
const admin = {} as SupabaseClient;
const identity = { species_id: id, scientific_name: "Fixtureus accepted" };
function request(name: unknown = "Fixtureus synonym", signal?: AbortSignal) {
  return new Request("https://example.invalid/resolve-species-dictionary", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ scientific_name: name }),
    signal,
  });
}
function harness() {
  const events: string[] = [];
  const deps: ResolutionDependencies = {
    admit: (_db, viewer) => {
      assertEquals(viewer, id);
      events.push("admit");
      return Promise.resolve();
    },
    find: () => {
      events.push("find");
      return Promise.resolve(null);
    },
    verify: (name) => {
      assertEquals(name, "Fixtureus synonym");
      events.push("verify");
      return Promise.resolve({
        scientific_name: identity.scientific_name,
        gbif_taxon_key: 900001,
        rank: "SPECIES",
        status: "ACCEPTED",
        kingdom: "Plantae",
      });
    },
    persist: (_db, taxon) => {
      assertEquals(taxon.scientific_name, identity.scientific_name);
      events.push("persist");
      return Promise.resolve(identity);
    },
  };
  return { deps, events };
}

Deno.test("resolution returns a canonical receipt for the exact verified synonym", async () => {
  const { deps, events } = harness();
  const response = await handleResolution(
    request("  Fixtureus   synonym  "),
    user,
    admin,
    deps,
  );
  assertEquals(events, ["admit", "find", "verify", "persist"]);
  assertEquals(await response.json(), {
    schema_version: 1,
    requested_scientific_name: "Fixtureus synonym",
    ...identity,
  });
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
});
Deno.test("existing public species does not call GBIF or write", async () => {
  const { deps, events } = harness();
  deps.find = () => Promise.resolve(identity);
  await handleResolution(request(), user, admin, deps);
  assertEquals(events, ["admit"]);
});
Deno.test("invalid inputs never consume admission or contact providers", async () => {
  for (const name of [null, {}, "", " ", "x".repeat(161), "bad\u0000name"]) {
    const { deps, events } = harness();
    await assertRejects(
      () => handleResolution(request(name), user, admin, deps),
      PublicHttpError,
    );
    assertEquals(events, []);
  }
});
Deno.test("rate limits and nonpublic identities stop before GBIF", async () => {
  for (const stage of ["admit", "find"] as const) {
    const { deps, events } = harness();
    deps[stage] = () => {
      throw publicHttpError(stage === "admit" ? 429 : 404, "Unavailable");
    };
    await assertRejects(
      () => handleResolution(request(), user, admin, deps),
      PublicHttpError,
    );
    assertEquals(events.includes("verify"), false);
    assertEquals(events.includes("persist"), false);
  }
});
Deno.test("unverified and unavailable providers never create a species", async () => {
  for (const fail of [false, true]) {
    const { deps, events } = harness();
    deps.verify = () => {
      if (fail) throw new Error("provider failure");
      return Promise.resolve(null);
    };
    const error = await assertRejects(
      () => handleResolution(request(), user, admin, deps),
      PublicHttpError,
    );
    assertEquals(error.status, fail ? 503 : 422);
    assertEquals(events.includes("persist"), false);
  }
});
Deno.test("cancellation after verification prevents persistence", async () => {
  const { deps, events } = harness();
  const controller = new AbortController();
  const verify = deps.verify;
  deps.verify = async (...args) => {
    const taxon = await verify(...args);
    controller.abort();
    return taxon;
  };
  await assertRejects(() =>
    handleResolution(request(undefined, controller.signal), user, admin, deps)
  );
  assertEquals(events.includes("persist"), false);
});

Deno.test("cancellation aborts a pending GBIF read and prevents persistence", async () => {
  const { deps, events } = harness();
  const controller = new AbortController();
  let observed: AbortSignal | null | undefined;
  const started = Promise.withResolvers<void>();
  const fetcher: typeof fetch = (_input, init) => {
    observed = init?.signal;
    started.resolve();
    return new Promise((_resolve, reject) => {
      observed?.addEventListener(
        "abort",
        () => reject(new DOMException("Aborted", "AbortError")),
        { once: true },
      );
    });
  };
  deps.verify = (name, primary, _fetcher, signal) =>
    fetchVerifiedLookalikeTaxon(name, primary, fetcher, signal);
  const result = handleResolution(
    request(undefined, controller.signal),
    user,
    admin,
    deps,
  );
  const rejected = assertRejects(() => result);
  await started.promise;
  controller.abort();
  await rejected;
  assertEquals(observed?.aborted, true);
  assertEquals(events.includes("persist"), false);
});
Deno.test("authenticated route rejects missing identity before all resolution work", async () => {
  const { deps, events } = harness();
  const names = ["SUPABASE_URL", "MERIAN_SUPABASE_SERVER_API_KEY"];
  const previous = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], "sb_secret_" + "a".repeat(32));
  try {
    const response = await handleAuthenticatedResolution(
      request(),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
      deps,
    );
    assertEquals(response.status, 401);
    assertEquals(events, []);
  } finally {
    names.forEach((name, index) => {
      const value = previous[index];
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    });
  }
});
