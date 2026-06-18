import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
// base is set to the repo name so the build works on GitHub Pages
// (https://<user>.github.io/wute/). In dev it stays at '/'.
export default defineConfig(({ command }) => ({
  base: command === 'build' ? '/wute/' : '/',
  plugins: [react()],
}))
