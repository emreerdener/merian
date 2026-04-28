/**
 * Standardized Cross-Origin Resource Sharing headers for browser preflight bypassing.
 */
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE",
};

/**
 * Standardized JSON response helper.
 */
export function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

/**
 * Timing-safe string comparison to prevent timing attacks on secret validation.
 * Uses constant-time XOR comparison so execution time does not reveal partial matches.
 */
export function timingSafeCompare(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  if (aBytes.byteLength !== bBytes.byteLength) return false;
  let result = 0;
  for (let i = 0; i < aBytes.byteLength; i++) {
    result |= aBytes[i] ^ bBytes[i];
  }
  return result === 0;
}

/**
 * Validates that all required fields are present and, for strings, non-empty in the request body.
 *
 * Returns a 400 `Response` if any field is missing or null, or if a required string field
 * is empty/whitespace-only. Boolean `false` and numeric `0` are treated as present.
 * Otherwise returns `null`
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
  const missing = fields.filter((field) => {
    if (!(field in body)) return true;

    const value = body[field];
    if (value === null || value === undefined) return true;
    if (typeof value === "string" && value.trim().length === 0) return true;

    return false;
  });
  if (missing.length === 0) return null;
  return jsonResponse(
    {
      error: `Missing required parameter${
        missing.length > 1 ? "s" : ""
      }: ${missing.join(", ")}`,
    },
    400,
  );
}

/**
 * Parses a JSON object body and returns a standardized 400 response when the
 * payload is missing or malformed.
 */
export async function parseJsonBody(
  req: Request,
): Promise<Record<string, unknown> | Response> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
    return jsonResponse({ error: "JSON body must be an object." }, 400);
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
}
