import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

const port = process.env.JC_ENGINE_PORT || '4000';
const target = `http://127.0.0.1:${port}`;

export default defineConfig({
  base: '/__jc/',
  plugins: [preact()],
  build: {
    outDir: '../engine/public',
    emptyOutDir: true,
    assetsDir: 'assets',
    chunkSizeWarningLimit: 4000,
  },
  server: {
    // Everything outside /__jc/ (the site itself) and the API go to the running engine.
    proxy: {
      '/__jc/api': { target, changeOrigin: false },
      '^/(?!__jc/).*': { target, changeOrigin: false },
    },
  },
});
