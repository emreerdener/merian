import { assertEquals } from "@std/assert";
import { trackPostHogEvent } from "./posthog.ts";

Deno.test("PostHog capture performs no request when account permission is absent", async () => {
  const previousKey = Deno.env.get("POSTHOG_API_KEY");
  Deno.env.set("POSTHOG_API_KEY", "test-project-key");
  let requestCount = 0;

  try {
    await trackPostHogEvent(
      "00000000-0000-4000-8000-00000000e101",
      "ConsentGateTest",
      {},
      () => {
        requestCount += 1;
        return Promise.resolve(new Response(null, { status: 200 }));
      },
      () => Promise.resolve(false),
    );
    assertEquals(requestCount, 0);
  } finally {
    if (previousKey === undefined) Deno.env.delete("POSTHOG_API_KEY");
    else Deno.env.set("POSTHOG_API_KEY", previousKey);
  }
});

Deno.test("PostHog capture is sent only after account permission is granted", async () => {
  const previousKey = Deno.env.get("POSTHOG_API_KEY");
  Deno.env.set("POSTHOG_API_KEY", "test-project-key");
  const requests: Request[] = [];

  try {
    await trackPostHogEvent(
      "00000000-0000-4000-8000-00000000e101",
      "ConsentGateTest",
      { result: "ok" },
      (input, init) => {
        requests.push(new Request(input, init));
        return Promise.resolve(new Response(null, { status: 200 }));
      },
      () => Promise.resolve(true),
    );

    assertEquals(requests.length, 1);
    assertEquals(requests[0].url, "https://us.i.posthog.com/capture/");
    const body = await requests[0].json();
    assertEquals(body.distinct_id, "00000000-0000-4000-8000-00000000e101");
    assertEquals(body.event, "ConsentGateTest");
    assertEquals(body.properties.result, "ok");
    assertEquals(body.properties.$set, undefined);
  } finally {
    if (previousKey === undefined) Deno.env.delete("POSTHOG_API_KEY");
    else Deno.env.set("POSTHOG_API_KEY", previousKey);
  }
});
