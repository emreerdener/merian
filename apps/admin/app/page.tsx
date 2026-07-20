import { redirect } from "next/navigation";
import { getAccessState } from "@/lib/admin";

export default async function Home() {
  const access = await getAccessState();
  if (!access.is_authenticated || !access.is_member) redirect("/login");
  if (access.aal !== "aal2") redirect("/mfa");
  redirect("/overview");
}
