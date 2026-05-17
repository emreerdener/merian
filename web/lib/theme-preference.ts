import type { MantineColorScheme } from "@mantine/core";

export const THEME_QUERY_PARAM = "theme";
export const MANTINE_COLOR_SCHEME_STORAGE_KEY = "mantine-color-scheme-value";

export function normalizeThemePreference(value: string | null): MantineColorScheme | null {
  const normalized = value?.trim().toLowerCase();

  if (normalized === "light" || normalized === "dark" || normalized === "auto") {
    return normalized;
  }

  if (normalized === "system") {
    return "auto";
  }

  return null;
}
