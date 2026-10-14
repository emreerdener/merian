import { requirePublicApiKeys } from "../../../functions/_shared/publishableKey.ts";
import { LIMITS, validAlias } from "../policy.ts";

export const PROJECT_REF = "qlarqavoqhkuwzmevrmf";
export const PROJECT_URL = `https://${PROJECT_REF}.supabase.co`;
export const ROUTE = "cpm-verifier-characterization";
export const BUCKET = "merian-cpm-verifier-fixtures";
export const OPERATOR_ALIAS = "qualification-operator";
export const DENIED_BEARER = "cpm-deliberately-invalid-caller";
export const SECRET_NAMES = Object.freeze(
  [
    "CPM_Q_RUN",
    "CPM_Q_OPERATOR_ID",
    "CPM_Q_CAPABILITY",
    "CPM_Q_EXPIRES_AT",
    "CPM_Q_R2_ENDPOINT",
    "CPM_Q_R2_ACCESS_KEY_ID",
    "CPM_Q_R2_SECRET_ACCESS_KEY",
  ] as const,
);
export interface RuntimeConfig {
  run: string;
  operatorID: string;
  capability: string;
  expiresAt: number;
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
  publicKey: string;
}
/** Read only named configuration; never enumerate or log the environment. */
export function readConfig(
  get: (key: string) => string | undefined,
  now: number,
): RuntimeConfig {
  const values = SECRET_NAMES.map((name) => get(name) ?? "");
  const [
    run,
    operatorID,
    capability,
    expiry,
    endpoint,
    accessKeyId,
    secretAccessKey,
  ] = values;
  const expiresAt = Number(expiry);
  if (
    get("SUPABASE_URL") !== PROJECT_URL || !validAlias(run) ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(operatorID) ||
    !/^[A-Za-z0-9_-]{32,128}$/.test(capability) ||
    !/^\d{13}$/.test(expiry) || !Number.isSafeInteger(expiresAt) ||
    expiresAt <= now || expiresAt - now > LIMITS.runMs ||
    !/^https:\/\/[a-f0-9]{32}\.r2\.cloudflarestorage\.com\/?$/.test(endpoint) ||
    !/^[a-f0-9]{32}$/i.test(accessKeyId) ||
    !/^[a-f0-9]{64}$/i.test(secretAccessKey)
  ) throw Error("qualification_config");
  const { publicApiKey } = requirePublicApiKeys({
    envPublishableKeys: get("SUPABASE_PUBLISHABLE_KEYS"),
    envAnonKey: get("SUPABASE_ANON_KEY"),
  });
  return Object.freeze({
    run,
    operatorID,
    capability,
    expiresAt,
    endpoint,
    accessKeyId,
    secretAccessKey,
    publicKey: publicApiKey,
  });
}
