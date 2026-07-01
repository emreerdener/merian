import "@mantine/core/styles.css";
import "@mantine/carousel/styles.css";
import "./globals.css";

import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { ColorSchemeScript, MantineProvider } from "@mantine/core";
import { MerianAppShell } from "@/components/MerianAppShell";
import { theme } from "./theme";

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
        <ColorSchemeScript defaultColorScheme="auto" />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="auto">
          <MerianAppShell>{children}</MerianAppShell>
        </MantineProvider>
      </body>
    </html>
  );
}
