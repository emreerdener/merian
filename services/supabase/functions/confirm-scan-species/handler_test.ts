import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { PublicHttpError, publicHttpError } from "../_shared/http.ts";
import {
  parseReviewReceipt,
  parseReviewRequest,
  type ReviewReceipt,
} from "./contract.ts";
import {
  handleAuthenticatedSpeciesReview,
  handleSpeciesReview,
  type ReviewDependencies,
} from "./index.ts";
const scanID = "00000000-0000-4000-8000-000000000011";
const user = { id: "00000000-0000-4000-8000-000000000001" } as User;
const admin = {} as SupabaseClient;
const proof = {
  scientific_name: "Fixtureus accepted",
  gbif_taxon_key: 980001,
  rank: "SPECIES",
  status: "ACCEPTED",
  kingdom: "Plantae",
} as const;
const cleared: ReviewReceipt = {
  schema_version: 1,
  scan_id: scanID,
  review: {
    version: 1,
    revision: 1,
    identity: null,
    confirmed_species_id: null,
    user_identification_override: null,
    user_confirmed_identification: false,
    user_review_state: "unreviewed",
  },
};
function request(
  body: unknown = {
    scan_id: scanID,
    expected_revision: 0,
    action: "confirm_name",
    scientific_name: "Fixtureus synonym",
  },
  signal?: AbortSignal,
) {
  return new Request("https://example.invalid/confirm-scan-species", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
}
function harness() {
  const events: string[] = [];
  const dependencies: ReviewDependencies = {
    find: (_admin, owner, scan) => {
      assertEquals(owner, user.id);
      assertEquals(scan, scanID);
      events.push("find");
      return Promise.resolve({
        primary: {
          version: 1,
          resolution: "genus",
          scientific_name: "Fixtureus",
          common_name: null,
        },
        revision: 0,
      });
    },
    admit: (_admin, owner) => {
      assertEquals(owner, user.id);
      events.push("admit");
      return Promise.resolve();
    },
    verify: (name) => {
      assertEquals(name, "Fixtureus synonym");
      events.push("verify");
      return Promise.resolve(proof);
    },
    apply: (_admin, owner, parsed, name, taxon) => {
      assertEquals(owner, user.id);
      assertEquals(parsed.scan_id, scanID);
      assertEquals(name, "Fixtureus synonym");
      assertEquals(taxon, proof);
      events.push("apply");
      return Promise.resolve(cleared);
    },
  };
  return { events, dependencies };
}
Deno.test("species confirmation authenticates owner, admits fresh proof and atomically applies", async () => {
  const { events, dependencies } = harness();
  const result = await handleSpeciesReview(
    request(),
    user,
    admin,
    dependencies,
  );
  assertEquals(events, ["find", "admit", "verify", "apply"]);
  assertEquals(result.headers.get("Cache-Control"), "private, no-store");
  assertEquals(await result.json(), cleared);
});
Deno.test("clear bypasses external verification and admission, but preserves ownership and CAS", async () => {
  const { events, dependencies } = harness();
  dependencies.apply = (_admin, _owner, parsed, name, taxon) => {
    assertEquals(parsed.action, "clear");
    assertEquals(name, null);
    assertEquals(taxon, null);
    events.push("apply");
    return Promise.resolve(cleared);
  };
  await handleSpeciesReview(
    request({ scan_id: scanID, expected_revision: 0, action: "clear" }),
    user,
    admin,
    dependencies,
  );
  assertEquals(events, ["find", "apply"]);
});
Deno.test("primary confirmation uses saved species name and rejects broader answers", async () => {
  const { events, dependencies } = harness();
  const body = {
    scan_id: scanID,
    expected_revision: 0,
    action: "confirm_primary",
  };
  const denied = await assertRejects(
    () => handleSpeciesReview(request(body), user, admin, dependencies),
    PublicHttpError,
  );
  assertEquals(denied.status, 422);
  assertEquals(events, ["find"]);
  events.length = 0;
  dependencies.find = () =>
    Promise.resolve({
      primary: {
        version: 1,
        resolution: "species",
        scientific_name: "Fixtureus synonym",
        common_name: null,
      },
      revision: 0,
    });
  await handleSpeciesReview(request(body), user, admin, dependencies);
  assertEquals(events, ["admit", "verify", "apply"]);
});
Deno.test("invalid, foreign, stale, limited and unverified requests cannot mutate", async () => {
  for (
    const stage of ["find", "stale", "admit", "verify", "unavailable"] as const
  ) {
    const { events, dependencies } = harness();
    if (stage === "find") {
      dependencies.find = () => {
        throw publicHttpError(404, "Unavailable");
      };
    }
    if (stage === "stale") {
      dependencies.find = () =>
        Promise.resolve({
          primary: {
            version: 1,
            resolution: "genus",
            scientific_name: "Fixtureus",
            common_name: null,
          },
          revision: 2,
        });
    }
    if (stage === "admit") {
      dependencies.admit = () => {
        throw publicHttpError(429, "Limited");
      };
    }
    if (stage === "verify") dependencies.verify = () => Promise.resolve(null);
    if (stage === "unavailable") {
      dependencies.verify = () => {
        throw new Error("private provider body must not be exposed");
      };
    }
    const error = await assertRejects(
      () => handleSpeciesReview(request(), user, admin, dependencies),
      PublicHttpError,
    );
    assertEquals(events.includes("apply"), false);
    assertEquals(
      error.status,
      {
        find: 404,
        stale: 409,
        admit: 429,
        verify: 422,
        unavailable: 503,
      }[stage],
    );
    assertEquals(error.message.includes("private provider body"), false);
  }
});
Deno.test("cancellation after verification does not apply a review", async () => {
  const { events, dependencies } = harness(),
    controller = new AbortController();
  dependencies.verify = () => {
    controller.abort();
    return Promise.resolve(proof);
  };
  await assertRejects(() =>
    handleSpeciesReview(
      request(undefined, controller.signal),
      user,
      admin,
      dependencies,
    )
  );
  assertEquals(events.includes("apply"), false);
});
Deno.test("review request rejects client authority and bounded contract drift", () => {
  const valid = {
    scan_id: scanID,
    expected_revision: 0,
    action: "confirm_name",
    scientific_name: "Fixtureus synonym",
  };
  assertEquals(
    parseReviewRequest({ ...valid, scientific_name: " Fixtureus   synonym " })
      .scientific_name,
    "Fixtureus synonym",
  );
  for (
    const invalid of [
      null,
      [],
      { ...valid, user_id: user.id },
      { ...valid, taxon: proof },
      { ...valid, species_id: scanID },
      { ...valid, expected_revision: -1 },
      { ...valid, expected_revision: 2147483647 },
      { ...valid, expected_revision: "0" },
      { ...valid, expected_revision: 0.5 },
      { ...valid, action: "clear" },
      { ...valid, action: "confirm_primary" },
      { ...valid, action: "unknown" },
      { ...valid, action: ["clear"] },
      { ...valid, scientific_name: "x".repeat(161) },
      { ...valid, scientific_name: "bad\nname" },
      { ...valid, scientific_name: "" },
    ]
  ) {
    assertThrows(() => parseReviewRequest(invalid), PublicHttpError);
  }
});
Deno.test("receipt requires coherent identity, original review flags, revision, nulls and exact scan", () => {
  assertEquals(parseReviewReceipt(cleared, scanID), cleared);
  const identity = {
    version: 1,
    species_id: scanID,
    scientific_name: "Fixtureus accepted",
    common_name: null,
    gbif_taxon_key: 980001,
  };
  const accepted = {
    ...cleared,
    review: {
      ...cleared.review,
      identity,
      confirmed_species_id: scanID,
      user_review_state: "user_overridden",
      user_identification_override: "Fixtureus synonym",
    },
  };
  assertEquals(
    parseReviewReceipt(accepted, scanID).review.user_confirmed_identification,
    false,
  );
  for (
    const invalid of [
      { ...cleared, schema_version: 2 },
      { ...cleared, scan_id: user.id },
      { ...cleared, review: { ...cleared.review, revision: -1 } },
      { ...cleared, review: { ...cleared.review, identity: undefined } },
      {
        ...cleared,
        review: { ...cleared.review, confirmed_species_id: scanID },
      },
      { ...accepted, review: { ...accepted.review, revision: 0 } },
      {
        ...accepted,
        review: { ...accepted.review, user_confirmed_identification: true },
      },
      {
        ...accepted,
        review: {
          ...accepted.review,
          identity: { ...identity, gbif_taxon_key: 0 },
        },
      },
      {
        ...accepted,
        review: {
          ...accepted.review,
          identity: { ...identity, common_name: "Untrusted" },
        },
      },
      {
        ...cleared,
        review: { ...cleared.review, user_review_state: "unknown" },
      },
    ]
  ) assertThrows(() => parseReviewReceipt(invalid, scanID));
});
Deno.test("authentication failure invokes no review work", async () => {
  const { events, dependencies } = harness();
  const names = ["SUPABASE_URL", "MERIAN_SUPABASE_SERVER_API_KEY"],
    prior = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], "sb_secret_" + "a".repeat(32));
  try {
    const result = await handleAuthenticatedSpeciesReview(
      request(),
      () =>
        Promise.resolve({
          user: null,
          response: new Response(null, { status: 401 }),
        }),
      dependencies,
    );
    assertEquals(result.status, 401);
    assertEquals(events, []);
    assertEquals(result.headers.get("Cache-Control"), "private, no-store");
  } finally {
    names.forEach((name, index) => {
      const value = prior[index];
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    });
  }
});
