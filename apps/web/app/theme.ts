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
      "#ededed",
      "#c1c1c1",
      "#a6a6a6",
      "#777777",
      "#505050",
      "#3b3b3b",
      "#2b2b2b",
      "#202020",
      "#191919",
      "#111111",
    ],
  },
  defaultRadius: "sm",
  radius: { xs: "6px", sm: "10px", md: "12px", lg: "16px", xl: "24px" },
  fontFamily: systemFont,
  headings: { fontFamily: systemFont, fontWeight: "600" },
  components: { Button: { defaultProps: { radius: "999px", fw: 500 } } },
});
