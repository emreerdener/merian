import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { requireLegacyReview } from "./legacyReview.ts";
import { findTarget } from "../../review-scan-identification/db.ts";
import { findReviewTarget } from "../../confirm-scan-species/db.ts";
const owner = "00000000-0000-4000-8000-000000000001";
const scan = "00000000-0000-4000-8000-000000000002";
Deno.test("both legacy target lookups fence enrolled history before reading scan evidence", async () => {
  for (const find of [findTarget, findReviewTarget]) {
    const calls: string[] = [];
    const admin = {
      rpc(name: string, args: unknown) {
        calls.push(name);
        assertEquals(args, { p_user_id: owner, p_scan_id: scan });
        return Promise.resolve({
          error: { message: "analysis_bound_review_required" },
        });
      },
      from() {
        throw new Error("Legacy evidence must not be read");
      },
    } as unknown as SupabaseClient;
    await assertRejects(
      () => find(admin, owner, scan),
      Error,
      "Review this identification",
    );
    assertEquals(calls, ["require_legacy_scan_review"]);
  }
});
Deno.test("legacy preflight admits success but fails closed on unavailable admission", async () => {
  for (
    const message of [
      null,
      "identification_review_not_found",
      "database unavailable",
    ]
  ) {
    const admin = {
      rpc: () => Promise.resolve({ error: message ? { message } : null }),
    } as unknown as SupabaseClient;
    if (message) {
      await assertRejects(() => requireLegacyReview(admin, owner, scan));
    } else await requireLegacyReview(admin, owner, scan);
  }
});
