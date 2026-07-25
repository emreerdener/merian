import { readByteStreamWithinLimit } from "../_shared/http.ts";
import { ExportWorkerError } from "./types.ts";

const RESEND_EMAIL_ENDPOINT = "https://api.resend.com/emails";
const RESEND_TIMEOUT_MS = 15_000;
const RESEND_RESPONSE_LIMIT_BYTES = 16 * 1024;
const decoder = new TextDecoder();

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function discardResponseBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // The status remains authoritative when the provider disconnects.
  }
}

export async function sendExportEmail(
  email: string,
  signedUrl: string,
  jobId: string,
  options: {
    apiKey?: string;
    fetcher?: typeof fetch;
    from?: string;
  } = {},
): Promise<string> {
  const resendKey = options.apiKey ?? Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    throw new ExportWorkerError(
      "delivery_failed",
      "RESEND_API_KEY is not configured.",
    );
  }

  let response: Response;
  try {
    response = await (options.fetcher ?? fetch)(RESEND_EMAIL_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `dwca-export/${jobId}`,
      },
      body: JSON.stringify({
        from: options.from ?? Deno.env.get("RESEND_FROM_EMAIL") ??
          "Naturebook Data Exports <onboarding@resend.dev>",
        to: [email],
        subject: "Your Naturebook Darwin Core Archive is Ready",
        html: `
        <h2>Your Export is Ready</h2>
        <p>Your Darwin Core Archive (DwC-A) containing your scans has finished processing.</p>
        <p>This secure link will expire in 24 hours.</p>
        <a href="${
          escapeHtml(signedUrl)
        }" style="display:inline-block;padding:12px 24px;background-color:#007AFF;color:white;text-decoration:none;border-radius:8px;">Download Archive</a>
        <br><br>
        <p>Thank you for contributing to Naturebook!</p>
      `,
      }),
      signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
    });
  } catch (error) {
    throw new ExportWorkerError(
      "delivery_failed",
      "Resend delivery was unavailable.",
      false,
      { cause: error },
    );
  }

  if (!response.ok) {
    await discardResponseBody(response);
    const retryable = response.status === 408 ||
      response.status === 409 ||
      response.status === 425 ||
      response.status === 429 ||
      response.status >= 500;
    throw new ExportWorkerError(
      "delivery_failed",
      `Resend rejected the idempotent export email with HTTP ${response.status}.`,
      !retryable,
    );
  }

  let responseText: string;
  try {
    const result = await readByteStreamWithinLimit(
      response.body,
      RESEND_RESPONSE_LIMIT_BYTES,
      "Resend response exceeded limit",
    );
    if (result.exceeded || !result.bytes) {
      throw new ExportWorkerError(
        "delivery_failed",
        "Resend returned an oversized delivery response.",
        false,
      );
    }
    responseText = decoder.decode(result.bytes);
  } catch (error) {
    if (error instanceof ExportWorkerError) throw error;
    throw new ExportWorkerError(
      "delivery_failed",
      "Resend returned an unreadable delivery response.",
      false,
      { cause: error },
    );
  }
  let responseBody: { id?: unknown; message?: unknown } = {};
  try {
    responseBody = JSON.parse(responseText);
  } catch {
    // The status remains authoritative when an upstream proxy returns text.
  }

  if (typeof responseBody.id !== "string") {
    throw new ExportWorkerError(
      "delivery_failed",
      "Resend accepted the request without a delivery identifier.",
      false,
    );
  }

  return responseBody.id;
}
