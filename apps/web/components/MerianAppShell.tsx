"use client";

import type { ReactNode } from "react";
import {
  Anchor,
  AppShell,
  AppShellFooter,
  AppShellHeader,
  AppShellMain,
  AppShellNavbar,
  Burger,
  Button,
  Container,
  Group,
  Stack,
  Text,
} from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import { IconArrowUpRight } from "@tabler/icons-react";
import { siteConfig } from "@/lib/site";

type MerianAppShellProps = {
  children: ReactNode;
};

const footerLinks = [
  { href: "/privacy", label: "Privacy" },
  { href: "/terms", label: "Terms" },
  { href: "/guidelines", label: "Guidelines" },
  { href: "/privacy-choices", label: "Privacy choices" },
  { href: "/support", label: "Support" },
];

export function MerianAppShell({ children }: MerianAppShellProps) {
  const [opened, { close, toggle }] = useDisclosure();

  return (
    <AppShell
      header={{ height: 60 }}
      navbar={{ width: 300, breakpoint: "sm", collapsed: { mobile: !opened } }}
      footer={{ height: { base: 174, sm: 118 } }}
      padding="md"
      className="merian-app-shell"
    >
      <AppShellHeader className="merian-app-shell__header">
        <Container size="lg" h="100%">
          <Group h="100%" justify="space-between" wrap="nowrap">
            <Anchor href="/" fw={800} size="xl">
              Merian Earth
            </Anchor>

            <Group gap="xs" wrap="nowrap">
              <Button
                component="a"
                href="/login"
                variant="subtle"
                size="sm"
                visibleFrom="sm"
              >
                Log in
              </Button>
              <Button
                component="a"
                href={siteConfig.appStoreUrl ?? "#"}
                size="sm"
                rightSection={<IconArrowUpRight size={16} />}
                visibleFrom="xs"
              >
                Download the app
              </Button>
              <Burger
                opened={opened}
                onClick={toggle}
                hiddenFrom="sm"
                size="sm"
                aria-label="Toggle navigation"
              />
            </Group>
          </Group>
        </Container>
      </AppShellHeader>

      <AppShellNavbar p="md" hiddenFrom="sm">
        <Stack gap="sm">
          <Button
            component="a"
            href="/login"
            variant="default"
            onClick={close}
          >
            Log in
          </Button>
          <Button
            component="a"
            href={siteConfig.appStoreUrl ?? "#"}
            rightSection={<IconArrowUpRight size={16} />}
            onClick={close}
          >
            Download the app
          </Button>
        </Stack>
      </AppShellNavbar>

      <AppShellMain>{children}</AppShellMain>

      <AppShellFooter className="merian-app-shell__footer">
        <Container size="lg" py="md">
          <Stack gap="xs">
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
              Merian helps people discover and document nature. It is not a
              substitute for professional medical, veterinary, safety, or
              ecological advice.
            </Text>
          </Stack>
        </Container>
      </AppShellFooter>
    </AppShell>
  );
}
