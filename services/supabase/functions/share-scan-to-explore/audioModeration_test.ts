import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { requireApprovedAudioMedia } from "./db.ts";
import {
  exploreShareFailureReason,
  moderationLatencyBucket,
} from "../_shared/exploreAudioTelemetry.ts";

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
  await requireApprovedAudioMedia([audioRow], {
    moderate: () => {
      calls += 1;
      return Promise.resolve({
        approved: true,
        model: "test",
        policyVersion: "test-policy",
      });
    },
  });
  assertEquals(calls, 1);
});

Deno.test("flagged audio rejects the share before persistence", async () => {
  const error = await assertRejects(
    () =>
      requireApprovedAudioMedia([audioRow], {
        moderate: () =>
          Promise.resolve({
            approved: false,
            model: "test",
            policyVersion: "test-policy",
          }),
      }),
    Error,
    "did not pass moderation",
  ) as Error & { status?: number };
  assertEquals(error.status, 422);
});

Deno.test("moderation failure rejects the share as unavailable", async () => {
  const error = await assertRejects(
    () =>
      requireApprovedAudioMedia([audioRow], {
        moderate: () => Promise.reject(new Error("provider unavailable")),
      }),
    Error,
    "Nothing was shared",
  ) as Error & { status?: number };
  assertEquals(error.status, 503);
});

Deno.test("audio moderation emits an approved privacy-safe event", async () => {
  const events: Array<{ event: string; properties: Record<string, unknown> }> =
    [];
  await requireApprovedAudioMedia([audioRow], {
    moderate: () =>
      Promise.resolve({
        approved: true,
        model: "test-model",
        policyVersion: "test-policy",
      }),
    telemetryUserId: "telemetry-user",
    trackEvent: (_user, event, properties = {}) => {
      events.push({ event, properties });
      return Promise.resolve();
    },
  });
  await Promise.resolve();

  assertEquals(events.length, 1);
  assertEquals(events[0].event, "ExploreAudioModerationCompleted");
  assertEquals(events[0].properties.outcome, "approved");
  assertEquals(events[0].properties.media_kind, "audio");
  assertEquals(events[0].properties.model, "test-model");
  const serialized = JSON.stringify(events[0]);
  for (
    const forbidden of [
      "url",
      "transcript",
      "filename",
      "post_id",
      "species",
      "location",
    ]
  ) {
    assertEquals(serialized.includes(forbidden), false);
  }
});

Deno.test("audio moderation emits rejected and provider-error outcomes", async () => {
  const outcomes: unknown[] = [];
  const track = (
    _user: unknown,
    _event: string,
    properties: Record<string, unknown> = {},
  ) => {
    outcomes.push(properties.outcome);
    return Promise.resolve();
  };
  await assertRejects(() =>
    requireApprovedAudioMedia([audioRow], {
      moderate: () =>
        Promise.resolve({
          approved: false,
          model: "test",
          policyVersion: "test-policy",
        }),
      telemetryUserId: "telemetry-user",
      trackEvent: track,
    })
  );
  await assertRejects(() =>
    requireApprovedAudioMedia([audioRow], {
      moderate: () => Promise.reject(new Error("provider unavailable")),
      telemetryUserId: "telemetry-user",
      trackEvent: track,
    })
  );
  await Promise.resolve();
  assertEquals(outcomes, ["rejected", "error"]);
});

Deno.test("telemetry bucketing and share failure reasons stay bounded", () => {
  assertEquals(moderationLatencyBucket(999), "under_1s");
  assertEquals(moderationLatencyBucket(1_000), "1_to_3s");
  assertEquals(moderationLatencyBucket(3_000), "3_to_10s");
  assertEquals(moderationLatencyBucket(10_000), "over_10s");
  assertEquals(
    exploreShareFailureReason({ status: 422 }),
    "moderation_rejected",
  );
  assertEquals(
    exploreShareFailureReason({ status: 503 }),
    "dependency_unavailable",
  );
  assertEquals(exploreShareFailureReason({ status: 400 }), "request_rejected");
  assertEquals(
    exploreShareFailureReason(new Error("database")),
    "publication_failed",
  );
});
