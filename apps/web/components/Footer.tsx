"use client";

import {
  ActionIcon,
  Anchor,
  Box,
  Button,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
  useComputedColorScheme,
  useMantineColorScheme,
} from "@mantine/core";
import { IconMoon, IconSun } from "@tabler/icons-react";
import Image from "next/image";
import { useEffect, useState } from "react";
import { QrPlaceholder } from "@/components/QrPlaceholder";
import { siteConfig } from "@/lib/site";

const linkGroups = [
  {
    title: "Explore",
    links: [
      ["Discoveries", "/explore"],
      ["About Naturebook", "/about"],
      ["Community guidelines", "/guidelines"],
    ],
  },
  {
    title: "Here to help",
    links: [
      ["Support", "/support"],
      ["Privacy choices", "/privacy-choices"],
      ["Data deletion", "/data-deletion"],
    ],
  },
  {
    title: "The essentials",
    links: [
      ["Privacy policy", "/privacy"],
      ["Terms of service", "/terms"],
      ["Legal", "/legal"],
    ],
  },
];

export function Footer() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", {
    getInitialValueInEffect: true,
  });
  // Stored preferences may be available before a streamed subtree hydrates.
  const displayedColorScheme = mounted ? colorScheme : "light";

  return (
    <Box component="footer" className="footer-section">
      <Container size="xl" className="footer-container">
        <div className="footer-main">
          <Stack gap="md" className="footer-intro">
            <Anchor
              href="/"
              aria-label="Naturebook home"
              className="footer-intro-mark"
            >
              <Image
                src="/assets/butterfly-static.png"
                alt=""
                width={56}
                height={56}
                unoptimized
              />
            </Anchor>
            <Title order={2} className="footer-title">
              Learn and explore
            </Title>
            <Group gap="sm" mt="sm">
              <Button
                component="a"
                href={siteConfig.appStoreUrl ?? "/about#waitlist"}
                className="home-primary"
                size="md"
              >
                {siteConfig.appStoreUrl ? "Get the app" : "Join the beta"}
              </Button>
              <Anchor href="/" className="footer-secondary">
                Explore discoveries
              </Anchor>
            </Group>
          </Stack>
          <SimpleGrid
            cols={{ base: 1, xs: 3 }}
            spacing="xl"
            component="nav"
            aria-label="Footer navigation"
          >
            {linkGroups.map((group) => (
              <Stack key={group.title} gap="sm">
                <Text fw={700} size="sm">
                  {group.title}
                </Text>
                {group.links.map(([label, href]) => (
                  <Anchor
                    key={href}
                    href={href}
                    className="footer-link"
                    size="sm"
                  >
                    {label}
                  </Anchor>
                ))}
              </Stack>
            ))}
          </SimpleGrid>
          <QrPlaceholder />
        </div>
        <Group justify="space-between" gap="lg" className="footer-bottom">
          <Text size="xs">© {new Date().getFullYear()} Naturebook</Text>
          <Group gap="sm">
            <Text size="xs">A world worth noticing.</Text>
            <ActionIcon
              variant="default"
              onClick={() =>
                setColorScheme(colorScheme === "dark" ? "light" : "dark")}
              size="lg"
              aria-label={`Switch to ${
                displayedColorScheme === "dark" ? "light" : "dark"
              } appearance`}
              radius="xl"
            >
              {displayedColorScheme === "dark"
                ? <IconSun size={18} />
                : <IconMoon size={18} />}
            </ActionIcon>
          </Group>
        </Group>
      </Container>
    </Box>
  );
}
