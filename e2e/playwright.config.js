// Runs against an already-running stack: `docker compose up --build -d` from the repo root.
// Override the SPA origin with SPA_URL if you changed SPA_HOST_PORT.
const { defineConfig } = require('@playwright/test')

module.exports = defineConfig({
  testDir: './tests',
  retries: 0,
  reporter: [['list']],
  use: { baseURL: process.env.SPA_URL || 'http://localhost:3000', screenshot: 'only-on-failure' },
})
