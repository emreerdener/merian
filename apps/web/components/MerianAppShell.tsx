"use client";

import type { ReactNode } from "react";
import {
  Anchor,
  AppShell,
  AppShellHeader,
  AppShellMain,
  Box,
  Burger,
  Button,
  Container,
  Drawer,
  Group,
  Modal,
  Stack,
  Text,
} from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import { IconArrowUpRight } from "@tabler/icons-react";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { siteConfig } from "@/lib/site";
import { WaitlistForm } from "@/components/WaitlistForm";
import { Footer } from "@/components/Footer";

const navigation = [
  { label: "Discover", href: "/#explore" },
  { label: "About Naturebook", href: "/#about" },
  { label: "Support", href: "/support" },
];

export function MerianAppShell({ children }: { children: ReactNode }) {
  const isHomePage = usePathname() === "/";
  const [opened, { toggle, close }] = useDisclosure();
  const [modalOpened, { open: openModal, close: closeModal }] = useDisclosure(
    false,
  );

  return (
    <>
      <a href="#main-content" className="skip-link">Skip to content</a>
      <AppShell
        header={{ height: 76 }}
        padding={0}
        className="merian-app-shell"
      >
        <AppShellHeader
          className="merian-app-shell__header"
          data-home={isHomePage || undefined}
        >
          <Container size="xl" h="100%">
            <Group h="100%" justify="space-between" wrap="nowrap" gap="sm">
              <Anchor
                href="/"
                underline="never"
                className="header-logo-container"
                aria-label="Naturebook home"
              >
                <Image
                  src="/assets/logo.png"
                  alt=""
                  width={36}
                  height={36}
                  unoptimized
                />
                <span>Naturebook</span>
              </Anchor>
              <Group
                component="nav"
                aria-label="Main navigation"
                gap="xl"
                visibleFrom="md"
                className="header-nav"
              >
                {navigation.map((link) => (
                  <Anchor key={link.href} href={link.href} underline="never">
                    {link.label}
                  </Anchor>
                ))}
              </Group>
              <Group gap="sm" wrap="nowrap">
                {siteConfig.appStoreUrl
                  ? (
                    <Button
                      component="a"
                      href={siteConfig.appStoreUrl}
                      size="sm"
                      radius="xl"
                      className="header-cta-button"
                    >
                      Get the app
                    </Button>
                  )
                  : isHomePage
                  ? (
                    <Button
                      component="a"
                      href="/#waitlist"
                      size="sm"
                      radius="xl"
                      className="header-cta-button"
                    >
                      Join beta
                    </Button>
                  )
                  : (
                    <Button
                      onClick={openModal}
                      size="sm"
                      radius="xl"
                      className="header-cta-button"
                    >
                      Join beta
                    </Button>
                  )}
                <Burger
                  opened={opened}
                  onClick={toggle}
                  hiddenFrom="md"
                  size="sm"
                  aria-label={opened ? "Close navigation" : "Open navigation"}
                  color={isHomePage ? "#f5fff2" : undefined}
                />
              </Group>
            </Group>
          </Container>
        </AppShellHeader>
        <AppShellMain id="main-content" tabIndex={-1}>
          <Stack gap={0} style={{ minHeight: "calc(100svh - 76px)" }}>
            <Box p={isHomePage ? 0 : "md"} style={{ flex: 1 }}>{children}</Box>
            <Footer />
          </Stack>
        </AppShellMain>
      </AppShell>
      <Drawer
        opened={opened}
        onClose={close}
        title="Explore Naturebook"
        position="right"
      >
        <Stack component="nav" aria-label="Mobile navigation" gap="lg">
          {navigation.map((link) => (
            <Anchor key={link.href} href={link.href} onClick={close}>
              {link.label} <IconArrowUpRight size={16} />
            </Anchor>
          ))}
          <Anchor href="/privacy" onClick={close}>Privacy</Anchor>
        </Stack>
      </Drawer>
      <Modal
        opened={modalOpened}
        onClose={closeModal}
        title="Join the Naturebook beta"
        centered
        radius="lg"
        size="md"
      >
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Get early access to learn about nearby nature, keep your
            discoveries, and explore what others are finding.
          </Text>
          <WaitlistForm />
        </Stack>
      </Modal>
    </>
  );
}
