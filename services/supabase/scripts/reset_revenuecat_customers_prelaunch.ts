/**
 * Irreversibly deletes every RevenueCat customer named by one exact prelaunch
 * "Export all" artifact. This exceptional project-reset operation never reads
 * from or mutates Supabase and does not attempt to preserve provider history.
 *
 * Dry-run is the default and performs no network requests. Apply is locked to
 * the exact export bytes, exact sorted customer IDs, both RevenueCat project
 * identifiers, an approved plan digest, an exact count, and two explicit
 * acknowledgements. A fresh export is required to discover customers created
 * after the approved snapshot.
 */

import {
  parseDelimitedText,
  readPossiblyGzippedTextArtifact,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";

const REVENUECAT_V2_BASE_URL = "https://api.revenuecat.com/v2";
const MAX_RESPONSE_BYTES = 64 * 1024;
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_ATTEMPTS = 3;
const MAX_CUSTOMERS = 10_000;
const RESET_CONFIRMATION = "--confirm-prelaunch-revenuecat-project-reset";
const ERASURE_ACKNOWLEDGEMENT =
  "--acknowledge-entitlement-alias-and-history-erasure";

const PURCHASE_OR_ENTITLEMENT_FIELDS = [
  "latest_entitlement",
  "latest_entitlements",
  "latest_product",
  "first_purchase_at",
  "trial_start_at",
  "trial_end_at",
  "most_recent_purchase_at",
  "most_recent_renewal_at",
  "latest_expiration_at",
  "subscription_opt_out_at",
  "trial_opt_out_at",
  "latest_store",
  "latest_auto_renew_intent",
  "all_purchased_product_ids",
  "most_recent_billing_issues_at",
  "latest_offer",
  "latest_offer_type",
  "latest_purchased_offering",
  "latest_ownership_type",
] as const;

export interface RevenueCatPrelaunchResetArgs {
  revenueCatCustomersCsvPath: string | null;
  projectID: string | null;
  exportProjectID: string | null;
  summaryJsonPath: string | null;
  reviewCsvPath: string | null;
  resultsCsvPath: string | null;
  apply: boolean;
  confirmedReset: boolean;
  acknowledgedErasure: boolean;
  approvedPlanSHA256: string | null;
  confirmedCount: number | null;
  concurrency: number;
}

export interface RevenueCatPrelaunchResetCandidate {
  app_user_id: string;
  export_project_id: string;
  last_seen_at: string;
  has_purchase_or_entitlement_evidence: boolean;
  has_customer_attributes: boolean;
}

export interface RevenueCatPrelaunchResetPlan {
  candidates: RevenueCatPrelaunchResetCandidate[];
  purchaseOrEntitlementEvidenceCount: number;
  customerAttributeEvidenceCount: number;
}

export type RevenueCatPrelaunchResetStatus =
  | "planned"
  | "deleted"
  | "queued"
  | "already_absent"
  | "failed";

export interface RevenueCatPrelaunchResetResult {
  app_user_id: string;
  status: RevenueCatPrelaunchResetStatus;
  error_code: string;
}

export interface RevenueCatPrelaunchResetSummary {
  generated_at: string;
  mode: "dry-run" | "apply";
  operation: "delete_all_exported_revenuecat_customers_prelaunch";
  irreversible: true;
  repopulation_possible: true;
  v2_project_id: string;
  export_project_id: string;
  revenuecat_export_sha256: string;
  candidate_count: number;
  candidate_sha256: string;
  purchase_or_entitlement_evidence_count: number;
  customer_attribute_evidence_count: number;
  deleted_count: number;
  queued_count: number;
  already_absent_count: number;
  failed_count: number;
  supabase_mutations: false;
}

if (import.meta.main) {
  try {
    Deno.exit(await runRevenueCatPrelaunchReset(Deno.args));
  } catch (error) {
    console.error(
      `RevenueCat prelaunch reset failed: ${safeErrorMessage(error)}`,
    );
    Deno.exit(2);
  }
}

export async function runRevenueCatPrelaunchReset(
  rawArgs: string[],
  dependencies: {
    fetcher?: typeof fetch;
    now?: Date;
    apiKey?: string | null;
    sleep?: (milliseconds: number) => Promise<void>;
  } = {},
): Promise<number> {
  const args = parseRevenueCatPrelaunchResetArgs(rawArgs);
  requireInputs(args);

  const artifact = await readPossiblyGzippedTextArtifact(
    args.revenueCatCustomersCsvPath!,
  );
  const plan = buildRevenueCatPrelaunchResetPlan({
    revenueCatSource: artifact.text,
    exportProjectID: args.exportProjectID!,
  });
  const sourceSHA = await sha256Hex(artifact.sourceBytes);
  const candidateSHA = await revenueCatPrelaunchResetPlanSHA256({
    candidates: plan.candidates,
    sourceSHA256: sourceSHA,
    projectID: args.projectID!,
    exportProjectID: args.exportProjectID!,
  });

  if (args.reviewCsvPath) {
    await writePrivateTextFile(
      args.reviewCsvPath,
      serializeDelimitedRows(
        [
          "app_user_id",
          "export_project_id",
          "last_seen_at",
          "has_purchase_or_entitlement_evidence",
          "has_customer_attributes",
        ],
        plan.candidates,
      ),
    );
  }

  let results: RevenueCatPrelaunchResetResult[] = plan.candidates.map(
    (candidate) => result(candidate.app_user_id, "planned", ""),
  );

  if (args.apply) {
    validateRevenueCatPrelaunchResetAuthorization({
      args,
      candidateSHA,
      candidateCount: plan.candidates.length,
    });
    const apiKey = dependencies.apiKey ??
      Deno.env.get("REVENUECAT_PRELAUNCH_RESET_V2_API_KEY") ?? null;
    if (!apiKey?.trim()) {
      throw new Error(
        "REVENUECAT_PRELAUNCH_RESET_V2_API_KEY is required for apply mode.",
      );
    }
    if (!apiKey.trim().startsWith("sk_")) {
      throw new Error(
        "REVENUECAT_PRELAUNCH_RESET_V2_API_KEY must be a V2 server-side secret key.",
      );
    }

    results = await applyRevenueCatPrelaunchReset({
      candidates: plan.candidates,
      projectID: args.projectID!,
      apiKey: apiKey.trim(),
      concurrency: args.concurrency,
      fetcher: dependencies.fetcher ?? fetch,
      sleep: dependencies.sleep ?? boundedSleep,
    });
    await writePrivateTextFile(
      args.resultsCsvPath!,
      serializeDelimitedRows(
        ["app_user_id", "status", "error_code"],
        results,
      ),
    );
  }

  const summary = buildSummary({
    args,
    plan,
    results,
    sourceSHA,
    candidateSHA,
    now: dependencies.now ?? new Date(),
  });
  printSummary(summary);
  if (args.summaryJsonPath) {
    await writePrivateTextFile(
      args.summaryJsonPath,
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  }
  if (args.reviewCsvPath) console.log(`review_csv: ${args.reviewCsvPath}`);
  if (args.resultsCsvPath && args.apply) {
    console.log(`results_csv: ${args.resultsCsvPath}`);
  }
  if (args.summaryJsonPath) {
    console.log(`summary_json: ${args.summaryJsonPath}`);
  }
  return results.some((entry) => entry.status === "failed") ? 1 : 0;
}

export function parseRevenueCatPrelaunchResetArgs(
  rawArgs: string[],
): RevenueCatPrelaunchResetArgs {
  const args: RevenueCatPrelaunchResetArgs = {
    revenueCatCustomersCsvPath: null,
    projectID: null,
    exportProjectID: null,
    summaryJsonPath: null,
    reviewCsvPath: null,
    resultsCsvPath: null,
    apply: false,
    confirmedReset: false,
    acknowledgedErasure: false,
    approvedPlanSHA256: null,
    confirmedCount: null,
    concurrency: 2,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const argument = rawArgs[index];
    switch (argument) {
      case "--revenuecat-customers-csv":
        args.revenueCatCustomersCsvPath = nextArgument(
          rawArgs,
          ++index,
          argument,
        );
        break;
      case "--project-id":
        args.projectID = nextArgument(rawArgs, ++index, argument);
        break;
      case "--export-project-id":
        args.exportProjectID = nextArgument(rawArgs, ++index, argument);
        break;
      case "--summary-json":
        args.summaryJsonPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--review-csv":
        args.reviewCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--results-csv":
        args.resultsCsvPath = nextArgument(rawArgs, ++index, argument);
        break;
      case "--approved-plan-sha256":
        args.approvedPlanSHA256 = nextArgument(rawArgs, ++index, argument)
          .toLowerCase();
        break;
      case "--confirm-count":
        args.confirmedCount = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          0,
          MAX_CUSTOMERS,
        );
        break;
      case "--concurrency":
        args.concurrency = boundedInteger(
          nextArgument(rawArgs, ++index, argument),
          argument,
          1,
          3,
        );
        break;
      case "--apply":
        args.apply = true;
        break;
      case RESET_CONFIRMATION:
        args.confirmedReset = true;
        break;
      case ERASURE_ACKNOWLEDGEMENT:
        args.acknowledgedErasure = true;
        break;
      default:
        throw new Error(`Unknown argument: ${argument}`);
    }
  }
  return args;
}

export function buildRevenueCatPrelaunchResetPlan(input: {
  revenueCatSource: string;
  exportProjectID: string;
}): RevenueCatPrelaunchResetPlan {
  const parsed = parseDelimitedText(input.revenueCatSource);
  for (const header of ["project_id", "app_user_id", "custom_attributes"]) {
    requireHeader(parsed.headers, header);
  }
  if (parsed.rows.length === 0) {
    throw new Error("RevenueCat export must contain at least one customer.");
  }
  if (parsed.rows.length > MAX_CUSTOMERS) {
    throw new Error(
      `RevenueCat export exceeds the ${MAX_CUSTOMERS}-customer reset limit.`,
    );
  }

  const seenIDs = new Set<string>();
  const candidates = parsed.rows.map((row) => {
    const appUserID = row.app_user_id;
    if (!appUserID || appUserID !== appUserID.trim()) {
      throw new Error(
        "RevenueCat export contains an empty or whitespace-padded app_user_id.",
      );
    }
    if (/\p{Cc}/u.test(appUserID) || appUserID.length > 1_024) {
      throw new Error(
        "RevenueCat export contains an unsafe app_user_id.",
      );
    }
    if (seenIDs.has(appUserID)) {
      throw new Error(
        "RevenueCat export contains a duplicate app_user_id.",
      );
    }
    seenIDs.add(appUserID);

    const rowProjectID = row.project_id.trim();
    if (rowProjectID !== input.exportProjectID) {
      throw new Error(
        "RevenueCat export contains a customer from an unexpected project.",
      );
    }
    return {
      app_user_id: appUserID,
      export_project_id: rowProjectID,
      last_seen_at: row.last_seen_at?.trim() ?? "",
      has_purchase_or_entitlement_evidence: hasPurchaseOrEntitlementEvidence(
        row,
      ),
      has_customer_attributes: meaningfulValue(row.custom_attributes),
    };
  }).sort((lhs, rhs) => compareText(lhs.app_user_id, rhs.app_user_id));

  return {
    candidates,
    purchaseOrEntitlementEvidenceCount:
      candidates.filter((candidate) =>
        candidate.has_purchase_or_entitlement_evidence
      ).length,
    customerAttributeEvidenceCount:
      candidates.filter((candidate) => candidate.has_customer_attributes)
        .length,
  };
}

export async function revenueCatPrelaunchResetPlanSHA256(input: {
  candidates: RevenueCatPrelaunchResetCandidate[];
  sourceSHA256: string;
  projectID: string;
  exportProjectID: string;
}): Promise<string> {
  const canonicalPlan = {
    operation: "delete_all_exported_revenuecat_customers_prelaunch_v1",
    revenuecat_export_sha256: input.sourceSHA256,
    v2_project_id: input.projectID,
    export_project_id: input.exportProjectID,
    candidates: input.candidates.map((candidate) => ({
      app_user_id: candidate.app_user_id,
      export_project_id: candidate.export_project_id,
      last_seen_at: candidate.last_seen_at,
      has_purchase_or_entitlement_evidence:
        candidate.has_purchase_or_entitlement_evidence,
      has_customer_attributes: candidate.has_customer_attributes,
    })),
  };
  return await sha256Hex(`${JSON.stringify(canonicalPlan)}\n`);
}

export function validateRevenueCatPrelaunchResetAuthorization(input: {
  args: RevenueCatPrelaunchResetArgs;
  candidateSHA: string;
  candidateCount: number;
}): void {
  if (!input.args.confirmedReset) {
    throw new Error(`Apply mode requires ${RESET_CONFIRMATION}.`);
  }
  if (!input.args.acknowledgedErasure) {
    throw new Error(`Apply mode requires ${ERASURE_ACKNOWLEDGEMENT}.`);
  }
  if (!input.args.resultsCsvPath || !input.args.summaryJsonPath) {
    throw new Error(
      "Apply mode requires --results-csv and --summary-json.",
    );
  }
  if (!/^[0-9a-f]{64}$/.test(input.args.approvedPlanSHA256 ?? "")) {
    throw new Error("Apply mode requires --approved-plan-sha256.");
  }
  if (input.args.approvedPlanSHA256 !== input.candidateSHA) {
    throw new Error("Approved plan digest does not match the current inputs.");
  }
  if (input.args.confirmedCount !== input.candidateCount) {
    throw new Error(
      "Confirmed count does not match the current candidate set.",
    );
  }
}

export async function applyRevenueCatPrelaunchReset(input: {
  candidates: RevenueCatPrelaunchResetCandidate[];
  projectID: string;
  apiKey: string;
  concurrency: number;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<RevenueCatPrelaunchResetResult[]> {
  const results = new Array<RevenueCatPrelaunchResetResult>(
    input.candidates.length,
  );
  let nextIndex = 0;
  let completedCount = 0;

  const worker = async () => {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= input.candidates.length) return;
      const customerID = input.candidates[index].app_user_id;
      results[index] = await deleteRevenueCatCustomer({
        customerID,
        projectID: input.projectID,
        apiKey: input.apiKey,
        fetcher: input.fetcher,
        sleep: input.sleep,
      });
      completedCount += 1;
      if (
        completedCount % 25 === 0 ||
        completedCount === input.candidates.length
      ) {
        console.log(
          `reset_progress: ${completedCount}/${input.candidates.length}`,
        );
      }
    }
  };
  await Promise.all(
    Array.from(
      { length: Math.min(input.concurrency, input.candidates.length) },
      worker,
    ),
  );
  return results;
}

async function deleteRevenueCatCustomer(input: {
  customerID: string;
  projectID: string;
  apiKey: string;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<RevenueCatPrelaunchResetResult> {
  try {
    const response = await requestRevenueCatDelete({
      url: `${REVENUECAT_V2_BASE_URL}/projects/${
        encodeURIComponent(input.projectID)
      }/customers/${encodeURIComponent(input.customerID)}`,
      headers: {
        Authorization: `Bearer ${input.apiKey}`,
        "Content-Type": "application/json",
      },
      fetcher: input.fetcher,
      sleep: input.sleep,
    });
    if (response.status === 200) {
      return result(input.customerID, "deleted", "");
    }
    if (response.status === 202) {
      return result(input.customerID, "queued", "");
    }
    if (response.status === 404) {
      return result(input.customerID, "already_absent", "");
    }
    return result(
      input.customerID,
      "failed",
      `delete_http_${response.status}`,
    );
  } catch (error) {
    return result(input.customerID, "failed", stableErrorCode(error));
  }
}

async function requestRevenueCatDelete(input: {
  url: string;
  headers: Record<string, string>;
  fetcher: typeof fetch;
  sleep: (milliseconds: number) => Promise<void>;
}): Promise<{ status: number }> {
  let lastStatus = 0;
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await input.fetcher(input.url, {
        method: "DELETE",
        headers: input.headers,
        signal: controller.signal,
      });
      lastStatus = response.status;
      await readBoundedResponseText(response);
      if (!retryableStatus(response.status) || attempt === MAX_ATTEMPTS) {
        return { status: response.status };
      }
    } catch (error) {
      lastError = error;
      if (attempt === MAX_ATTEMPTS) throw error;
    } finally {
      clearTimeout(timer);
    }
    await input.sleep(Math.min(2_000, 250 * 2 ** (attempt - 1)));
  }
  if (lastStatus !== 0) return { status: lastStatus };
  throw lastError ?? new Error("RevenueCat request failed.");
}

async function readBoundedResponseText(response: Response): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new Error("response_too_large");
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("response_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function requireInputs(args: RevenueCatPrelaunchResetArgs): void {
  if (
    !args.revenueCatCustomersCsvPath || !args.projectID ||
    !args.exportProjectID
  ) {
    throw new Error(
      "--revenuecat-customers-csv, --project-id, and --export-project-id are required.",
    );
  }
  if (!/^proj[a-zA-Z0-9_-]{4,251}$/.test(args.projectID)) {
    throw new Error("--project-id must be a valid RevenueCat V2 project ID.");
  }
  if (!/^[a-zA-Z0-9_-]{4,255}$/.test(args.exportProjectID)) {
    throw new Error(
      "--export-project-id must be a valid dashboard export project ID.",
    );
  }
  if (args.projectID !== `proj${args.exportProjectID}`) {
    throw new Error(
      "The V2 project ID must equal proj plus the export project ID.",
    );
  }
}

function buildSummary(input: {
  args: RevenueCatPrelaunchResetArgs;
  plan: RevenueCatPrelaunchResetPlan;
  results: RevenueCatPrelaunchResetResult[];
  sourceSHA: string;
  candidateSHA: string;
  now: Date;
}): RevenueCatPrelaunchResetSummary {
  const count = (status: RevenueCatPrelaunchResetStatus) =>
    input.results.filter((entry) => entry.status === status).length;
  return {
    generated_at: input.now.toISOString(),
    mode: input.args.apply ? "apply" : "dry-run",
    operation: "delete_all_exported_revenuecat_customers_prelaunch",
    irreversible: true,
    repopulation_possible: true,
    v2_project_id: input.args.projectID!,
    export_project_id: input.args.exportProjectID!,
    revenuecat_export_sha256: input.sourceSHA,
    candidate_count: input.plan.candidates.length,
    candidate_sha256: input.candidateSHA,
    purchase_or_entitlement_evidence_count:
      input.plan.purchaseOrEntitlementEvidenceCount,
    customer_attribute_evidence_count:
      input.plan.customerAttributeEvidenceCount,
    deleted_count: count("deleted"),
    queued_count: count("queued"),
    already_absent_count: count("already_absent"),
    failed_count: count("failed"),
    supabase_mutations: false,
  };
}

function printSummary(summary: RevenueCatPrelaunchResetSummary): void {
  console.log(`mode: ${summary.mode}`);
  console.log(`operation: ${summary.operation}`);
  console.log(`v2_project_id: ${summary.v2_project_id}`);
  console.log(`export_project_id: ${summary.export_project_id}`);
  console.log(`revenuecat_export_sha256: ${summary.revenuecat_export_sha256}`);
  console.log(`candidate_count: ${summary.candidate_count}`);
  console.log(`candidate_sha256: ${summary.candidate_sha256}`);
  console.log(
    `purchase_or_entitlement_evidence_count: ${summary.purchase_or_entitlement_evidence_count}`,
  );
  console.log(
    `customer_attribute_evidence_count: ${summary.customer_attribute_evidence_count}`,
  );
  console.log(`deleted_count: ${summary.deleted_count}`);
  console.log(`queued_count: ${summary.queued_count}`);
  console.log(`already_absent_count: ${summary.already_absent_count}`);
  console.log(`failed_count: ${summary.failed_count}`);
  console.log("irreversible: true");
  console.log("repopulation_possible: true");
  console.log("supabase_mutations: false");
}

function hasPurchaseOrEntitlementEvidence(
  row: Record<string, string>,
): boolean {
  if (truthy(row.has_made_sandbox_purchase)) return true;
  if (truthy(row.is_rc_promo)) return true;
  if (truthy(row.has_made_a_non_subscription_purchase)) return true;
  const totalSpent = Number(
    (row.total_spent ?? "").replaceAll(/[^0-9.-]/g, ""),
  );
  if (Number.isFinite(totalSpent) && totalSpent > 0) return true;
  const totalRenewals = Number(row.total_renewals ?? "");
  if (Number.isFinite(totalRenewals) && totalRenewals > 0) return true;
  return PURCHASE_OR_ENTITLEMENT_FIELDS.some((field) =>
    meaningfulValue(row[field])
  );
}

function meaningfulValue(value: string | undefined): boolean {
  const normalized = value?.trim().toLowerCase() ?? "";
  return !["", "[]", "{}", "null", "false", "f", "no", "n", "0", "-"]
    .includes(
      normalized,
    );
}

function truthy(value: string | undefined): boolean {
  return ["true", "t", "1", "yes"].includes(
    value?.trim().toLowerCase() ?? "",
  );
}

function result(
  appUserID: string,
  status: RevenueCatPrelaunchResetStatus,
  errorCode: string,
): RevenueCatPrelaunchResetResult {
  return { app_user_id: appUserID, status, error_code: errorCode };
}

function requireHeader(headers: string[], header: string): void {
  if (!headers.includes(header)) {
    throw new Error(`RevenueCat export is missing required header: ${header}`);
  }
}

function retryableStatus(status: number): boolean {
  return [408, 409, 423, 425, 429, 500, 502, 503, 504].includes(status);
}

function stableErrorCode(error: unknown): string {
  if (error instanceof DOMException && error.name === "AbortError") {
    return "request_timeout";
  }
  if (error instanceof Error && error.message === "response_too_large") {
    return "response_too_large";
  }
  return "request_failed";
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

function nextArgument(
  rawArgs: string[],
  index: number,
  argument: string,
): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${argument} requires a value.`);
  }
  return value;
}

function boundedInteger(
  value: string,
  argument: string,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(
      `${argument} must be an integer from ${minimum} through ${maximum}.`,
    );
  }
  return parsed;
}

function compareText(lhs: string, rhs: string): number {
  return lhs < rhs ? -1 : lhs > rhs ? 1 : 0;
}

async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : new Uint8Array(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function writePrivateTextFile(path: string, content: string) {
  await Deno.writeTextFile(path, content, { mode: 0o600 });
  await Deno.chmod(path, 0o600);
}

function boundedSleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
