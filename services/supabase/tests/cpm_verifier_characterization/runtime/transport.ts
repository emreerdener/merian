import {
  AUTH_MODE,
  DENIED_BEARER,
  PROJECT_URL,
  ROUTE,
  validOperatorKey,
} from "./config.ts";

/** Driver alone chooses caller credentials; URLs and case bodies are fixed. */
export function driverTransport(options: {
  operatorKey: string;
  publicKey: string;
  beforeSend?(): void;
  recordRuntime?(
    versions: { deno: string; v8: string; authMode: typeof AUTH_MODE },
  ): void;
  fetchOnce(request: Request): Promise<Response>;
}) {
  if (!validOperatorKey(options.operatorKey) || !options.publicKey) {
    throw Error("driver_credentials");
  }
  return async (request: Request, signal: AbortSignal) => {
    signal.throwIfAborted();
    // Request is created by the fixed driver, not untrusted ingress.
    const body = await request.text();
    const item = JSON.parse(body);
    const headers = new Headers(request.headers);
    headers.set("apikey", options.publicKey);
    headers.set(
      "authorization",
      `Bearer ${item.case === 26 ? DENIED_BEARER : options.operatorKey}`,
    );
    options.beforeSend?.();
    const response = await options.fetchOnce(
      new Request(`${PROJECT_URL}/functions/v1/${ROUTE}`, {
        method: "POST",
        headers,
        body,
        signal,
        redirect: "error",
      }),
    );
    const deno = response.headers.get("x-cpm-runtime-deno") ?? "",
      v8 = response.headers.get("x-cpm-runtime-v8") ?? "";
    if (
      response.headers.get("x-cpm-auth-mode") !== AUTH_MODE ||
      ![deno, v8].every((v) => /^[A-Za-z0-9.+_-]{1,80}$/.test(v))
    ) {
      await response.body?.cancel();
      throw Error("runtime_metadata");
    }
    try {
      options.recordRuntime?.({ deno, v8, authMode: AUTH_MODE });
    } catch {
      await response.body?.cancel();
      throw Error("runtime_metadata");
    }
    return response;
  };
}
