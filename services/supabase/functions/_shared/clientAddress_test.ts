import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  clientAddressFromHeaders,
  ClientAddressHashError,
  hmacClientAddressForPurpose,
  resolveClientAddressHashSecret,
} from "./clientAddress.ts";

const SECRET = "test-only-client-address-secret-32-bytes";

Deno.test("client address uses proxy-observed headers and the right-most forwarding peer", () => {
  assertEquals(
    clientAddressFromHeaders(
      new Headers({
        "x-real-ip": "203.0.113.8",
        "x-forwarded-for": "attacker-value, 192.0.2.7",
      }),
    ),
    "203.0.113.8",
  );
  assertEquals(
    clientAddressFromHeaders(
      new Headers({
        "x-forwarded-for": "attacker-value, 192.0.2.7",
      }),
    ),
    "192.0.2.7",
  );
  assertEquals(clientAddressFromHeaders(new Headers()), "unavailable");
});

Deno.test("client address hashes rotate daily and separate abuse-control purposes", async () => {
  const address = "203.0.113.8";
  const first = await hmacClientAddressForPurpose(
    address,
    SECRET,
    "merian-species-stats-ip-v1",
    new Date("2026-07-24T12:00:00Z"),
  );
  const replay = await hmacClientAddressForPurpose(
    address,
    SECRET,
    "merian-species-stats-ip-v1",
    new Date("2026-07-24T23:59:59Z"),
  );
  const otherPurpose = await hmacClientAddressForPurpose(
    address,
    SECRET,
    "merian-ai-quota-ip-v1",
    new Date("2026-07-24T12:00:00Z"),
  );
  const nextDay = await hmacClientAddressForPurpose(
    address,
    SECRET,
    "merian-species-stats-ip-v1",
    new Date("2026-07-25T00:00:00Z"),
  );

  assertEquals(first, replay);
  assertNotEquals(first, otherPurpose);
  assertNotEquals(first, nextDay);
  assert(/^[0-9a-f]{64}$/.test(first));
  assert(!first.includes(address));
});

Deno.test("client address hashing fails closed for weak keys or invalid purposes", async () => {
  await assertRejects(
    () =>
      hmacClientAddressForPurpose(
        "203.0.113.8",
        "short",
        "merian-species-stats-ip-v1",
      ),
    ClientAddressHashError,
  );
  await assertRejects(
    () =>
      hmacClientAddressForPurpose(
        "203.0.113.8",
        SECRET,
        "INVALID PURPOSE",
      ),
    ClientAddressHashError,
  );
});

Deno.test("client address hashing prefers a dedicated override and otherwise uses a server key", () => {
  assertEquals(
    resolveClientAddressHashSecret({
      dedicatedSecret: ` ${SECRET}-dedicated `,
      platformSecretKey: `${SECRET}-platform`,
    }),
    `${SECRET}-dedicated`,
  );
  assertEquals(
    resolveClientAddressHashSecret({
      platformSecretKey: `${SECRET}-platform`,
      serviceRoleKey: `${SECRET}-legacy`,
    }),
    `${SECRET}-platform`,
  );
  assertThrows(
    () =>
      resolveClientAddressHashSecret({
        dedicatedSecret: "too-short",
        platformSecretKey: `${SECRET}-platform`,
      }),
    ClientAddressHashError,
  );
});
