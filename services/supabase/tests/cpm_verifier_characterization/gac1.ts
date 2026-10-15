import { LIMITS } from "./policy.ts";
import { Growth } from "./telemetry.ts";

export type GrowthDecision =
  | "pending"
  | "pass"
  | "drift_failure"
  | "cross_cohort_envelope_review_hold"
  | "cross_cohort_endpoint_review_hold";
export interface GrowthAck {
  contract: "GAC-1";
  warning: boolean;
  decision: GrowthDecision;
}
const median = (x: number[]) => [...x].sort((a, b) => a - b)[1];
function drift(q: number[]) {
  const first = q.slice(0, 3), last = q.slice(-3);
  return median(last) - median(first) >= LIMITS.growthBytes ||
    Math.max(...last) - Math.max(...first) >= LIMITS.growthBytes;
}
/** Serial cases 1..20 only. No new memory call, timer, GC or retry. */
export class GAC1 {
  private next = 1;
  private terminal = false;
  private warning = new Growth();
  private q: number[] = [];
  private p: number[] = [];
  accepts(id: number): boolean {
    return !this.terminal && id === this.next && id <= 20;
  }
  add(id: number, q: number, p: number): GrowthAck {
    if (
      !this.accepts(id) ||
      !Number.isSafeInteger(q) || !Number.isSafeInteger(p) ||
      q <= 0 || p < q || p >= LIMITS.proxyBytes
    ) throw Error("gac_input");
    this.next++;
    const warning = this.warning.add(q);
    if (id > 2) {
      this.q.push(q);
      this.p.push(p);
    }
    let decision: GrowthDecision = "pending";
    if (id === 11 && drift(this.q)) decision = "drift_failure";
    if (id === 20) {
      const a = this.q.slice(0, 9), b = this.q.slice(9);
      const pa = this.p.slice(0, 9), pb = this.p.slice(9);
      if (drift(a) || drift(b)) decision = "drift_failure";
      else if (
        Math.max(...b) - Math.max(...a) >= LIMITS.growthBytes ||
        Math.max(...pb) - Math.max(...pa) >= LIMITS.growthBytes
      ) decision = "cross_cohort_envelope_review_hold";
      else if (
        median(b.slice(-3)) - median(a.slice(0, 3)) >= LIMITS.growthBytes
      ) decision = "cross_cohort_endpoint_review_hold";
      else decision = "pass";
    }
    this.terminal = decision !== "pending";
    return { contract: "GAC-1", warning, decision };
  }
}
