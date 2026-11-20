import { visibilityIds } from "./exploreVisibility.ts";
// Bound long-lived work in each server instance. Refused streams use the same
// bounded short-request fallback; platform traffic limits still apply.
let activeStreams = 0;
const STREAM_LIMIT = 16;
export function exploreVisibilityStream(
  request: Request,
  read: (ids: string[], signal: AbortSignal) => Promise<{ visible: string[] }>,
): Response {
  const raw = new URL(request.url).searchParams.get("ids");
  const ids = raw && raw.length <= 4735 ? visibilityIds(raw.split(",")) : null;
  if (!ids) {
    return Response.json({ error: "invalid_ids" }, {
      status: 400,
      headers: { "Cache-Control": "no-store" },
    });
  }
  if (activeStreams >= STREAM_LIMIT) {
    return Response.json({ error: "stream_busy" }, {
      status: 429,
      headers: { "Cache-Control": "no-store", "Retry-After": "5" },
    });
  }
  activeStreams++;
  const abort = new AbortController();
  const signal = AbortSignal.any([abort.signal, request.signal]);
  let timer: ReturnType<typeof setTimeout> | undefined;
  let released = false;
  const release = () => {
    if (!released) {
      released = true;
      activeStreams--;
    }
  };
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const encoder = new TextEncoder();
      const until = Date.now() + 50000;
      try {
        while (!signal.aborted && Date.now() < until) {
          const snapshot = await read(ids, signal);
          if (signal.aborted) break;
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(snapshot)}\n\n`),
          );
          await new Promise<void>((resolve) => {
            const done = () => {
              clearTimeout(timer);
              signal.removeEventListener("abort", done);
              resolve();
            };
            timer = setTimeout(done, 2000);
            signal.addEventListener("abort", done, { once: true });
            if (signal.aborted) done();
          });
        }
        if (!signal.aborted) {
          controller.enqueue(encoder.encode("event: reconnect\ndata: {}\n\n"));
        }
      } catch {
        if (!signal.aborted) {
          controller.enqueue(
            encoder.encode("event: unavailable\ndata: {}\n\n"),
          );
        }
      } finally {
        release();
        if (!signal.aborted) controller.close();
      }
    },
    cancel() {
      abort.abort();
      clearTimeout(timer);
      release();
    },
  });
  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-store, no-transform",
      "X-Accel-Buffering": "no",
    },
  });
}
