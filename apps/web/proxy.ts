import { NextRequest, NextResponse } from "next/server";
import { canonicalRedirectURL } from "@/lib/canonicalHost";

export function proxy(request: NextRequest) {
  const redirectURL = canonicalRedirectURL(
    request.nextUrl.hostname,
    request.nextUrl.pathname,
    request.nextUrl.search,
  );

  return redirectURL
    ? NextResponse.redirect(redirectURL, 308)
    : NextResponse.next();
}
