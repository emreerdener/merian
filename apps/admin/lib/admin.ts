import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "./supabase-server";

export type AdminRole = "owner" | "moderator" | "analyst";

export interface AdminAccessState {
  is_authenticated: boolean;
  is_member: boolean;
  role?: AdminRole | null;
  aal?: "aal1" | "aal2";
  session_active?: boolean;
}

const roleRank: Record<AdminRole, number> = { analyst: 1, moderator: 2, owner: 3 };

export async function getAccessState(): Promise<AdminAccessState> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase.rpc("admin_get_access_state");
  if (error) return { is_authenticated: false, is_member: false };
  return data as AdminAccessState;
}

export async function requireAdmin(minimumRole: AdminRole = "analyst") {
  const supabase = await createServerSupabaseClient();
  const { data: userResult } = await supabase.auth.getUser();
  if (!userResult.user) redirect("/login");

  const { data, error } = await supabase.rpc("admin_get_access_state");
  if (error) redirect("/login?error=access-check");
  const access = data as AdminAccessState;
  if (!access.is_member || !access.role) redirect("/login?error=not-authorized");
  if (access.aal !== "aal2") redirect("/mfa");
  if (roleRank[access.role] < roleRank[minimumRole]) redirect("/overview");

  if (!access.session_active) {
    const { error: sessionError } = await supabase.rpc("admin_begin_session");
    if (sessionError) {
      await supabase.auth.signOut();
      redirect("/login?error=session-expired");
    }
  }
  return { supabase, user: userResult.user, role: access.role };
}

export async function adminRpc<T>(
  name: string,
  args: Record<string, unknown> = {},
  minimumRole: AdminRole = "analyst",
): Promise<T> {
  const { supabase } = await requireAdmin(minimumRole);
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data as T;
}
