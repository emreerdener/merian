"use client";

import {
  ActionIcon,
  Anchor,
  Box,
  Container,
  Group,
  SimpleGrid,
  Stack,
  Text,
  useComputedColorScheme,
  useMantineColorScheme,
} from "@mantine/core";
import { IconMoon, IconSun } from "@tabler/icons-react";
import Image from "next/image";

const linkGroups = [
  {
    title: "Explore",
    links: [["Discoveries", "/#explore"], ["About Naturebook", "/#about"], [
      "Community guidelines",
      "/guidelines",
    ]],
  },
  {
    title: "Here to help",
    links: [["Support", "/support"], ["Privacy choices", "/privacy-choices"], [
      "Data deletion",
      "/data-deletion",
    ]],
  },
  {
    title: "The essentials",
    links: [["Privacy policy", "/privacy"], ["Terms of service", "/terms"], [
      "Legal",
      "/legal",
    ]],
  },
];

export function Footer() {
  const { setColorScheme } = useMantineColorScheme();
  const colorScheme = useComputedColorScheme("light", {
    getInitialValueInEffect: true,
  });

  return (
    <Box component="footer" className="footer-section">
      <Container size="xl">
        <div className="footer-main">
          <Stack gap="md" className="footer-intro">
            <Anchor href="/" underline="never" className="footer-brand">
              <Image
                src="/assets/logo.png"
                alt=""
                width={44}
                height={44}
                unoptimized
              />
              <span>Naturebook</span>
            </Anchor>
            <Text>
              A little curiosity.<br />A deeper connection to nature.
            </Text>
          </Stack>
          <SimpleGrid
            cols={{ base: 1, xs: 3 }}
            spacing="xl"
            component="nav"
            aria-label="Footer navigation"
          >
            {linkGroups.map((group) => (
              <Stack key={group.title} gap="sm">
                <Text fw={700} size="sm">{group.title}</Text>
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
                colorScheme === "dark" ? "light" : "dark"
              } appearance`}
              radius="xl"
            >
              {colorScheme === "dark"
                ? <IconSun size={18} />
                : <IconMoon size={18} />}
            </ActionIcon>
          </Group>
        </Group>
        <div className="footer-wordmark" aria-hidden="true">
          naturebook<span>↗</span>
        </div>
      </Container>
    </Box>
  );
}
