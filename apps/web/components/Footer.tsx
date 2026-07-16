"use client";

import React from "react";
import {
  ActionIcon,
  Anchor,
  Box,
  Container,
  Divider,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
  useMantineColorScheme,
} from "@mantine/core";
import { IconMoon, IconSun } from "@tabler/icons-react";
import Link from "next/link";
import { WaitlistForm } from "./WaitlistForm";
import Image from "next/image";

export function Footer() {
  const { colorScheme, setColorScheme } = useMantineColorScheme();
  const [mounted, setMounted] = React.useState(false);

  React.useEffect(() => {
    setMounted(true);
  }, []);

  return (
    <Box component="footer" className="footer-section" py="xl">
      <Container size="xl" py="xl" w="100%">
        <SimpleGrid
          cols={{ base: 1, md: 2 }}
          spacing="xl"
          style={{ alignItems: "flex-start" }}
        >
          {/* Left Column: Logo & Signup */}
          <Stack gap="md" style={{ maxWidth: "420px" }}>
            <Anchor
              component={Link}
              href="/"
              className="footer-logo"
              style={{ display: "inline-block" }}
            >
              <Image
                src="/assets/logo.png"
                alt="Naturebook Logo"
                width={80}
                height={80}
                style={{ borderRadius: "50%" }}
                unoptimized
              />
            </Anchor>
            <Text size="sm" c="dimmed">
              A field companion for curious naturalists: identify living things,
              keep context with every observation, and explore community
              discoveries.
            </Text>
            <Stack gap="xs" mt="sm">
              <Text
                size="xs"
                fw={700}
                tt="uppercase"
                style={{ letterSpacing: "1px" }}
                c="dimmed"
              >
                Join the Beta waitlist
              </Text>
              <WaitlistForm />
            </Stack>
          </Stack>

          {/* Right Column: Grid of Links */}
          <SimpleGrid
            cols={{ base: 2, sm: 3 }}
            spacing="xl"
            mt={{ base: "lg", md: 0 }}
          >
            <Stack gap="sm">
              <Text
                fw={700}
                size="xs"
                tt="uppercase"
                style={{ letterSpacing: "0.5px" }}
              >
                Community
              </Text>
              <Anchor
                component={Link}
                href="/#explore"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Explore Feed
              </Anchor>
              <Anchor
                component={Link}
                href="/community-guidelines"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Guidelines
              </Anchor>
              <Anchor
                component={Link}
                href="/support"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Support Help
              </Anchor>
            </Stack>

            <Stack gap="sm">
              <Text
                fw={700}
                size="xs"
                tt="uppercase"
                style={{ letterSpacing: "0.5px" }}
              >
                Marketing
              </Text>
              <Anchor
                component={Link}
                href="/about"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                About Us
              </Anchor>
              <Anchor
                component={Link}
                href="/careers"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Careers
              </Anchor>
              <Anchor
                component={Link}
                href="/press"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Press Kit
              </Anchor>
              <Anchor
                component={Link}
                href="/field-guide"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Field Guide
              </Anchor>
            </Stack>

            <Stack gap="sm">
              <Text
                fw={700}
                size="xs"
                tt="uppercase"
                style={{ letterSpacing: "0.5px" }}
              >
                Legal
              </Text>
              <Anchor
                component={Link}
                href="/privacy"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Privacy Policy
              </Anchor>
              <Anchor
                component={Link}
                href="/terms"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Terms of Service
              </Anchor>
              <Anchor
                component={Link}
                href="/privacy-choices"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Ad Choices
              </Anchor>
              <Anchor
                component={Link}
                href="/data-deletion"
                size="sm"
                c="dimmed"
                className="footer-link"
              >
                Data Deletion
              </Anchor>
            </Stack>
          </SimpleGrid>
        </SimpleGrid>

        <Divider my="xl" style={{ opacity: 0.1 }} />

        <Group justify="space-between" align="center">
          <Text size="xs" c="dimmed">
            &copy; {new Date().getFullYear()} Naturebook. All rights reserved.
          </Text>
          <Group gap="md">
            <Text size="xs" c="dimmed">
              Built for field naturalists.
            </Text>
            <ActionIcon
              variant="default"
              onClick={() =>
                setColorScheme(colorScheme === "dark" ? "light" : "dark")
              }
              size="lg"
              aria-label="Toggle color scheme"
              radius="xl"
            >
              {!mounted ? null : colorScheme === "dark" ? (
                <IconSun size={18} stroke={1.5} />
              ) : (
                <IconMoon size={18} stroke={1.5} />
              )}
            </ActionIcon>
          </Group>
        </Group>
      </Container>
    </Box>
  );
}
