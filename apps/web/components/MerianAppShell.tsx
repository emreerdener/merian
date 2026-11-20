"use client";

import type { ReactNode } from "react";
import {
  Anchor,
  AppShell,
  AppShellHeader,
  AppShellMain,
  Box,
  Button,
  Container,
  Group,
  Modal,
  Stack,
  Text,
} from "@mantine/core";
import { useDisclosure } from "@mantine/hooks";
import { usePathname } from "next/navigation";
import { siteConfig } from "@/lib/site";
import { WaitlistForm } from "@/components/WaitlistForm";
import { Footer } from "@/components/Footer";
import { ButterflyMark } from "@/components/ButterflyMark";

const navigation = [
  { label: "Explore", href: "/" },
  { label: "About", href: "/about" },
  { label: "Support", href: "/support" },
];

export function MerianAppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isExplorePage = pathname === "/";
  const isAboutPage = pathname === "/about";
  const isHomePage = isExplorePage || isAboutPage;
  const [modalOpened, { open: openModal, close: closeModal }] = useDisclosure(
    false,
  );

  return (
    <>
      <a href="#main-content" className="skip-link">
        Skip to content
      </a>
      <AppShell
        header={{ height: 76 }}
        padding={0}
        className="merian-app-shell"
      >
        <AppShellHeader
          className={`merian-app-shell__header${
            isExplorePage
              ? " home-header explore-header"
              : isAboutPage
              ? " home-header"
              : ""
          }`}
        >
          <Container
            size="xl"
            h="100%"
            className={isHomePage ? "home-header-container" : undefined}
          >
            <Group
              h="100%"
              justify="space-between"
              wrap="nowrap"
              gap="md"
              className={`site-header-layout${
                isHomePage ? " home-header-layout" : ""
              }`}
            >
              <Anchor
                href="/"
                underline="never"
                className="header-logo-container"
                aria-label="Naturebook home"
              >
                <Group wrap="nowrap" gap={8} align="center">
                  <span className="header-wordmark-butterfly">
                    <ButterflyMark size={40} />
                  </span>
                  <Text fz={36} fw={600}>
                    naturebook
                  </Text>
                </Group>
              </Anchor>
            </Group>
          </Container>
        </AppShellHeader>
        <AppShellMain
          id="main-content"
          tabIndex={-1}
          pb={isExplorePage ? 0 : 100}
          className={isExplorePage
            ? "home-main explore-main"
            : isAboutPage
            ? "home-main"
            : undefined}
        >
          <Stack gap={0} style={{ minHeight: "calc(100svh - 76px)" }}>
            <Box p={isHomePage ? 0 : "md"} style={{ flex: 1 }}>
              {children}
            </Box>
            {!isExplorePage && <Footer />}
          </Stack>
        </AppShellMain>
      </AppShell>
      <nav className="site-bottom-nav" aria-label="Main navigation">
        {navigation.map((link) => (
          <Anchor
            key={link.href}
            href={link.href}
            underline="never"
            aria-current={pathname === link.href ? "page" : undefined}
          >
            {link.label}
          </Anchor>
        ))}
        {siteConfig.appStoreUrl
          ? (
            <Button
              component="a"
              href={siteConfig.appStoreUrl}
              size="sm"
              className="header-cta-button"
            >
              Get the app
            </Button>
          )
          : isAboutPage
          ? (
            <Button
              component="a"
              href="/about#waitlist"
              size="sm"
              className="header-cta-button"
            >
              Join beta
            </Button>
          )
          : (
            <Button
              onClick={openModal}
              size="sm"
              className="header-cta-button"
            >
              Join beta
            </Button>
          )}
      </nav>
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
