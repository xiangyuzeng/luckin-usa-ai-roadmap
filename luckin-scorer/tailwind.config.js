/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#FAFBFC',
        card: '#FFFFFF',
        border: '#E5E7EB',
        accent: {
          teal: '#0891B2',
          purple: '#7C3AED',
          amber: '#D97706',
          green: '#059669',
          red: '#DC2626',
        },
        text: {
          primary: '#111827',
          secondary: '#4B5563',
          muted: '#9CA3AF',
        },
      },
      fontFamily: {
        sans: ['Segoe UI', 'Microsoft YaHei', 'system-ui', 'sans-serif'],
        serif: ['Georgia', 'serif'],
      },
      borderRadius: {
        card: '10px',
      },
    },
  },
  plugins: [],
};
