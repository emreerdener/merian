import type { Metadata } from "next";
import { headers } from "next/headers";
import type { ReactNode } from "react";
import { Providers } from "@/components/Providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "Naturebook Internal",
  description: "Authorized Naturebook operations",
  robots: { index: false, follow: false, nocache: true },
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  return (
    <html lang="en">
      <body><Providers nonce={nonce}>{children}</Providers></body>
    </html>
  );
}
