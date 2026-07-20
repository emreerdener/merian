import { Anchor, Badge, Button, Group, Select, Stack, Table, Text, TextInput, Title } from "@mantine/core";
import Link from "next/link";
import { AutoRefresh } from "@/components/AutoRefresh";
import { adminRpc } from "@/lib/admin";
import { dateTime, text } from "@/lib/format";

interface Queue {
  items: Record<string, unknown>[];
  limit: number;
  next_cursor?: { updated_at: string; id: string } | null;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;

export default async function ReviewsPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const status = ["open", "in_review", "resolved", "dismissed"].includes(params.status ?? "") ? params.status : null;
  const type = ["identification", "post", "comment", "user"].includes(params.type ?? "") ? params.type : null;
  const priority = ["low", "normal", "high", "urgent"].includes(params.priority ?? "") ? params.priority : null;
  const assignedTo = uuidPattern.test(params.assignee ?? "") ? params.assignee : null;
  const cursorId = uuidPattern.test(params.cursor_id ?? "") ? params.cursor_id : null;
  const cursorUpdatedAt = cursorId && params.cursor_updated_at && !Number.isNaN(Date.parse(params.cursor_updated_at)) ? params.cursor_updated_at : null;
  const from = params.from && datePattern.test(params.from) && !Number.isNaN(Date.parse(params.from)) ? `${params.from}T00:00:00Z` : null;
  const to = params.to && datePattern.test(params.to) && !Number.isNaN(Date.parse(params.to)) ? `${params.to}T23:59:59.999Z` : null;
  const reason = params.reason?.trim().slice(0, 100) || null;
  const data = await adminRpc<Queue>("admin_list_review_cases", {
    p_status: status,
    p_case_type: type,
    p_priority: priority,
    p_assigned_to: assignedTo,
    p_reason: reason,
    p_from: from,
    p_to: to,
    p_cursor_updated_at: cursorUpdatedAt,
    p_cursor_id: cursorId,
    p_limit: 100,
  }, "moderator");

  const nextParams = new URLSearchParams();
  for (const key of ["status", "type", "priority", "assignee", "reason", "from", "to"]) {
    if (params[key]) nextParams.set(key, params[key]);
  }
  if (data.next_cursor) {
    nextParams.set("cursor_updated_at", data.next_cursor.updated_at);
    nextParams.set("cursor_id", data.next_cursor.id);
  }

  return (
    <Stack>
      <AutoRefresh />
      <Group justify="space-between" align="flex-end">
        <div><Title>Review queue</Title><Text c="dimmed">Live on entry; refreshes every 30 seconds.</Text></div>
        <form>
          <Group align="end">
            <Select name="status" label="Status" placeholder="All" clearable defaultValue={status ?? undefined} data={["open", "in_review", "resolved", "dismissed"]} />
            <Select name="type" label="Type" placeholder="All" clearable defaultValue={type ?? undefined} data={["identification", "post", "comment", "user"]} />
            <Select name="priority" label="Priority" placeholder="All" clearable defaultValue={priority ?? undefined} data={["low", "normal", "high", "urgent"]} />
            <TextInput name="assignee" label="Assignee UUID" defaultValue={assignedTo ?? ""} />
            <TextInput name="reason" label="Reason" defaultValue={reason ?? ""} />
            <TextInput name="from" type="date" label="From" defaultValue={params.from ?? ""} />
            <TextInput name="to" type="date" label="To" defaultValue={params.to ?? ""} />
            <Button type="submit" variant="light">Apply</Button>
          </Group>
        </form>
      </Group>
      <div className="table-scroll">
        <Table striped highlightOnHover>
          <Table.Thead><Table.Tr><Table.Th>Updated</Table.Th><Table.Th>Type</Table.Th><Table.Th>Status</Table.Th><Table.Th>Priority</Table.Th><Table.Th>Reports</Table.Th><Table.Th>Account</Table.Th></Table.Tr></Table.Thead>
          <Table.Tbody>{data.items.map((item) => <Table.Tr key={String(item.id)}><Table.Td>{dateTime(item.updated_at)}</Table.Td><Table.Td><Anchor component={Link} href={`/reviews/${String(item.id)}`}>{text(item.case_type)}</Anchor></Table.Td><Table.Td><Badge variant="light">{text(item.status)}</Badge></Table.Td><Table.Td>{text(item.priority)}</Table.Td><Table.Td>{String(item.report_count ?? 0)}</Table.Td><Table.Td>{text(item.public_username, text(item.email))}</Table.Td></Table.Tr>)}</Table.Tbody>
        </Table>
      </div>
      {data.next_cursor && data.items.length === data.limit && <Button component={Link} href={`/reviews?${nextParams.toString()}`} variant="subtle" ml="auto">Next page</Button>}
    </Stack>
  );
}
