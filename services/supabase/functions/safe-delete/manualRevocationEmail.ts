import {
  fetchWithDeadline,
  readResponseTextWithinLimit,
} from "../_shared/outbound.ts";

const RESEND_EMAIL_ENDPOINT = "https://api.resend.com/emails";
const RESEND_TIMEOUT_MS = 15_000;
const RESEND_RESPONSE_LIMIT_BYTES = 16 * 1024;
const APPLE_MANAGEMENT_URL = "https://account.apple.com/";
const APPLE_SUPPORT_URL = "https://support.apple.com/102571";

export type ManualRevocationDeliveryResult =
  | { succeeded: true; providerDeliveryId: string }
  | { succeeded: false; errorCode: string };

export async function sendManualAppleRevocationEmail(
  recipientEmail: string,
  attemptId: string,
  idempotencyKey: string,
  options: {
    apiKey?: string;
    fetcher?: typeof fetch;
    from?: string;
  } = {},
): Promise<ManualRevocationDeliveryResult> {
  if (
    !isSafeEmail(recipientEmail) ||
    !isUuid(attemptId) ||
    idempotencyKey !== `account-deletion-manual-apple/${attemptId}`
  ) {
    return failure("manual_revocation_email_input_invalid");
  }

  const resendKey = options.apiKey ?? Deno.env.get("RESEND_API_KEY");
  const from = options.from ?? Deno.env.get("ACCOUNT_DELETION_FROM_EMAIL");
  if (!isSafeSecret(resendKey)) {
    return failure("manual_revocation_email_not_configured");
  }
  if (!isSafeSender(from)) {
    return failure("manual_revocation_sender_not_configured");
  }

  let response: Response;
  try {
    response = await fetchWithDeadline(
      RESEND_EMAIL_ENDPOINT,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${resendKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": idempotencyKey,
        },
        body: JSON.stringify({
          from,
          to: [recipientEmail],
          subject:
            "Action required to finish removing Naturebook from Sign in with Apple",
          text: manualRevocationText(),
          html: manualRevocationHtml(),
          tags: [
            { name: "purpose", value: "apple_manual_revocation" },
            { name: "attempt_id", value: attemptId },
          ],
        }),
      },
      {
        fetcher: options.fetcher,
        timeoutMs: RESEND_TIMEOUT_MS,
      },
    );
  } catch {
    return failure("manual_revocation_email_unavailable");
  }

  if (!response.ok) {
    await discardResponseBody(response);
    return failure(`manual_revocation_email_http_${response.status}`);
  }

  let responseText: string;
  try {
    responseText = await readResponseTextWithinLimit(
      response,
      RESEND_RESPONSE_LIMIT_BYTES,
    );
  } catch (error) {
    return failure(
      error instanceof RangeError
        ? "manual_revocation_email_response_oversized"
        : "manual_revocation_email_response_unreadable",
    );
  }

  let responseBody: { id?: unknown } = {};
  try {
    responseBody = JSON.parse(responseText);
  } catch {
    return failure("manual_revocation_email_response_invalid");
  }

  if (!isSafeProviderDeliveryId(responseBody.id)) {
    return failure("manual_revocation_email_response_ambiguous");
  }

  return {
    succeeded: true,
    providerDeliveryId: responseBody.id,
  };
}

function manualRevocationText(): string {
  return [
    "Your Naturebook account deletion is being finalized.",
    "",
    "We did not have an Apple token that could be revoked automatically. One final action is required to stop using Sign in with Apple for Naturebook:",
    "",
    "On iPhone or iPad: open Settings, tap your name, tap Sign in with Apple, select Naturebook (or the Naturebook developer), then tap Delete and confirm.",
    `On the web: sign in at ${APPLE_MANAGEMENT_URL}, open Sign-In & Security, then select Sign in with Apple.`,
    "",
    `Apple's instructions: ${APPLE_SUPPORT_URL}`,
    "",
    "If you already stopped using Sign in with Apple for Naturebook, no further action is needed.",
    "",
    "This automated message contains no Naturebook sign-in or account-restoration link.",
  ].join("\n");
}

function manualRevocationHtml(): string {
  return `
    <h2>One final Apple setting</h2>
    <p>Your Naturebook account deletion is being finalized.</p>
    <p>We did not have an Apple token that could be revoked automatically. One final action is required to stop using Sign in with Apple for Naturebook:</p>
    <ol>
      <li>On iPhone or iPad, open <strong>Settings</strong> and tap your name.</li>
      <li>Tap <strong>Sign in with Apple</strong>.</li>
      <li>Select Naturebook (or the Naturebook developer), then tap <strong>Delete</strong> and confirm.</li>
    </ol>
    <p>You can also manage this on the web under <strong>Sign-In &amp; Security</strong> at <a href="${APPLE_MANAGEMENT_URL}">account.apple.com</a>.</p>
    <p><a href="${APPLE_SUPPORT_URL}">Read Apple's official instructions</a>.</p>
    <p>If you already stopped using Sign in with Apple for Naturebook, no further action is needed.</p>
    <p><small>This automated message contains no Naturebook sign-in or account-restoration link.</small></p>
  `;
}

async function discardResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // The HTTP status remains authoritative when the provider disconnects.
  }
}

function failure(errorCode: string): ManualRevocationDeliveryResult {
  return { succeeded: false, errorCode };
}

function isSafeEmail(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 3 &&
    value.length <= 320 &&
    !containsAsciiControlCharacter(value) &&
    /^[^\s@]+@[^\s@]+$/.test(value);
}

function isSafeSender(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 3 &&
    value.length <= 320 &&
    value.includes("@") &&
    !containsAsciiControlCharacter(value);
}

function isSafeSecret(value: unknown): value is string {
  return typeof value === "string" &&
    value.length >= 8 &&
    value.length <= 1_024 &&
    !containsAsciiControlCharacter(value);
}

function isSafeProviderDeliveryId(value: unknown): value is string {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,255}$/.test(value);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function containsAsciiControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x1F || code === 0x7F) return true;
  }
  return false;
}
