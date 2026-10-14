import { createClient } from "@supabase/supabase-js";
import { OPERATOR_ALIAS, PROJECT_URL } from "./config.ts";

/** Own the reader through explicit abort/cancel/closed settlement. An unknown
 * cancel remains pending, never an authorization success or released obligation. */
async function authBody(
  body: ReadableStream<Uint8Array> | null,
  signal: AbortSignal,
) {
  if (!body) throw Error("auth_response");
  const reader = body.getReader();
  reader.closed.catch(() => {});
  let cancellation: Promise<void> | undefined,
    complete = false,
    used = 0,
    chunks = 0;
  const buffer = new Uint8Array(65_536);
  const cancel = () => {
    cancellation ??= reader.cancel();
    cancellation.catch(() => {});
  };
  signal.addEventListener("abort", cancel, { once: true });
  try {
    if (signal.aborted) cancel();
    for (;;) {
      signal.throwIfAborted();
      const next = await reader.read();
      signal.throwIfAborted();
      if (next.done) {
        complete = true;
        break;
      }
      if (++chunks > 65_536 || used + next.value.byteLength > buffer.length) {
        throw Error("auth_response_bound");
      }
      buffer.set(next.value, used);
      used += next.value.byteLength;
    }
    return buffer.slice(0, used);
  } finally {
    signal.removeEventListener("abort", cancel);
    if (!complete) cancel();
    try {
      await cancellation;
      await reader.closed;
    } finally {
      reader.releaseLock();
    }
  }
}

/** Same Auth-server getUser strategy as requireAuth, with an experiment-only
 * single-attempt, bounded-body, cancellable transport. No privileged client. */
export function authAdapter(options: {
  publicKey: string;
  operatorID: string;
  fetchOnce(request: Request): Promise<Response>;
}) {
  return async (
    bearer: string,
    signal: AbortSignal,
  ): Promise<string | null> => {
    let attempts = 0;
    let transportFailed = false;
    const client = createClient(PROJECT_URL, options.publicKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
      global: {
        fetch: async (input, init) => {
          try {
            signal.throwIfAborted();
            const request = new Request(input, {
              ...init,
              signal,
              redirect: "error",
            });
            if (
              ++attempts !== 1 || request.method !== "GET" ||
              request.url !== `${PROJECT_URL}/auth/v1/user`
            ) {
              throw Error("auth_transport");
            }
            const response = await options.fetchOnce(request);
            if (
              response.redirected || ![200, 401, 403].includes(response.status)
            ) {
              await response.body?.cancel();
              throw Error("auth_transport");
            }
            const body = await authBody(response.body, signal);
            signal.throwIfAborted();
            return new Response(body, {
              status: response.status,
              headers: { "content-type": "application/json" },
            });
          } catch {
            transportFailed = true;
            throw Error("auth_transport");
          }
        },
      },
    });
    const { data, error } = await client.auth.getUser(bearer);
    signal.throwIfAborted();
    if (transportFailed || attempts !== 1) throw Error("auth_transport");
    if (error) {
      if (error.status === 401 || error.status === 403) return null;
      throw Error("auth_response");
    }
    return data.user?.id === options.operatorID ? OPERATOR_ALIAS : null;
  };
}
