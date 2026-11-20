import {
  VISIBILITY_BATCH_SIZE,
  VISIBILITY_LEASE_MS,
  VISIBILITY_POLL_MS,
  visibilityResult,
} from "./exploreVisibility.ts";

type Dependencies = {
  check: (ids: string[], signal: AbortSignal) => Promise<unknown>;
  changes: (
    snapshot: (value: unknown) => void,
    failed: () => void,
  ) => (() => void) | null;
};
/** Expiring approval. Stream and fallback polling never race to restore content. */
export function watchExploreVisibility(
  ids: string[],
  publish: (visible: ReadonlySet<string>) => void,
  deps: Dependencies,
) {
  let stopped = false;
  let active: AbortController | null = null;
  let generation = 0;
  let expires = 0;
  let streamFreshUntil = Date.now() + VISIBILITY_LEASE_MS;
  let streaming = true;
  let disconnect: (() => void) | null = null;
  let approved = false;
  const clear = () => {
    approved = false;
    expires = 0;
    publish(new Set());
  };
  const accept = (visible: string[]) => {
    approved = true;
    expires = Date.now() + VISIBILITY_LEASE_MS;
    publish(new Set(visible));
  };
  const fail = () => {
    if (stopped) return;
    generation++;
    active?.abort();
    active = null;
    streaming = false;
    disconnect?.();
    disconnect = null;
    streamFreshUntil = 0;
    clear();
  };
  async function check() {
    if (stopped || active) return;
    if (streaming) {
      if (Date.now() < streamFreshUntil) return;
      fail(); // Close the stalled stream before polling; ignore any queued frames.
    }
    const version = generation;
    const started = Date.now();
    const deadline = AbortSignal.timeout(5000);
    const request = new AbortController();
    active = request;
    try {
      const visible: string[] = [];
      for (
        let offset = 0;
        offset < ids.length;
        offset += VISIBILITY_BATCH_SIZE
      ) {
        const batch = ids.slice(offset, offset + VISIBILITY_BATCH_SIZE);
        visible.push(
          ...visibilityResult(
            await deps.check(
              batch,
              AbortSignal.any([
                request.signal,
                deadline,
                AbortSignal.timeout(3000),
              ]),
            ),
            batch,
          ),
        );
      }
      if (stopped || request.signal.aborted || version !== generation) return;
      if (Date.now() - started >= 5000) {
        clear();
        return;
      }
      accept(visible);
      expires = started + VISIBILITY_LEASE_MS;
    } catch {
      if (!stopped && version === generation) clear();
    } finally {
      if (active === request) active = null;
    }
  }
  clear();
  disconnect = deps.changes((value) => {
    if (stopped || !streaming) return;
    try {
      const visible = visibilityResult(value, ids);
      generation++;
      active?.abort();
      active = null;
      streamFreshUntil = Date.now() + VISIBILITY_LEASE_MS;
      accept(visible);
    } catch {
      fail();
    }
  }, () => {
    if (streaming) fail();
  });
  if (!disconnect) {
    streaming = false;
    void check();
  }
  // The stream provides the initial snapshot. Polling also works without SSE.
  const polling = setInterval(() => void check(), VISIBILITY_POLL_MS);
  const expiry = setInterval(() => {
    if (approved && Date.now() >= expires) {
      if (streaming) fail();
      else clear();
    }
  }, 250);
  return () => {
    stopped = true;
    generation++;
    active?.abort();
    disconnect?.();
    clearInterval(polling);
    clearInterval(expiry);
  };
}
