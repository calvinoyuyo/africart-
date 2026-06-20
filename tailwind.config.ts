import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        'custom-yellow':'#FED700',
        'africart-blue': {
          DEFAULT: '#0A5C8A',
          light: '#1B7FB8',
          dark: '#073F5E',
        },
        'africart-orange': {
          DEFAULT: '#F2772F',
          light: '#F8954F',
          dark: '#D45F1E',
        },
      }
    },
  },  
  plugins: [require("@tailwindcss/typography"), require("@tailwindcss/forms"), require("daisyui")],
};
export default config;
