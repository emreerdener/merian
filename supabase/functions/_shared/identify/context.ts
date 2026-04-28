import type { MerianIdentification } from "./types.ts";

type LifeStage = MerianIdentification["life_stage"];
type ReproductiveCondition = MerianIdentification["reproductive_condition"];

export const VALID_LIFE_STAGES = new Set([
  "egg",
  "larva",
  "pupa",
  "nymph",
  "juvenile",
  "subadult",
  "adult",
  "seedling",
  "sapling",
  "unknown",
]) as ReadonlySet<NonNullable<LifeStage>>;

export const VALID_REPRODUCTIVE_CONDITIONS = new Set([
  "flowering",
  "fruiting",
  "budding",
  "vegetative",
  "sporing",
  "pregnant",
  "gravid",
  "mating",
  "spawning",
  "nesting",
  "dormant",
  "not_applicable",
]) as ReadonlySet<NonNullable<ReproductiveCondition>>;

export interface TelemetryContextInput {
  safeGpsLat: number | null;
  safeGpsLon: number | null;
  gpsElevation?: number | null;
  depthScaleText?: string | null;
  zoomFactor?: number | null;
  estimatedSizeCm?: number | null;
  semanticLocation?: string | null;
  weatherCondition?: string | null;
  weatherTemperatureF?: number | null;
  deviceLocale?: string | null;
  deviceTimeZone?: string | null;
  deviceRegion?: string | null;
  currentMonth?: number | null;
  timeOfDay?: string | null;
}

export function normalizeCurrentMonth(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    const month = Math.trunc(value);
    return month >= 1 && month <= 12 ? month : undefined;
  }

  if (typeof value === "string") {
    const trimmed = value.trim();
    if (/^\d{1,2}$/.test(trimmed)) {
      const month = Number(trimmed);
      return month >= 1 && month <= 12 ? month : undefined;
    }
  }

  return undefined;
}

export function buildTelemetryItems(telemetry: TelemetryContextInput): string[] {
  return [
    telemetry.safeGpsLat != null && telemetry.safeGpsLon != null
      ? `GPS:${telemetry.safeGpsLat},${telemetry.safeGpsLon}`
      : null,
    telemetry.gpsElevation != null ? `Elev:${telemetry.gpsElevation}m` : null,
    telemetry.depthScaleText ? `Depth:${telemetry.depthScaleText}` : null,
    telemetry.zoomFactor != null && Number.isFinite(telemetry.zoomFactor) && telemetry.zoomFactor > 1
      ? `Zoom:${telemetry.zoomFactor.toFixed(1)}x`
      : null,
    telemetry.estimatedSizeCm != null &&
        Number.isFinite(telemetry.estimatedSizeCm) &&
        telemetry.estimatedSizeCm > 0
      ? `Size:${telemetry.estimatedSizeCm}cm`
      : null,
    telemetry.semanticLocation ? `Loc:${telemetry.semanticLocation}` : null,
    telemetry.weatherCondition ? `Wx:${telemetry.weatherCondition}` : null,
    telemetry.weatherTemperatureF != null ? `Temp:${telemetry.weatherTemperatureF}F` : null,
    telemetry.deviceLocale ? `Locale:${telemetry.deviceLocale}` : null,
    telemetry.deviceTimeZone ? `TZ:${telemetry.deviceTimeZone}` : null,
    telemetry.deviceRegion ? `Region:${telemetry.deviceRegion}` : null,
    telemetry.currentMonth != null ? `Month:${telemetry.currentMonth}` : null,
    telemetry.timeOfDay ? `Time:${telemetry.timeOfDay}` : null,
  ].filter((item): item is string => typeof item === "string" && item.length > 0);
}

export function buildContextText(
  telemetry: TelemetryContextInput,
  trailingInstruction?: string,
): string {
  const contextBody = buildTelemetryItems(telemetry).join(", ") || "no telemetry";
  if (trailingInstruction) {
    return `Context: ${contextBody}. ${trailingInstruction}`;
  }
  return `Context: ${contextBody}.`;
}

export function buildObservationPrompt(
  description: string,
  telemetry: TelemetryContextInput,
): string {
  const contextItems = buildTelemetryItems(telemetry);
  const contextBlock = contextItems.length > 0
    ? `Context: ${contextItems.join(", ")}.\n\n`
    : "";

  return `${contextBlock}Observation Description:\n${description}`;
}

export function sanitizeLifeStage(value: string | null | undefined): LifeStage {
  if (value == null) return undefined;
  if (VALID_LIFE_STAGES.has(value as NonNullable<LifeStage>)) {
    return value as NonNullable<LifeStage>;
  }
  return "unknown";
}

export function sanitizeReproductiveCondition(
  value: string | null | undefined,
): ReproductiveCondition {
  if (value == null) return undefined;
  if (VALID_REPRODUCTIVE_CONDITIONS.has(value as NonNullable<ReproductiveCondition>)) {
    return value as NonNullable<ReproductiveCondition>;
  }
  return "not_applicable";
}
