export const EXPORT_PAGE_SIZE = 100;
export const MAXIMUM_EXPORT_SOURCE_PAGE_BYTES = 256 * 1024;
export const MAXIMUM_WORK_CHUNK_BYTES = 512 * 1024;

export const MAXIMUM_DWCA_IMAGE_URLS = 24;
export const MAXIMUM_DWCA_IMAGE_URL_BYTES = 4_096;
export const MAXIMUM_DWCA_INTERACTIONS = 10;
export const MAXIMUM_DWCA_INTERACTION_BYTES = 2_048;
export const MAXIMUM_DWCA_SCIENTIFIC_NAME_BYTES = 1_024;
export const MAXIMUM_DWCA_TAXON_RANK_BYTES = 512;
export const MAXIMUM_DWCA_IUCN_STATUS_BYTES = 128;

// The once-per-minute dispatcher checks this soft deadline only between
// durable steps. The reserve prevents a fresh step from starting at the budget
// edge and normally leaves room for the final aggregate health read.
export const EXPORT_DRAIN_RUNTIME_BUDGET_MS = 45_000;
export const EXPORT_DRAIN_FINAL_STEP_RESERVE_MS = 5_000;
export const EXPORT_DRAIN_DISCOVERY_BATCH_SIZE = 5;
export const EXPORT_DRAIN_MAXIMUM_STEPS = 40;

export const EXPORT_BACKLOG_WARNING_AGE_SECONDS = 5 * 60;
export const EXPORT_BACKLOG_CRITICAL_AGE_SECONDS = 15 * 60;
export const EXPORT_BACKLOG_WARNING_COUNT = 25;
export const EXPORT_BACKLOG_CRITICAL_COUNT = 100;
