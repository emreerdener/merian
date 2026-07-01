"use client";

import type { ReactNode } from "react";
import {
  Anchor,
  AppShell,
  AppShellHeader,
  AppShellMain,
  Burger,
  Button,
  Container,
  Group,
  Modal,
  Stack,
  Text,
} from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import { IconArrowUpRight } from "@tabler/icons-react";
import { siteConfig } from "@/lib/site";
import { usePathname } from "next/navigation";
import { WaitlistForm } from "@/components/WaitlistForm";

type MerianAppShellProps = {
  children: ReactNode;
};

export function MerianAppShell({ children }: MerianAppShellProps) {
  const pathname = usePathname();
  const isSplashPage = pathname === "/";
  const [opened, { toggle }] = useDisclosure();
  const [modalOpened, { open: openModal, close: closeModal }] = useDisclosure(false);
  const primaryCtaHref = siteConfig.appStoreUrl ?? "/#waitlist";
  const primaryCtaLabel = siteConfig.appStoreUrl
    ? "Download the app"
    : "Join beta";

  if (isSplashPage) {
    return <main className="splash-layout">{children}</main>;
  }

  return (
    <>
      <AppShell header={{ height: 60 }} padding="md" className="merian-app-shell">
        <AppShellHeader className="merian-app-shell__header">
          <Container size="lg" h="100%">
            <Group h="100%" justify="space-between" wrap="nowrap">
              <Anchor href="/" fw={800} size="xl">
                Merian Earth
              </Anchor>

              <Group gap="xs" wrap="nowrap">
                {primaryCtaLabel === "Join beta" ? (
                  <Button
                    onClick={openModal}
                    size="sm"
                    visibleFrom="xs"
                  >
                    Join beta
                  </Button>
                ) : (
                  <Button
                    component="a"
                    href={primaryCtaHref}
                    size="sm"
                    visibleFrom="xs"
                  >
                    {primaryCtaLabel}
                  </Button>
                )}
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

      <Modal
        opened={modalOpened}
        onClose={closeModal}
        title="Join the Merian Beta"
        centered
        radius="lg"
        size="md"
      >
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Get early access to identify and explore wild species, keep track of your life lists, and see what is being found around you.
          </Text>
          <WaitlistForm />
        </Stack>
      </Modal>
    </>
  );
}
