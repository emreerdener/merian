/** Exact comparison of bounded plain decimal strings; no IEEE rounding. */
export function compareInitialDecimals(left: string, right: string): number {
  const parts = (value: string): [bigint, number] => {
    const [whole, fraction = ""] = value.split(".");
    return [BigInt(whole + fraction), fraction.length];
  };
  const [a, ap] = parts(left), [b, bp] = parts(right);
  const scale = Math.max(ap, bp);
  const av = a * 10n ** BigInt(scale - ap), bv = b * 10n ** BigInt(scale - bp);
  return av < bv ? -1 : av > bv ? 1 : 0;
}
export function addInitialDecimals(left: string, right: string): string {
  const [a, af = ""] = left.split("."), [b, bf = ""] = right.split(".");
  const scale = Math.max(af.length, bf.length);
  const sum = BigInt(a + af) * 10n ** BigInt(scale - af.length) +
    BigInt(b + bf) * 10n ** BigInt(scale - bf.length);
  const digits = sum.toString().padStart(scale + 1, "0");
  return scale ? `${digits.slice(0, -scale)}.${digits.slice(-scale)}` : digits;
}
