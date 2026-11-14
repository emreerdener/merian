/** Only the I7 and requested-model additions may differ from retained SQL schemas. */
export function historicalI6Schema(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.filter((v) => v !== "gemini-3.8-flash").map(
      historicalI6Schema,
    );
  }
  if (value && typeof value === "object") {
    const row = value as Record<string, unknown>;
    return Object.fromEntries(
      Object.entries(row).map(([key, child]) => {
        if (
          (key === "identification_protocol" ||
            key === "accepted_identification_protocol") &&
          child && typeof child === "object"
        ) {
          const field = child as Record<string, unknown>;
          if (field.minimum === 6 && field.maximum === 7) {
            return [key, { ...field, maximum: 6 }];
          }
        }
        return [key, historicalI6Schema(child)];
      }),
    );
  }
  return value;
}
