import "@mantine/core/styles.css";
import "./globals.css";

import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { ColorSchemeScript, MantineProvider } from "@mantine/core";
import { ThemePreferenceBridge } from "@/components/ThemePreferenceBridge";
import {
  MANTINE_COLOR_SCHEME_STORAGE_KEY,
  THEME_QUERY_PARAM
} from "@/lib/theme-preference";
import { theme } from "./theme";

const themePreferenceScript = `
(() => {
  try {
    const params = new URLSearchParams(window.location.search);
    const rawTheme = params.get("${THEME_QUERY_PARAM}");
    const normalizedTheme = rawTheme?.trim().toLowerCase();
    const colorScheme =
      normalizedTheme === "system"
        ? "auto"
        : normalizedTheme === "light" || normalizedTheme === "dark" || normalizedTheme === "auto"
          ? normalizedTheme
          : null;

    if (colorScheme) {
      window.localStorage.setItem("${MANTINE_COLOR_SCHEME_STORAGE_KEY}", colorScheme);
    }
  } catch (_error) {
  }
})();
`;

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "https://merian.earth"),
  title: {
    default: "Merian",
    template: "%s | Merian"
  },
  description: "Discover and share ecological observations with Merian."
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#0b0f14"
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themePreferenceScript }} />
        <ColorSchemeScript defaultColorScheme="auto" />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="auto">
          <ThemePreferenceBridge />
          {children}
        </MantineProvider>
      </body>
    </html>
  );
}
