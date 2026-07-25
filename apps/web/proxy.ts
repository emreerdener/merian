import { NextRequest, NextResponse } from "next/server";
import { canonicalRedirectURL } from "@/lib/canonicalHost";
import {
  explicitSecurityHeaders,
  NONCE_REQUEST_HEADER,
} from "@/lib/securityHeaders";

export function proxy(request: NextRequest) {
  const nonce = crypto.randomUUID().replaceAll("-", "");
  const development = process.env.NODE_ENV !== "production";
  const securityHeaders = explicitSecurityHeaders({ nonce, development });
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(NONCE_REQUEST_HEADER, nonce);
  for (const [name, value] of securityHeaders) {
    requestHeaders.set(name, value);
  }

  const redirectURL = canonicalRedirectURL(
    request.nextUrl.hostname,
    request.nextUrl.pathname,
    request.nextUrl.search,
  );

  const response = redirectURL
    ? NextResponse.redirect(redirectURL, 308)
    : NextResponse.next({ request: { headers: requestHeaders } });
  for (const [name, value] of securityHeaders) {
    response.headers.set(name, value);
  }
  return response;
}
