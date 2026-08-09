/**
 * One-time, guarded migration of Merian's existing permanent Supabase Pro
 * cohort to RevenueCat promotional entitlements.
 *
 * Dry-run is the default and performs no network requests. Apply mode requires
 * a reviewed results path, finite expiration, secret API key, and confirmation.
 */

import { readByteStreamWithinLimit } from "../functions/_shared/http.ts";
import { fetchWithDeadline } from "../functions/_shared/outbound.ts";
import {
  parseDelimitedText,
  readPossiblyGzippedText,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";
import { canonicalUUID } from "./audit_revenuecat_customers.ts";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const REQUEST_TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const MAX_RETRIES = 3;
const DEFAULT_CONCURRENCY = 3;
const MAX_CONCURRENCY = 5;
const DEFAULT_MAX_USERS = 500;
const MAX_GRANT_HORIZON_MS = 366 * 24 * 60 * 60 * 1_000;

export interface BetaEntitlementGrantArgs {
  usersCsvPath: string | null;
  entitlementID: string;
  expiresAt: string | null;
  includeTimedPro: boolean;
  apply: boolean;
  confirmed: boolean;
  concurrency: number;
  maxUsers: number;
  summaryJsonPath: string | null;
  resultsCsvPath: string | null;
}

export interface BetaEntitlementCandidate {
  app_user_id: string;
}

export type BetaEntitlementGrantStatus =
  | "planned"
  | "already_active"
  | "granted"
  | "failed";

export interface BetaEntitlementGrantResult {
  app_user_id: string;
  status: BetaEntitlementGrantStatus;
  error_code: string;
}

export interface BetaEntitlementGrantSummary {
  generated_at: string;
  mode: "dry_run" | "apply";
  selection: "existing_permanent_supabase_pro" | "all_existing_supabase_pro";
  entitlement_id: string;
  expires_at: string | null;
  candidate_count: number;
  planned_count: number;
  already_active_count: number;
  granted_count: number;
  failed_count: number;
  revenuecat_requests_performed: boolean;
}

class RevenueCatOperationError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "RevenueCatOperationError";
  }
}

if (import.meta.main) {
  try {
    const exitCode = await runBetaEntitlementGrant(Deno.args);
    Deno.exit(exitCode);
  } catch (error) {
    console.error(
      `RevenueCat beta grant failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    Deno.exit(2);
  }
}

export async function runBetaEntitlementGrant(
  rawArgs: string[],
  fetcher: typeof fetch = fetch,
): Promise<number> {
  const args = parseBetaEntitlementGrantArgs(rawArgs);
  if (!args.usersCsvPath) throw new Error("--users-csv is required.");

  const source = await readPossiblyGzippedText(args.usersCsvPath);
  const candidates = selectBetaEntitlementCandidates(
    source,
    args.includeTimedPro,
  );
  if (candidates.length > args.maxUsers) {
    throw new Error(
      `Candidate count ${candidates.length} exceeds --max-users ${args.maxUsers}.`,
    );
  }

  const now = new Date();
  const expiresAt = args.expiresAt
    ? validateGrantExpiration(args.expiresAt, now)
    : null;
  let results: BetaEntitlementGrantResult[];

  if (!args.apply) {
    results = candidates.map((candidate) => ({
      app_user_id: candidate.app_user_id,
      status: "planned",
      error_code: "",
    }));
  } else {
    if (!args.confirmed) {
      throw new Error("--apply also requires --confirm-beta-pro-grant.");
    }
    if (!expiresAt) {
      throw new Error("--apply requires a finite --expires-at timestamp.");
    }
    if (!args.resultsCsvPath) {
      throw new Error("--apply requires --results-csv for an operator ledger.");
    }
    const apiKey = requireRevenueCatSecretAPIKey();
    results = await applyBetaEntitlementGrants({
      candidates,
      entitlementID: args.entitlementID,
      expiresAt,
      apiKey,
      concurrency: args.concurrency,
      fetcher,
    });
  }

  const summary = buildBetaEntitlementGrantSummary(
    args,
    results,
    expiresAt,
    now,
  );
  printBetaEntitlementGrantSummary(summary);
  if (args.summaryJsonPath) {
    await Deno.writeTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }
  if (args.resultsCsvPath) {
    await Deno.writeTextFile(
      args.resultsCsvPath,
      serializeDelimitedRows(
        ["app_user_id", "status", "error_code"],
        results,
      ),
    );
    console.log(`results_csv: ${args.resultsCsvPath}`);
  }

  return summary.failed_count > 0 ? 1 : 0;
}

export function parseBetaEntitlementGrantArgs(
  rawArgs: string[],
): BetaEntitlementGrantArgs {
  const args: BetaEntitlementGrantArgs = {
    usersCsvPath: null,
    entitlementID: "pro",
    expiresAt: null,
    includeTimedPro: false,
    apply: false,
    confirmed: false,
    concurrency: DEFAULT_CONCURRENCY,
    maxUsers: DEFAULT_MAX_USERS,
    summaryJsonPath: null,
    resultsCsvPath: null,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    switch (argument) {
      case "--users-csv":
        args.usersCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--entitlement-id":
        args.entitlementID = validatedEntitlementID(
          nextArgument(rawArgs, ++index, argument),
        );
        break;
      case "--expires-at":
        args.expiresAt = nextArgument(rawArgs, ++index, argument);
        break;
      case "--include-timed-pro":
        args.includeTimedPro = true;
        break;
      case "--apply":
        args.apply = true;
        break;
      case "--confirm-beta-pro-grant":
        args.confirmed = true;
        break;
      case "--concurrency":
        args.concurrency = boundedPositiveInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          MAX_CONCURRENCY,
        );
        break;
      case "--max-users":
        args.maxUsers = boundedPositiveInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          10_000,
        );
        break;
      case "--summary-json":
        args.summaryJsonPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--results-csv":
        args.resultsCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return args;
}

export function selectBetaEntitlementCandidates(
  source: string,
  includeTimedPro = false,
): BetaEntitlementCandidate[] {
  const parsed = parseDelimitedText(source);
  for (
    const requiredHeader of [
      "id",
      "subscription_tier",
      "subscription_expires_at",
    ]
  ) {
    if (!parsed.headers.includes(requiredHeader)) {
      throw new Error(
        `Supabase users CSV is missing header: ${requiredHeader}`,
      );
    }
  }

  const candidates: BetaEntitlementCandidate[] = [];
  const seen = new Set<string>();
  for (const row of parsed.rows) {
    if (row.subscription_tier.trim().toLowerCase() !== "pro") continue;
    if (!includeTimedPro && row.subscription_expires_at.trim().length > 0) {
      continue;
    }
    const appUserID = canonicalUUID(row.id);
    if (!appUserID) {
      throw new Error(`Supabase users CSV has invalid id: ${row.id}`);
    }
    if (seen.has(appUserID)) {
      throw new Error(`Supabase users CSV contains duplicate id: ${row.id}`);
    }
    seen.add(appUserID);
    candidates.push({ app_user_id: appUserID });
  }
  return candidates.sort((lhs, rhs) =>
    lhs.app_user_id.localeCompare(rhs.app_user_id)
  );
}

export function validateGrantExpiration(value: string, now: Date): string {
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) {
    throw new Error("--expires-at must be an ISO-8601 timestamp.");
  }
  const horizon = parsed - now.getTime();
  if (horizon < 60 * 60 * 1_000) {
    throw new Error("--expires-at must be at least one hour in the future.");
  }
  if (horizon > MAX_GRANT_HORIZON_MS) {
    throw new Error("--expires-at cannot be more than 366 days in the future.");
  }
  return new Date(parsed).toISOString();
}

export async function applyBetaEntitlementGrants(input: {
  candidates: BetaEntitlementCandidate[];
  entitlementID: string;
  expiresAt: string;
  apiKey: string;
  concurrency: number;
  fetcher: typeof fetch;
}): Promise<BetaEntitlementGrantResult[]> {
  return await mapWithConcurrency(
    input.candidates,
    input.concurrency,
    async (candidate) => {
      try {
        const existing = await revenueCatRequest({
          method: "GET",
          appUserID: candidate.app_user_id,
          entitlementID: input.entitlementID,
          apiKey: input.apiKey,
          fetcher: input.fetcher,
        });
        if (isEntitlementActive(existing, input.entitlementID)) {
          return {
            app_user_id: candidate.app_user_id,
            status: "already_active" as const,
            error_code: "",
          };
        }

        const granted = await revenueCatRequest({
          method: "POST",
          appUserID: candidate.app_user_id,
          entitlementID: input.entitlementID,
          endTimeMs: Date.parse(input.expiresAt),
          apiKey: input.apiKey,
          fetcher: input.fetcher,
        });
        if (!isEntitlementActive(granted, input.entitlementID)) {
          throw new RevenueCatOperationError(
            "grant_not_active",
            "RevenueCat grant response did not contain an active entitlement.",
          );
        }
        return {
          app_user_id: candidate.app_user_id,
          status: "granted" as const,
          error_code: "",
        };
      } catch (error) {
        return {
          app_user_id: candidate.app_user_id,
          status: "failed" as const,
          error_code: error instanceof RevenueCatOperationError
            ? error.code
            : "unexpected_error",
        };
      }
    },
  );
}

export function isEntitlementActive(
  payload: unknown,
  entitlementID: string,
): boolean {
  const root = record(payload);
  const value = record(root?.value) ?? root;
  const subscriber = record(value?.subscriber);
  const entitlements = record(subscriber?.entitlements);
  const entitlement = record(entitlements?.[entitlementID]);
  if (!entitlement) return false;
  if (entitlement.expires_date === null) return true;

  const expiresAt = timestampMilliseconds(entitlement.expires_date);
  const gracePeriodEndsAt = timestampMilliseconds(
    entitlement.grace_period_expires_date,
  );
  const requestAt = typeof value?.request_date_ms === "number"
    ? value.request_date_ms
    : Date.now();
  return Math.max(expiresAt ?? 0, gracePeriodEndsAt ?? 0) > requestAt;
}

function buildBetaEntitlementGrantSummary(
  args: BetaEntitlementGrantArgs,
  results: BetaEntitlementGrantResult[],
  expiresAt: string | null,
  now: Date,
): BetaEntitlementGrantSummary {
  const count = (status: BetaEntitlementGrantStatus) =>
    results.filter((result) => result.status === status).length;
  return {
    generated_at: now.toISOString(),
    mode: args.apply ? "apply" : "dry_run",
    selection: args.includeTimedPro
      ? "all_existing_supabase_pro"
      : "existing_permanent_supabase_pro",
    entitlement_id: args.entitlementID,
    expires_at: expiresAt,
    candidate_count: results.length,
    planned_count: count("planned"),
    already_active_count: count("already_active"),
    granted_count: count("granted"),
    failed_count: count("failed"),
    revenuecat_requests_performed: args.apply,
  };
}

async function revenueCatRequest(input: {
  method: "GET" | "POST";
  appUserID: string;
  entitlementID: string;
  endTimeMs?: number;
  apiKey: string;
  fetcher: typeof fetch;
}): Promise<unknown> {
  const base = `${REVENUECAT_API_BASE_URL}/subscribers/${
    encodeURIComponent(input.appUserID)
  }`;
  const url = input.method === "GET"
    ? base
    : `${base}/entitlements/${
      encodeURIComponent(input.entitlementID)
    }/promotional`;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt += 1) {
    let response: Response;
    try {
      response = await fetchWithDeadline(
        url,
        {
          method: input.method,
          headers: {
            Accept: "application/json",
            Authorization: `Bearer ${input.apiKey}`,
            ...(input.method === "POST"
              ? { "Content-Type": "application/json" }
              : {}),
          },
          body: input.method === "POST"
            ? JSON.stringify({ end_time_ms: input.endTimeMs })
            : undefined,
        },
        { fetcher: input.fetcher, timeoutMs: REQUEST_TIMEOUT_MS },
      );
    } catch {
      if (attempt < MAX_RETRIES) {
        await retryPause(attempt);
        continue;
      }
      throw new RevenueCatOperationError(
        "network_failure",
        "RevenueCat request failed after bounded retries.",
      );
    }

    const expectedStatus = input.method === "GET" ? 200 : 201;
    if (response.status !== expectedStatus) {
      const retryable = response.status === 408 || response.status === 425 ||
        response.status === 429 || response.status >= 500;
      await response.body?.cancel().catch(() => undefined);
      if (retryable && attempt < MAX_RETRIES) {
        await retryPause(attempt);
        continue;
      }
      throw new RevenueCatOperationError(
        `http_${response.status}`,
        `RevenueCat returned HTTP ${response.status}.`,
      );
    }

    const contentLength = Number(response.headers.get("Content-Length"));
    if (Number.isFinite(contentLength) && contentLength > MAX_RESPONSE_BYTES) {
      await response.body?.cancel().catch(() => undefined);
      throw new RevenueCatOperationError(
        "response_too_large",
        "RevenueCat response exceeded the size limit.",
      );
    }
    const bounded = await readByteStreamWithinLimit(
      response.body,
      MAX_RESPONSE_BYTES,
      "RevenueCat response exceeded the size limit",
    );
    if (bounded.exceeded || !bounded.bytes) {
      throw new RevenueCatOperationError(
        "response_too_large",
        "RevenueCat response exceeded the size limit.",
      );
    }
    try {
      const source = new TextDecoder("utf-8", { fatal: true }).decode(
        bounded.bytes,
      );
      return JSON.parse(source);
    } catch {
      throw new RevenueCatOperationError(
        "invalid_response",
        "RevenueCat returned invalid JSON.",
      );
    }
  }
  throw new RevenueCatOperationError("retry_exhausted", "Retry exhausted.");
}

async function mapWithConcurrency<T, U>(
  values: T[],
  concurrency: number,
  operation: (value: T) => Promise<U>,
): Promise<U[]> {
  const results = new Array<U>(values.length);
  let nextIndex = 0;
  const workers = Array.from(
    { length: Math.min(concurrency, values.length) },
    async () => {
      while (nextIndex < values.length) {
        const index = nextIndex++;
        results[index] = await operation(values[index]);
      }
    },
  );
  await Promise.all(workers);
  return results;
}

function requireRevenueCatSecretAPIKey(): string {
  const apiKey = Deno.env.get("REVENUECAT_SECRET_API_KEY")?.trim() ?? "";
  if (!apiKey) throw new Error("REVENUECAT_SECRET_API_KEY is required.");
  if (!apiKey.startsWith("sk_")) {
    throw new Error(
      "REVENUECAT_SECRET_API_KEY must be a server-side secret key, not a public SDK key.",
    );
  }
  return apiKey;
}

function printBetaEntitlementGrantSummary(
  summary: BetaEntitlementGrantSummary,
): void {
  console.log(`mode: ${summary.mode}`);
  console.log(`selection: ${summary.selection}`);
  console.log(`entitlement_id: ${summary.entitlement_id}`);
  console.log(`expires_at: ${summary.expires_at ?? "required_for_apply"}`);
  console.log(`candidate_count: ${summary.candidate_count}`);
  console.log(`already_active_count: ${summary.already_active_count}`);
  console.log(`granted_count: ${summary.granted_count}`);
  console.log(`failed_count: ${summary.failed_count}`);
  console.log(
    `revenuecat_requests_performed: ${summary.revenuecat_requests_performed}`,
  );
}

function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function timestampMilliseconds(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function validatedEntitlementID(value: string): string {
  if (!/^[A-Za-z0-9._-]{1,100}$/.test(value)) {
    throw new Error("--entitlement-id contains unsupported characters.");
  }
  return value;
}

function boundedPositiveInteger(
  value: string,
  argument: string,
  maximum: number,
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new Error(`${argument} must be between 1 and ${maximum}.`);
  }
  return parsed;
}

function nextArgument(
  rawArgs: string[],
  index: number,
  argument: string,
): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${argument} requires a value.`);
  }
  return value;
}

async function retryPause(attempt: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, attempt * 250));
}
