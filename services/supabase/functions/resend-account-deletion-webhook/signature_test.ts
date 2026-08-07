import { assert, assertEquals } from "@std/assert";
import { createResendSignature, verifyResendSignature } from "./signature.ts";

const SECRET = "whsec_plJ3nmyCDGBKInavdOK15jsl";
const MESSAGE_ID = "msg_loFOjxBNrRLzqYUf";
const TIMESTAMP = 1_731_705_121;
const BODY = '{"event_type":"ping","data":{"success":true}}';

Deno.test("Resend signature verifier matches the published Svix vector", async () => {
  const signature = await createResendSignature(
    SECRET,
    MESSAGE_ID,
    TIMESTAMP,
    BODY,
  );
  assertEquals(signature, "v1,rAvfW3dJ/X/qxhsaXPOyyCGmRKsaKWcsNccKXlIktD0=");
  assertEquals(
    await verifyResendSignature(
      {
        id: MESSAGE_ID,
        timestamp: String(TIMESTAMP),
        signature,
      },
      SECRET,
      BODY,
      TIMESTAMP * 1_000,
    ),
    { messageId: MESSAGE_ID, timestampSeconds: TIMESTAMP },
  );
});

Deno.test("Resend signature verifier uses exact raw bytes and accepts key rotation signatures", async () => {
  const signature = await createResendSignature(
    SECRET,
    MESSAGE_ID,
    TIMESTAMP,
    BODY,
  );
  assert(
    await verifyResendSignature(
      {
        id: MESSAGE_ID,
        timestamp: String(TIMESTAMP),
        signature: `v1,${"A".repeat(43)}= ${signature}`,
      },
      SECRET,
      new TextEncoder().encode(BODY),
      TIMESTAMP * 1_000,
    ),
  );
  assertEquals(
    await verifyResendSignature(
      {
        id: MESSAGE_ID,
        timestamp: String(TIMESTAMP),
        signature,
      },
      SECRET,
      `${BODY}\n`,
      TIMESTAMP * 1_000,
    ),
    null,
  );
});

Deno.test("Resend signature verifier rejects stale and malformed envelopes", async () => {
  const signature = await createResendSignature(
    SECRET,
    MESSAGE_ID,
    TIMESTAMP,
    BODY,
  );
  assertEquals(
    await verifyResendSignature(
      {
        id: MESSAGE_ID,
        timestamp: String(TIMESTAMP),
        signature,
      },
      SECRET,
      BODY,
      (TIMESTAMP + 301) * 1_000,
    ),
    null,
  );
  assertEquals(
    await verifyResendSignature(
      { id: MESSAGE_ID, timestamp: String(TIMESTAMP), signature: null },
      SECRET,
      BODY,
      TIMESTAMP * 1_000,
    ),
    null,
  );
  assertEquals(
    await verifyResendSignature(
      {
        id: MESSAGE_ID,
        timestamp: String(TIMESTAMP),
        signature,
      },
      "invalid-secret",
      BODY,
      TIMESTAMP * 1_000,
    ),
    null,
  );
});
