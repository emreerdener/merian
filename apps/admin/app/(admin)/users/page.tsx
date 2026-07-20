import { Stack, Text, Title } from "@mantine/core";
import { UserSearch } from "@/components/UserSearch";
import { requireAdmin } from "@/lib/admin";

export default async function UsersPage() {
  await requireAdmin("moderator");
  return <Stack><div><Title>Users</Title><Text c="dimmed">Searchable account context. Every search and detail access is audited.</Text></div><UserSearch /></Stack>;
}
