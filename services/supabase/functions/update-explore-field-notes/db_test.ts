import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { prepareExplorePostMediaRows } from "./db.ts";

Deno.test("edited audio media is approved before its spectrogram is attached", async () => {
  const calls: string[] = [];
  const rows = [{
    kind: "audio" as const,
    url: "https://media.merian.app/public_uploads/pro/user/clip.wav",
    thumbnail_url: "",
    order_index: 0,
    duration_seconds: null,
    has_audio: true,
  }];

  const result = await prepareExplorePostMediaRows(
    "00000000-0000-0000-0000-000000000001",
    "00000000-0000-0000-0000-000000000002",
    rows,
    {} as SupabaseClient,
    () => {
      calls.push("approve");
      return Promise.resolve();
    },
    (_scanId, approvedRows) => {
      calls.push("attach");
      return Promise.resolve(approvedRows.map((row) => ({
        ...row,
        thumbnail_url:
          "https://media.merian.app/public_uploads/pro/user/spectrogram.png",
      })));
    },
  );

  assertEquals(calls, ["approve", "attach"]);
  assertEquals(
    result[0].thumbnail_url,
    "https://media.merian.app/public_uploads/pro/user/spectrogram.png",
  );
});
