"use client";

import { MantineProvider, createTheme } from "@mantine/core";
import type { ReactNode } from "react";

const theme = createTheme({
  primaryColor: "green",
  defaultRadius: "md",
  fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif",
  headings: { fontFamily: "Inter, ui-sans-serif, system-ui, sans-serif" },
});

export function Providers({ children, nonce }: { children: ReactNode; nonce?: string }) {
  return <MantineProvider theme={theme} getStyleNonce={() => nonce ?? ""}>{children}</MantineProvider>;
}
