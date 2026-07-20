import { Badge, Button, Card, Group, NativeSelect, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import { revokeAdminSession, upsertMember } from "@/app/actions";
import { adminRpc } from "@/lib/admin";
import { dateTime, text } from "@/lib/format";

export default async function AccessPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const auditAction = params.action?.trim().slice(0, 100) || null;
  const cursorId = params.audit_id && /^\d+$/.test(params.audit_id) ? params.audit_id : null;
  const cursorCreatedAt = cursorId && params.audit_created_at && !Number.isNaN(Date.parse(params.audit_created_at)) ? params.audit_created_at : null;
  const [members, sessions, audit] = await Promise.all([
    adminRpc<Record<string, unknown>[]>("admin_list_members", {}, "owner"),
    adminRpc<Record<string, unknown>[]>("admin_list_sessions", {}, "owner"),
    adminRpc<{ items: Record<string, unknown>[]; limit: number; next_cursor?: { created_at: string; id: string | number } | null }>("admin_list_audit", {
      p_action: auditAction,
      p_cursor_created_at: cursorCreatedAt,
      p_cursor_id: cursorId,
      p_limit: 100,
    }, "owner"),
  ]);
  const auditNext = new URLSearchParams();
  if (auditAction) auditNext.set("action", auditAction);
  if (audit.next_cursor) {
    auditNext.set("audit_created_at", audit.next_cursor.created_at);
    auditNext.set("audit_id", String(audit.next_cursor.id));
  }

  return (
    <Stack>
      <div>
        <Title>Audit & access</Title>
        <Text c="dimmed">Owner-only membership, active sessions, and immutable access history.</Text>
      </div>

      <Card withBorder>
        <Title order={4}>Add or update member</Title>
        <form action={upsertMember}>
          <Group align="end" mt="md">
            <TextInput name="email" type="email" label="Exact verified Google email" required flex={1} autoComplete="off" />
            <NativeSelect name="role" label="Role" data={["analyst", "moderator", "owner"]} />
            <NativeSelect name="is_active" label="State" data={[{ value: "true", label: "Active" }, { value: "false", label: "Disabled" }]} />
            <Button type="submit">Save member</Button>
          </Group>
        </form>
        <Text size="xs" c="dimmed" mt="xs">The final active owner cannot be disabled or demoted.</Text>
      </Card>

      <Card withBorder>
        <Title order={4}>Memberships</Title>
        <div className="table-scroll">
          <Table>
            <Table.Thead><Table.Tr><Table.Th>Email</Table.Th><Table.Th>Role</Table.Th><Table.Th>State</Table.Th><Table.Th>Updated</Table.Th></Table.Tr></Table.Thead>
            <Table.Tbody>{members.map((member) => <Table.Tr key={String(member.user_id)}><Table.Td>{text(member.email)}</Table.Td><Table.Td><Badge>{text(member.role)}</Badge></Table.Td><Table.Td>{member.is_active ? "Active" : "Disabled"}</Table.Td><Table.Td>{dateTime(member.updated_at)}</Table.Td></Table.Tr>)}</Table.Tbody>
          </Table>
        </div>
      </Card>

      <Card withBorder>
        <Title order={4}>Admin sessions</Title>
        <Stack mt="md">{sessions.map((session) => <Card withBorder key={String(session.session_id)}><Group justify="space-between"><div><Text fw={600}>{text(session.email)}</Text><Text size="xs" c="dimmed">Last seen {dateTime(session.last_seen_at)} · expires {dateTime(session.expires_at)}</Text></div>{session.revoked_at ? <Badge color="red">Revoked</Badge> : <form action={revokeAdminSession}><input type="hidden" name="session_id" value={String(session.session_id)} /><Group><TextInput name="reason" placeholder="Revocation reason" minLength={3} required /><Button type="submit" color="red" variant="light">Revoke</Button></Group></form>}</Group></Card>)}</Stack>
      </Card>

      <Card withBorder>
        <Group justify="space-between" align="end"><Title order={4}>Audit history</Title><form><Group align="end"><TextInput name="action" label="Exact action" defaultValue={auditAction ?? ""} /><Button type="submit" variant="light">Search</Button></Group></form></Group>
        <div className="table-scroll">
          <Table striped>
            <Table.Thead><Table.Tr><Table.Th>Time</Table.Th><Table.Th>Actor</Table.Th><Table.Th>Action</Table.Th><Table.Th>Target</Table.Th><Table.Th>Request</Table.Th></Table.Tr></Table.Thead>
            <Table.Tbody>{audit.items.map((entry) => <Table.Tr key={String(entry.id)}><Table.Td>{dateTime(entry.created_at)}</Table.Td><Table.Td>{text(entry.actor_email)} <Badge size="xs" variant="light">{text(entry.actor_role)}</Badge></Table.Td><Table.Td>{text(entry.action)}</Table.Td><Table.Td>{text(entry.target_type)} {text(entry.target_id, "")}</Table.Td><Table.Td>{text(entry.request_id)}</Table.Td></Table.Tr>)}</Table.Tbody>
          </Table>
        </div>
        {audit.next_cursor && audit.items.length === audit.limit && <Button component="a" href={`/access?${auditNext.toString()}`} variant="subtle" mt="md">Next audit page</Button>}
      </Card>
    </Stack>
  );
}
