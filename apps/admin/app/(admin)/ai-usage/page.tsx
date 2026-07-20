import { Badge, Button, Card, Group, NativeSelect, SimpleGrid, Stack, Text, TextInput, Title } from "@mantine/core";
import { Suspense } from "react";
import { RangeControls } from "@/components/RangeControls";
import { adminRpc } from "@/lib/admin";
import { dollarsFromMicrousd, number } from "@/lib/format";

interface Usage {
  events: number;
  prompt_tokens: number;
  cached_tokens: number;
  candidate_tokens: number;
  thinking_tokens: number;
  tool_tokens: number;
  total_tokens: number;
  estimated_cost_microusd: number;
  cache_hit_rate: number;
  scan_avg: number;
  scan_p50: number;
  scan_p95: number;
  scan_scope: string;
  modality_tokens: Record<string, number>;
  complete_from?: string | null;
  daily: Array<{ day: string; events: number; total_tokens: number; estimated_cost_microusd: number }>;
}

export default async function AIUsagePage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const raw = Number(params.days ?? 30);
  const days = Number.isFinite(raw) ? Math.max(0, Math.min(36500, Math.floor(raw))) : 30;
  const operation = params.operation?.trim().slice(0, 80) || null;
  const model = params.model?.trim().slice(0, 120) || null;
  const plan = ["free", "pro_paid", "pro_trial", "unknown"].includes(params.plan ?? "") ? params.plan : null;
  const modality = ["text", "image", "audio", "video", "mixed", "unknown"].includes(params.modality ?? "") ? params.modality : null;
  const scanScope = params.scan_scope === "all_scan_related" ? "all_scan_related" : "primary";
  const data = await adminRpc<Usage>("admin_ai_usage_summary", {
    p_days: days,
    p_operation: operation,
    p_model: model,
    p_effective_plan: plan,
    p_input_modality: modality,
    p_scan_scope: scanScope,
    p_refresh: params.refresh === "1",
  });
  const metrics = [
    ["Events", number(data.events)],
    ["Total tokens", number(data.total_tokens)],
    ["Prompt / cached", `${number(data.prompt_tokens)} / ${number(data.cached_tokens)}`],
    ["Candidate / thinking", `${number(data.candidate_tokens)} / ${number(data.thinking_tokens)}`],
    ["Tool tokens", number(data.tool_tokens)],
    ["Cache rate", `${number(data.cache_hit_rate)}%`],
    ["Estimated spend", dollarsFromMicrousd(data.estimated_cost_microusd)],
    ["Scan avg", number(data.scan_avg)],
    ["Scan p50 / p95", `${number(data.scan_p50)} / ${number(data.scan_p95)}`],
  ];
  const maxTokens = Math.max(1, ...data.daily.map((day) => Number(day.total_tokens)));

  return (
    <Stack>
      <Group justify="space-between" align="flex-end">
        <div><Title>AI usage</Title><Text c="dimmed">Canonical token ledger and effective-dated estimated cost.</Text></div>
        <Suspense><RangeControls days={days} /></Suspense>
      </Group>
      <Card withBorder>
        <form>
          <input type="hidden" name="days" value={days} />
          <Group align="end">
            <TextInput name="operation" label="Feature / operation" defaultValue={operation ?? ""} />
            <TextInput name="model" label="Model" defaultValue={model ?? ""} />
            <NativeSelect name="plan" label="Plan" defaultValue={plan ?? ""} data={[{ value: "", label: "All plans" }, "free", "pro_paid", "pro_trial", "unknown"]} />
            <NativeSelect name="modality" label="Modality" defaultValue={modality ?? ""} data={[{ value: "", label: "All modalities" }, "text", "image", "audio", "video", "mixed", "unknown"]} />
            <NativeSelect name="scan_scope" label="Per-scan scope" defaultValue={scanScope} data={[{ value: "primary", label: "Primary identification" }, { value: "all_scan_related", label: "All scan-related" }]} />
            <Button type="submit" variant="light">Apply</Button>
          </Group>
        </form>
      </Card>
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }}>{metrics.map(([label, value]) => <Card withBorder key={label}><Text c="dimmed" size="sm">{label}</Text><Text fz="xl" fw={700}>{value}</Text></Card>)}</SimpleGrid>
      <Card withBorder>
        <Group justify="space-between"><Title order={4}>Daily usage</Title><Badge variant="light">{scanScope === "primary" ? "Primary identification" : "All scan-related"}</Badge></Group>
        <div className="trend" aria-label="Daily AI token trend">{data.daily.map((day) => <div key={day.day} className="trend-bar" title={`${day.day}: ${number(day.total_tokens)} tokens · ${dollarsFromMicrousd(day.estimated_cost_microusd)}`} style={{ height: `${Math.max(3, Number(day.total_tokens) / maxTokens * 130)}px` }} />)}</div>
      </Card>
      <Card withBorder><Title order={4}>Prompt token modalities</Title><pre className="json-context">{JSON.stringify(data.modality_tokens, null, 2)}</pre></Card>
      {data.complete_from && <Text size="xs" c="dimmed">Complete-coverage cutover: {new Date(data.complete_from).toLocaleString()}. Earlier periods are partial.</Text>}
    </Stack>
  );
}
