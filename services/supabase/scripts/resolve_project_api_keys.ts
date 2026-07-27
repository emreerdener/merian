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

  const url = new URL(
    `/v1/projects/${projectRef}/api-keys`,
    MANAGEMENT_API_ORIGIN,
  );
  url.searchParams.set("reveal", "true");

  const response = await fetchWithDeadline(
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
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(
      `Supabase Management API key lookup failed with HTTP ${response.status}.`,
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
    );
    console.log(JSON.stringify(keys));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
