import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import {
  recordResendAccountDeletionEvent,
  ResendAccountDeletionDatabaseError,
} from "./db.ts";
import type { ResendAccountDeletionEvent } from "./protocol.ts";

const EVENT: ResendAccountDeletionEvent = {
  relevant: true,
  type: "email.delivered",
  createdAt: "2026-08-07T12:00:00.000Z",
  emailId: "resend-email-1",
  attemptId: "00000000-0000-4000-8000-00000000d501",
};

function clientReturning(data: unknown, error: unknown = null): SupabaseClient {
  return {
    rpc: (name: string, parameters: unknown) => {
      assertEquals(name, "record_account_deletion_manual_revocation_event");
      assertEquals(parameters, {
        p_attempt_token: EVENT.attemptId,
        p_provider_event_id: "msg-account-deletion-1",
        p_provider_delivery_id: EVENT.emailId,
        p_event_type: EVENT.type,
        p_provider_created_at: EVENT.createdAt,
      });
      return Promise.resolve({ data, error });
    },
  } as unknown as SupabaseClient;
}

Deno.test("Resend database boundary forwards only bounded event metadata", async () => {
  assertEquals(
    await recordResendAccountDeletionEvent(
      EVENT,
      "msg-account-deletion-1",
      clientReturning("delivered"),
    ),
    "delivered",
  );
});

Deno.test("Resend database boundary rejects ambiguous RPC outcomes", async () => {
  await assertRejects(
    () =>
      recordResendAccountDeletionEvent(
        EVENT,
        "msg-account-deletion-1",
        clientReturning("completed"),
      ),
    ResendAccountDeletionDatabaseError,
    "invalid state",
  );
});

Deno.test("Resend database boundary retains provider-independent error codes", async () => {
  await assertRejects(
    () =>
      recordResendAccountDeletionEvent(
        EVENT,
        "msg-account-deletion-1",
        clientReturning(null, {
          code: "40001",
          message: "serialization failure",
        }),
      ),
    ResendAccountDeletionDatabaseError,
    "serialization failure",
  );
});
