"use client";

import { Button, Group, NumberInput, Select } from "@mantine/core";
import { useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

export function RangeControls({ days }: { days: number }) {
  const router = useRouter();
  const params = useSearchParams();
  const [customDays, setCustomDays] = useState(days > 90 ? days : 365);

  function navigate(nextDays: number, refresh = false) {
    const next = new URLSearchParams(params);
    next.set("days", String(nextDays));
    next.set("tz", Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
    if (refresh) next.set("refresh", "1"); else next.delete("refresh");
    router.push(`?${next.toString()}`);
  }

  return <Group>
    <Select w={150} value={[7, 30, 90, 0].includes(days) ? String(days) : "custom"} data={[{ value: "7", label: "7 days" }, { value: "30", label: "30 days" }, { value: "90", label: "90 days" }, { value: "0", label: "All time" }, { value: "custom", label: "Custom" }]} onChange={(value) => value && value !== "custom" && navigate(Number(value))} />
    {!([7, 30, 90, 0].includes(days)) && <NumberInput w={130} min={1} max={36500} value={customDays} onChange={(value) => setCustomDays(Number(value) || 30)} onBlur={() => navigate(customDays)} suffix=" days" />}
    <Button variant="light" onClick={() => navigate(days, true)}>Refresh</Button>
  </Group>;
}
