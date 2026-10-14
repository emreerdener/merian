import { LIMITS, validAlias } from "../policy.ts";

export const PROJECT_REF = "qlarqavoqhkuwzmevrmf";
export const PROJECT_URL = `https://${PROJECT_REF}.supabase.co`;
export const ROUTE = "cpm-verifier-characterization";
export const BUCKET = "merian-cpm-verifier-fixtures";
export const OPERATOR_ALIAS = "qualification-operator";
export const AUTH_MODE = "test-run-key-v1";
export function validOperatorKey(value: string): boolean {
  return /^[a-f0-9]{64}$/.test(value);
}
export const DENIED_BEARER = "0".repeat(64);
export const SECRET_NAMES = Object.freeze(
  [
    "CPM_Q_RUN",
    "CPM_Q_OPERATOR_KEY",
    "CPM_Q_CAPABILITY",
    "CPM_Q_EXPIRES_AT",
    "CPM_Q_R2_ENDPOINT",
    "CPM_Q_R2_ACCESS_KEY_ID",
    "CPM_Q_R2_SECRET_ACCESS_KEY",
  ] as const,
);
export interface RuntimeConfig {
  run: string;
  operatorKey: string;
  capability: string;
  expiresAt: number;
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
}
/** Read only named configuration; never enumerate or log the environment. */
export function readConfig(
  get: (key: string) => string | undefined,
  now: number,
): RuntimeConfig {
  const values = SECRET_NAMES.map((name) => get(name) ?? "");
  const [
    run,
    operatorKey,
    capability,
    expiry,
    endpoint,
    accessKeyId,
    secretAccessKey,
  ] = values;
  const expiresAt = Number(expiry);
  if (
    get("SUPABASE_URL") !== PROJECT_URL || !validAlias(run) ||
    !validOperatorKey(operatorKey) || operatorKey === DENIED_BEARER ||
    operatorKey === capability ||
    operatorKey === secretAccessKey ||
    !/^[A-Za-z0-9_-]{32,128}$/.test(capability) ||
    !/^\d{13}$/.test(expiry) || !Number.isSafeInteger(expiresAt) ||
    expiresAt <= now || expiresAt - now > LIMITS.runMs ||
    !/^https:\/\/[a-f0-9]{32}\.r2\.cloudflarestorage\.com\/?$/.test(endpoint) ||
    !/^[a-f0-9]{32}$/i.test(accessKeyId) ||
    !/^[a-f0-9]{64}$/i.test(secretAccessKey)
  ) throw Error("qualification_config");
  return Object.freeze({
    run,
    operatorKey,
    capability,
    expiresAt,
    endpoint,
    accessKeyId,
    secretAccessKey,
  });
}
