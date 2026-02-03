/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        lobster: {
          red: '#E63946',
          dark: '#1D3557',
          light: '#A8DADC',
          accent: '#F1FAEE',
          blue: '#457B9D',
        }
      },
      animation: {
        'flip': 'flip 0.6s ease-in-out',
        'pulse-glow': 'pulse-glow 2s ease-in-out infinite',
      },
      keyframes: {
        flip: {
          '0%': { transform: 'rotateY(0deg)' },
          '50%': { transform: 'rotateY(90deg)' },
          '100%': { transform: 'rotateY(0deg)' },
        },
        'pulse-glow': {
          '0%, 100%': { boxShadow: '0 0 20px rgba(230, 57, 70, 0.5)' },
          '50%': { boxShadow: '0 0 40px rgba(230, 57, 70, 0.8)' },
        }
      }
    },
  },
  plugins: [],
}
