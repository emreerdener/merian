/** Dormant server composition. No route, profile or signer is installed here.
 * Bootstrap dependencies are trusted server configuration, never request proof. */
import type { CpmAdmissionIdentity } from "./cpmPhotoAdmission.ts";
import { createCpmPhotoAdmissionDb } from "./cpmPhotoAdmissionDb.ts";
import { createCpmPhotoClosureDb } from "./cpmPhotoClosureDb.ts";
import {
  cpmPhotoVerificationCatalog,
  type CpmPhotoVerificationContext,
  verifyAndAdmitInitialCpmPhotoMedia,
} from "./cpmPhotoVerification.ts";
import {
  type CpmWriteObservationDependencies,
  snapshotCpmWriteObservationBinding,
  snapshotCpmWriteObservationTarget,
} from "./cpmPhotoWriteObservation.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaUnavailable } from "./mediaBinding.ts";
import { checkInitialDeadline, initialAbortable } from "./transport.ts";

export async function createCpmPhotoAdmissionRuntime(
  profiles: readonly CpmPhotoVerificationContext[],
  trustedIpHash: string,
  storage: Pick<CpmWriteObservationDependencies, "sign" | "fetch">,
  rpcFetch: typeof fetch = fetch,
) {
  // Capture trusted functions/configuration before bootstrap's first await.
  const sign = storage.sign.bind(storage);
  const fetchStorage = storage.fetch.bind(storage);
  const admission = createCpmPhotoAdmissionDb(trustedIpHash, rpcFetch);
  const closure = createCpmPhotoClosureDb(null, rpcFetch);
  const catalog = await cpmPhotoVerificationCatalog(profiles);
  const dependencies = Object.freeze({
    load: catalog.load,
    requireCurrent: admission.requireCurrent,
    storage: Object.freeze(
      {
        sign,
        fetch: fetchStorage,
        async requireCurrent(binding, target, signal) {
          const expectedBinding = snapshotCpmWriteObservationBinding(binding);
          const expectedTarget = snapshotCpmWriteObservationTarget(target);
          if (expectedTarget.outcome !== "live_object") {
            throw initialMediaUnavailable();
          }
          const observed = await initialAbortable(
            signal,
            () =>
              closure.load(expectedBinding.attempt_id, "live_object", signal),
          );
          // A current but different object/declaration cannot authorize this read.
          if (
            initialCanonicalText(observed.binding) !==
              initialCanonicalText(expectedBinding) ||
            initialCanonicalText(observed.target) !==
              initialCanonicalText(expectedTarget)
          ) {
            throw initialMediaUnavailable();
          }
          await initialAbortable(
            signal,
            () => closure.requireCurrent(observed, signal),
          );
          checkInitialDeadline(signal);
        },
      } satisfies CpmWriteObservationDependencies,
    ),
  });
  return Object.freeze({
    admit(identity: CpmAdmissionIdentity, signal: AbortSignal) {
      return verifyAndAdmitInitialCpmPhotoMedia(
        admission,
        dependencies,
        identity,
        signal,
      );
    },
  });
}
