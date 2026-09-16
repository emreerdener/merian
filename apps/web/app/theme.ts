import { createTheme } from "@mantine/core";

const systemFont = '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

export const theme = createTheme({
  primaryColor: "forest",
  primaryShade: { light: 8, dark: 3 },
  autoContrast: true,
  colors: {
    forest: [
      "#f2f8e9",
      "#e5f2cf",
      "#d2e8ac",
      "#bfdc91",
      "#9bbf73",
      "#719b55",
      "#53773e",
      "#3a6033",
      "#234d35",
      "#173c29",
    ],
    dark: [
      "#dce8dd",
      "#b3c8b7",
      "#8fa996",
      "#607f6c",
      "#3d5d49",
      "#2a4737",
      "#203d2b",
      "#19352a",
      "#10241d",
      "#071f1b",
    ],
  },
  defaultRadius: "md",
  radius: { xs: "8px", sm: "12px", md: "16px", lg: "24px", xl: "32px" },
  fontFamily: systemFont,
  headings: { fontFamily: systemFont, fontWeight: "750" },
  components: { Button: { defaultProps: { radius: "xl", fw: 650 } } },
});
