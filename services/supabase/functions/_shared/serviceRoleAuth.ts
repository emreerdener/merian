import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { timingSafeCompare } from "./http.ts";

export interface ServiceRoleAuthResult {
  ok: boolean;
  token?: string;
  reason?: "missing_token" | "missing_supabase_url" | "probe_failed";
}

export type ServiceRoleProbe = (token: string) => Promise<boolean>;

export function serviceRoleTokenFromRequest(req: Request): string | null {
  const authorization = req.headers.get("Authorization")?.trim() ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (match?.[1]?.trim()) return match[1].trim();

  const apiKey = req.headers.get("apikey")?.trim();
  return apiKey && apiKey.length > 0 ? apiKey : null;
}

export async function authorizeServiceRoleRequest(
  req: Request,
  options: {
    supabaseUrl: string;
    envServiceRoleKey: string;
    probe?: ServiceRoleProbe;
  },
): Promise<ServiceRoleAuthResult> {
  const token = serviceRoleTokenFromRequest(req);
  if (!token) return { ok: false, reason: "missing_token" };

  if (
    options.envServiceRoleKey &&
    timingSafeCompare(token, options.envServiceRoleKey)
  ) {
    return { ok: true, token };
  }

  if (!options.supabaseUrl) {
    return { ok: false, reason: "missing_supabase_url" };
  }

  const probe = options.probe ??
    ((candidateToken) =>
      probeServiceRoleDatabaseAccess(options.supabaseUrl, candidateToken));
  const hasServiceRoleAccess = await probe(token);
  if (!hasServiceRoleAccess) return { ok: false, reason: "probe_failed" };

  return { ok: true, token };
}

async function probeServiceRoleDatabaseAccess(
  supabaseUrl: string,
  token: string,
): Promise<boolean> {
  const supabase = createClient(supabaseUrl, token, {
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: token,
      },
    },
  });

  const { error } = await supabase
    .from("taxonomy_import_runs")
    .select("id", { count: "exact", head: true })
    .limit(1);

  return !error;
}
