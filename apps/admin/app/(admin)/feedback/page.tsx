import { Badge, Button, Card, Group, NativeSelect, Stack, Text, Textarea, TextInput, Title } from "@mantine/core";
import { updateFeedback } from "@/app/actions";
import { adminRpc } from "@/lib/admin";
import { dateTime, text } from "@/lib/format";

interface FeedbackQueue {
  items: Record<string, unknown>[];
  limit: number;
  next_cursor?: { created_at: string; id: string } | null;
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default async function FeedbackPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const source = ["community", "survey", "chat_message", "chat_feature"].includes(params.source ?? "") ? params.source : null;
  const status = ["new", "reviewed", "planned", "closed"].includes(params.status ?? "") ? params.status : null;
  const rating = params.rating?.trim().slice(0, 40) || null;
  const appVersion = params.version?.trim().slice(0, 40) || null;
  const cursorId = uuidPattern.test(params.cursor_id ?? "") ? params.cursor_id : null;
  const cursorCreatedAt = cursorId && params.cursor_created_at && !Number.isNaN(Date.parse(params.cursor_created_at)) ? params.cursor_created_at : null;
  const data = await adminRpc<FeedbackQueue>("admin_list_feedback", {
    p_source_type: source,
    p_status: status,
    p_rating: rating,
    p_app_version: appVersion,
    p_cursor_created_at: cursorCreatedAt,
    p_cursor_id: cursorId,
    p_limit: 100,
  }, "moderator");

  const nextParams = new URLSearchParams();
  for (const key of ["source", "status", "rating", "version"]) if (params[key]) nextParams.set(key, params[key]);
  if (data.next_cursor) {
    nextParams.set("cursor_created_at", data.next_cursor.created_at);
    nextParams.set("cursor_id", data.next_cursor.id);
  }

  return (
    <Stack>
      <Group justify="space-between" align="flex-end">
        <div><Title>Feedback</Title><Text c="dimmed">Original submissions are immutable; workflow state is an internal overlay.</Text></div>
        <form>
          <Group align="end">
            <NativeSelect name="source" label="Source" defaultValue={source ?? ""} data={[{ value: "", label: "All sources" }, "community", "survey", "chat_message", "chat_feature"]} />
            <NativeSelect name="status" label="State" defaultValue={status ?? ""} data={[{ value: "", label: "All states" }, "new", "reviewed", "planned", "closed"]} />
            <TextInput name="rating" label="Rating" defaultValue={rating ?? ""} />
            <TextInput name="version" label="App version" defaultValue={appVersion ?? ""} />
            <Button type="submit" variant="light">Apply</Button>
          </Group>
        </form>
      </Group>
      {data.items.map((item) => (
        <Card key={`${String(item.source_type)}-${String(item.source_id)}`} withBorder>
          <Group justify="space-between"><div><Badge>{text(item.source_type)}</Badge><Text size="sm" c="dimmed" mt={4}>{dateTime(item.created_at)} · {text(item.public_username, text(item.email))}</Text></div><Badge variant="light">{text(item.status)}</Badge></Group>
          <pre className="json-context">{JSON.stringify(item.payload, null, 2)}</pre>
          <form action={updateFeedback}>
            <input type="hidden" name="source_type" value={String(item.source_type)} />
            <input type="hidden" name="source_id" value={String(item.source_id)} />
            <Group align="end">
              <NativeSelect name="status" label="State" defaultValue={text(item.status)} data={["new", "reviewed", "planned", "closed"]} />
              <TextInput name="assigned_to" label="Assignee UUID" defaultValue={text(item.assigned_to, "")} />
              <TextInput name="tags" label="Tags" placeholder="bug, ios" defaultValue={Array.isArray(item.tags) ? item.tags.join(", ") : ""} flex={1} />
              <Textarea name="note" label="Internal note" maxLength={4000} flex={2} />
              <Button type="submit">Save</Button>
            </Group>
          </form>
        </Card>
      ))}
      {data.next_cursor && data.items.length === data.limit && <Button component="a" href={`/feedback?${nextParams.toString()}`} variant="subtle" ml="auto">Next page</Button>}
    </Stack>
  );
}
