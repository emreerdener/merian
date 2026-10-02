import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { handleReview } from "./index.ts";
import { parseReceipt } from "./contract.ts";
import { publicHttpError } from "../_shared/http.ts";
const id = "00000000-0000-4000-8000-000000000001";
const operation = "00000000-0000-4000-8000-000000000002";
const user = { id } as User;
const admin = {} as SupabaseClient;
const base = {
  scan_id: id,
  expected_revision: 0,
  operation_id: operation,
  action: "reject",
  expected_species_review_revision: null,
};
const receipt = parseReceipt({
  schema_version: 1,
  scan_id: id,
  confirmed_species_id: null,
  species_review: null,
  review: {
    version: 1,
    revision: 1,
    state: "ai_rejected",
    origin_scan_id: id,
    origin_identification: null,
    operation_id: operation,
    operation_digest: null,
    community: null,
  },
}, id);
function request(value: unknown) {
  return new Request("https://example.invalid/review-scan-identification", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(value),
  });
}
function harness(revision = 0) {
  const calls: string[] = [];
  const deps: NonNullable<Parameters<typeof handleReview>[3]> = {
    find: (_db, owner, scan) => {
      assertEquals(owner, id);
      assertEquals(scan, id);
      calls.push("find");
      return Promise.resolve({
        revision,
        primary: null,
        name: "Fixtureus species",
      });
    },
    admit: () => {
      calls.push("admit");
      return Promise.resolve();
    },
    verify: () => {
      calls.push("verify");
      return Promise.resolve({
        scientific_name: "Fixtureus species",
        gbif_taxon_key: 987600001,
        rank: "SPECIES",
        status: "ACCEPTED",
        kingdom: "Plantae",
      });
    },
    apply: () => {
      calls.push("apply");
      return Promise.resolve(receipt);
    },
  };
  return { calls, deps };
}
Deno.test("owner rejection has no taxonomy or quota dependency", async () => {
  const { calls, deps } = harness();
  const response = await handleReview(request(base), user, admin, deps);
  assertEquals(calls, ["find", "apply"]);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
});
Deno.test("confirmation retry checks the receipt before quota and taxonomy", async () => {
  const { calls, deps } = harness(1);
  await handleReview(
    request({
      ...base,
      action: "confirm_name",
      scientific_name: "Fixtureus species",
    }),
    user,
    admin,
    deps,
  );
  assertEquals(calls, ["find", "apply"]);
});
Deno.test("a mismatched retry propagates its atomic revision conflict", async () => {
  const { calls, deps } = harness(1);
  deps.apply = () =>
    Promise.reject(publicHttpError(
      409,
      "Changed",
      "identification_review_revision_conflict",
    ));
  await assertRejects(() => handleReview(request(base), user, admin, deps));
  assertEquals(calls, ["find"]);
});
Deno.test("fresh acceptance verifies taxonomy before applying", async () => {
  const { calls, deps } = harness();
  await handleReview(
    request({
      ...base,
      action: "confirm_name",
      scientific_name: "Fixtureus species",
    }),
    user,
    admin,
    deps,
  );
  assertEquals(calls, ["find", "admit", "verify", "apply"]);
});
Deno.test("legacy records reject invented species review revisions", async () => {
  const { calls, deps } = harness();
  await assertRejects(() =>
    handleReview(
      request({ ...base, expected_species_review_revision: 0 }),
      user,
      admin,
      deps,
    )
  );
  assertEquals(calls, ["find"]);
});
