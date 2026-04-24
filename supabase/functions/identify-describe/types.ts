// Re-export the shared response types from the canonical shared identify stack.
// identify-describe returns the exact same ClientPayload so the iOS client
// needs zero changes to parse describe results.
export type {
  MerianIdentification,
  IdentificationCandidate,
  ImageQuality,
  ClientPayload,
  CachedSpeciesRow,
  StaticSpeciesData,
} from "../_shared/identify/types.ts";

// ---------------------------------------------------------------------------
// Describe-specific request shape
// ---------------------------------------------------------------------------

export interface DescribeRequest {
  user_id: string;
  /** Serialized ObservationContext from the iOS client — key: value lines. */
  description: string;
  client_scan_id?: string;

  // Optional telemetry — all fields mirror the identify endpoint
  gpsLatitude?: number;
  gpsLongitude?: number;
  gpsElevation?: number;
  weatherCondition?: string;
  weatherTemperatureF?: number;
  deviceLocale?: string;
  deviceTimeZone?: string;
  deviceRegion?: string;
  currentMonth?: number;
  semanticLocation?: string;
  timeOfDay?: string;
  timestamp?: string;
}
