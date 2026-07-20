import { Card, SimpleGrid, Stack, Text, Title } from "@mantine/core";
import { notFound } from "next/navigation";
import { adminRpc } from "@/lib/admin";

export default async function UserDetailPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(userId)) notFound();
  const data = await adminRpc<Record<string, unknown>>("admin_get_user_detail", { p_user_id: userId }, "moderator");
  return <Stack><div><Title order={2}>Account detail</Title><Text c="dimmed">{userId}</Text></div><SimpleGrid cols={{ base: 1, lg: 2 }}>{Object.entries(data).map(([key, value]) => <Card key={key} withBorder><Title order={4}>{key.replaceAll("_", " ")}</Title><pre className="json-context">{JSON.stringify(value, null, 2)}</pre></Card>)}</SimpleGrid></Stack>;
}
