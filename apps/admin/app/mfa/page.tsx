import { Center } from "@mantine/core";
import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { MfaCard } from "./MfaCard";

export default async function MfaPage() {
  const supabase = await createServerSupabaseClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) redirect("/login");
  const { data: access, error } = await supabase.rpc("admin_get_access_state");
  if (error || !access?.is_member) redirect("/login?error=not-authorized");
  if (access.aal === "aal2") redirect("/overview");
  return <Center mih="100vh"><MfaCard /></Center>;
}
