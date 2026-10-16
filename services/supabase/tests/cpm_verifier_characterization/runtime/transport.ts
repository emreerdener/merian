import {
  AUTH_MODE,
  DENIED_BEARER,
  PROJECT_URL,
  ROUTE,
  validOperatorKey,
  validRuntimeVersion,
} from "./config.ts";

export interface TransportDiagnostic {
  case: number;
  stage: "transport_failed" | "response_received";
  status: number | null;
  authModeValid: boolean;
  denoVersionValid: boolean;
  v8VersionValid: boolean;
  handlerMarked: boolean;
  startupFailureMarked: boolean;
}
/** Driver alone chooses caller credentials; URLs and case bodies are fixed. */
export function driverTransport(options: {
  operatorKey: string;
  publicKey: string;
  beforeSend?(): void;
  recordDiagnostic?(diagnostic: TransportDiagnostic): void;
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
    let response: Response;
    try {
      response = await options.fetchOnce(
        new Request(`${PROJECT_URL}/functions/v1/${ROUTE}`, {
          method: "POST",
          headers,
          body,
          signal,
          redirect: "error",
        }),
      );
    } catch {
      options.recordDiagnostic?.({
        case: item.case,
        stage: "transport_failed",
        status: null,
        authModeValid: false,
        denoVersionValid: false,
        v8VersionValid: false,
        handlerMarked: false,
        startupFailureMarked: false,
      });
      throw Error("transport_failed");
    }
    const deno = response.headers.get("x-cpm-runtime-deno") ?? "",
      v8 = response.headers.get("x-cpm-runtime-v8") ?? "";
    try {
      options.recordDiagnostic?.({
        case: item.case,
        stage: "response_received",
        status: response.status,
        authModeValid: response.headers.get("x-cpm-auth-mode") === AUTH_MODE,
        denoVersionValid: validRuntimeVersion(deno),
        v8VersionValid: validRuntimeVersion(v8),
        handlerMarked: response.headers.get("x-merian-handler") === "1",
        startupFailureMarked: response.headers.get("x-cpm-startup-error") ===
          "initialization_failed",
      });
    } catch {
      await response.body?.cancel();
      throw Error("diagnostic_recording");
    }
    if (
      response.headers.get("x-cpm-auth-mode") !== AUTH_MODE ||
      ![deno, v8].every(validRuntimeVersion)
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
