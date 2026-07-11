import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { requireApprovedAudioMedia } from "./db.ts";

const audioRow = {
  kind: "audio" as const,
  url: "https://media.merian.app/audio.wav",
  thumbnail_url: "",
  order_index: 0,
  duration_seconds: null,
  has_audio: true,
};

Deno.test("audio approval is a strict prerequisite for sharing", async () => {
  let calls = 0;
  await requireApprovedAudioMedia([audioRow], async () => {
    calls += 1;
    return { approved: true, model: "test" };
  });
  assertEquals(calls, 1);
});

Deno.test("flagged audio rejects the share before persistence", async () => {
  const error = await assertRejects(
    () => requireApprovedAudioMedia([audioRow], async () => ({
      approved: false,
      model: "test",
    })),
    Error,
    "did not pass moderation",
  ) as Error & { status?: number };
  assertEquals(error.status, 422);
});

Deno.test("moderation failure rejects the share as unavailable", async () => {
  const error = await assertRejects(
    () => requireApprovedAudioMedia([audioRow], async () => {
      throw new Error("provider unavailable");
    }),
    Error,
    "Nothing was shared",
  ) as Error & { status?: number };
  assertEquals(error.status, 503);
});
