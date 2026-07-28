/**
 * Resolves callable project API keys from Supabase's Management API.
 *
 * Secret API keys are hidden unless the API request explicitly sets
 * `reveal=true`. Never replace this request with `supabase projects api-keys`
 * unless that command exposes and uses an equivalent reveal option.
 */

import {
  isCurrentSecretKey,
  isLegacyServiceRoleJwt,
} from "../functions/_shared/serviceRoleAuth.ts";
import {
  isCurrentPublishableKey,
  isLegacyAnonJwt,
} from "../functions/_shared/publishableKey.ts";
import {
  fetchWithDeadline,
  readResponseTextWithinLimit,
} from "../functions/_shared/outbound.ts";

const MANAGEMENT_API_ORIGIN = "https://api.supabase.com";
const REQUEST_DEADLINE_MS = 15_000;
const MAXIMUM_RESPONSE_BYTES = 512 * 1_024;
const MAXIMUM_LOOKUP_ATTEMPTS = 5;
const INITIAL_RETRY_DELAY_MS = 1_000;
const MAXIMUM_RETRY_DELAY_MS = 8_000;

export interface ManagementApiKeyLookupRetry {
  attempt: number;
  maximumAttempts: number;
  delayMs: number;
  reason: "transport_error" | `http_${number}`;
}

export interface ManagementApiKeyLookupOptions {
  maximumAttempts?: number;
  wait?: (milliseconds: number) => Promise<void>;
  random?: () => number;
  onRetry?: (retry: ManagementApiKeyLookupRetry) => void;
}

export interface ResolvedProjectApiKeys {
  server_api_key: string;
  public_api_keys: string[];
}

interface KeyCandidate {
  key: string;
  name: string;
  priority: number;
}

function exactString(value: unknown): string | null {
  if (typeof value !== "string" || value.trim() !== value || !value) {
    return null;
  }
  return value;
}

function candidateSort(
  left: KeyCandidate,
  right: KeyCandidate,
): number {
  return left.priority - right.priority ||
    left.name.localeCompare(right.name) ||
    left.key.localeCompare(right.key);
}

function uniqueCandidateKeys(candidates: KeyCandidate[]): string[] {
  const keys = new Set<string>();
  for (const candidate of candidates.sort(candidateSort)) {
    keys.add(candidate.key);
  }
  return [...keys];
}

function isRetryableManagementApiStatus(status: number): boolean {
  return status === 408 ||
    status === 425 ||
    status === 429 ||
    (status >= 500 && status <= 599);
}

function retryAfterMilliseconds(response: Response): number {
  const value = response.headers.get("Retry-After")?.trim() ?? "";
  if (!/^(0|[1-9][0-9]*)$/.test(value)) return 0;

  const seconds = Number(value);
  if (!Number.isSafeInteger(seconds)) return 0;
  return Math.min(seconds * 1_000, MAXIMUM_RETRY_DELAY_MS);
}

async function cancelResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel(
      "Management API response will not be consumed.",
    );
  } catch {
    // Status and headers are sufficient; disposal failure must not block retry.
  }
}

function boundedRandom(random: () => number): number {
  const value = random();
  if (!Number.isFinite(value)) return 0.5;
  return Math.min(Math.max(value, 0), 1);
}

function retryDelayMilliseconds(
  attempt: number,
  response: Response | null,
  random: () => number,
): number {
  const exponentialDelay = Math.min(
    INITIAL_RETRY_DELAY_MS * (2 ** (attempt - 1)),
    MAXIMUM_RETRY_DELAY_MS,
  );
  const jitteredDelay = Math.round(
    exponentialDelay * (0.5 + boundedRandom(random) * 0.5),
  );
  return Math.max(
    jitteredDelay,
    response ? retryAfterMilliseconds(response) : 0,
  );
}

async function waitForManagementApiRetry(
  attempt: number,
  maximumAttempts: number,
  response: Response | null,
  reason: ManagementApiKeyLookupRetry["reason"],
  options: ManagementApiKeyLookupOptions,
): Promise<void> {
  const delayMs = retryDelayMilliseconds(
    attempt,
    response,
    options.random ?? Math.random,
  );
  options.onRetry?.({
    attempt,
    maximumAttempts,
    delayMs,
    reason,
  });
  const wait = options.wait ??
    ((milliseconds: number) =>
      new Promise<void>((resolve) => setTimeout(resolve, milliseconds)));
  await wait(delayMs);
}

export function resolveProjectApiKeys(
  payload: unknown,
): ResolvedProjectApiKeys {
  if (!Array.isArray(payload)) {
    throw new Error("Supabase Management API returned an invalid key list.");
  }

  const serverCandidates: KeyCandidate[] = [];
  const publicCandidates: KeyCandidate[] = [];

  for (const rawEntry of payload) {
    if (!rawEntry || typeof rawEntry !== "object" || Array.isArray(rawEntry)) {
      continue;
    }
    const entry = rawEntry as Record<string, unknown>;
    const type = exactString(entry.type)?.toLowerCase() ?? "";
    const name = exactString(entry.name)?.toLowerCase() ?? "";
    const key = exactString(entry.api_key);
    if (!key) continue;

    if (type === "secret" && isCurrentSecretKey(key)) {
      serverCandidates.push({
        key,
        name,
        priority: name === "default" ? 0 : 1,
      });
    } else if (
      type === "legacy" &&
      name === "service_role" &&
      isLegacyServiceRoleJwt(key)
    ) {
      serverCandidates.push({ key, name, priority: 2 });
    }

    if (type === "publishable" && isCurrentPublishableKey(key)) {
      publicCandidates.push({
        key,
        name,
        priority: name === "default" ? 0 : 1,
      });
    } else if (
      type === "legacy" &&
      name === "anon" &&
      isLegacyAnonJwt(key)
    ) {
      publicCandidates.push({ key, name, priority: 2 });
    }
  }

  const serverApiKeys = uniqueCandidateKeys(serverCandidates);
  if (serverApiKeys.length === 0) {
    throw new Error(
      "Supabase Management API returned no revealed secret or exact legacy service-role key.",
    );
  }

  return {
    server_api_key: serverApiKeys[0],
    public_api_keys: uniqueCandidateKeys(publicCandidates),
  };
}

export async function fetchRevealedProjectApiKeys(
  projectRef: string,
  accessToken: string,
  fetchImplementation: typeof fetch = fetch,
  options: ManagementApiKeyLookupOptions = {},
): Promise<ResolvedProjectApiKeys> {
  if (!/^[a-z0-9]{20}$/.test(projectRef)) {
    throw new Error("Invalid Supabase project ref.");
  }
  if (
    !accessToken ||
    accessToken.trim() !== accessToken ||
    /\s/.test(accessToken)
  ) {
    throw new Error("Invalid SUPABASE_ACCESS_TOKEN.");
  }
  const maximumAttempts = options.maximumAttempts ?? MAXIMUM_LOOKUP_ATTEMPTS;
  if (
    !Number.isSafeInteger(maximumAttempts) ||
    maximumAttempts < 1 ||
    maximumAttempts > MAXIMUM_LOOKUP_ATTEMPTS
  ) {
    throw new TypeError(
      `maximumAttempts must be between 1 and ${MAXIMUM_LOOKUP_ATTEMPTS}.`,
    );
  }

  const url = new URL(
    `/v1/projects/${projectRef}/api-keys`,
    MANAGEMENT_API_ORIGIN,
  );
  url.searchParams.set("reveal", "true");

  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    let response: Response;
    try {
      response = await fetchWithDeadline(
        url,
        {
          headers: {
            Accept: "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
        },
        {
          fetcher: fetchImplementation,
          timeoutMs: REQUEST_DEADLINE_MS,
        },
      );
    } catch {
      if (attempt === maximumAttempts) {
        throw new Error(
          `Supabase Management API key lookup failed after ${maximumAttempts} attempts due to transport errors.`,
        );
      }
      await waitForManagementApiRetry(
        attempt,
        maximumAttempts,
        null,
        "transport_error",
        options,
      );
      continue;
    }

    if (!response.ok) {
      const status = response.status;
      const retryable = isRetryableManagementApiStatus(status);
      if (retryable && attempt < maximumAttempts) {
        await cancelResponseBody(response);
        await waitForManagementApiRetry(
          attempt,
          maximumAttempts,
          response,
          `http_${status}`,
          options,
        );
        continue;
      }
      await cancelResponseBody(response);
      throw new Error(
        retryable
          ? `Supabase Management API key lookup failed after ${maximumAttempts} attempts with HTTP ${status}.`
          : `Supabase Management API key lookup failed with HTTP ${status}.`,
      );
    }

    const text = await readResponseTextWithinLimit(
      response,
      MAXIMUM_RESPONSE_BYTES,
    );
    let payload: unknown;
    try {
      payload = JSON.parse(text);
    } catch {
      throw new Error("Supabase Management API returned invalid key JSON.");
    }
    return resolveProjectApiKeys(payload);
  }

  throw new Error("Supabase Management API key retry loop ended unexpectedly.");
}

function parseArguments(
  args: string[],
): { projectRef: string } {
  let projectRef = "";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--project-ref" && i + 1 < args.length) {
      projectRef = args[i + 1];
      i++;
    } else {
      throw new Error(`Unknown or incomplete argument: ${args[i]}`);
    }
  }

  if (!projectRef) {
    throw new Error(
      "Usage: resolve_project_api_keys.ts --project-ref <project-ref>",
    );
  }
  return { projectRef };
}

if (import.meta.main) {
  try {
    const { projectRef } = parseArguments(Deno.args);
    const accessToken = Deno.env.get("SUPABASE_ACCESS_TOKEN") ?? "";
    const keys = await fetchRevealedProjectApiKeys(
      projectRef,
      accessToken,
      fetch,
      {
        onRetry: (retry) => {
          console.error(
            `Supabase Management API key lookup transient failure (${retry.reason}); retrying in ${
              retry.delayMs / 1_000
            }s (attempt ${retry.attempt}/${retry.maximumAttempts}).`,
          );
        },
      },
    );
    console.log(JSON.stringify(keys));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
