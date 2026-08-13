"use client";

import { Anchor, Badge, Button, Card, Group, Stack, Table, Text, TextInput } from "@mantine/core";
import Link from "next/link";
import { useState } from "react";
import { searchUsers } from "@/app/actions";

export function UserSearch() {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<Record<string, unknown>[]>([]);
  const [nextCursor, setNextCursor] = useState<{ created_at: string; id: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function search(loadMore = false) {
    setBusy(true); setError(null);
    try {
      const result = await searchUsers(query, loadMore ? nextCursor : null);
      setItems((current) => loadMore ? [...current, ...result.items] : result.items);
      setNextCursor(result.items.length === result.limit ? result.next_cursor ?? null : null);
    }
    catch (reason) { setError(reason instanceof Error ? reason.message : "Search failed."); }
    finally { setBusy(false); }
  }

  return <Stack><Card withBorder><Group align="end"><TextInput label="Email, UUID, or public handle" value={query} onChange={(event) => setQuery(event.currentTarget.value)} onKeyDown={(event) => { if (event.key === "Enter") void search(); }} flex={1} autoComplete="off" /><Button onClick={() => void search()} loading={busy} disabled={query.trim().length < 2}>Search</Button></Group><Text size="xs" c="dimmed" mt="xs">Search terms are sent in the request body and never placed in the URL.</Text>{error && <Text c="red" size="sm">{error}</Text>}</Card><div className="table-scroll"><Table striped><Table.Thead><Table.Tr><Table.Th>Account</Table.Th><Table.Th>Auth</Table.Th><Table.Th>Plan</Table.Th><Table.Th>Scans</Table.Th><Table.Th>Last sign-in</Table.Th></Table.Tr></Table.Thead><Table.Tbody>{items.map((item) => <Table.Tr key={String(item.id)}><Table.Td><Anchor component={Link} href={`/users/${String(item.id)}`}>{String(item.email ?? item.public_username ?? item.id)}</Anchor><Text size="xs" c="dimmed">{String(item.id)}</Text></Table.Td><Table.Td>{item.is_anonymous ? "Signed out" : "Registered"}</Table.Td><Table.Td><Badge variant="light">{String(item.effective_plan ?? "unknown")}</Badge></Table.Td><Table.Td>{String(item.scan_count ?? 0)}</Table.Td><Table.Td>{item.last_sign_in_at ? new Date(String(item.last_sign_in_at)).toLocaleString() : "—"}</Table.Td></Table.Tr>)}</Table.Tbody></Table></div>{nextCursor && <Button variant="subtle" loading={busy} onClick={() => void search(true)} ml="auto">Load more</Button>}</Stack>;
}
