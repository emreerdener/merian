export type AudioTelemetryEvent =
  | "ExploreAudioPlaybackStarted"
  | "ExploreAudioPlaybackCompleted"
  | "ExploreAudioPlaybackFailed";

type AudioTelemetryEnvironment = {
  apiKey?: string;
  getDistinctId: () => string;
  fetcher: typeof fetch;
};

export function markAudioPlaybackStarted(startedItems: Set<string>, clipKey: string): boolean {
  if (startedItems.has(clipKey)) return false;
  startedItems.add(clipKey);
  return true;
}

export function captureAudioTelemetry(
  event: AudioTelemetryEvent,
  surface: string,
  environment: AudioTelemetryEnvironment = browserEnvironment(),
): boolean {
  if (!environment.apiKey) return false;

  void environment.fetcher("https://us.i.posthog.com/capture/", {
    method: "POST",
    keepalive: true,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: environment.apiKey,
      event,
      distinct_id: environment.getDistinctId(),
      properties: { event_source: "public_web", surface },
    }),
  });
  return true;
}

function browserEnvironment(): AudioTelemetryEnvironment {
  return {
    apiKey: process.env.NEXT_PUBLIC_POSTHOG_API_KEY,
    getDistinctId: browserDistinctId,
    fetcher: fetch,
  };
}

function browserDistinctId(): string {
  const storageKey = "merian_posthog_distinct_id";
  try {
    const distinctId = window.localStorage.getItem(storageKey) ?? window.crypto.randomUUID();
    window.localStorage.setItem(storageKey, distinctId);
    return distinctId;
  } catch {
    return window.crypto.randomUUID();
  }
}
