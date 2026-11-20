type Handlers = {
  message: (data: string) => void;
  error: () => void;
  reconnect: () => void;
};
type Connect = (handlers: Handlers) => () => void;

/** One live connection and one retry timer; superseded callbacks are ignored. */
export function subscribeExploreVisibility(
  connect: Connect,
  snapshot: (value: unknown) => void,
  failed: () => void,
) {
  let stopped = false;
  let generation = 0;
  let close: (() => void) | undefined;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const open = () => {
    if (stopped) return;
    const version = ++generation;
    const current = () => !stopped && version === generation;
    const retry = (delay: number, failure: boolean) => {
      if (!current()) return;
      generation++;
      close?.();
      close = undefined;
      clearTimeout(timer);
      if (failure) failed();
      if (!stopped) timer = setTimeout(open, delay);
    };
    close = connect({
      message: (data) => {
        if (!current()) return;
        try {
          snapshot(JSON.parse(data));
        } catch {
          retry(5000, true);
        }
      },
      error: () => retry(5000, true),
      reconnect: () => retry(100, false),
    });
  };
  open();
  return () => {
    stopped = true;
    generation++;
    clearTimeout(timer);
    close?.();
  };
}
