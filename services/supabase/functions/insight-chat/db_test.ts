import { assertEquals, assertRejects } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { fetchOwnedScan } from "./db.ts";

const ownerId = "00000000-0000-4000-8000-000000000001";
const scanId = "00000000-0000-4000-8000-000000000002";

for (const withoutZoom of [false, true]) {
  Deno.test(`owned scan retrieves saved traits (zoom fallback: ${withoutZoom})`, async () => {
    let requests = 0;
    const client = createClient("https://supabase.invalid", "test-key", {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: (input) => {
          requests++;
          const url = new URL(
            input instanceof Request ? input.url : String(input),
          );
          assertEquals(url.pathname, "/rest/v1/scans");
          assertEquals(url.searchParams.get("id"), `eq.${scanId}`);
          const selected = url.searchParams.get("select")?.split(",") ?? [];
          assertEquals(selected.includes("extracted_visual_traits"), true);
          assertEquals(selected.includes("zoom_factor"), requests === 1);
          if (withoutZoom && requests === 1) {
            return Promise.resolve(Response.json({
              code: "42703",
              message: "column scans.zoom_factor does not exist",
            }, { status: 400 }));
          }
          return Promise.resolve(Response.json({
            id: scanId,
            user_id: ownerId,
            extracted_visual_traits: ["White border spots"],
          }));
        },
      },
    });
    const scan = await fetchOwnedScan(ownerId, scanId, client);
    assertEquals(scan?.extracted_visual_traits, ["White border spots"]);
    assertEquals(requests, withoutZoom ? 2 : 1);
  });
}

Deno.test("saved traits do not bypass owned scan authorization", async () => {
  const client = createClient("https://supabase.invalid", "test-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: () =>
        Promise.resolve(Response.json({
          id: scanId,
          user_id: "00000000-0000-4000-8000-000000000003",
          extracted_visual_traits: ["White border spots"],
        })),
    },
  });
  await assertRejects(
    () => fetchOwnedScan(ownerId, scanId, client),
    Error,
    "You do not have permission to chat about this scan.",
  );
});
