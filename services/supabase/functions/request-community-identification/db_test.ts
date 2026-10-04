import { assertEquals, assertRejects } from "@std/assert";
import {
  communityRequestMatchesIdentity,
  requestCommunityIdentification,
} from "./db.ts";

Deno.test("Community response identity accepts UUID case normalization only", () => {
  const scanId = "A1B2C3D4-0000-4000-8000-000000000001";
  const userId = "B1C2D3E4-0000-4000-8000-000000000002";
  const row = {
    scan_id: scanId.toLowerCase(),
    requested_by: userId.toLowerCase(),
  };

  assertEquals(communityRequestMatchesIdentity(row, scanId, userId), true);
  assertEquals(
    communityRequestMatchesIdentity(
      row,
      "A1B2C3D4-0000-4000-8000-000000000099",
      userId,
    ),
    false,
  );
  assertEquals(
    communityRequestMatchesIdentity(
      row,
      scanId,
      "B1C2D3E4-0000-4000-8000-000000000099",
    ),
    false,
  );
});

Deno.test("enrolled community request refuses before media restoration, taxonomy, moderation or publication", async () => {
  const calls: string[] = [];
  const admin = {
    rpc(name: string) {
      calls.push(name);
      return Promise.resolve({
        error: { message: "analysis_bound_review_required" },
      });
    },
    from() {
      throw new Error("Media eligibility and restoration must not run");
    },
  } as unknown as import("@supabase/supabase-js").SupabaseClient;
  const error = await assertRejects(() =>
    requestCommunityIdentification(
      "00000000-0000-4000-8000-000000000001",
      "00000000-0000-4000-8000-000000000002",
      null,
      null,
      null,
      [],
      [],
      [],
      admin,
      {
        beforeProvider() {
          throw new Error("Moderation quota must not be admitted");
        },
      },
    )
  );
  assertEquals((error as { status?: number }).status, 409);
  assertEquals(
    (error as { code?: string }).code,
    "analysis_bound_review_required",
  );
  assertEquals(calls, ["require_legacy_scan_review"]);
});
