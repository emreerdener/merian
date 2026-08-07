export const MAX_RESEND_WEBHOOK_BYTES = 64 * 1024;

const SUPPORTED_EVENT_TYPES = [
  "email.delivered",
  "email.delivery_delayed",
  "email.bounced",
  "email.failed",
  "email.suppressed",
] as const;

export type ResendAccountDeletionEventType =
  (typeof SUPPORTED_EVENT_TYPES)[number];

export type ResendAccountDeletionEvent = {
  relevant: true;
  type: ResendAccountDeletionEventType;
  createdAt: string;
  emailId: string;
  attemptId: string;
};

export type IgnoredResendEvent = { relevant: false };

export class ResendPayloadError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ResendPayloadError";
  }
}

export function parseResendAccountDeletionEvent(
  rawBody: string,
): ResendAccountDeletionEvent | IgnoredResendEvent {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    throw new ResendPayloadError("Invalid JSON.");
  }
  if (!isRecord(parsed)) {
    throw new ResendPayloadError("Webhook body must be an object.");
  }

  const eventType = parsed.type;
  if (typeof eventType !== "string" || eventType.length > 64) {
    throw new ResendPayloadError("Webhook event type is invalid.");
  }
  if (!isSupportedEventType(eventType)) return { relevant: false };
  if (!isRecord(parsed.data)) {
    throw new ResendPayloadError("Webhook data is invalid.");
  }

  const tags = parsed.data.tags;
  if (!isRecord(tags) || tags.purpose !== "apple_manual_revocation") {
    return { relevant: false };
  }

  const attemptId = tags.attempt_id;
  const emailId = parsed.data.email_id;
  const createdAt = parsed.created_at;
  if (typeof attemptId !== "string" || !isUuid(attemptId)) {
    throw new ResendPayloadError("Attempt tag is invalid.");
  }
  if (!isSafeIdentifier(emailId)) {
    throw new ResendPayloadError("Provider email identifier is invalid.");
  }
  if (!isSafeTimestamp(createdAt)) {
    throw new ResendPayloadError("Provider event timestamp is invalid.");
  }

  return {
    relevant: true,
    type: eventType,
    createdAt,
    emailId,
    attemptId: attemptId.toLowerCase(),
  };
}

function isSupportedEventType(
  value: string,
): value is ResendAccountDeletionEventType {
  return (SUPPORTED_EVENT_TYPES as readonly string[]).includes(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isSafeIdentifier(value: unknown): value is string {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,255}$/.test(value);
}

function isSafeTimestamp(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 20 &&
    value.length <= 64 &&
    Number.isFinite(Date.parse(value));
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}
