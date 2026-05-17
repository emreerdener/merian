import type { ReactNode } from "react";
import { Anchor, Container, Divider, Group, Stack, Text } from "@mantine/core";

type PublicPageShellProps = {
  children: ReactNode;
  size?: "sm" | "md" | "lg";
};

const footerLinks = [
  { href: "/privacy", label: "Privacy" },
  { href: "/terms", label: "Terms" },
  { href: "/guidelines", label: "Guidelines" },
  { href: "/privacy-choices", label: "Privacy choices" },
  { href: "/support", label: "Support" }
];

export function PublicPageShell({ children, size = "md" }: PublicPageShellProps) {
  return (
    <main>
      <Container size={size} py={{ base: 32, sm: 72 }}>
        <Stack gap="xl">
          {children}

          <Divider />

          <Group justify="space-between" align="center" gap="md">
            <Anchor href="/" fw={700}>
              Merian
            </Anchor>
            <Group gap="md">
              {footerLinks.map((link) => (
                <Anchor key={link.href} href={link.href} size="sm" c="dimmed">
                  {link.label}
                </Anchor>
              ))}
            </Group>
          </Group>

          <Text size="xs" c="dimmed">
            Merian helps people discover and document nature. It is not a substitute for
            professional medical, veterinary, safety, or ecological advice.
          </Text>
        </Stack>
      </Container>
    </main>
  );
}
