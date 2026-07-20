import type { ReactNode } from "react";
import { AdminShell } from "@/components/AdminShell";
import { requireAdmin } from "@/lib/admin";

export const dynamic = "force-dynamic";

export default async function AuthorizedLayout({ children }: { children: ReactNode }) {
  const { user, role } = await requireAdmin();
  return <AdminShell role={role} email={user.email ?? user.id}>{children}</AdminShell>;
}
