import {
  STAGING_ALLOWED_CONTENT_TYPES,
  validateStagingObjectKey,
} from "../_shared/mediaBudgets.ts";

export type ShareImportValidationError = {
  status: number;
  message: string;
};

export type ShareImportRequest = {
  scan_id?: unknown;
  r2ObjectKey?: unknown;
  r2ObjectKeys?: unknown;
  mimeType?: unknown;
  timestamp?: unknown;
  gpsLatitude?: unknown;
  gpsLongitude?: unknown;
  gpsElevation?: unknown;
  deviceLocale?: unknown;
  deviceTimeZone?: unknown;
  deviceRegion?: unknown;
};

export type ValidShareImportRequest = {
  scanId: string;
  r2ObjectKey: string;
  mimeType: string;
  timestamp: string;
  gpsLatitude: number | null;
  gpsLongitude: number | null;
  gpsElevation: number | null;
  deviceLocale: string;
  deviceTimeZone: string;
  deviceRegion: string | null;
};

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateShareImportRequest(
  body: unknown,
  userId: string,
): { value?: ValidShareImportRequest; error?: ShareImportValidationError } {
  if (!isRecord(body)) {
    return { error: { status: 400, message: "Invalid JSON body" } };
  }

  const request = body as ShareImportRequest;
  const r2ObjectKeys = Array.isArray(request.r2ObjectKeys)
    ? request.r2ObjectKeys
    : request.r2ObjectKey != null
    ? [request.r2ObjectKey]
    : [];

  if (r2ObjectKeys.length !== 1 || typeof r2ObjectKeys[0] !== "string") {
    return {
      error: {
        status: 400,
        message: "Bad Request: exactly one staged image key is required.",
      },
    };
  }

  const r2ObjectKey = r2ObjectKeys[0];
  const keyError = validateStagingObjectKey(r2ObjectKey, userId);
  if (keyError === "path_traversal") {
    return {
      error: {
        status: 400,
        message: "Bad Request: invalid staged image key.",
      },
    };
  }
  if (keyError === "wrong_user") {
    return {
      error: {
        status: 403,
        message: "Forbidden: staged image does not belong to this user.",
      },
    };
  }

  const mimeType = typeof request.mimeType === "string"
    ? request.mimeType
    : "image/webp";
  if (!STAGING_ALLOWED_CONTENT_TYPES.image.includes(mimeType)) {
    return {
      error: {
        status: 400,
        message: "Bad Request: mimeType is not supported for image import.",
      },
    };
  }

  return {
    value: {
      scanId: normalizedScanId(request.scan_id),
      r2ObjectKey,
      mimeType,
      timestamp: normalizedTimestamp(request.timestamp),
      gpsLatitude: safeLatitude(request.gpsLatitude),
      gpsLongitude: safeLongitude(request.gpsLongitude),
      gpsElevation: safeNumber(request.gpsElevation),
      deviceLocale: typeof request.deviceLocale === "string" && request.deviceLocale.length > 0
        ? request.deviceLocale
        : "en",
      deviceTimeZone: typeof request.deviceTimeZone === "string" && request.deviceTimeZone.length > 0
        ? request.deviceTimeZone
        : "UTC",
      deviceRegion: typeof request.deviceRegion === "string" && request.deviceRegion.length > 0
        ? request.deviceRegion
        : null,
    },
  };
}

export function buildIdentifyMultimodalPayload(
  request: ValidShareImportRequest,
  userId: string,
): Record<string, unknown> {
  const captureDate = new Date(request.timestamp);
  const currentMonth = Number.isFinite(captureDate.getTime())
    ? captureDate.getUTCMonth() + 1
    : new Date().getUTCMonth() + 1;

  return {
    user_id: userId,
    client_scan_id: request.scanId,
    r2ObjectKeys: [request.r2ObjectKey],
    mimeType: request.mimeType,
    timestamp: request.timestamp,
    gpsLatitude: request.gpsLatitude,
    gpsLongitude: request.gpsLongitude,
    gpsElevation: request.gpsElevation,
    deviceLocale: request.deviceLocale,
    deviceTimeZone: request.deviceTimeZone,
    deviceRegion: request.deviceRegion,
    currentMonth,
    timeOfDay: timeOfDayLabel(captureDate),
  };
}

export function queuedJobRow(
  request: ValidShareImportRequest,
  userId: string,
): Record<string, unknown> {
  return {
    scan_id: request.scanId,
    user_id: userId,
    status: "queued",
    r2_object_key: request.r2ObjectKey,
    mime_type: request.mimeType,
  };
}

export function jobStatusForIdentifyResponse(
  status: number,
  bodyText: string,
): Record<string, unknown> {
  if (status >= 200 && status < 300) {
    return {
      status: "completed",
      response_status: status,
      error_message: null,
      updated_at: new Date().toISOString(),
    };
  }

  return {
    status: "failed",
    response_status: status,
    error_message: bodyText.slice(0, 1_000),
    updated_at: new Date().toISOString(),
  };
}

function normalizedTimestamp(value: unknown): string {
  if (typeof value === "string") {
    const date = new Date(value);
    if (Number.isFinite(date.getTime())) {
      return date.toISOString();
    }
  }
  return new Date().toISOString();
}

function normalizedScanId(value: unknown): string {
  if (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    return value.toLowerCase();
  }
  return crypto.randomUUID();
}

function safeLatitude(value: unknown): number | null {
  const numberValue = safeNumber(value);
  return numberValue != null && numberValue >= -90 && numberValue <= 90
    ? numberValue
    : null;
}

function safeLongitude(value: unknown): number | null {
  const numberValue = safeNumber(value);
  return numberValue != null && numberValue >= -180 && numberValue <= 180
    ? numberValue
    : null;
}

function safeNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function timeOfDayLabel(date: Date): string {
  if (!Number.isFinite(date.getTime())) {
    return new Date().toISOString().slice(11, 16);
  }
  return date.toISOString().slice(11, 16);
}
