import type { SupabaseClient } from "@supabase/supabase-js";
import {
  clientAddressFromHeaders,
  hmacClientAddressForPurpose,
} from "../_shared/clientAddress.ts";
import { fetchDwcaExportReleaseState } from "../_shared/dwcaReleaseState.ts";
import { publicErrorResponse, requestIdFor } from "../_shared/http.ts";
import { sha256Hex } from "../export-dwca/downloadGrant.ts";
import { createDwcaArchiveRedirectUrl } from "../export-dwca/storage.ts";
import {
  authorizeDwcaArchiveDownload,
  DwcaDownloadAuthorization,
} from "./db.ts";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export interface DownloadDwcaDependencies {
  authorize(
    tokenSha256: string,
    ipHash: string,
  ): Promise<DwcaDownloadAuthorization>;
  hashToken(token: string): Promise<string>;
  hashAddress(address: string): Promise<string>;
  createRedirect(objectKey: string): Promise<string>;
}

export function defaultDownloadDwcaDependencies(
  supabaseAdmin: SupabaseClient,
  clientAddressHashSecret: string,
): DownloadDwcaDependencies {
  return {
    authorize: async (tokenSha256, ipHash) => {
      // Preserve the database-backed per-IP window even while exports are
      // disabled. Random capability-shaped traffic must not turn the release
      // singleton into an unmetered public probe.
      const authorization = await authorizeDwcaArchiveDownload(
        tokenSha256,
        ipHash,
        supabaseAdmin,
      );
      if (
        authorization.status !== "authorized" &&
        authorization.status !== "not_ready"
      ) {
        return authorization;
      }

      const releaseState = await fetchDwcaExportReleaseState(supabaseAdmin);
      if (!releaseState.enabled) return { status: "gone" };
      return authorization;
    },
    hashToken: sha256Hex,
    hashAddress: (address) =>
      hmacClientAddressForPurpose(
        address,
        clientAddressHashSecret,
        "merian-dwca-download-ip-v1",
      ),
    createRedirect: createDwcaArchiveRedirectUrl,
  };
}

export async function handleDownloadDwca(
  req: Request,
  dependencies: DownloadDwcaDependencies,
): Promise<Response> {
  if (req.method !== "GET") {
    return publicErrorResponse(
      req,
      405,
      "method_not_allowed",
      "Method not allowed.",
      { extraHeaders: { Allow: "GET" } },
    );
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  if (
    !TOKEN_PATTERN.test(token) ||
    url.searchParams.getAll("token").length !== 1 ||
    [...url.searchParams.keys()].some((key) => key !== "token")
  ) {
    return unavailableResponse(req, 404, "download_not_found");
  }

  try {
    const [tokenSha256, ipHash] = await Promise.all([
      dependencies.hashToken(token),
      dependencies.hashAddress(clientAddressFromHeaders(req.headers)),
    ]);
    const authorization = await dependencies.authorize(
      tokenSha256,
      ipHash,
    );

    if (authorization.status === "not_found") {
      return unavailableResponse(req, 404, "download_not_found");
    }
    if (authorization.status === "gone") {
      return unavailableResponse(req, 410, "download_unavailable");
    }
    if (authorization.status === "not_ready") {
      return publicErrorResponse(
        req,
        425,
        "download_not_ready",
        "The download is still being finalized. Please try again.",
        {
          retryAfterSeconds: authorization.retryAfterSeconds,
          extraHeaders: { "Cache-Control": "private, no-store" },
        },
      );
    }
    if (authorization.status === "rate_limited") {
      return publicErrorResponse(
        req,
        429,
        "rate_limited",
        "Too many download attempts.",
        {
          retryAfterSeconds: authorization.retryAfterSeconds,
          extraHeaders: { "Cache-Control": "private, no-store" },
        },
      );
    }

    const location = await dependencies.createRedirect(
      authorization.objectKey,
    );
    return new Response(null, {
      status: 303,
      headers: {
        "Cache-Control": "private, no-store",
        "Location": location,
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "X-Request-ID": requestIdFor(req),
      },
    });
  } catch (error) {
    console.error(JSON.stringify({
      event: "dwca_download_authorization_failed",
      request_id: requestIdFor(req),
      error: error instanceof Error ? error.name : typeof error,
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      503,
      "download_unavailable",
      "The download is temporarily unavailable.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}

function unavailableResponse(
  req: Request,
  status: 404 | 410,
  code: "download_not_found" | "download_unavailable",
): Response {
  return publicErrorResponse(
    req,
    status,
    code,
    "The download is unavailable.",
    { extraHeaders: { "Cache-Control": "private, no-store" } },
  );
}
