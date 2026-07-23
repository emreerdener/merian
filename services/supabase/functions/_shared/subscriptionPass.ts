export const SEVEN_DAY_PASS_PRODUCT_ID = "pro_week";
export const SEVEN_DAY_PASS_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

export function isSevenDayPassProduct(productId: unknown): boolean {
  return productId === SEVEN_DAY_PASS_PRODUCT_ID;
}
