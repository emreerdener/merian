// Qualification-only entrypoint. Not registered in the repository fleet.
import { createWorker } from "./worker.ts";

// Module lifetime owns the sole handler, reader gate and worker alias.
let handle: (request: Request) => Promise<Response>;
try {
  const worker = createWorker({
    env: (name) => Deno.env.get(name),
    fetchOnce: (request) => fetch(request),
    memoryUsage: () => Deno.memoryUsage(),
    uuid: () => crypto.randomUUID(),
    versions: Deno.version,
  });
  handle = worker.handle;
} catch {
  // Do not expose configuration values or errors; no partial startup.
  handle = () =>
    Promise.resolve(
      new Response(null, {
        status: 503,
        headers: { "x-cpm-startup-error": "initialization_failed" },
      }),
    );
}
Deno.serve(handle);
