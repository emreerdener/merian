import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { allowedReferenceMedia } from "./viewerMedia.ts";

Deno.test("viewer media filtering batches candidates, fails closed, and preserves public projection", async () => {
  const calls: number[] = [];
  const admin = {
    rpc: (_name: string, args: { candidate_urls: string[] }) => {
      calls.push(args.candidate_urls.length);
      return Promise.resolve({
        data: args.candidate_urls.filter((url) => url !== "hidden"),
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const candidates = [
    "hidden",
    ...Array.from({ length: 501 }, (_, i) => `https://example.com/${i}`),
  ];
  const allowed = await allowedReferenceMedia(candidates, "viewer", admin);
  assertEquals(calls, [500, 2]);
  assertEquals(allowed.has("hidden"), false);
  calls.length = 0;
  assertEquals(
    (await allowedReferenceMedia(["hidden"], undefined, admin)).has("hidden"),
    true,
  );
  assertEquals(calls, []);
  const broken = {
    rpc: () => Promise.resolve({ error: {}, data: null }),
  } as unknown as SupabaseClient;
  await assertRejects(() =>
    allowedReferenceMedia(["hidden"], "viewer", broken)
  );
});
