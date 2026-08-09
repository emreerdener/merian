import { assertEquals, assertRejects } from "@std/assert";
import {
  canonicalRevenueCatAppUserID,
  preserveRevenueCatAccessForGhostMerge,
  RevenueCatGhostMergeError,
  transferRevenueCatAccessForGhostMerge,
} from "./revenuecat.ts";

const GHOST_ID = "a07ed83e-dfc9-42da-a581-d00000000711";
const TARGET_ID = "ba7ed83e-dfc9-42da-a581-d00000000721";
const REQUEST_AT = Date.parse("2026-08-09T12:00:00.000Z");
const EXPIRES_AT = "2026-09-09T12:00:00.000Z";

function customerInfo(input: {
  proExpiresAt?: string | null;
  wrapped?: boolean;
} = {}): string {
  const value = {
    request_date_ms: REQUEST_AT,
    subscriber: {
      entitlements: input.proExpiresAt === undefined ? {} : {
        pro: {
          expires_date: input.proExpiresAt,
          grace_period_expires_date: null,
        },
      },
      non_subscriptions: {},
    },
  };
  return JSON.stringify(input.wrapped ? { value } : value);
}

Deno.test("RevenueCat ghost merge canonicalizes database UUIDs without creating case variants", async () => {
  const requested: string[] = [];
  const fetcher: typeof fetch = (input, init) => {
    const url = String(input);
    requested.push(`${init?.method ?? "GET"} ${url}`);
    if (url.includes(GHOST_ID.toUpperCase())) {
      return Promise.resolve(
        new Response(customerInfo({ proExpiresAt: EXPIRES_AT }), {
          status: 200,
        }),
      );
    }
    if ((init?.method ?? "GET") === "POST") {
      assertEquals(
        JSON.parse(String(init?.body)),
        { end_time_ms: Date.parse(EXPIRES_AT) },
      );
      return Promise.resolve(
        new Response(
          customerInfo({ proExpiresAt: EXPIRES_AT, wrapped: true }),
          { status: 201 },
        ),
      );
    }
    return Promise.resolve(new Response(customerInfo(), { status: 200 }));
  };

  assertEquals(
    await transferRevenueCatAccessForGhostMerge(
      GHOST_ID.toLowerCase(),
      TARGET_ID.toLowerCase(),
      "sk_test",
      fetcher,
    ),
    "granted",
  );
  assertEquals(requested.length, 3);
  assertEquals(
    requested.every((request) =>
      !request.includes(GHOST_ID.toLowerCase()) &&
      !request.includes(TARGET_ID.toLowerCase())
    ),
    true,
  );
});

Deno.test("RevenueCat ghost merge preserves lifetime access with a lifetime grant", async () => {
  const bodies: unknown[] = [];
  let requestCount = 0;
  const fetcher: typeof fetch = (_input, init) => {
    requestCount += 1;
    if (requestCount === 1) {
      return Promise.resolve(
        new Response(customerInfo({ proExpiresAt: null }), { status: 200 }),
      );
    }
    if (requestCount === 2) {
      return Promise.resolve(new Response(customerInfo(), { status: 200 }));
    }
    bodies.push(JSON.parse(String(init?.body)));
    return Promise.resolve(
      new Response(customerInfo({ proExpiresAt: null }), { status: 201 }),
    );
  };

  assertEquals(
    await transferRevenueCatAccessForGhostMerge(
      GHOST_ID,
      TARGET_ID,
      "sk_test",
      fetcher,
    ),
    "granted",
  );
  assertEquals(bodies, [{ duration: "lifetime" }]);
});

Deno.test("RevenueCat ghost merge does not mutate a free source or a covered target", async () => {
  let freeSourceRequests = 0;
  assertEquals(
    await transferRevenueCatAccessForGhostMerge(
      GHOST_ID,
      TARGET_ID,
      "sk_test",
      () => {
        freeSourceRequests += 1;
        return Promise.resolve(
          new Response(customerInfo(), { status: 200 }),
        );
      },
    ),
    "source_free",
  );
  assertEquals(freeSourceRequests, 1);

  let coveredTargetRequests = 0;
  assertEquals(
    await transferRevenueCatAccessForGhostMerge(
      GHOST_ID,
      TARGET_ID,
      "sk_test",
      () => {
        coveredTargetRequests += 1;
        return Promise.resolve(
          new Response(customerInfo({ proExpiresAt: null }), { status: 200 }),
        );
      },
    ),
    "target_already_covers",
  );
  assertEquals(coveredTargetRequests, 2);
});

Deno.test("RevenueCat ghost merge fails closed for invalid identity and secret evidence", async () => {
  assertEquals(
    canonicalRevenueCatAppUserID(GHOST_ID.toLowerCase()),
    GHOST_ID.toUpperCase(),
  );
  await assertRejects(
    () =>
      transferRevenueCatAccessForGhostMerge(
        "$RCAnonymousID:unsafe",
        TARGET_ID,
        "sk_test",
        fetch,
      ),
    RevenueCatGhostMergeError,
    "invalid RevenueCat App User ID",
  );

  let requests = 0;
  assertEquals(
    await preserveRevenueCatAccessForGhostMerge(
      GHOST_ID,
      TARGET_ID,
      "appl_public",
      () => {
        requests += 1;
        return Promise.resolve(new Response(null, { status: 500 }));
      },
    ),
    { succeeded: false, errorCode: "revenuecat_secret_invalid" },
  );
  assertEquals(requests, 0);
});
