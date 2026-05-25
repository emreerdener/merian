import type { ReactNode } from "react";
import { Container, Stack } from "@mantine/core";

type PublicPageShellProps = {
  children: ReactNode;
  size?: "sm" | "md" | "lg";
};

export function PublicPageShell({ children, size = "md" }: PublicPageShellProps) {
  return (
    <Container size={size} py={{ base: 32, sm: 72 }}>
      <Stack gap="xl">{children}</Stack>
    </Container>
  );
}
