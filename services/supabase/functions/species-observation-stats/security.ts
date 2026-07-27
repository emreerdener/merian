import type { SupabaseClient } from "@supabase/supabase-js";
import {
  bearerTokenFromAuthorizationHeader,
  requireAuth,
} from "../_shared/auth.ts";
import {
  clientAddressFromHeaders,
  ClientAddressHashError,
  hmacClientAddressForPurpose,
  resolveClientAddressHashSecret,
} from "../_shared/clientAddress.ts";
import { requirePublicApiKeysFromEnvironment } from "../_shared/publishableKey.ts";
import { resolveServerApiKeyFromEnvironment } from "../_shared/serviceRoleAuth.ts";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const IP_HASH_PATTERN = /^[0-9a-f]{64}$/;
const DATABASE_TIMEOUT_MS = 5_000;

export class SpeciesObservationStatsError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfterSeconds?: number;

  constructor(
    status: number,
    code: string,
    message: string,
    retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "SpeciesObservationStatsError";
    this.status = status;
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export interface SpeciesObservationStatsSecurityContext {
  userId: string | null;
  ipHash: string;
}

export interface AuthorizedSpeciesObservationStats {
  speciesId: string;
  scientificName: string;
  inaturalistTaxonId: number | null;
}

export interface SpeciesObservationStatsPopulationLease {
  claimed: boolean;
  leaseToken: string | null;
  leaseExpiresAt: string;
  retryAfterSeconds: number;
  cacheAvailable: boolean;
}

interface AuthorizedSpeciesRow {
  species_id?: unknown;
  scientific_name?: unknown;
  inaturalist_taxon_id?: unknown;
  denial_code?: unknown;
}

interface PopulationLeaseRow {
  claimed?: unknown;
  lease_token?: unknown;
  lease_expires_at?: unknown;
  retry_after_seconds?: unknown;
  cache_available?: unknown;
}

export async function resolveSpeciesObservationStatsSecurityContext(
  req: Request,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesObservationStatsSecurityContext> {
  let secret: string;
  try {
    const serverKey = resolveServerApiKeyFromEnvironment();
    secret = resolveClientAddressHashSecret({
      platformSecretKey: serverKey.ok ? serverKey.serverApiKey : undefined,
    });
  } catch (error) {
    if (!(error instanceof ClientAddressHashError)) throw error;
    throw unavailableError();
  }

  let ipHash: string;
  try {
    ipHash = await hmacClientAddressForPurpose(
      clientAddressFromHeaders(req.headers),
      secret,
      "merian-species-stats-ip-v1",
    );
  } catch (error) {
    if (!(error instanceof ClientAddressHashError)) throw error;
    throw unavailableError();
  }

  if (!IP_HASH_PATTERN.test(ipHash)) throw unavailableError();
  await preflightSpeciesObservationStatsRequest(ipHash, supabaseAdmin);
  const userId = await optionalAuthenticatedUserId(req, supabaseAdmin);
  return { userId, ipHash };
}

export async function preflightSpeciesObservationStatsRequest(
  ipHash: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await rpcWithDeadline(
    supabaseAdmin,
    "preflight_species_observation_stats_request",
    { p_ip_hash: ipHash },
  );
  if (error) throw databaseError(error.message);
  if (!Number.isSafeInteger(data) || Number(data) < 1 || Number(data) > 120) {
    throw unavailableError();
  }
}

export async function authorizeSpeciesObservationStatsRequest(
  request: { speciesId: string; scientificName: string },
  context: SpeciesObservationStatsSecurityContext,
  supabaseAdmin: SupabaseClient,
): Promise<AuthorizedSpeciesObservationStats> {
  const { data, error } = await rpcWithDeadline(
    supabaseAdmin,
    "authorize_species_observation_stats_request",
    {
      p_species_id: request.speciesId,
      p_scientific_name: request.scientificName,
      p_user_id: context.userId,
    },
  );

  if (error) throw databaseError(error.message);
  const row = singleRow(data) as AuthorizedSpeciesRow | null;
  if (typeof row?.denial_code === "string" && row.denial_code.length > 0) {
    throw databaseError(row.denial_code);
  }
  const speciesId = typeof row?.species_id === "string"
    ? row.species_id.toLowerCase()
    : "";
  const scientificName = typeof row?.scientific_name === "string"
    ? row.scientific_name.trim().replace(/\s+/g, " ")
    : "";
  const taxonId = row?.inaturalist_taxon_id;
  if (
    !UUID_PATTERN.test(speciesId) ||
    scientificName.length === 0 ||
    scientificName.length > 160 ||
    (taxonId !== null &&
      (!Number.isSafeInteger(taxonId) || Number(taxonId) <= 0))
  ) {
    throw unavailableError();
  }

  return {
    speciesId,
    scientificName,
    inaturalistTaxonId: taxonId === null ? null : Number(taxonId),
  };
}

export async function claimSpeciesObservationStatsPopulation(
  speciesId: string,
  context: SpeciesObservationStatsSecurityContext,
  supabaseAdmin: SupabaseClient,
): Promise<SpeciesObservationStatsPopulationLease> {
  const { data, error } = await rpcWithDeadline(
    supabaseAdmin,
    "claim_species_observation_stats_population",
    {
      p_species_id: speciesId,
      p_user_id: context.userId,
      p_ip_hash: context.ipHash,
    },
  );

  if (error) throw databaseError(error.message);
  const row = singleRow(data) as PopulationLeaseRow | null;
  const claimed = row?.claimed;
  const leaseToken = row?.lease_token;
  const leaseExpiresAt = row?.lease_expires_at;
  const retryAfterSeconds = row?.retry_after_seconds;
  const cacheAvailable = row?.cache_available;
  if (
    typeof claimed !== "boolean" ||
    typeof cacheAvailable !== "boolean" ||
    (leaseToken !== null &&
      (typeof leaseToken !== "string" || !UUID_PATTERN.test(leaseToken))) ||
    typeof leaseExpiresAt !== "string" ||
    !Number.isFinite(Date.parse(leaseExpiresAt)) ||
    !Number.isSafeInteger(retryAfterSeconds) ||
    Number(retryAfterSeconds) < 1 ||
    Number(retryAfterSeconds) > 90 ||
    (claimed && leaseToken === null) ||
    (!claimed && leaseToken !== null) ||
    (claimed && cacheAvailable)
  ) {
    throw unavailableError();
  }

  return {
    claimed,
    leaseToken,
    leaseExpiresAt,
    retryAfterSeconds: Number(retryAfterSeconds),
    cacheAvailable,
  };
}

export async function finalizeSpeciesObservationStatsPopulation(
  input: {
    speciesId: string;
    leaseToken: string;
    taxonId: number | null;
    payload: Record<string, unknown>;
    status: "fresh" | "no_data" | "unavailable" | "partial";
    providerError: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await rpcWithDeadline(
    supabaseAdmin,
    "finalize_species_observation_stats_population",
    {
      p_species_id: input.speciesId,
      p_lease_token: input.leaseToken,
      p_inaturalist_taxon_id: input.taxonId,
      p_payload: input.payload,
      p_status: input.status,
      p_provider_error: input.providerError,
    },
  );
  if (error || typeof data !== "boolean") {
    throw unavailableError();
  }
  return data;
}

async function optionalAuthenticatedUserId(
  req: Request,
  supabaseAdmin: SupabaseClient,
): Promise<string | null> {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return null;

  const token = bearerTokenFromAuthorizationHeader(authorization);
  if (!token) {
    throw new SpeciesObservationStatsError(
      401,
      "invalid_session_token",
      "Invalid Authorization header.",
    );
  }

  // Supabase clients invoke public functions with the project publishable/anon
  // key when no user session exists. That credential identifies the project,
  // not a user, so the request remains in the IP-only bucket.
  if (token.startsWith("sb_publishable_")) return null;
  const { acceptedPublicApiKeys } = requirePublicApiKeysFromEnvironment();
  if (acceptedPublicApiKeys.includes(token)) return null;

  const { user, response } = await requireAuth(req, supabaseAdmin);
  if (response || !user || !UUID_PATTERN.test(user.id)) {
    throw new SpeciesObservationStatsError(
      401,
      "invalid_session_token",
      "Invalid or expired session token.",
    );
  }
  return user.id.toLowerCase();
}

async function rpcWithDeadline(
  supabaseAdmin: SupabaseClient,
  name: string,
  args: Record<string, unknown>,
): Promise<{
  data: unknown;
  error: { message: string; code?: string } | null;
}> {
  try {
    return await supabaseAdmin.rpc(name, args).abortSignal(
      AbortSignal.timeout(DATABASE_TIMEOUT_MS),
    );
  } catch {
    throw unavailableError();
  }
}

function singleRow(data: unknown): Record<string, unknown> | null {
  if (Array.isArray(data)) {
    if (data.length !== 1) return null;
    const row = data[0];
    return row && typeof row === "object" && !Array.isArray(row)
      ? row as Record<string, unknown>
      : null;
  }
  return data && typeof data === "object" && !Array.isArray(data)
    ? data as Record<string, unknown>
    : null;
}

function databaseError(message: string): SpeciesObservationStatsError {
  if (
    message.includes("species_stats_request_user_rate_limited") ||
    message.includes("species_stats_request_ip_rate_limited") ||
    message.includes("species_stats_population_user_rate_limited") ||
    message.includes("species_stats_population_ip_rate_limited") ||
    message.includes("species_stats_population_global_rate_limited")
  ) {
    return new SpeciesObservationStatsError(
      429,
      "species_stats_rate_limited",
      "Too many species-stat requests. Try again shortly.",
      60,
    );
  }
  if (
    message.includes("species_stats_species_not_found") ||
    message.includes("species_stats_species_mismatch")
  ) {
    return new SpeciesObservationStatsError(
      404,
      "species_stats_species_not_found",
      "Species is not available in the Merian dictionary.",
    );
  }
  if (message.includes("species_stats_invalid_request")) {
    return new SpeciesObservationStatsError(
      400,
      "species_stats_invalid_request",
      "Species-stat request is invalid.",
    );
  }
  return unavailableError();
}

function unavailableError(): SpeciesObservationStatsError {
  return new SpeciesObservationStatsError(
    503,
    "species_stats_unavailable",
    "Species statistics are temporarily unavailable.",
    30,
  );
}
