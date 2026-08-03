import { Badge, Card, Group, SimpleGrid, Stack, Text, Title } from "@mantine/core";
import { adminRpc } from "@/lib/admin";
import { number } from "@/lib/format";

interface ComplimentaryEntitlementSummary {
  grant: number;
  accounts: number;
  accounts_with_complimentary_access: number;
  exhausted_accounts: number;
  exhausted_paid_accounts: number;
  in_flight: number;
  stale_holds_15m: number;
  stale_holds_1h: number;
  oldest_hold_at?: string | null;
  flash_fallback_reservations: number;
  states: Record<string, number>;
  settlement_reasons: Record<string, number>;
  available_balance_histogram: Record<string, number>;
}

function Distribution({ values }: { values: Record<string, number> }) {
  const entries = Object.entries(values).sort(([left], [right]) => left.localeCompare(right));
  if (entries.length === 0) return <Text c="dimmed">No events yet.</Text>;
  return (
    <Stack gap="xs">
      {entries.map(([label, value]) => (
        <Group key={label} justify="space-between">
          <Text>{label.replaceAll("_", " ")}</Text>
          <Badge variant="light">{number(value)}</Badge>
        </Group>
      ))}
    </Stack>
  );
}

export default async function ComplimentaryEntitlementsPage() {
  const data = await adminRpc<ComplimentaryEntitlementSummary>(
    "admin_complimentary_entitlement_summary",
  );
  const metrics = [
    ["Active complimentary", data.accounts_with_complimentary_access],
    ["In flight", data.in_flight],
    ["Exhausted", data.exhausted_accounts],
    ["Converted after exhaustion", data.exhausted_paid_accounts],
    ["Flash fallbacks", data.flash_fallback_reservations],
    ["Stale holds > 15m", data.stale_holds_15m],
    ["Stale holds > 1h", data.stale_holds_1h],
  ] as const;

  return (
    <Stack gap="xl">
      <div>
        <Title>Complimentary scans</Title>
        <Text c="dimmed">
          Lifetime grant {number(data.grant)} across {number(data.accounts)} accounts.
        </Text>
      </div>
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }}>
        {metrics.map(([label, value]) => (
          <Card withBorder key={label}>
            <Text c="dimmed" size="sm">{label}</Text>
            <Text fz="xl" fw={700}>{number(value)}</Text>
          </Card>
        ))}
      </SimpleGrid>
      <Text size="sm" c="dimmed">
        Oldest active hold: {data.oldest_hold_at ? new Date(data.oldest_hold_at).toLocaleString() : "None"}
      </Text>
      <SimpleGrid cols={{ base: 1, md: 3 }}>
        <Card withBorder><Title order={4} mb="md">Ledger states</Title><Distribution values={data.states} /></Card>
        <Card withBorder><Title order={4} mb="md">Settlement reasons</Title><Distribution values={data.settlement_reasons} /></Card>
        <Card withBorder><Title order={4} mb="md">Available balance</Title><Distribution values={data.available_balance_histogram} /></Card>
      </SimpleGrid>
    </Stack>
  );
}
