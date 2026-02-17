/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        dark: {
          bg: '#0a0a0a',
          card: '#1a1a1a',
          border: '#282828',
          hover: '#333333',
        },
        accent: {
          blue: '#3b82f6',
          green: '#22c55e',
          yellow: '#eab308',
          red: '#ef4444',
          orange: '#f97316',
          purple: '#a855f7',
        },
      },
    },
  },
  plugins: [],
};
