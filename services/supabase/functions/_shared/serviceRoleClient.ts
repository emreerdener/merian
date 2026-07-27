import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  createDeadlineFetchTransport,
  createResponseBodyLimitFetchTransport,
} from "./outbound.ts";
import {
  requireServerApiKey,
  requireServerApiKeyFromEnvironment,
} from "./serviceRoleAuth.ts";
import { timingSafeCompare } from "./http.ts";

const SUPABASE_SERVICE_REQUEST_TIMEOUT_MS = 30_000;
const EDGE_FUNCTION_NAME_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SAFE_FAILURE_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9]{0,63}$/;
const MERIAN_HANDLER_HEADER = "X-Merian-Handler";

export interface ServiceRoleClientTransportOptions {
  fetchImplementation?: typeof fetch;
  requestTimeoutMs?: number;
  maximumResponseBytes?: number;
}

export class ServiceRoleFunctionInvocationError extends Error {
  constructor(
    readonly functionName: string,
    readonly status: number | null,
    readonly reachedMerianHandler: boolean,
    readonly failureName: string,
  ) {
    const statusMessage = status === null
      ? "HTTP status unavailable"
      : `HTTP ${status}`;
    const handlerMessage = reachedMerianHandler
      ? "Merian handler reached"
      : "Merian handler not confirmed";
    super(
      `${functionName} invocation failed (${statusMessage}; ${handlerMessage}; ${failureName}). Response body withheld.`,
    );
    this.name = "ServiceRoleFunctionInvocationError";
  }
}

function safeFailureName(error: unknown): string {
  const candidate = error instanceof Error ? error.name : typeof error;
  return SAFE_FAILURE_NAME_PATTERN.test(candidate)
    ? candidate
    : "UnknownFailure";
}

function invocationResponse(
  response: Response | undefined,
  error: unknown,
): Response | undefined {
  if (response instanceof Response) return response;
  if (!error || typeof error !== "object") return undefined;
  const context = (error as { context?: unknown }).context;
  return context instanceof Response ? context : undefined;
}

/**
 * Invokes a JSON Edge Function through the privileged SDK client while
 * preserving only safe failure metadata.
 *
 * FunctionsHttpError keeps the upstream Response in `context`; logging the
 * whole SDK error can therefore expose an internal response body. This helper
 * records only the fixed handler marker, numeric status, and bounded error
 * class, then cancels the untrusted body before throwing.
 */
export async function invokeServiceRoleJson<T>(
  supabase: SupabaseClient,
  functionName: string,
  body: Record<string, unknown>,
): Promise<T> {
  if (!EDGE_FUNCTION_NAME_PATTERN.test(functionName)) {
    throw new TypeError("Invalid Edge Function name.");
  }

  const { data, error, response } = await supabase.functions.invoke<T>(
    functionName,
    { body },
  );
  if (!error) return data as T;

  const failedResponse = invocationResponse(response, error);
  const status = failedResponse &&
      Number.isInteger(failedResponse.status) &&
      failedResponse.status >= 100 &&
      failedResponse.status <= 599
    ? failedResponse.status
    : null;
  const reachedMerianHandler =
    failedResponse?.headers.get(MERIAN_HANDLER_HEADER) === "1";
  try {
    await failedResponse?.body?.cancel("response body withheld");
  } catch {
    // Status and the fixed marker are sufficient for safe classification.
  }

  throw new ServiceRoleFunctionInvocationError(
    functionName,
    status,
    reachedMerianHandler,
    safeFailureName(error),
  );
}

/**
 * Applies the API-key transport policy at the final fetch boundary.
 *
 * supabase-js currently uses its project key as a fallback Bearer token when
 * there is no user session. Current `sb_secret_...` credentials are API keys,
 * not JWTs, so the fetch boundary removes only that exact fallback credential.
 * Any different Authorization value (for example a real user access token) is
 * preserved.
 */
export function createServiceRoleFetchTransport(
  serverApiKey: string,
  fetchImplementation: typeof fetch = fetch,
  requestTimeoutMs = SUPABASE_SERVICE_REQUEST_TIMEOUT_MS,
): typeof fetch {
  const validatedServerApiKey = requireServerApiKey({
    envServerApiKey: serverApiKey,
  });
  const deadlineTransport = createDeadlineFetchTransport(
    requestTimeoutMs,
    fetchImplementation,
  );

  return (input, init) => {
    if (!validatedServerApiKey.startsWith("sb_secret_")) {
      return deadlineTransport(input, init as unknown as RequestInit);
    }

    // A Request inherits its headers unless init.headers replaces them. Always
    // inspect the effective set so the SDK's opaque-key Bearer fallback cannot
    // leak through either calling form.
    const initHeaders = init && "headers" in init
      ? (init.headers as HeadersInit)
      : undefined;
    const sourceHeaders = initHeaders ??
      (input instanceof Request ? input.headers : undefined);
    const headers = new Headers(sourceHeaders);
    const authorization = headers.get("Authorization")?.trim() ?? "";
    const bearerCredential = authorization.match(
      /^Bearer\s+([^\s]+)$/i,
    )?.[1];
    if (
      bearerCredential &&
      timingSafeCompare(bearerCredential, validatedServerApiKey)
    ) {
      headers.delete("Authorization");
    }

    return deadlineTransport(
      input,
      { ...init, headers } as unknown as RequestInit,
    );
  };
}

/**
 * Creates a privileged client for PostgREST, Storage, Functions, Auth, and RPC.
 */
export function createServiceRoleClient(
  supabaseUrl: string,
  serverApiKey: string,
  fetchImplementation: typeof fetch = fetch,
): SupabaseClient {
  return createServiceRoleClientWithOptions(supabaseUrl, serverApiKey, {
    fetchImplementation,
  });
}

export function createServiceRoleClientWithOptions(
  supabaseUrl: string,
  serverApiKey: string,
  options: ServiceRoleClientTransportOptions = {},
): SupabaseClient {
  const validatedServerApiKey = requireServerApiKey({
    envServerApiKey: serverApiKey,
  });
  let fetchImplementation = options.fetchImplementation ?? fetch;
  if (options.maximumResponseBytes !== undefined) {
    fetchImplementation = createResponseBodyLimitFetchTransport(
      options.maximumResponseBytes,
      fetchImplementation,
    );
  }
  const transport = createServiceRoleFetchTransport(
    validatedServerApiKey,
    fetchImplementation,
    options.requestTimeoutMs ?? SUPABASE_SERVICE_REQUEST_TIMEOUT_MS,
  );

  return createClient(supabaseUrl, validatedServerApiKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
    global: {
      fetch: transport,
    },
  });
}

/**
 * Compatibility alias for callers that only use data APIs.
 */
export const createServiceRoleDataClient = createServiceRoleClient;

export function createServiceRoleClientFromEnvironment(
  supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "",
  fetchImplementation: typeof fetch = fetch,
): SupabaseClient {
  return createServiceRoleClient(
    supabaseUrl,
    requireServerApiKeyFromEnvironment(),
    fetchImplementation,
  );
}

export function createServiceRoleClientFromEnvironmentWithOptions(
  options: ServiceRoleClientTransportOptions,
  supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "",
): SupabaseClient {
  return createServiceRoleClientWithOptions(
    supabaseUrl,
    requireServerApiKeyFromEnvironment(),
    options,
  );
}
