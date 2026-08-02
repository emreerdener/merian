import { assert, assertEquals } from "@std/assert";
import {
  createRevenueCatSignature,
  sha256Hex,
  verifyRevenueCatSignature,
} from "./signature.ts";

const NOW_MS = 1_750_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1000);
const SECRET = "revenuecat-signing-secret-for-unit-tests";
const RAW_BODY = '{"event":{"id":"event-123"}}';

Deno.test("RevenueCat HMAC verifies the exact timestamp-prefixed raw body", async () => {
  const header = await createRevenueCatSignature(
    SECRET,
    NOW_SECONDS,
    RAW_BODY,
  );

  assertEquals(
    await verifyRevenueCatSignature(header, SECRET, RAW_BODY, NOW_MS),
    { timestampSeconds: NOW_SECONDS },
  );
  assertEquals(
    await verifyRevenueCatSignature(
      header,
      SECRET,
      `${RAW_BODY}\n`,
      NOW_MS,
    ),
    null,
  );
});

Deno.test("RevenueCat HMAC signs exact bytes before UTF-8 decoding", async () => {
  const rawBytes = new Uint8Array([0xff, 0x00, 0x7f]);
  const header = await createRevenueCatSignature(
    SECRET,
    NOW_SECONDS,
    rawBytes,
  );

  assert(
    await verifyRevenueCatSignature(
      header,
      SECRET,
      rawBytes,
      NOW_MS,
    ),
  );
  assertEquals(
    await verifyRevenueCatSignature(
      header,
      SECRET,
      new Uint8Array([0xfe, 0x00, 0x7f]),
      NOW_MS,
    ),
    null,
  );
});

Deno.test("RevenueCat HMAC rejects invalid, stale, and future signatures", async () => {
  const header = await createRevenueCatSignature(
    SECRET,
    NOW_SECONDS,
    RAW_BODY,
  );
  assertEquals(
    await verifyRevenueCatSignature(header, "wrong-secret", RAW_BODY, NOW_MS),
    null,
  );

  for (const offset of [-301, 301]) {
    const timestamp = NOW_SECONDS + offset;
    const outsideWindow = await createRevenueCatSignature(
      SECRET,
      timestamp,
      RAW_BODY,
    );
    assertEquals(
      await verifyRevenueCatSignature(
        outsideWindow,
        SECRET,
        RAW_BODY,
        NOW_MS,
      ),
      null,
    );
  }
});

Deno.test("RevenueCat HMAC accepts one matching v1 value without weakening parsing", async () => {
  const valid = await createRevenueCatSignature(
    SECRET,
    NOW_SECONDS,
    RAW_BODY,
  );
  const signature = valid.split("v1=")[1];

  assert(
    await verifyRevenueCatSignature(
      `t=${NOW_SECONDS},v1=${"0".repeat(64)},v1=${signature}`,
      SECRET,
      RAW_BODY,
      NOW_MS,
    ),
  );
  assertEquals(
    await verifyRevenueCatSignature(
      `t=${NOW_SECONDS},t=${NOW_SECONDS},v1=${signature}`,
      SECRET,
      RAW_BODY,
      NOW_MS,
    ),
    null,
  );
});

Deno.test("payload SHA-256 is deterministic and lowercase", async () => {
  const digest = await sha256Hex(RAW_BODY);
  assertEquals(digest.length, 64);
  assert(/^[0-9a-f]{64}$/.test(digest));
  assertEquals(await sha256Hex(RAW_BODY), digest);
});
