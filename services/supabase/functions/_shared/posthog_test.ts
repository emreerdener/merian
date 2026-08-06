import { assertEquals } from "@std/assert";
import {
  hasCurrentPostHogConsent,
  isCurrentPostHogConsentHead,
  trackPostHogEvent,
} from "./posthog.ts";

const TEST_USER_ID = "00000000-0000-4000-8000-00000000e101";
const TEST_SERVER_API_KEY = `sb_secret_posthog_test_${"a".repeat(20)}`;

async function withPostHogDatabaseEnvironment<T>(
  operation: () => Promise<T>,
): Promise<T> {
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousServerApiKey = Deno.env.get("SUPABASE_SERVER_API_KEY");
  Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");
  Deno.env.set("SUPABASE_SERVER_API_KEY", TEST_SERVER_API_KEY);

  try {
    return await operation();
  } finally {
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousServerApiKey === undefined) {
      Deno.env.delete("SUPABASE_SERVER_API_KEY");
    } else {
      Deno.env.set("SUPABASE_SERVER_API_KEY", previousServerApiKey);
    }
  }
}

Deno.test("PostHog authority requires the all-version head to be a current grant", () => {
  assertEquals(
    isCurrentPostHogConsentHead({
      event_kind: "granted",
      disclosure_version: "2026-08-04",
    }),
    true,
  );
  assertEquals(
    isCurrentPostHogConsentHead({
      event_kind: "revoked",
      disclosure_version: "2026-08-03",
    }),
    false,
  );
  assertEquals(
    isCurrentPostHogConsentHead({
      event_kind: "granted",
      disclosure_version: "2026-08-03",
    }),
    false,
  );
});

Deno.test("PostHog lookup reads the provider head without a disclosure filter", async () => {
  await withPostHogDatabaseEnvironment(async () => {
    let databaseRequest: Request | undefined;
    const authorized = await hasCurrentPostHogConsent(
      TEST_USER_ID,
      (input, init) => {
        databaseRequest = new Request(input, init);
        return Promise.resolve(
          new Response(
            JSON.stringify([{
              event_kind: "revoked",
              disclosure_version: "2026-08-03",
            }]),
            {
              status: 200,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      },
    );

    assertEquals(authorized, false);
    const url = new URL(databaseRequest?.url ?? "");
    assertEquals(
      url.pathname,
      "/rest/v1/user_analytics_consent_events",
    );
    assertEquals(
      url.searchParams.get("select"),
      "event_kind,disclosure_version",
    );
    assertEquals(url.searchParams.get("user_id"), `eq.${TEST_USER_ID}`);
    assertEquals(url.searchParams.get("provider"), "eq.posthog");
    assertEquals(url.searchParams.get("disclosure_version"), null);
    assertEquals(url.searchParams.get("order"), "consent_revision.desc");
    assertEquals(url.searchParams.get("limit"), "1");
  });
});

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
