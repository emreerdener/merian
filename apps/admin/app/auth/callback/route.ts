import { type NextRequest, NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { adminRedirectURL, safeAdminRedirectPath } from "@/lib/adminRedirect";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const requestedNext = request.nextUrl.searchParams.get("next");
  const next = safeAdminRedirectPath(requestedNext);
  if (!code) {
    return NextResponse.redirect(adminRedirectURL("/login?error=oauth"));
  }
  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  return NextResponse.redirect(
    adminRedirectURL(error ? "/login?error=oauth" : next),
  );
}
