import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import { handleAppleCredentialRegistration } from "./handler.ts";

const supabaseAdmin = {} as SupabaseClient;
const userId = "00000000-0000-0000-0000-00000000a101";
const registrationId = "00000000-0000-0000-0000-00000000a102";

function request(): Request {
  return new Request(
    "https://example.test/register-apple-revocation-token",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        registration_id: registrationId,
        authorization_code: "single-use-authorization-code",
        identity_token: "header.payload.signature-that-is-long-enough",
      }),
    },
  );
}

Deno.test("Apple credential registration is idempotent before code exchange", async () => {
  let exchanged = false;
  let stored = false;
  const response = await handleAppleCredentialRegistration(
    request(),
    userId,
    supabaseAdmin,
    {
      registrationExists: () => Promise.resolve(true),
      exchange: () => {
        exchanged = true;
        return Promise.resolve({
          subject: "subject",
          refreshToken: "refresh-token-value-123456789",
        });
      },
      store: () => {
        stored = true;
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(exchanged, false);
  assertEquals(stored, false);
});

Deno.test("Apple credential registration exchanges before one atomic Vault store", async () => {
  const order: string[] = [];
  const response = await handleAppleCredentialRegistration(
    request(),
    userId,
    supabaseAdmin,
    {
      registrationExists: () => {
        order.push("receipt");
        return Promise.resolve(false);
      },
      exchange: () => {
        order.push("exchange");
        return Promise.resolve({
          subject: "apple-subject",
          refreshToken: "refresh-token-value-123456789",
        });
      },
      store: (_client, input) => {
        order.push("store");
        assertEquals(input.userId, userId);
        assertEquals(input.registrationId, registrationId);
        assertEquals(input.appleSubject, "apple-subject");
        return Promise.resolve();
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(order, ["receipt", "exchange", "store"]);
});

Deno.test("Apple credential registration revokes an issued token if Vault persistence fails", async () => {
  const order: string[] = [];
  let receiptChecks = 0;
  let thrownStatus: number | null = null;
  try {
    await handleAppleCredentialRegistration(
      request(),
      userId,
      supabaseAdmin,
      {
        registrationExists: () => {
          receiptChecks += 1;
          return Promise.resolve(false);
        },
        exchange: () => {
          order.push("exchange");
          return Promise.resolve({
            subject: "apple-subject",
            refreshToken: "refresh-token-value-123456789",
          });
        },
        store: () => {
          order.push("store_failed");
          return Promise.reject(new Error("database unavailable"));
        },
        compensate: (token) => {
          order.push(`revoke:${token}`);
          return Promise.resolve({ succeeded: true });
        },
      },
    );
  } catch (error) {
    thrownStatus = (error as { status?: number }).status ?? null;
  }

  assertEquals(thrownStatus, 503);
  assertEquals(receiptChecks, 2);
  assertEquals(order, [
    "exchange",
    "store_failed",
    "revoke:refresh-token-value-123456789",
  ]);
});

Deno.test("Apple credential registration reconciles a committed receipt after a lost store response", async () => {
  let receiptChecks = 0;
  let compensated = false;
  const response = await handleAppleCredentialRegistration(
    request(),
    userId,
    supabaseAdmin,
    {
      registrationExists: () => {
        receiptChecks += 1;
        return Promise.resolve(receiptChecks === 2);
      },
      exchange: () =>
        Promise.resolve({
          subject: "apple-subject",
          refreshToken: "refresh-token-value-123456789",
        }),
      store: () => Promise.reject(new Error("response lost after commit")),
      compensate: () => {
        compensated = true;
        return Promise.resolve({ succeeded: true });
      },
    },
  );

  assertEquals(response.status, 200);
  assertEquals(receiptChecks, 2);
  assertEquals(compensated, false);
});
