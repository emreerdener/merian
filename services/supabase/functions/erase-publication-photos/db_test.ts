import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicationPhotoErasureRepository } from "./db.ts";
Deno.test("photo erasure RPCs bind object and original claim without owner lookup", async () => {
  const calls: unknown[] = [];
  const client = {
    rpc: (name: string, args: unknown) => ({
      abortSignal: (signal: AbortSignal) => {
        calls.push([name, args, signal instanceof AbortSignal]);
        return Promise.resolve({ data: true, error: null });
      },
    }),
  } as unknown as SupabaseClient;
  const repository = publicationPhotoErasureRepository(client);
  await repository.claim("object");
  await repository.finish("object", "claim", false);
  assertEquals(calls, [["claim_publication_photo_erasure", {
    p_object: "object",
  }, true], ["finish_publication_photo_erasure", {
    p_object: "object",
    p_claim: "claim",
    p_success: false,
  }, true]]);
});
Deno.test("photo erasure RPC failure omits database details", async () => {
  const client = {
    rpc: () => ({
      abortSignal: () =>
        Promise.resolve({
          data: null,
          error: { message: "private diagnostic" },
        }),
    }),
  } as unknown as SupabaseClient;
  await assertRejects(
    () => publicationPhotoErasureRepository(client).claim(null),
    Error,
    "publication_photo_erasure_unavailable",
  );
});
