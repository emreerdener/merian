import { assertEquals, assertThrows } from "@std/assert";
import {
  candidateMerianUserIds,
  parseRevenueCatWebhook,
  RevenueCatPayloadError,
  revenueCatWebhookSubjects,
} from "./protocol.ts";

function webhookBody(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    api_version: "1.0",
    event: {
      id: "event-123",
      type: "RENEWAL",
      event_timestamp_ms: 1_750_000_000_000,
      app_user_id: "550e8400-e29b-41d4-a716-446655440000",
      original_app_user_id: "$RCAnonymousID:original",
      aliases: ["$RCAnonymousID:alias"],
      ...overrides,
    },
  });
}

Deno.test("webhook parser requires RevenueCat's durable event identity and timestamp", () => {
  const event = parseRevenueCatWebhook(webhookBody());
  assertEquals(event.id, "event-123");
  assertEquals(event.type, "RENEWAL");
  assertEquals(event.eventTimestampMs, 1_750_000_000_000);

  assertThrows(
    () => parseRevenueCatWebhook(webhookBody({ id: undefined })),
    RevenueCatPayloadError,
  );
  assertThrows(
    () => parseRevenueCatWebhook(webhookBody({ event_timestamp_ms: 1.5 })),
    RevenueCatPayloadError,
  );
});

Deno.test("Merian identity resolution prefers current id, then original and aliases", () => {
  const event = parseRevenueCatWebhook(
    webhookBody({
      app_user_id: "$RCAnonymousID:current",
      original_app_user_id: "550E8400-E29B-41D4-A716-446655440001",
      aliases: [
        "550e8400-e29b-41d4-a716-446655440002",
        "550e8400-e29b-41d4-a716-446655440001",
        "not-a-uuid",
      ],
    }),
  );

  assertEquals(candidateMerianUserIds(event), [
    "550e8400-e29b-41d4-a716-446655440001",
    "550e8400-e29b-41d4-a716-446655440002",
  ]);
});

Deno.test("anonymous RevenueCat events have no Merian user candidate", () => {
  const event = parseRevenueCatWebhook(
    webhookBody({
      app_user_id: "$RCAnonymousID:current",
      original_app_user_id: "$RCAnonymousID:original",
      aliases: ["$RCAnonymousID:alias"],
    }),
  );

  assertEquals(candidateMerianUserIds(event), []);
});

Deno.test("the tombstone UUID is never a RevenueCat target", () => {
  const event = parseRevenueCatWebhook(
    webhookBody({
      app_user_id: "00000000-0000-0000-0000-000000000000",
      aliases: ["550e8400-e29b-41d4-a716-446655440003"],
    }),
  );

  assertEquals(candidateMerianUserIds(event), [
    "550e8400-e29b-41d4-a716-446655440003",
  ]);
});

Deno.test("TRANSFER creates independent source and destination subjects", () => {
  const event = parseRevenueCatWebhook(
    webhookBody({
      type: "TRANSFER",
      app_user_id: undefined,
      original_app_user_id: undefined,
      aliases: undefined,
      transferred_from: [
        "$RCAnonymousID:source",
        "550E8400-E29B-41D4-A716-446655440010",
      ],
      transferred_to: [
        "$RCAnonymousID:destination",
        "550e8400-e29b-41d4-a716-446655440011",
      ],
    }),
  );

  assertEquals(revenueCatWebhookSubjects(event), [
    {
      kind: "transfer_source",
      lookupAppUserId: "550E8400-E29B-41D4-A716-446655440010",
      candidateUserIds: ["550e8400-e29b-41d4-a716-446655440010"],
    },
    {
      kind: "transfer_destination",
      lookupAppUserId: "550e8400-e29b-41d4-a716-446655440011",
      candidateUserIds: ["550e8400-e29b-41d4-a716-446655440011"],
    },
  ]);
});

Deno.test("TRANSFER requires both RevenueCat customer groups", () => {
  assertThrows(
    () =>
      parseRevenueCatWebhook(
        webhookBody({
          type: "TRANSFER",
          app_user_id: undefined,
          transferred_from: ["550e8400-e29b-41d4-a716-446655440010"],
          transferred_to: [],
        }),
      ),
    RevenueCatPayloadError,
  );
});
