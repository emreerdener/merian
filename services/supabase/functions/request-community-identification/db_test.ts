import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { communityRequestMatchesIdentity } from "./db.ts";

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
