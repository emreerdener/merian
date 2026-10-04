import { HistoryError } from "./contract.ts";

/** Regain control even when a transport's cancellation acknowledgement stalls.
 * A timed-out mutation may have committed; callers must recover durable state. */
export function publicationAbortable<T>(
  signal: AbortSignal,
  run: () => PromiseLike<T>,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const fail = () => reject(new HistoryError("analysis_history_unavailable"));
    if (signal.aborted) {
      fail();
      return;
    }
    signal.addEventListener("abort", fail, { once: true });
    Promise.resolve().then(() => {
      signal.throwIfAborted();
      return run();
    }).then(resolve, reject).finally(() =>
      signal.removeEventListener("abort", fail)
    );
  });
}
