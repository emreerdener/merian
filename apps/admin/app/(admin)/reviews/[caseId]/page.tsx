import { Badge, Button, Card, Group, NativeSelect, Stack, Text, Textarea, TextInput, Title } from "@mantine/core";
import { notFound } from "next/navigation";
import { setContentVisibility, updateReviewCase } from "@/app/actions";
import { adminRpc } from "@/lib/admin";
import { dateTime, text } from "@/lib/format";

interface Detail {
  case: Record<string, unknown>;
  subject: Record<string, unknown> | null;
  sources: Record<string, unknown>[];
  notes: Record<string, unknown>[];
  scan: Record<string, unknown> | null;
}

export default async function ReviewDetailPage({ params }: { params: Promise<{ caseId: string }> }) {
  const { caseId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(caseId)) notFound();
  const data = await adminRpc<Detail>("admin_get_review_case", { p_case_id: caseId }, "moderator");
  const item = data.case;

  return (
    <Stack>
      <div><Title order={2}>{text(item.case_type)} review</Title><Group><Badge>{text(item.status)}</Badge><Badge color="orange" variant="light">{text(item.priority)}</Badge><Text size="sm" c="dimmed">{dateTime(item.updated_at)}</Text></Group></div>
      <Card withBorder>
        <Title order={4}>Triage</Title>
        <form action={updateReviewCase}>
          <input type="hidden" name="case_id" value={caseId} />
          <Stack mt="md">
            <NativeSelect name="status" label="Status" defaultValue={text(item.status)} data={["open", "in_review", "resolved", "dismissed"]} />
            <NativeSelect name="priority" label="Priority" defaultValue={text(item.priority)} data={["low", "normal", "high", "urgent"]} />
            <TextInput name="assigned_to" label="Assignee UUID (blank to unassign)" defaultValue={text(item.assigned_to, "")} />
            <TextInput name="resolution_code" label="Resolution code" defaultValue={text(item.resolution_code, "")} />
            <Textarea name="note" label="Append internal note" maxLength={4000} />
            <Button type="submit">Save transition</Button>
          </Stack>
        </form>
      </Card>
      {["post", "comment"].includes(text(item.case_type)) && <Card withBorder><Title order={4}>Content visibility</Title><Text size="sm" c="dimmed">Hide or restore is reversible and does not resolve this case.</Text><form action={setContentVisibility}><input type="hidden" name="case_id" value={caseId} /><TextInput name="reason" label="Required reason" minLength={3} required mt="md" /><Group mt="md"><Button name="hidden" value="true" type="submit" color="red">Hide content</Button><Button name="hidden" value="false" type="submit" variant="light">Restore content</Button></Group></form></Card>}
      <Card withBorder><Title order={4}>Reports and evidence</Title>{data.sources.map((source, index) => <Card key={`${String(source.source_id)}-${index}`} withBorder mt="sm"><Text fw={600}>{text(source.source_type)}</Text><pre className="json-context">{JSON.stringify(source.payload, null, 2)}</pre></Card>)}</Card>
      <Card withBorder><Title order={4}>Account context</Title><pre className="json-context">{JSON.stringify(data.subject, null, 2)}</pre></Card>
      {data.scan && <Card withBorder><Title order={4}>Identification context</Title><Text size="xs" c="orange">Exact private coordinates are displayed only here; this access is audited.</Text><pre className="json-context">{JSON.stringify(data.scan, null, 2)}</pre></Card>}
      <Card withBorder><Title order={4}>Action notes</Title><pre className="json-context">{JSON.stringify(data.notes, null, 2)}</pre></Card>
    </Stack>
  );
}
