import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { requireClaimsAuth } from "../_shared/claimsAuth.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function finiteNumber(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return typeof value === "number" && Number.isFinite(value) &&
      value >= minimum && value <= maximum
    ? value
    : null;
}

function boundedString(value: unknown, maximumLength: number): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maximumLength
    ? normalized
    : null;
}

Deno.serve((req: Request) =>
  withEdgeHandler(
    req,
    async (user, supabaseAdmin) => {
      if (req.method !== "POST") {
        return jsonResponse({ error: "Method Not Allowed" }, 405);
      }

      let body: Record<string, unknown>;
      try {
        body = await req.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON body" }, 400);
      }

      const scanId = typeof body.scan_id === "string"
        ? body.scan_id.trim().toLowerCase()
        : "";
      if (!uuidPattern.test(scanId)) {
        return jsonResponse({ error: "scan_id must be a valid UUID." }, 400);
      }

      const context: Record<string, unknown> = {};
      const gpsElevation = finiteNumber(
        body.gps_elevation ?? body.gpsElevation,
        -500,
        9500,
      );
      const weatherTemperature = finiteNumber(
        body.weather_temperature_f ?? body.weatherTemperatureF,
        -200,
        200,
      );
      const weatherCondition = boundedString(
        body.weather_condition ?? body.weatherCondition,
        120,
      );
      const semanticLocation = boundedString(
        body.semantic_location ?? body.semanticLocation,
        240,
      );

      if (gpsElevation != null) context.gps_elevation = gpsElevation;
      if (weatherTemperature != null) {
        context.weather_temperature_f = weatherTemperature;
      }
      if (weatherCondition != null) {
        context.weather_condition = weatherCondition;
      }
      if (semanticLocation != null) {
        context.semantic_location = semanticLocation;
      }
      if (Object.keys(context).length === 0) {
        return jsonResponse(
          { error: "No valid deferred context fields." },
          400,
        );
      }

      const { data, error } = await supabaseAdmin.rpc(
        "apply_or_stage_scan_context",
        {
          p_scan_id: scanId,
          p_user_id: user.id,
          p_context: context,
        },
      );
      if (error) {
        logStructuredError("update-scan-context/apply_failed", {
          user_id: user.id,
          scan_id: scanId,
          error: error.message,
        });
        return jsonResponse({ error: "Scan ingestion is not ready." }, 409);
      }

      return jsonResponse({ success: true, applied: data === true });
    },
    { authenticate: requireClaimsAuth },
  )
);
