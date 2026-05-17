"use client";

import { useEffect } from "react";
import { useMantineColorScheme } from "@mantine/core";
import { normalizeThemePreference, THEME_QUERY_PARAM } from "@/lib/theme-preference";

export function ThemePreferenceBridge() {
  const { setColorScheme } = useMantineColorScheme();

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const colorScheme = normalizeThemePreference(params.get(THEME_QUERY_PARAM));

    if (colorScheme) {
      setColorScheme(colorScheme);
    }
  }, [setColorScheme]);

  return null;
}
