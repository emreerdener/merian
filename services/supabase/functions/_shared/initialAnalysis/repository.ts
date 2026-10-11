import {
  initialCanonicalText,
  initialDigest,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  INITIAL_CONFIGURATION_ASSET_DIGEST,
  verifyInitialConfigurationAssets,
} from "./configuration.ts";
import {
  assertPreparedInitialAdmission,
  type PreparedInitialAdmission,
} from "./preparation.ts";
import { validateInitialInput } from "./schema.ts";

interface RpcClient {
  rpc(
    name: "admit_initial_analysis",
    args: Record<string, unknown>,
  ): PromiseLike<
    { data: unknown; error: null | { code?: string; message?: string } }
  >;
}
export interface InitialAdmissionBinding {
  readonly version: 1;
  readonly owner_id: string;
  readonly scan_id: string;
  readonly route: string;
  readonly submission_digest: string;
  readonly configuration_digest: string;
  readonly funding_digest: string;
  readonly descriptions_digest: string;
  readonly funding_binding_id: string;
  readonly assets_digest: string;
}
export type InitialAdmissionOutcome =
  | { outcome: "admitted" | "replay"; binding: InitialAdmissionBinding }
  | {
    outcome: "held";
    reason:
      | "unavailable"
      | "configuration_unavailable"
      | "experiment_unavailable"
      | "conflict"
      | "deleted"
      | "owner_unavailable"
      | "invalid_input";
  }
  | { outcome: "unknown"; reason: "write_outcome_unknown" };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const sha = /^[0-9a-f]{64}$/;
const unknown: InitialAdmissionOutcome = Object.freeze({
  outcome: "unknown",
  reason: "write_outcome_unknown",
});

/** Initial engine repository; currently uninstalled by all live handlers.
 * One fixed RPC and zero transport retries, dispatches or refunds. Canonical
 * identity must be persisted by the caller before fresh I/O. After uncertainty,
 * recoverAdmission is replay-only: absence cannot allocate or authorize work.
 */
export class InitialAnalysisLifecycleRepository {
  constructor(
    private readonly client: RpcClient,
    private readonly readAsset: (
      path: string,
      revision: string,
    ) => Promise<Uint8Array>,
  ) {}

  async admit(
    owner: string,
    scan: string,
    input: PreparedInitialAdmission,
    ipHash: string,
  ): Promise<InitialAdmissionOutcome> {
    assertPreparedInitialAdmission(input);
    try {
      await verifyInitialConfigurationAssets(this.readAsset);
    } catch {
      return { outcome: "held", reason: "configuration_unavailable" };
    }
    return this.call(
      owner,
      scan,
      input.canonicalInput,
      input.submissionDigest,
      INITIAL_CONFIGURATION_ASSET_DIGEST,
      ipHash,
    );
  }
  recoverAdmission(
    owner: string,
    scan: string,
    canonicalInput: string,
    submissionDigest: string,
  ): Promise<InitialAdmissionOutcome> {
    // NULL fresh-asset authority forces SQL to return only an existing binding.
    // This path does not load assets, reprocess media or consult new defaults.
    return this.call(owner, scan, canonicalInput, submissionDigest, null, null);
  }
  private async call(
    owner: string,
    scan: string,
    canonical: string,
    digest: string,
    assets: string | null,
    ip: string | null,
  ): Promise<InitialAdmissionOutcome> {
    if (!uuid.test(owner) || !uuid.test(scan) || !sha.test(digest)) {
      return { outcome: "held", reason: "invalid_input" };
    }
    try {
      if (
        validateInitialInput(parseInitialCanonicalText(canonical)) !==
          canonical || await initialDigest("input", canonical) !== digest
      ) return { outcome: "held", reason: "invalid_input" };
      const response = await this.client.rpc("admit_initial_analysis", {
        p_owner: owner,
        p_scan: scan,
        p_canonical_input: canonical,
        p_submission_digest: digest,
        p_assets_digest: assets,
        p_ip_hash: ip,
      });
      if (response.error) {
        const reasons: Record<
          string,
          InitialAdmissionOutcome & { outcome: "held" }
        > = {
          "22023:initial_analysis_identity_conflict": {
            outcome: "held",
            reason: "conflict",
          },
          "22023:initial_analysis_input_invalid": {
            outcome: "held",
            reason: "invalid_input",
          },
          "55000:initial_analysis_unavailable": {
            outcome: "held",
            reason: "unavailable",
          },
          "55000:initial_analysis_configuration_unavailable": {
            outcome: "held",
            reason: "configuration_unavailable",
          },
          "55000:initial_analysis_experiment_unavailable": {
            outcome: "held",
            reason: "experiment_unavailable",
          },
          "55000:initial_analysis_deleted": {
            outcome: "held",
            reason: "deleted",
          },
          "P0002:initial_analysis_owner_unavailable": {
            outcome: "held",
            reason: "owner_unavailable",
          },
        };
        return reasons[`${response.error.code}:${response.error.message}`] ??
          unknown;
      }
      const envelope = parseInitialCanonicalText(
        initialCanonicalText(response.data),
      ) as Record<string, unknown>;
      if (
        Object.keys(envelope).sort().join() !== "binding,outcome" ||
        !["admitted", "replay"].includes(envelope.outcome as string) ||
        (assets === null && envelope.outcome !== "replay")
      ) return unknown;
      const binding = envelope.binding as InitialAdmissionBinding;
      if (
        !binding ||
        Object.keys(binding).sort().join() !==
          "assets_digest,configuration_digest,descriptions_digest,funding_binding_id,funding_digest,owner_id,route,scan_id,submission_digest,version" ||
        binding.version !== 1 || binding.owner_id !== owner ||
        binding.scan_id !== scan || binding.submission_digest !== digest ||
        binding.route !== (JSON.parse(canonical) as { route: string }).route ||
        !uuid.test(binding.funding_binding_id) ||
        ![
          binding.assets_digest,
          binding.configuration_digest,
          binding.funding_digest,
          binding.descriptions_digest,
        ].every((v) => typeof v === "string" && sha.test(v))
      ) return unknown;
      if (envelope.outcome === "admitted" && binding.assets_digest !== assets) {
        return unknown;
      }
      return {
        outcome: envelope.outcome as "admitted" | "replay",
        binding: Object.freeze(binding),
      };
    } catch {
      return unknown;
    }
  }
}
