import { Badge, Card, Group, SimpleGrid, Stack, Text, Title } from "@mantine/core";
import { Suspense } from "react";
import { RangeControls } from "@/components/RangeControls";
import { adminRpc } from "@/lib/admin";
import { dollarsFromMicrousd, number } from "@/lib/format";

interface Overview {
  range_start: string; range_end: string; coverage_complete_from?: string | null;
  accounts: Record<string, number>; plans: Record<string, number>;
  open_reviews: number; new_feedback: number;
  ai: Record<string, number>; previous_period?: Record<string, number> | null;
  daily: Array<{ day: string; scans: number; total_tokens: number; estimated_cost_microusd: number }>;
}

export default async function OverviewPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const params = await searchParams;
  const parsedDays = Number(params.days ?? 30);
  const days = Number.isFinite(parsedDays) ? Math.max(0, Math.min(36500, Math.floor(parsedDays))) : 30;
  const timezone = params.tz?.slice(0, 80) || "UTC";
  const data = await adminRpc<Overview>("admin_get_overview", { p_days: days, p_timezone: timezone, p_refresh: params.refresh === "1" });
  const maxTokens = Math.max(1, ...data.daily.map((day) => Number(day.total_tokens)));
  const cards = [
    ["Registered", number(data.accounts.registered), `Ghost ${number(data.accounts.ghost)}`],
    ["Effective Pro", number((data.plans.pro_paid ?? 0) + (data.plans.pro_complimentary ?? 0) + (data.plans.pro_trial ?? 0)), `Paid ${number(data.plans.pro_paid)} · Complimentary ${number(data.plans.pro_complimentary)} · Historical trial ${number(data.plans.pro_trial)}`],
    ["Completed scans", number(data.daily.reduce((sum, day) => sum + Number(day.scans), 0)), "Primary identification events"],
    ["Open reviews", number(data.open_reviews), "Open and in review"],
    ["Unread feedback", number(data.new_feedback), "All feedback sources"],
    ["AI tokens", number(data.ai.total_tokens), `${number(data.ai.avg_tokens_per_scan)} avg / scan`],
    ["Estimated spend", dollarsFromMicrousd(data.ai.estimated_cost_microusd), "Effective-dated Gemini pricing"],
  ];
  return <Stack gap="xl"><Group justify="space-between" align="end"><div><Title>Overview</Title><Text c="dimmed">Authorized aggregate operations metrics</Text></div><Suspense><RangeControls days={days} /></Suspense></Group><div className="metric-grid">{cards.map(([label, value, note]) => <Card key={label} withBorder><Text size="sm" c="dimmed">{label}</Text><Text fz={28} fw={750}>{value}</Text><Text size="xs" c="dimmed">{note}</Text></Card>)}</div><Card withBorder><Group justify="space-between"><div><Text fw={700}>Daily tokens</Text><Text size="sm" c="dimmed">Browser timezone: {timezone}</Text></div><Badge variant="light">{days === 0 ? "All time" : `${days} days`}</Badge></Group><div className="trend" aria-label="Daily AI token trend">{data.daily.map((day) => <div key={day.day} className="trend-bar" title={`${day.day}: ${number(day.total_tokens)} tokens`} style={{ height: `${Math.max(3, Number(day.total_tokens) / maxTokens * 130)}px` }} />)}</div></Card>{data.coverage_complete_from && <Text size="xs" c="dimmed">Complete usage coverage begins {new Date(data.coverage_complete_from).toLocaleDateString()}; earlier data is labeled partial or primary-only.</Text>}</Stack>;
}
