import { timingSafeCompare } from "../../../functions/_shared/http.ts";
import { DENIED_BEARER, OPERATOR_ALIAS, validOperatorKey } from "./config.ts";

/** Test-only possession credential. No product identity, Auth API, session or
 * privileged client. The handler separately enforces run capability and expiry. */
export function authAdapter(operatorKey: string) {
  if (!validOperatorKey(operatorKey) || operatorKey === DENIED_BEARER) {
    throw Error("operator_key_config");
  }
  return (bearer: string, signal: AbortSignal): Promise<string | null> => {
    signal.throwIfAborted();
    // Bound the input before encoding/comparison; differing lengths are public.
    const accepted = validOperatorKey(bearer) &&
      timingSafeCompare(bearer, operatorKey);
    return Promise.resolve(accepted ? OPERATOR_ALIAS : null);
  };
}
