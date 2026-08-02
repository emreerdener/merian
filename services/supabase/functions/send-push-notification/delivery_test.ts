import { assertEquals, assertObjectMatch } from "@std/assert";
import { OutboundRequestTimeoutError } from "../_shared/outbound.ts";
import type { PushDeviceRow } from "./db.ts";
import { apnsDeliveryExceptionReason, sendApnsPush } from "./delivery.ts";

function pushDevice(
  overrides: Partial<PushDeviceRow> = {},
): PushDeviceRow {
  return {
    id: "00000000-0000-4000-8000-00000000d101",
    device_token: "device-token",
    platform: "ios",
    environment: "production",
    explore_enabled: true,
    comment_mentions_enabled: true,
    community_identifications_enabled: true,
    is_active: true,
    ...overrides,
  };
}

Deno.test("APNs delivery is deadline-bound and retry-collapsed", async () => {
  let requestedUrl = "";
  let requestedInit: RequestInit | undefined;
  const fetcher = ((input: RequestInfo | URL, init?: RequestInit) => {
    requestedUrl = String(input);
    requestedInit = init;
    return Promise.resolve(new Response(null, { status: 200 }));
  }) as typeof fetch;

  const result = await sendApnsPush(
    pushDevice(),
    { title: "New activity", body: "Open Explore" },
    "bearer-token",
    "earth.naturebook",
    "00000000-0000-4000-8000-00000000d102",
    "00000000-0000-4000-8000-00000000d103",
    null,
    null,
    null,
    "like",
    7,
    fetcher,
  );

  assertEquals(result, null);
  assertEquals(
    requestedUrl,
    "https://api.push.apple.com/3/device/device-token",
  );
  assertEquals(requestedInit?.signal instanceof AbortSignal, true);
  const headers = new Headers(requestedInit?.headers);
  assertEquals(
    headers.get("apns-collapse-id"),
    "00000000-0000-4000-8000-00000000d102",
  );
  assertEquals(headers.get("apns-topic"), "earth.naturebook");
  assertObjectMatch(JSON.parse(String(requestedInit?.body)), {
    aps: {
      badge: 7,
      "thread-id": "explore_activity",
    },
    notificationId: "00000000-0000-4000-8000-00000000d102",
  });
});

Deno.test("APNs delivery bounds diagnostics and preserves stable reasons", async () => {
  let bodyCancelled = false;
  const fetcher =
    ((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            start(controller) {
              controller.enqueue(new Uint8Array(4 * 1024 + 1));
            },
            cancel() {
              bodyCancelled = true;
            },
          }),
          { status: 503 },
        ),
      )) as typeof fetch;

  const result = await sendApnsPush(
    pushDevice({ environment: "sandbox" }),
    { title: "New activity", body: "Open Explore" },
    "bearer-token",
    "earth.naturebook",
    "00000000-0000-4000-8000-00000000d104",
    "00000000-0000-4000-8000-00000000d105",
    null,
    null,
    null,
    "like",
    null,
    fetcher,
  );

  assertEquals(result, { status: 503, reason: "HTTP_503" });
  assertEquals(bodyCancelled, true);
});

Deno.test("APNs delivery accepts a bounded provider reason", async () => {
  const fetcher =
    ((_input: RequestInfo | URL, _init?: RequestInit) =>
      Promise.resolve(
        new Response(JSON.stringify({ reason: "Unregistered" }), {
          headers: { "Content-Type": "application/json" },
          status: 410,
        }),
      )) as typeof fetch;

  const result = await sendApnsPush(
    pushDevice(),
    { title: "New activity", body: "Open Explore" },
    "bearer-token",
    "earth.naturebook",
    "00000000-0000-4000-8000-00000000d106",
    "00000000-0000-4000-8000-00000000d107",
    null,
    null,
    null,
    "like",
    0,
    fetcher,
  );

  assertEquals(result, { status: 410, reason: "Unregistered" });
});

Deno.test("APNs delivery maps exceptions to stable non-sensitive reasons", () => {
  assertEquals(
    apnsDeliveryExceptionReason(new OutboundRequestTimeoutError(10_000)),
    "RequestTimeout",
  );
  assertEquals(
    apnsDeliveryExceptionReason(
      new TypeError("connect ECONNREFUSED secret.internal.example"),
    ),
    "NetworkError",
  );
  assertEquals(
    apnsDeliveryExceptionReason(
      new Error("APNS_PRIVATE_KEY=must-not-persist"),
    ),
    "DeliveryException",
  );
});
