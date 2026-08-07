import { assertEquals, assertStringIncludes } from "@std/assert";
import { sendManualAppleRevocationEmail } from "./manualRevocationEmail.ts";

const JOB_ID = "00000000-0000-4000-8000-00000000d401";
const IDEMPOTENCY_KEY = `account-deletion-manual-apple/${JOB_ID}`;

Deno.test("manual Apple revocation email is idempotent and contains official instructions", async () => {
  const captured: Request[] = [];
  const requestBodies: string[] = [];
  const receivedSignals: Array<AbortSignal | null | undefined> = [];
  const options = {
    apiKey: "re_test_key",
    from: "Naturebook Privacy <privacy@example.invalid>",
    fetcher: (input: RequestInfo | URL, init?: RequestInit) => {
      captured.push(new Request(input, init));
      requestBodies.push(typeof init?.body === "string" ? init.body : "");
      receivedSignals.push(init?.signal);
      return Promise.resolve(
        new Response(JSON.stringify({ id: "resend-message-1" })),
      );
    },
  };
  const result = await sendManualAppleRevocationEmail(
    "apple-relay@example.invalid",
    JOB_ID,
    IDEMPOTENCY_KEY,
    options,
  );
  const retryResult = await sendManualAppleRevocationEmail(
    "apple-relay@example.invalid",
    JOB_ID,
    IDEMPOTENCY_KEY,
    options,
  );

  assertEquals(result, {
    succeeded: true,
    providerDeliveryId: "resend-message-1",
  });
  assertEquals(retryResult, result);
  assertEquals(captured.length, 2);
  assertEquals(requestBodies[1], requestBodies[0]);
  assertEquals(
    captured[0].headers.get("Idempotency-Key"),
    IDEMPOTENCY_KEY,
  );
  assertEquals(
    receivedSignals.every((signal) => signal instanceof AbortSignal),
    true,
  );
  const body = JSON.parse(requestBodies[0]);
  assertEquals(body.from, "Naturebook Privacy <privacy@example.invalid>");
  assertEquals(body.to, ["apple-relay@example.invalid"]);
  assertStringIncludes(body.subject, "Sign in with Apple");
  assertStringIncludes(body.text, "https://account.apple.com/");
  assertStringIncludes(body.text, "https://support.apple.com/102571");
  assertStringIncludes(body.html, "Sign-In &amp; Security");
  assertEquals(body.tags, [
    { name: "purpose", value: "apple_manual_revocation" },
    { name: "attempt_id", value: JOB_ID },
  ]);
  assertStringIncludes(
    body.html,
    "Your Naturebook account deletion is being finalized",
  );
});

Deno.test("manual Apple revocation email fails closed without required secrets", async () => {
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      {
        apiKey: "",
        from: "Naturebook Privacy <privacy@example.invalid>",
      },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_email_not_configured",
    },
  );
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      { apiKey: "re_test_key", from: "" },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_sender_not_configured",
    },
  );
});

Deno.test("manual Apple revocation email keeps provider failures retryable", async () => {
  const result = await sendManualAppleRevocationEmail(
    "user@example.invalid",
    JOB_ID,
    IDEMPOTENCY_KEY,
    {
      apiKey: "re_test_key",
      from: "Naturebook Privacy <privacy@example.invalid>",
      fetcher: () =>
        Promise.resolve(
          new Response(JSON.stringify({ message: "unavailable" }), {
            status: 503,
          }),
        ),
    },
  );

  assertEquals(result, {
    succeeded: false,
    errorCode: "manual_revocation_email_http_503",
  });
});

Deno.test("manual Apple revocation email treats network and ambiguous success as retryable", async () => {
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      {
        apiKey: "re_test_key",
        from: "Naturebook Privacy <privacy@example.invalid>",
        fetcher: () => Promise.reject(new TypeError("network unavailable")),
      },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_email_unavailable",
    },
  );
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      {
        apiKey: "re_test_key",
        from: "Naturebook Privacy <privacy@example.invalid>",
        fetcher: () =>
          Promise.resolve(new Response(JSON.stringify({ accepted: true }))),
      },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_email_response_ambiguous",
    },
  );
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      {
        apiKey: "re_test_key",
        from: "Naturebook Privacy <privacy@example.invalid>",
        fetcher: () =>
          Promise.resolve(
            new Response(JSON.stringify({ id: "unsafe provider id" })),
          ),
      },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_email_response_ambiguous",
    },
  );
});

Deno.test("manual Apple revocation email rejects unsafe header inputs", async () => {
  assertEquals(
    await sendManualAppleRevocationEmail(
      "user@example.invalid\r\nBcc: attacker@example.invalid",
      JOB_ID,
      IDEMPOTENCY_KEY,
      {
        apiKey: "re_test_key",
        from: "Naturebook Privacy <privacy@example.invalid>",
      },
    ),
    {
      succeeded: false,
      errorCode: "manual_revocation_email_input_invalid",
    },
  );
});
