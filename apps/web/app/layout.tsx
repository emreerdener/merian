import "@mantine/core/styles.css";
import "@mantine/carousel/styles.css";
import "./globals.css";

import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { MantineProvider } from "@mantine/core";
import { MerianAppShell } from "@/components/MerianAppShell";
import { siteConfig } from "@/lib/site";
import { theme } from "./theme";
import Script from "next/script";

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.siteUrl),
  title: {
    default: siteConfig.name,
    template: `%s | ${siteConfig.name}`
  },
  description: "Discover and share ecological observations with Naturebook."
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
        <Script
          id="mantine-color-scheme-script"
          strategy="beforeInteractive"
          dangerouslySetInnerHTML={{
            __html: `
              try {
                var colorScheme = localStorage.getItem('mantine-color-scheme') || 'auto';
                var computed = colorScheme === 'auto' ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : colorScheme;
                document.documentElement.setAttribute('data-mantine-color-scheme', computed);
              } catch (e) {}
            `
          }}
        />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="auto">
          <MerianAppShell>{children}</MerianAppShell>
        </MantineProvider>
      </body>
    </html>
  );
}
