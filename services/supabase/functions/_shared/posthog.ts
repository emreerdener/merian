import type { User } from "@supabase/supabase-js";
import { fetchWithDeadline } from "./outbound.ts";
import { createServiceRoleClientFromEnvironmentWithOptions } from "./serviceRoleClient.ts";

const POSTHOG_REQUEST_TIMEOUT_MS = 2_500;
const POSTHOG_DISCLOSURE_VERSION = "2026-08-03";

export async function hasCurrentPostHogConsent(
  userId: string,
  fetcher: typeof fetch = fetch,
): Promise<boolean> {
  try {
    const supabaseAdmin = createServiceRoleClientFromEnvironmentWithOptions({
      fetchImplementation: fetcher,
      requestTimeoutMs: POSTHOG_REQUEST_TIMEOUT_MS,
      maximumResponseBytes: 16_384,
    });
    const { data, error } = await supabaseAdmin
      .from("user_analytics_consent_events")
      .select("event_kind")
      .eq("user_id", userId)
      .eq("provider", "posthog")
      .eq("disclosure_version", POSTHOG_DISCLOSURE_VERSION)
      .order("recorded_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(1);

    if (error) {
      console.error("PostHog permission lookup failed. Skipping telemetry.");
      return false;
    }
    return data?.[0]?.event_kind === "granted";
  } catch {
    console.error("PostHog permission lookup failed. Skipping telemetry.");
    return false;
  }
}

export async function trackPostHogEvent(
  userOrId: string | User,
  event: string,
  properties: Record<string, unknown> = {},
  fetcher: typeof fetch = fetch,
  consentChecker: (
    userId: string,
    fetcher: typeof fetch,
  ) => Promise<boolean> = hasCurrentPostHogConsent,
) {
  const apiKey = Deno.env.get("POSTHOG_API_KEY");
  if (!apiKey) {
    console.warn("POSTHOG_API_KEY not set. Skipping PostHog telemetry.");
    return;
  }

  const userId = typeof userOrId === "string" ? userOrId : userOrId.id;
  if (!await consentChecker(userId, fetcher)) {
    return;
  }

  const payload: Record<string, unknown> = {
    $lib: "deno-edge-function",
    ...properties,
  };

  try {
    const res = await fetchWithDeadline(
      "https://us.i.posthog.com/capture/",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          api_key: apiKey,
          event: event,
          distinct_id: userId,
          properties: payload,
        }),
      },
      {
        fetcher,
        timeoutMs: POSTHOG_REQUEST_TIMEOUT_MS,
      },
    );

    if (!res.ok) {
      console.error(
        `PostHog event '${event}' failed: ${res.status} ${res.statusText}`,
      );
    }
    await res.body?.cancel().catch(() => undefined);
  } catch (err) {
    console.error(`PostHog fetch error for event '${event}':`, err);
  }
}
