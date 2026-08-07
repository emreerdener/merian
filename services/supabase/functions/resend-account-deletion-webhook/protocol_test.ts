import { assertEquals, assertThrows } from "@std/assert";
import {
  parseResendAccountDeletionEvent,
  ResendPayloadError,
} from "./protocol.ts";

const ATTEMPT_ID = "00000000-0000-4000-8000-00000000d501";

function payload(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    type: "email.delivered",
    created_at: "2026-08-07T12:00:00.000Z",
    data: {
      email_id: "resend-email-1",
      to: ["must-not-be-read@example.invalid"],
      subject: "must not be persisted",
      tags: {
        purpose: "apple_manual_revocation",
        attempt_id: ATTEMPT_ID,
      },
    },
    ...overrides,
  });
}

Deno.test("Resend protocol extracts only bounded correlation metadata", () => {
  assertEquals(parseResendAccountDeletionEvent(payload()), {
    relevant: true,
    type: "email.delivered",
    createdAt: "2026-08-07T12:00:00.000Z",
    emailId: "resend-email-1",
    attemptId: ATTEMPT_ID,
  });
});

Deno.test("Resend protocol ignores unrelated email events and tags", () => {
  assertEquals(
    parseResendAccountDeletionEvent(payload({ type: "email.opened" })),
    { relevant: false },
  );
  assertEquals(
    parseResendAccountDeletionEvent(payload({
      data: {
        email_id: "other-email",
        tags: { purpose: "another_workflow", attempt_id: ATTEMPT_ID },
      },
    })),
    { relevant: false },
  );
});

Deno.test("Resend protocol fails closed for malformed correlated events", () => {
  assertThrows(
    () =>
      parseResendAccountDeletionEvent(payload({
        data: {
          email_id: "resend-email-1",
          tags: {
            purpose: "apple_manual_revocation",
            attempt_id: "not-a-uuid",
          },
        },
      })),
    ResendPayloadError,
  );
  assertThrows(
    () => parseResendAccountDeletionEvent("not-json"),
    ResendPayloadError,
  );
  assertThrows(
    () =>
      parseResendAccountDeletionEvent(payload({
        data: {
          email_id: "unsafe provider id",
          tags: {
            purpose: "apple_manual_revocation",
            attempt_id: ATTEMPT_ID,
          },
        },
      })),
    ResendPayloadError,
  );
});
