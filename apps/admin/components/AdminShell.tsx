"use client";

import { AppShell, Badge, Burger, Button, Group, NavLink, Stack, Text } from "@mantine/core";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, type ReactNode } from "react";
import type { AdminRole } from "@/lib/admin";
import { createBrowserSupabaseClient } from "@/lib/supabase-browser";

const destinations = [
  { href: "/overview", label: "Overview", minimum: 1 },
  { href: "/reviews", label: "Review queue", minimum: 2 },
  { href: "/feedback", label: "Feedback", minimum: 2 },
  { href: "/users", label: "Users", minimum: 2 },
  { href: "/ai-usage", label: "AI usage", minimum: 1 },
  { href: "/access", label: "Audit & access", minimum: 3 },
];
const rank: Record<AdminRole, number> = { analyst: 1, moderator: 2, owner: 3 };

export function AdminShell({ children, role, email }: { children: ReactNode; role: AdminRole; email: string }) {
  const [opened, setOpened] = useState(false);
  const pathname = usePathname();

  async function signOut() {
    await createBrowserSupabaseClient().auth.signOut();
    window.location.assign("/login");
  }

  return (
    <AppShell header={{ height: 64 }} navbar={{ width: 250, breakpoint: "sm", collapsed: { mobile: !opened } }} padding="lg">
      <AppShell.Header px="lg"><Group h="100%" justify="space-between"><Group><Burger opened={opened} onClick={() => setOpened(!opened)} hiddenFrom="sm" size="sm" /><Text fw={800}>Naturebook Internal</Text><Badge variant="light">{role}</Badge></Group><Button variant="subtle" color="gray" onClick={signOut}>Sign out</Button></Group></AppShell.Header>
      <AppShell.Navbar p="md"><Stack gap="xs" h="100%">{destinations.filter((item) => rank[role] >= item.minimum).map((item) => <NavLink key={item.href} component={Link} href={item.href} label={item.label} active={pathname === item.href || pathname.startsWith(`${item.href}/`)} onClick={() => setOpened(false)} />)}<Text mt="auto" size="xs" c="dimmed" truncate>{email}</Text><Text size="xs" c="dimmed">30m idle · 8h maximum</Text></Stack></AppShell.Navbar>
      <AppShell.Main>{children}</AppShell.Main>
    </AppShell>
  );
}
