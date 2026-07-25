import { User } from "@supabase/supabase-js";

export async function trackPostHogEvent(
  userOrId: string | User,
  event: string,
  properties: Record<string, unknown> = {},
) {
  const apiKey = Deno.env.get("POSTHOG_API_KEY");
  if (!apiKey) {
    console.warn("POSTHOG_API_KEY not set. Skipping PostHog telemetry.");
    return;
  }

  const userId = typeof userOrId === "string" ? userOrId : userOrId.id;
  const userObj = typeof userOrId === "string" ? null : userOrId;

  const setProps: Record<string, unknown> = {};
  if (userObj) {
    if (userObj.email) setProps.email = userObj.email;
    const name = userObj.user_metadata?.full_name ||
      userObj.user_metadata?.name;
    if (name) setProps.name = name;
  }

  const payload: Record<string, unknown> = {
    $lib: "deno-edge-function",
    ...properties,
  };

  if (Object.keys(setProps).length > 0) {
    payload.$set = {
      ...((payload.$set as Record<string, unknown>) || {}),
      ...setProps,
    };
  }

  try {
    const res = await fetch("https://us.i.posthog.com/capture/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: apiKey,
        event: event,
        distinct_id: userId,
        properties: payload,
      }),
    });

    if (!res.ok) {
      console.error(
        `PostHog event '${event}' failed: ${res.status} ${res.statusText}`,
      );
    }
  } catch (err) {
    console.error(`PostHog fetch error for event '${event}':`, err);
  }
}
