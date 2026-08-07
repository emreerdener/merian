import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import {
  ResendAccountDeletionDatabaseError,
  type ResendAccountDeletionEventOutcome,
} from "./db.ts";
import { createResendAccountDeletionWebhookHandler } from "./handler.ts";
import { createResendSignature } from "./signature.ts";

const supabaseAdmin = {} as SupabaseClient;
const SECRET = "whsec_plJ3nmyCDGBKInavdOK15jsl";
const MESSAGE_ID = "msg_account_deletion_1";
const TIMESTAMP = 1_786_104_000;
const ATTEMPT_ID = "00000000-0000-4000-8000-00000000d501";

function body(type = "email.delivered"): string {
  return JSON.stringify({
    type,
    created_at: "2026-08-07T12:00:00.000Z",
    data: {
      email_id: "resend-email-1",
      to: ["private@example.invalid"],
      subject: "private",
      tags: {
        purpose: "apple_manual_revocation",
        attempt_id: ATTEMPT_ID,
      },
    },
  });
}

async function signedRequest(rawBody = body()): Promise<Request> {
  const signature = await createResendSignature(
    SECRET,
    MESSAGE_ID,
    TIMESTAMP,
    rawBody,
  );
  return new Request("https://example.invalid/webhook", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "svix-id": MESSAGE_ID,
      "svix-timestamp": String(TIMESTAMP),
      "svix-signature": signature,
    },
    body: rawBody,
  });
}

Deno.test("signed Resend delivery records only verified correlation state", async () => {
  let captured: unknown;
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: SECRET,
    now: () => TIMESTAMP * 1_000,
    recordEvent: (event, messageId) => {
      captured = { event, messageId };
      return Promise.resolve("delivered");
    },
  });
  const response = await handler(await signedRequest());

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { success: true, outcome: "delivered" });
  assertEquals(captured, {
    event: {
      relevant: true,
      type: "email.delivered",
      createdAt: "2026-08-07T12:00:00.000Z",
      emailId: "resend-email-1",
      attemptId: ATTEMPT_ID,
    },
    messageId: MESSAGE_ID,
  });
});

Deno.test("signature verification happens before JSON parsing or database work", async () => {
  let databaseCalled = false;
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: SECRET,
    now: () => TIMESTAMP * 1_000,
    recordEvent: () => {
      databaseCalled = true;
      return Promise.resolve("delivered");
    },
  });
  const response = await handler(
    new Request("https://example.invalid/webhook", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "svix-id": MESSAGE_ID,
        "svix-timestamp": String(TIMESTAMP),
        "svix-signature": `v1,${"A".repeat(43)}=`,
      },
      body: "not-json",
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(databaseCalled, false);
});

Deno.test("malformed webhook configuration fails as unavailable", async () => {
  let databaseCalled = false;
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: "whsec_not-valid-base64-material",
    now: () => TIMESTAMP * 1_000,
    recordEvent: () => {
      databaseCalled = true;
      return Promise.resolve("delivered");
    },
  });
  const response = await handler(await signedRequest());

  assertEquals(response.status, 503);
  assertEquals(databaseCalled, false);
});

Deno.test("unrelated signed Resend events are acknowledged without mutation", async () => {
  let databaseCalled = false;
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: SECRET,
    now: () => TIMESTAMP * 1_000,
    recordEvent: () => {
      databaseCalled = true;
      return Promise.resolve("delivered");
    },
  });
  const response = await handler(await signedRequest(body("email.opened")));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { success: true, outcome: "ignored" });
  assertEquals(databaseCalled, false);
});

Deno.test("retryable database failures request a provider retry", async () => {
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: SECRET,
    now: () => TIMESTAMP * 1_000,
    recordEvent: () =>
      Promise.reject(
        new ResendAccountDeletionDatabaseError("database unavailable", "40001"),
      ),
  });
  const response = await handler(await signedRequest());

  assertEquals(response.status, 503);
  assertEquals(response.headers.get("Retry-After"), "30");
});

Deno.test("conflicting durable event identifiers fail closed", async () => {
  const handler = createResendAccountDeletionWebhookHandler({
    supabaseAdmin,
    signingSecret: SECRET,
    now: () => TIMESTAMP * 1_000,
    recordEvent: () =>
      Promise.reject(
        new ResendAccountDeletionDatabaseError(
          "manual_revocation_event_id_conflict",
          "23505",
        ),
      ),
  });
  const response = await handler(await signedRequest());

  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "event_identifier_conflict");
});

Deno.test("handler preserves every durable database outcome", async () => {
  const outcomes: ResendAccountDeletionEventOutcome[] = [
    "delivery_pending",
    "retry_required",
    "duplicate",
    "ignored_unknown_attempt",
    "ignored_stale_attempt",
  ];
  for (const outcome of outcomes) {
    const handler = createResendAccountDeletionWebhookHandler({
      supabaseAdmin,
      signingSecret: SECRET,
      now: () => TIMESTAMP * 1_000,
      recordEvent: () => Promise.resolve(outcome),
    });
    const response = await handler(await signedRequest());
    assertEquals(response.status, 200);
    assertEquals((await response.json()).outcome, outcome);
  }
});
