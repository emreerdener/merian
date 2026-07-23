export const MAX_REVENUECAT_WEBHOOK_BYTES = 256 * 1024;
const MAX_APP_USER_ID_LENGTH = 1_500;
const MAX_ALIASES = 100;
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NIL_UUID = "00000000-0000-0000-0000-000000000000";

export class RevenueCatPayloadError extends Error {}

export interface RevenueCatWebhookEvent {
  id: string;
  type: string;
  eventTimestampMs: number;
  appUserId: string | null;
  originalAppUserId: string | null;
  aliases: string[];
  transferredFrom: string[];
  transferredTo: string[];
  productId: string | null;
  transactionId: string | null;
  originalTransactionId: string | null;
}

export interface RevenueCatWebhookSubject {
  kind: "customer" | "transfer_source" | "transfer_destination";
  lookupAppUserId: string;
  candidateUserIds: string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function containsControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index++) {
    const code = value.charCodeAt(index);
    if (code <= 31 || code === 127) return true;
  }
  return false;
}

function requiredBoundedString(
  value: unknown,
  field: string,
  maximumLength: number,
): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > maximumLength ||
    containsControlCharacter(value)
  ) {
    throw new RevenueCatPayloadError(`Invalid ${field}.`);
  }
  return value;
}

function optionalBoundedString(
  value: unknown,
  field: string,
  maximumLength: number,
): string | null {
  if (value === undefined || value === null) return null;
  return requiredBoundedString(value, field, maximumLength);
}

function optionalBoundedStringArray(
  value: unknown,
  field: string,
): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > MAX_ALIASES) {
    throw new RevenueCatPayloadError(`Invalid ${field}.`);
  }
  return value.map((item, index) =>
    requiredBoundedString(
      item,
      `${field}[${index}]`,
      MAX_APP_USER_ID_LENGTH,
    )
  );
}

export function parseRevenueCatWebhook(
  rawBody: string,
): RevenueCatWebhookEvent {
  let envelope: unknown;
  try {
    envelope = JSON.parse(rawBody);
  } catch {
    throw new RevenueCatPayloadError("Invalid JSON.");
  }

  if (!isRecord(envelope) || !isRecord(envelope.event)) {
    throw new RevenueCatPayloadError("Missing event.");
  }

  const event = envelope.event;
  const eventTimestampMs = event.event_timestamp_ms;
  if (
    typeof eventTimestampMs !== "number" ||
    !Number.isSafeInteger(eventTimestampMs) ||
    eventTimestampMs < 0 ||
    eventTimestampMs > 253_402_300_799_999
  ) {
    throw new RevenueCatPayloadError("Invalid event_timestamp_ms.");
  }

  const type = requiredBoundedString(event.type, "event.type", 100);
  const aliases = optionalBoundedStringArray(event.aliases, "aliases");
  const transferredFrom = optionalBoundedStringArray(
    event.transferred_from,
    "transferred_from",
  );
  const transferredTo = optionalBoundedStringArray(
    event.transferred_to,
    "transferred_to",
  );
  if (
    type === "TRANSFER" &&
    (transferredFrom.length === 0 || transferredTo.length === 0)
  ) {
    throw new RevenueCatPayloadError(
      "TRANSFER requires transferred_from and transferred_to.",
    );
  }

  return {
    id: requiredBoundedString(event.id, "event.id", 255),
    type,
    eventTimestampMs,
    appUserId: optionalBoundedString(
      event.app_user_id,
      "event.app_user_id",
      MAX_APP_USER_ID_LENGTH,
    ),
    originalAppUserId: optionalBoundedString(
      event.original_app_user_id,
      "event.original_app_user_id",
      MAX_APP_USER_ID_LENGTH,
    ),
    aliases,
    transferredFrom,
    transferredTo,
    productId: optionalBoundedString(event.product_id, "event.product_id", 255),
    transactionId: optionalBoundedString(
      event.transaction_id,
      "event.transaction_id",
      255,
    ),
    originalTransactionId: optionalBoundedString(
      event.original_transaction_id,
      "event.original_transaction_id",
      255,
    ),
  };
}

function candidateMerianUserIdsFromIdentifiers(
  identifiers: Array<string | null>,
): string[] {
  const seen = new Set<string>();
  const candidates: string[] = [];

  for (const identifier of identifiers) {
    if (!identifier || !UUID_REGEX.test(identifier)) continue;
    const normalized = identifier.toLowerCase();
    if (normalized === NIL_UUID || seen.has(normalized)) continue;
    seen.add(normalized);
    candidates.push(normalized);
    if (candidates.length === 32) break;
  }

  return candidates;
}

export function candidateMerianUserIds(
  event: RevenueCatWebhookEvent,
): string[] {
  return candidateMerianUserIdsFromIdentifiers([
    event.appUserId,
    event.originalAppUserId,
    ...event.aliases,
  ]);
}

function subjectFromIdentifiers(
  kind: RevenueCatWebhookSubject["kind"],
  identifiers: string[],
): RevenueCatWebhookSubject | null {
  const candidateUserIds = candidateMerianUserIdsFromIdentifiers(identifiers);
  if (candidateUserIds.length === 0) return null;

  const lookupAppUserId =
    identifiers.find((identifier) => UUID_REGEX.test(identifier)) ??
      identifiers[0];
  if (!lookupAppUserId) return null;

  return { kind, lookupAppUserId, candidateUserIds };
}

export function revenueCatWebhookSubjects(
  event: RevenueCatWebhookEvent,
): RevenueCatWebhookSubject[] {
  if (event.type === "TRANSFER") {
    return [
      subjectFromIdentifiers("transfer_source", event.transferredFrom),
      subjectFromIdentifiers("transfer_destination", event.transferredTo),
    ].filter((subject): subject is RevenueCatWebhookSubject =>
      subject !== null
    );
  }

  const identifiers = [
    event.appUserId,
    event.originalAppUserId,
    ...event.aliases,
  ].filter((identifier): identifier is string => identifier !== null);
  const subject = subjectFromIdentifiers("customer", identifiers);
  return subject ? [subject] : [];
}
