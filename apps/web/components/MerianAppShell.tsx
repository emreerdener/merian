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
  const primaryCtaHref = siteConfig.appStoreUrl ?? "/#waitlist";
  const primaryCtaLabel = siteConfig.appStoreUrl
    ? "Download the app"
    : "Join beta";

  return (
    <AppShell header={{ height: 60 }} padding="md" className="merian-app-shell">
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
                href={primaryCtaHref}
                size="sm"
                rightSection={<IconArrowUpRight size={16} />}
                visibleFrom="xs"
              >
                {primaryCtaLabel}
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

      <AppShellMain>{children}</AppShellMain>
    </AppShell>
  );
}
