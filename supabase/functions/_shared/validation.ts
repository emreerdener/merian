import { jsonResponse } from "./edgeHandler.ts";

/**
 * Validates that all required fields are present and non-empty in the request body.
 *
 * Returns a 400 `Response` if any field is missing or falsy, otherwise returns `null`
 * so the caller can proceed.
 *
 * @example
 * const err = requireParams(body, ["scan_id", "scientific_name"]);
 * if (err) return err;
 */
export function requireParams(
  body: Record<string, unknown>,
  fields: string[],
): Response | null {
  const missing = fields.filter((f) => !body[f]);
  if (missing.length === 0) return null;
  return jsonResponse(
    {
      error: `Missing required parameter${missing.length > 1 ? "s" : ""}: ${missing.join(", ")}`,
    },
    400,
  );
}
