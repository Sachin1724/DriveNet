/** @type {import('tailwindcss').Config} */
export default {
    darkMode: 'class',
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                "primary": "#ff4757",
                "background-light": "#f8f5f6",
                "background-dark": "#0f1923",
                "surface-dark": "#172535",
                "accent-dark": "#2a3e52"
            },
            fontFamily: {
                "display": ["Space Grotesk", "sans-serif"]
            }
        },
    },
    plugins: [],
}
