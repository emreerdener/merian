import { dollarsFromMicrousd, number } from "./format.ts";

export interface PricingCoverage {
  events?: number;
  priced_events?: number;
  unpriced_events?: number;
  estimated_cost_microusd?: number | null;
}

/** A partial estimate must never look like a total, and unknown is not free. */
export function usageCost(
  usage: PricingCoverage,
): { value: string; detail: string } {
  const {
    events,
    priced_events: priced,
    unpriced_events: unpriced,
    estimated_cost_microusd: cost,
  } = usage;
  const validCount = (value: unknown): value is number =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (
    !validCount(events) || !validCount(priced) || !validCount(unpriced) ||
    priced + unpriced !== events || typeof cost !== "number" ||
    !Number.isSafeInteger(cost) || cost < 0 || (priced === 0 && cost !== 0)
  ) {
    return { value: "Unavailable", detail: "Pricing coverage unavailable" };
  }
  if (events === 0) {
    return { value: dollarsFromMicrousd(0), detail: "No recorded usage" };
  }
  if (priced === 0) {
    return {
      value: "Unavailable",
      detail: `${number(unpriced)} events unpriced`,
    };
  }
  return {
    value: dollarsFromMicrousd(cost),
    detail: unpriced > 0
      ? `${number(priced)} of ${number(events)} events priced · ${
        number(unpriced)
      } unpriced; total cost unknown`
      : `All ${number(events)} events priced`,
  };
}

export function attributionLabel(value: string): string {
  switch (value) {
    case "saved_result":
      return "Saved result";
    case "legacy_tier":
      return "Inferred from legacy tier";
    case "execution_metadata":
      return "Execution metadata";
    case "legacy_model":
      return "Inferred from legacy model";
    default:
      return "Unknown";
  }
}
