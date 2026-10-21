/** @type {import('tailwindcss').Config} */
// Stitch W01 V9.1 (00_REFERENCES/stitch/W01_V9_1.html)의 인라인 Tailwind 설정을 그대로 이식했습니다.
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        roseTone: {
          50: '#FFF5F8',
          100: '#FDEBF1',
          200: '#F8DCE6', // Blossom Pink
          500: '#D94D83', // Primary Rose
          600: '#C2366F',
          800: '#7E2046',
        },
        berry: '#35232C', // Deep Berry
        cream: '#FFF9F6', // Soft Cream
        warmGray: '#765D69', // Warm Gray
        ivoryBorder: '#F0E2DA',
      },
      fontFamily: {
        serif: [
          '"Playfair Display"',
          '"Noto Serif KR"',
          '"Batang"',
          '"AppleMyungjo"',
          'Georgia',
          'serif',
        ],
        sans: [
          '"Plus Jakarta Sans"',
          'system-ui',
          '-apple-system',
          '"Apple SD Gothic Neo"',
          'sans-serif',
        ],
      },
      boxShadow: {
        luxury:
          '0 20px 45px -15px rgba(53, 35, 44, 0.08), 0 0 1px 1px rgba(217, 77, 131, 0.05)',
        floating: '0 30px 60px -20px rgba(217, 77, 131, 0.25)',
      },
    },
  },
  plugins: [],
}
