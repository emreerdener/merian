import type { ConfidenceCase } from "./confidenceCorpus.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { random } from "./profiles.ts";
import { requireCondition as check } from "./validation.ts";

/** Seeded, group-preserving allocation before freezing; never accepts model scores. */
export function assignConfidenceSplits(
  cases: readonly ConfidenceCase[],
): ConfidenceCase[] {
  check(cases.length === 200);
  const dimensions = [
    ...["clear", "lookalike", "limited"].flatMap((c) =>
      P.taxaGroups.map((g) => `${c}:${g}`)
    ),
    "cultivated",
    "nonbiological",
    "limited:genus",
    "limited:unresolved",
  ];
  const target = dimensions.map((_, i) => i < 12 ? 5 : i < 14 ? 20 : 10);
  const weight = (c: ConfidenceCase) =>
    dimensions.map((d) =>
      Number(
        d === c.category || d === `${c.category}:${c.taxaGroup}` ||
          c.category === "limited" &&
            d === `limited:${c.reference.supportedRank ?? "unresolved"}`,
      )
    );
  const members = new Map<string, ConfidenceCase[]>();
  for (const c of cases) {
    members.set(c.input.groupId, [...(members.get(c.input.groupId) ?? []), c]);
  }
  const groups = [...members.entries()].sort(([a], [b]) => a.localeCompare(b))
    .map(([id, values]) => ({
      id,
      forced: values.some((c) =>
        c.curation.kind === "reviewed" && c.curation.developmentOnly
      ),
      weights: values.reduce(
        (n, c) => n.map((v, i) => v + weight(c)[i]),
        target.map(() => 0),
      ),
    }));
  const rng = random(P.splitSeed);
  for (let i = groups.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [groups[i], groups[j]] = [groups[j], groups[i]];
  }
  const remaining = groups.map(() => target.map(() => 0));
  remaining.push(target.map(() => 0));
  const forcedRemaining = groups.map(() => target.map(() => 0));
  forcedRemaining.push(target.map(() => 0));
  for (let i = groups.length - 1; i >= 0; i--) {
    remaining[i] = remaining[i + 1].map((v, j) => v + groups[i].weights[j]);
  }
  for (let i = groups.length - 1; i >= 0; i--) {
    forcedRemaining[i] = forcedRemaining[i + 1].map((v, j) =>
      v + (groups[i].forced ? groups[i].weights[j] : 0)
    );
  }
  check(remaining[0].every((v, i) => v === 2 * target[i]));
  const chosen = new Set<string>(), failed = new Set<string>();
  let visits = 0;
  function search(index: number, need: number[]): boolean {
    check(++visits <= 1_000_000); // Infeasible clustering requires curation, never a partial split.
    if (
      need.some((n, i) =>
        n < forcedRemaining[index][i] || n > remaining[index][i]
      )
    ) return false;
    if (index === groups.length) return need.every((n) => n === 0);
    const key = `${index}:${need.join(",")}`;
    if (failed.has(key)) return false;
    const group = groups[index];
    chosen.add(group.id);
    if (search(index + 1, need.map((n, i) => n - group.weights[i]))) {
      return true;
    }
    chosen.delete(group.id);
    if (!group.forced && search(index + 1, need)) return true;
    failed.add(key);
    return false;
  }
  check(search(0, target));
  return cases.map((c) => ({
    ...c,
    input: {
      ...c.input,
      split: chosen.has(c.input.groupId) ? "development" : "held_out",
    },
  }));
}
